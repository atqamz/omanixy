"""Discover literal executable invocations from supported Quattro sources."""

from __future__ import annotations

import ast
import re
import shlex
from collections import Counter


SHELL_BUILTINS = {
    "!",
    ".",
    ":",
    "[",
    "[[",
    "]",
    "]]",
    "break",
    "case",
    "continue",
    "declare",
    "do",
    "done",
    "echo",
    "elif",
    "else",
    "esac",
    "exit",
    "export",
    "false",
    "fi",
    "for",
    "function",
    "getopts",
    "hash",
    "help",
    "if",
    "jobs",
    "kill",
    "let",
    "local",
    "mapfile",
    "popd",
    "printf",
    "pushd",
    "read",
    "readarray",
    "readonly",
    "return",
    "set",
    "shift",
    "source",
    "test",
    "then",
    "time",
    "trap",
    "true",
    "type",
    "typeset",
    "unset",
    "until",
    "umask",
    "unalias",
    "ulimit",
    "wait",
    "while",
}

SHELL_COMMAND_RE = re.compile(
    r"(?:^\s*|[;&|!)]\s*|<\s*<\()((?:/[A-Za-z0-9_.+-]+)+|[A-Za-z][A-Za-z0-9_.+-]*)"
)
COMMAND_SUBSHELL_RE = re.compile(r"\$\(([^()]*)\)")
PROCESS_SUBSHELL_RE = re.compile(r"<\s*<\(([^()]*)\)")
BACKTICK_SUBSHELL_RE = re.compile(r"`([^`]*)`")
DYNAMIC_EXECUTABLE = "__dynamic-executable__"
ARRAY_COMMAND_RE = re.compile(
    r"(?:(?:\b[A-Za-z_][A-Za-z0-9_]*\.)?command\s*[:=]|"
    r"(?:Quickshell|Util)\.exec(?:Detached)?\s*\()\s*"
    r"\[((?:\\.|[^\"'\]]|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')*)\]",
    re.DOTALL,
)
DYNAMIC_COMMAND_RE = re.compile(r"\bcommand\s*:\s+(?![\"'\[])[^\n,}]+")
DYNAMIC_SCRIPT_RE = re.compile(r"\bscript\s*:\s+(?![\"'\[])[^\n,}]+")
DYNAMIC_ASSIGNMENT_RE = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.command\s*=\s+(?![\"'\[])[^\n;]+"
)
DYNAMIC_CALL_RE = re.compile(
    r"\b(?:Quickshell|Util)\.exec(?:Detached)?\(\s*(?![\"'\[])[^\)\n]+\)"
)
DYNAMIC_RUN_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\.run\(\s*(?![\"'\[])[^\)\n]+\)")
SHELL_PAYLOAD_RE = re.compile(
    r"\b(?:command|script)\s*:\s*([\"'])(.*?)(?<!\\)\1",
    re.DOTALL,
)
SHELL_STRING_RE = re.compile(
    r"(?:\b[A-Za-z_][A-Za-z0-9_]*\.run|(?:Quickshell|Util)\.exec(?:Detached)?)\(\s*"
    r"([\"'])(.*?)(?<!\\)\1",
    re.DOTALL,
)


def _is_literal_command_word(word: str) -> bool:
    return bool(word.startswith("/") or re.fullmatch(r"[A-Za-z][A-Za-z0-9_.+-]*", word))


_REDIRECTION_WORD_RE = re.compile(r"^(?:\{[A-Za-z_][A-Za-z0-9_]*\}|[0-9]*)(?:>>?|<>?|>&|<&)")

# The only SHELL_BUILTINS members that introduce a following simple command
# rather than being one themselves. Everything else in SHELL_BUILTINS (read,
# echo, export, if, for, ...) is either a terminal builtin invocation or a
# reserved word that opens a compound construct - in both cases its own
# trailing words are its arguments or a test expression, never a further
# command to resolve, so _next_command must stop there rather than treat the
# next word (e.g. `read -ra name`'s `name`) as if it were the invocation.
_COMMAND_INTRODUCER_WORDS = {"!", "time", "do", "then", "else"}


def _next_command(words: list[str], start: int) -> list[str]:
    """Return the next command-head word: a literal name, or DYNAMIC_EXECUTABLE
    if the first non-flag, non-assignment, non-introducer, non-redirection
    word is not a literal shape. Never skips past a dynamic word looking for
    a literal one - a bare redirection (`exec {fd}>file`, `2>&1`) performs no
    execution at all, so it is the only shape safe to skip past
    unconditionally."""

    for word in words[start:]:
        if word.startswith("-"):
            continue
        if "=" in word and word.split("=", 1)[0].isidentifier():
            continue
        if word in _COMMAND_INTRODUCER_WORDS:
            continue
        if word in SHELL_BUILTINS:
            return []
        if _REDIRECTION_WORD_RE.match(word):
            continue
        if _is_literal_command_word(word):
            return [word]
        return [DYNAMIC_EXECUTABLE]
    return []


def shell_executables(value: str) -> list[str]:
    """Return literal command names from a shell command string."""

    value = _strip_shell_comment(value)
    if not value.strip() or value.lstrip().startswith("#!"):
        return []

    commands: list[str] = []
    for match in COMMAND_SUBSHELL_RE.finditer(value):
        commands.extend(shell_executables(match.group(1)))
    for match in PROCESS_SUBSHELL_RE.finditer(value):
        commands.extend(shell_executables(match.group(1)))
    for match in BACKTICK_SUBSHELL_RE.finditer(value):
        commands.extend(shell_executables(match.group(1)))
    if value.count("`") % 2:
        commands.append(DYNAMIC_EXECUTABLE)
    parts: list[str] = []
    part_start = 0
    quote: str | None = None
    escaped = False
    for index, char in enumerate(value):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in {"'", '"'}:
            quote = char
        elif char in ";&|\n":
            parts.append(value[part_start:index])
            part_start = index + 1
    parts.append(value[part_start:])
    for part in parts:
        try:
            words = shlex.split(part, comments=False, posix=True)
        except ValueError:
            words = re.findall(r"[A-Za-z][A-Za-z0-9_.+-]*", part)
        while words and words[0] in {"if", "then", "else"}:
            words.pop(0)
        if not words:
            continue
        first = words[0]
        if first in SHELL_BUILTINS:
            if first in {"!", "time", "do", "then", "else"}:
                commands.extend(_next_command(words, 1))
            elif first in {"for", "while", "until"}:
                if "do" in words:
                    commands.extend(_next_command(words, words.index("do") + 1))
            elif first == "case":
                if ")" in words:
                    commands.extend(_next_command(words, words.index(")") + 1))
            elif first == "function" and "{" in words:
                commands.extend(shell_executables(" ".join(words[words.index("{") + 1 :])))
            elif first in {"source", "."}:
                commands.append(DYNAMIC_EXECUTABLE)
            continue
        if first in {"command", "builtin", "exec"}:
            commands.extend(_next_command(words, 1))
            for index, word in enumerate(words[1:], 1):
                if word.rsplit("/", 1)[-1] in {"bash", "dash", "sh", "zsh"}:
                    for option_index, option in enumerate(words[index + 1 :], index + 1):
                        if option.startswith("-") and "c" in option:
                            payload = " ".join(words[option_index + 1 :])
                            if payload.startswith("$"):
                                commands.append(DYNAMIC_EXECUTABLE)
                            else:
                                commands.extend(shell_executables(payload))
                            break
                    break
        elif first == "eval":
            payload = " ".join(words[1:])
            if not payload or payload.startswith("$"):
                commands.append(DYNAMIC_EXECUTABLE)
            else:
                commands.extend(shell_executables(payload))
        elif first.rsplit("/", 1)[-1] in {"bash", "dash", "sh", "zsh"}:
            commands.append(first)
            for index, word in enumerate(words[1:], 1):
                if word.startswith("-") and "c" in word:
                    payload = " ".join(words[index + 1 :])
                    if payload.startswith("$"):
                        commands.append(DYNAMIC_EXECUTABLE)
                    else:
                        commands.extend(shell_executables(payload))
                    break
        elif first == "timeout":
            commands.append(first)
            commands.extend(_next_command(words, 2))
            for index, word in enumerate(words[2:], 2):
                if word.rsplit("/", 1)[-1] in {"bash", "dash", "sh", "zsh"}:
                    for option_index, option in enumerate(words[index + 1 :], index + 1):
                        if option.startswith("-") and "c" in option:
                            payload = " ".join(words[option_index + 1 :])
                            if payload.startswith("$"):
                                commands.append(DYNAMIC_EXECUTABLE)
                            else:
                                commands.extend(shell_executables(payload))
                            break
                    break
        elif first == "env":
            commands.append(first)
            commands.extend(_next_command(words, 1))
            for index, word in enumerate(words[1:], 1):
                if word.rsplit("/", 1)[-1] in {"bash", "dash", "sh", "zsh"}:
                    for option_index, option in enumerate(words[index + 1 :], index + 1):
                        if option.startswith("-") and "c" in option:
                            payload = " ".join(words[option_index + 1 :])
                            if payload.startswith("$"):
                                commands.append(DYNAMIC_EXECUTABLE)
                            else:
                                commands.extend(shell_executables(payload))
                            break
                    break
        elif "=" in first and (
            (_head := first.split("=", 1)[0]).isidentifier()
            or (_head.endswith("+") and _head[:-1].isidentifier())
        ):
            value_part = first.split("=", 1)[1]
            if value_part.count("(") <= value_part.count(")"):
                commands.extend(_next_command(words, 1))
            # else: this word is only the leading fragment of a $(...) value
            # containing unquoted whitespace - shlex split it into further
            # words that are its own arguments, not a following command, and
            # COMMAND_SUBSHELL_RE already scanned its real content above.
        elif first.startswith("$"):
            commands.append(DYNAMIC_EXECUTABLE)
        elif (
            first not in SHELL_BUILTINS
            and not first.startswith(("-", "#", "{"))
            and not first.endswith((")", "}"))
            and (first.startswith("/") or re.fullmatch(r"[A-Za-z][A-Za-z0-9_.+-]*", first))
        ):
            commands.append(first)
    return list(dict.fromkeys(commands))


class UnsafeSource(ValueError):
    """A QML/JS backtick template literal (or a `${...}` interpolation
    inside one) is not closed before the source ends.

    This lexical masker treats a backtick literal as the only construct
    that can legitimately span multiple lines, so an actually-unterminated
    one could otherwise silently absorb the rest of the file as inert
    string content - hiding whatever real code follows rather than merely
    misreading the malformed literal itself. Callers that need a hermetic,
    fail-closed guarantee (the lock executable-surface scanner) must treat
    this as unverifiable input and reject the file outright.
    """


def _find_string_end(text: str, start: int, quote: str) -> int:
    """`start` is just past an opening '"'/"'" at `quote`. Return the index
    just past the matching unescaped closing quote, or -1 if the string is
    not closed before a literal newline or the end of text - a "..."/'...'
    string cannot legally contain an unescaped newline, so this masker
    never treats one as spanning lines."""

    index = start
    length = len(text)
    while index < length:
        char = text[index]
        if char == "\\" and index + 1 < length:
            index += 2
            continue
        if char == quote:
            return index + 1
        if char == "\n":
            return -1
        index += 1
    return -1


def _blank(body: str) -> str:
    """Replace every non-newline character with a space, preserving length
    and every newline position so offsets into the result still line up
    1:1 with offsets into `body`."""

    return "".join("\n" if char == "\n" else " " for char in body)


def _consume_interpolation(text: str, start: int, mask: bool) -> tuple[int, str]:
    """`start` is the index of the "$" opening a "${" inside a backtick
    literal. Returns the index just past the matching unescaped "}" and the
    interpolation's text (delimiters included).

    `${...}` is treated as a live JS-like lexical region: identifiers,
    operators, calls, assignments, array/object syntax, and nested
    `${...}` expressions stay live so a command built through interpolation
    remains visible to discovery. Everything else is inert and cannot
    perturb that liveness:

    - "//" and "/* */" comments are recognized and blanked to whitespace
      (never deleted, unlike top-level `strip_comments` - the interpolation
      walker relies on 1:1 index correspondence with `text` to track brace
      depth, so shrinking the output here would desync the match) before
      depth-counting sees them, so a "}" inside a comment can never
      terminate the interpolation early and comment-only text can never
      satisfy command discovery.
    - Quoted string bodies are masked exactly like `mask_string_literals`
      does at top level: verbatim when `mask` is False (Stage 1 preserves
      string content), blanked when `mask` is True (Stage 2 hides
      string-only content from discovery), with the delimiting quotes kept
      either way so downstream span matching still sees a well-formed
      string shape.
    - Nested backtick literals recurse through `_consume_backtick`, so
      their static text stays inert while any further nested `${...}`
      inside them stays live.

    Braces inside any of the above are consumed as part of that region and
    never reach the depth counter, so they cannot desync the match."""

    length = len(text)
    index = start + 2
    depth = 1
    pieces = ["${"]
    while index < length:
        char = text[index]
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            pieces.append(_blank(text[index:end]))
            index = end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end < 0 else end + 2
            pieces.append(_blank(text[index:end]))
            index = end
            continue
        if char in "\"'":
            end = _find_string_end(text, index + 1, char)
            if end < 0:
                raise UnsafeSource("unterminated string literal inside template interpolation")
            body = text[index + 1 : end - 1]
            pieces.append(char)
            pieces.append(_blank(body) if mask else body)
            pieces.append(char)
            index = end
            continue
        if char == "`":
            end, content = _consume_backtick(text, index + 1, mask)
            pieces.append(f"`{content}`")
            index = end
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                pieces.append("}")
                return index + 1, "".join(pieces)
        pieces.append(char)
        index += 1
    raise UnsafeSource("unterminated ${...} template interpolation")


def _consume_backtick(text: str, start: int, mask: bool) -> tuple[int, str]:
    """`start` is just past an opening backtick. Returns the index just past
    the matching unescaped closing backtick and the literal's content
    (excluding delimiters) - verbatim when `mask` is False, with static text
    blanked when `mask` is True. `${...}` interpolation is always recursed
    into as live code (see `_consume_interpolation`) rather than being
    blanked as static text, regardless of `mask`."""

    length = len(text)
    index = start
    out: list[str] = []
    while index < length:
        char = text[index]
        if char == "\\" and index + 1 < length:
            pair = text[index : index + 2]
            out.append(_blank(pair) if mask else pair)
            index += 2
            continue
        if char == "`":
            return index + 1, "".join(out)
        if char == "$" and index + 1 < length and text[index + 1] == "{":
            end, live = _consume_interpolation(text, index, mask)
            out.append(live)
            index = end
            continue
        out.append((" " if char != "\n" else "\n") if mask else char)
        index += 1
    raise UnsafeSource("unterminated template literal (backtick string)")


def strip_comments(text: str, shell: bool = False) -> str:
    """Lexically mask comments for line-oriented scanning.

    This is a lexical masker, not a parser: it recognizes comments, quoted
    strings, and (QML/JS only) backtick template literals with `${...}`
    interpolation well enough that a comment marker sitting inside a
    properly quoted string or template literal cannot hide the real code
    that follows it, without attempting to understand QML/JS grammar
    beyond that.

    Shell has no block-comment or template-literal syntax, so treating "/*"
    as a QML/JS block comment opener would eat glob patterns like
    "image/*)" in a case arm, and a backtick is just a command-substitution
    delimiter, not a multiline string. Shell scripts strip only unquoted
    "#" to end of line and never span a comment or quote across lines.

    String and template-literal CONTENT is preserved (only comments are
    removed) so contract discovery that reads literal values out of quoted
    text (e.g. `Quickshell.env("HOME")`) keeps working unchanged. Use
    `mask_string_literals` on the result when literal-looking text inside a
    string must not itself satisfy command discovery.

    A `${...}` interpolation is live code, not a string: comments inside
    one are still removed, but - unlike top-level comments, which are
    deleted and collapse to a bare newline - they are blanked to
    whitespace in place. `_consume_interpolation` tracks brace depth by
    walking `text` index-for-index, so shrinking its output here would
    desync that walk; blanking keeps every offset aligned.

    Raises UnsafeSource (QML/JS only) if a backtick template literal or a
    `${...}` interpolation inside one is not closed before the source ends.
    """

    if shell:
        return _strip_shell_comments(text)
    return _strip_qml_comments(text)


def _strip_shell_comments(text: str) -> str:
    result: list[str] = []
    for line in text.splitlines(keepends=True):
        out: list[str] = []
        quote = ""
        index = 0
        length = len(line)
        while index < length:
            char = line[index]
            if quote:
                if char == "\\" and index + 1 < length:
                    out.append(line[index : index + 2])
                    index += 2
                    continue
                if char == quote:
                    quote = ""
                out.append(char)
                index += 1
                continue
            if char == "#":
                out.append("\n" if line.endswith("\n") else "")
                break
            if char in "\"'`":
                quote = char
            out.append(char)
            index += 1
        result.append("".join(out))
    return "".join(result)


def _strip_qml_comments(text: str) -> str:
    out: list[str] = []
    index = 0
    length = len(text)
    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            if end < 0:
                break
            out.append("\n")
            index = end + 1
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            span = text[index:] if end < 0 else text[index : end + 2]
            out.append("\n" * span.count("\n"))
            index = length if end < 0 else end + 2
            continue
        char = text[index]
        if char in "\"'":
            end = _find_string_end(text, index + 1, char)
            if end < 0:
                newline = text.find("\n", index + 1)
                end = newline if newline >= 0 else length
                out.append(text[index:end])
                index = end
                continue
            out.append(text[index:end])
            index = end
            continue
        if char == "`":
            end, content = _consume_backtick(text, index + 1, mask=False)
            out.append(f"`{content}`")
            index = end
            continue
        out.append(char)
        index += 1
    return "".join(out)


def mask_string_literals(text: str) -> str:
    """Blank the CONTENT of quoted strings and backtick template literals in
    already comment-stripped QML/JS-like text (see `strip_comments`),
    preserving length and every newline position so a regex match found in
    the result has the identical span in `text` - callers use this to
    locate genuine command bindings (a "command:" keyword inside a masked
    string can no longer match) and then re-read the real string content
    for the matched span directly out of `text`, rather than out of this
    masked copy.

    `${...}` interpolation inside a template literal is walked as live
    code (see `_consume_interpolation`) rather than blanked as static
    text, so a command built through interpolation stays visible to
    further discovery instead of silently disappearing into blanked
    template text. Quoted strings and comments inside the interpolation
    are still inert and get blanked/masked the same as everywhere else.

    Raises UnsafeSource under the same conditions as `strip_comments`.
    """

    out: list[str] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char in "\"'":
            end = _find_string_end(text, index + 1, char)
            if end < 0:
                newline = text.find("\n", index + 1)
                end = newline if newline >= 0 else length
                out.append(char)
                out.append(_blank(text[index + 1 : end]))
                index = end
                continue
            out.append(char)
            out.append(_blank(text[index + 1 : end - 1]))
            out.append(char)
            index = end
            continue
        if char == "`":
            end, content = _consume_backtick(text, index + 1, mask=True)
            out.append(f"`{content}`")
            index = end
            continue
        out.append(char)
        index += 1
    return "".join(out)


def _strip_shell_comment(value: str) -> str:
    quote: str | None = None
    escaped = False
    for index, char in enumerate(value):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in {"'", '"'}:
            quote = char
        elif char == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index]
    return value


def source_executables(path: str, text: str, pinned_text: str = "") -> list[dict[str, object]]:
    """Discover command names and source-line identity from a supported file."""

    references: list[dict[str, object]] = []
    dynamic_name = DYNAMIC_EXECUTABLE
    pinned_lines = pinned_text.splitlines()
    pinned_shape_counts = Counter(" ".join(line.split()) for line in pinned_lines)
    shell_functions = {
        match.group(1)
        for match in re.finditer(
            r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{",
            text,
            re.MULTILINE,
        )
    }

    allowed_dynamic_shapes = {
            ("shell/plugins/panels/network/Panel.qml", 'command: ["bash", "-c", root.dnsCommand("")]'),
            ("shell/plugins/panels/network/Panel.qml", 'actionProc.command = ["bash", "-c", root.dnsCommand(provider)]'),
            ("shell/plugins/menu/Menu.qml", 'providerProc.command = ["bash", "-lc", spec.script]'),
            ("shell/plugins/menu/Menu.qml", 'guardProc.command = ["bash", "-lc", script]'),
            ("shell/plugins/menu/Menu.qml", 'resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]'),
            ("shell/plugins/menu/Menu.qml", 'resultProc.command = ["bash", "-c", "printf \'%s\\\\n\' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]'),
            ("shell/plugins/menu/Menu.qml", 'Util.execDetached(command)'),
            ("shell/plugins/panels/network/Panel.qml", 'enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]'),
            ("shell/services/AppLibrary.qml", 'command: ["bash", "-c", root.userOwnedEntryScanCommand()]'),
            ("shell/services/AppLibrary.qml", 'command: ["bash", "-c", root.hiddenEntryScanCommand()]'),
            ("shell/services/AppLibrary.qml", 'command: ["bash", "-c", root.iconIndexScanCommand()]'),
            ("shell/services/PluginRegistry.qml", 'scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]'),
            ("shell/plugins/bar/Bar.qml", 'command: ["bash", "-lc", String(customRoot.setting("exec", ""))]'),
            ("shell/plugins/bar/Bar.qml", 'customProc.command = ["bash", "-lc", String(customRoot.setting("exec", ""))]'),
            ("shell/plugins/bar/Bar.qml", 'transparentForegroundProc.command = ['),
            ("shell/Ui/MultiSelect.qml", 'optionsProcess.command = cmd'),
            ("shell/services/AppLibrary.qml", 'if (command) Util.execDetached(command)'),
            ("shell/services/AppLibrary.qml", 'Util.execDetached(command)'),
            ("shell/services/AppLibrary.qml", 'removeProcess.command = ['),
            ("shell/plugins/bar/Bar.qml", 'if (command) root.run(command)'),
            ("shell/plugins/bar/Bar.qml", 'Util.execDetached(command)'),
            ("shell/Commons/Util.qml", 'Quickshell.execDetached(["bash", "-lc", command])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])'),
            ("shell/plugins/clipboard/Clipboard.qml", 'command: [root.captureScript]'),
            ("shell/plugins/clipboard/Clipboard.qml", 'command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]'),
            ("shell/plugins/clipboard/Clipboard.qml", 'command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]'),
            ("shell/plugins/emojis/Emojis.qml", 'Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", emoji])'),
    }
    allowed_dynamic_used: Counter[tuple[str, str]] = Counter()

    def add(name: str, line: int, invocation: str, shape: str) -> None:
        normalized_shape = " ".join(shape.split())
        dynamic_key = (path, normalized_shape)
        pinned_identity = normalized_shape in pinned_shape_counts
        if (
            name == dynamic_name
            and (dynamic_key in allowed_dynamic_shapes or pinned_identity)
            and allowed_dynamic_used[dynamic_key]
            < (pinned_shape_counts[normalized_shape] if pinned_identity else 1)
        ):
            allowed_dynamic_used[dynamic_key] += 1
            return
        if name.startswith("/"):
            name = name.rsplit("/", 1)[-1]
        if (
            not name
            or name in SHELL_BUILTINS
            or name in shell_functions
            or name.startswith(("$", "omarchy-"))
        ):
            return
        references.append({"name": name, "line": line, "invocation": invocation, "shape": shape.strip()})

    def literal_array_values(value: str) -> list[str]:
        values = []
        for match in re.finditer(r"(['\"])(.*?)(?<!\\)\1", value, re.DOTALL):
            try:
                values.append(ast.literal_eval(match.group(0)))
            except (SyntaxError, ValueError):
                continue
        return values

    def array_has_dynamic_elements(value: str) -> bool:
        remainder = re.sub(r"(['\"])(.*?)(?<!\\)\1", "", value, flags=re.DOTALL)
        return any(part.strip() for part in remainder.split(","))

    def literal_shell_payload(value: str) -> str | None:
        match = re.match(
            r"\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*,\s*"
            r"(['\"])((?:\\.|(?!\3).)*?)\3",
            value,
            re.DOTALL,
        )
        if not match or not match.group(1).rsplit("/", 1)[-1] in {"bash", "dash", "sh", "zsh"}:
            return None
        if not match.group(2).startswith("-") or "c" not in match.group(2):
            return None
        return match.group(4)

    for line_number, line in enumerate(text.splitlines(), 1):
        if path.endswith((".sh", ".bash")):
            command_line = line
            function_body = re.match(r"^\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\s*\)\s*\{", line)
            if function_body:
                command_line = line[function_body.end() :]
            else:
                case_arm = re.match(r"^\s*[^;&]+\)\s*", line)
                if case_arm:
                    command_line = line[case_arm.end() :]
            for name in shell_executables(command_line):
                add(name, line_number, "shell-script", line)
            for match in COMMAND_SUBSHELL_RE.finditer(line):
                for name in shell_executables(match.group(1)):
                    add(name, line_number, "shell-substitution", line)
            for match in PROCESS_SUBSHELL_RE.finditer(line):
                for name in shell_executables(match.group(1)):
                    add(name, line_number, "process-substitution", line)

    for match in ARRAY_COMMAND_RE.finditer(text):
        line_number = text.count("\n", 0, match.start()) + 1
        source_line = text.splitlines()[line_number - 1]
        values = literal_array_values(match.group(1))
        if not values:
            if match.group(1).strip():
                add(dynamic_name, line_number, "command-array", source_line)
            continue
        if array_has_dynamic_elements(match.group(1)):
            add(dynamic_name, line_number, "command-array", source_line)
            continue
        add(values[0], line_number, "command-array", source_line)
        executable = values[0].rsplit("/", 1)[-1]
        if executable in {"bash", "dash", "sh", "zsh", "command", "builtin", "exec", "env", "timeout"}:
            array_command = " ".join(shlex.quote(value) for value in values)
            for name in shell_executables(array_command):
                add(name, line_number, "command-array-shell", source_line)
        payload = literal_shell_payload(match.group(1))
        if payload is not None:
            for name in shell_executables(payload):
                add(name, line_number, "command-array-shell", source_line)
        elif (
            re.match(
                r"\s*(?:(?:[A-Za-z_][A-Za-z0-9_]*\.)?command\s*[:=]|"
                r"(?:Quickshell|Util)\.exec(?:Detached)?\s*\()",
                match.group(0),
            )
            and re.search(
            r"['\"](?:[^'\"]*/)?(?:bash|dash|sh|zsh)['\"]\s*,\s*"
            r"['\"][^'\"]*c[^'\"]*['\"]\s*,\s*(?!['\"])",
            match.group(1),
            )
        ):
            add(dynamic_name, line_number, "command-array-shell", source_line)

    for pattern in (DYNAMIC_COMMAND_RE, DYNAMIC_SCRIPT_RE):
        for match in pattern.finditer(text):
            line_number = text.count("\n", 0, match.start()) + 1
            source_line = text.splitlines()[line_number - 1]
            add(dynamic_name, line_number, "dynamic-command", source_line)

    for pattern in (DYNAMIC_ASSIGNMENT_RE, DYNAMIC_CALL_RE, DYNAMIC_RUN_RE):
        for match in pattern.finditer(text):
            line_number = text.count("\n", 0, match.start()) + 1
            source_line = text.splitlines()[line_number - 1]
            add(dynamic_name, line_number, "dynamic-invocation", source_line)

    for match in SHELL_PAYLOAD_RE.finditer(text):
        line_number = text.count("\n", 0, match.start()) + 1
        source_line = text.splitlines()[line_number - 1]
        for name in shell_executables(match.group(2)):
            add(name, line_number, "shell-payload", source_line)

    for match in SHELL_STRING_RE.finditer(text):
        line_number = text.count("\n", 0, match.start()) + 1
        source_line = text.splitlines()[line_number - 1]
        for name in shell_executables(match.group(2)):
            add(name, line_number, "shell-string", source_line)

    unique: dict[tuple[str, int, str], dict[str, object]] = {}
    for reference in references:
        key = (str(reference["name"]), int(reference["line"]), str(reference["invocation"]))
        unique[key] = reference
    return [unique[key] for key in sorted(unique)]

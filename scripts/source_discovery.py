"""Discover literal executable invocations from supported Quattro sources."""

from __future__ import annotations

import ast
import re
import shlex


SHELL_BUILTINS = {
    "!",
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
    "elif",
    "else",
    "exec",
    "esac",
    "eval",
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
    r"(?:^\s*|[;&|]|<\s*<\()([A-Za-z][A-Za-z0-9_.+-]*)"
)
COMMAND_SUBSHELL_RE = re.compile(r"\$\(([^()]*)\)")
PROCESS_SUBSHELL_RE = re.compile(r"<\s*<\(([^()]*)\)")
ARRAY_COMMAND_RE = re.compile(
    r"(?:\bcommand\s*[:=]|(?:Quickshell|Util)\.exec(?:Detached)?\s*\()\s*"
    r"\[([^\]]*)\]",
    re.DOTALL,
)
SHELL_PAYLOAD_RE = re.compile(
    r"\b(?:command|script)\s*:\s*([\"'])(.*?)(?<!\\)\1",
    re.DOTALL,
)
SHELL_STRING_RE = re.compile(
    r"(?:\bbar\.run|(?:Quickshell|Util)\.exec(?:Detached)?)\(\s*"
    r"([\"'])(.*?)(?<!\\)\1",
    re.DOTALL,
)


def _next_command(words: list[str], start: int) -> list[str]:
    result: list[str] = []
    for word in words[start:]:
        if word.startswith("-"):
            continue
        if word.startswith("$") or "=" in word and word.split("=", 1)[0].isidentifier():
            continue
        if word in SHELL_BUILTINS:
            continue
        result.append(word)
        break
    return result


def shell_executables(value: str) -> list[str]:
    """Return literal command names from a shell command string."""

    commands: list[str] = []
    for match in COMMAND_SUBSHELL_RE.finditer(value):
        commands.extend(shell_executables(match.group(1)))
    for part in re.split(r"(?:&&|\|\||[;&|])", value):
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
            continue
        if first in {"command", "builtin"}:
            commands.extend(_next_command(words, 1))
        elif first == "timeout":
            commands.append(first)
            commands.extend(_next_command(words, 2))
        elif first == "env":
            commands.append(first)
            commands.extend(_next_command(words, 1))
        elif first.startswith("$") or "=" in first and first.split("=", 1)[0].isidentifier():
            if "$(" not in first:
                commands.extend(_next_command(words, 1))
        elif first not in SHELL_BUILTINS and not first.startswith(("/", "-")):
            commands.append(first)
    return list(dict.fromkeys(commands))


def source_executables(path: str, text: str) -> list[dict[str, object]]:
    """Discover command names and source-line identity from a supported file."""

    references: list[dict[str, object]] = []

    def add(name: str, line: int, invocation: str, shape: str) -> None:
        if not name or name in SHELL_BUILTINS or name.startswith(("/", "$", "omarchy-")):
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
            command_line = re.sub(r"^\s*[A-Za-z_][A-Za-z0-9_]*(?:\[[^]]+\])?=", "", line)
            if re.match(r"^\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{", line):
                command_line = ""
            if re.match(r"^\s*[^;&]+\)\s+", line):
                command_line = ""
            if re.match(r"^\s*[^;&]+\)\s*$", line):
                command_line = ""
            for match in SHELL_COMMAND_RE.finditer(command_line):
                for name in shell_executables(match.group(1)):
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
            continue
        add(values[0], line_number, "command-array", source_line)
        payload = literal_shell_payload(match.group(1))
        if payload is not None:
            for name in shell_executables(payload):
                add(name, line_number, "command-array-shell", source_line)

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

    function_names = {
        match.group(1)
        for match in re.finditer(
            r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\s*\))?\s*\{", text, re.MULTILINE
        )
    }
    references = [reference for reference in references if reference["name"] not in function_names]
    unique: dict[tuple[str, int, str], dict[str, object]] = {}
    for reference in references:
        key = (str(reference["name"]), int(reference["line"]), str(reference["invocation"]))
        unique[key] = reference
    return [unique[key] for key in sorted(unique)]

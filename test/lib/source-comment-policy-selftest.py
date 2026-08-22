#!/usr/bin/env python3
import ast
import contextlib
import io
import sys
import tempfile
from pathlib import Path

policy_path = Path(sys.argv[1])

ns = {}
with open(policy_path, encoding="utf-8") as f:
    exec(compile(f.read(), str(policy_path), "exec"), ns)

classify_language = ns["classify_language"]
discover_source_files = ns["discover_source_files"]
Violation = ns["Violation"]
DIRECTIVE_GRAMMARS = ns["DIRECTIVE_GRAMMARS"]
match_directive = ns["match_directive"]
is_shebang_line = ns["is_shebang_line"]
SHEBANG_PATTERN = ns["SHEBANG_PATTERN"]
SHELLCHECK_DISABLE_PATTERN = ns["SHELLCHECK_DISABLE_PATTERN"]
scan_python = ns["scan_python"]
_docstring_owning_nodes = ns["_docstring_owning_nodes"]
_leading_string_expr = ns["_leading_string_expr"]
PythonEmbeddedStringError = ns["PythonEmbeddedStringError"]
PYTHON_EMBEDDED_QML_ASSIGNMENTS = ns["PYTHON_EMBEDDED_QML_ASSIGNMENTS"]
PYTHON_PINNED_DATA_ASSIGNMENTS = ns["PYTHON_PINNED_DATA_ASSIGNMENTS"]
PYTHON_EMBEDDED_ASSIGNMENT_FILES = ns["PYTHON_EMBEDDED_ASSIGNMENT_FILES"]
_top_level_string_assignments = ns["_top_level_string_assignments"]
_is_triple_quoted = ns["_is_triple_quoted"]
_looks_like_source_code = ns["_looks_like_source_code"]
_scan_embedded_python_string = ns["_scan_embedded_python_string"]
_scan_python_embedded_assignments = ns["_scan_python_embedded_assignments"]
scan_shell = ns["scan_shell"]
ShellLexError = ns["ShellLexError"]
_ShellLexer = ns["_ShellLexer"]
scan_nix = ns["scan_nix"]
NixLexError = ns["NixLexError"]
BINDING_NAME_PATTERN = ns["BINDING_NAME_PATTERN"]
CALL_HEAD_PATTERN = ns["CALL_HEAD_PATTERN"]
WRITETEXT_NAME_PATTERN = ns["WRITETEXT_NAME_PATTERN"]
EMBEDDED_CODE_BINDING_NAMES = ns["EMBEDDED_CODE_BINDING_NAMES"]
AMBIGUOUS_CODE_SHAPED_BINDING_NAMES = ns["AMBIGUOUS_CODE_SHAPED_BINDING_NAMES"]
SHELL_APPLICATION_TEXT_CONTEXT_PATTERN = ns["SHELL_APPLICATION_TEXT_CONTEXT_PATTERN"]
PRIORITY_WRAPPER_PATTERN = ns["PRIORITY_WRAPPER_PATTERN"]
EMBEDDED_CODE_CALL_HEADS = ns["EMBEDDED_CODE_CALL_HEADS"]
EMBEDDED_LANGUAGE_SCANNERS = ns["EMBEDDED_LANGUAGE_SCANNERS"]
_lookback_context = ns["_lookback_context"]
_is_nix_code_shaped_context = ns["_is_nix_code_shaped_context"]
classify_nix_string_binding = ns["classify_nix_string_binding"]
classify_write_text_by_name = ns["classify_write_text_by_name"]
_dedent_nix_indented_string = ns["_dedent_nix_indented_string"]
_scan_embedded_nix_string = ns["_scan_embedded_nix_string"]
scan_js = ns["scan_js"]
JsLexError = ns["JsLexError"]
scan_yaml = ns["scan_yaml"]
YamlLexError = ns["YamlLexError"]
scan_toml = ns["scan_toml"]
TomlLexError = ns["TomlLexError"]
SCANNERS = ns["SCANNERS"]
main = ns["main"]


def _kinds(violations):
    return {v.kind for v in violations}


def test_classify_language_by_extension():
    assert classify_language(Path("x/y.py"), Path("x")) == "python"
    assert classify_language(Path("x/y.nix"), Path("x")) == "nix"
    assert classify_language(Path("x/y.unknownext"), Path("x")) == "unsupported"


def test_classify_language_by_shebang():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        script = tmp_path / "myscript"
        script.write_text("#!/usr/bin/env python3\npass\n")
        assert classify_language(script, tmp_path) == "python"


def test_classify_language_excludes_generated_lock():
    assert classify_language(Path("x/flake.lock"), Path("x")) is None


def test_discover_skips_git_directory():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / ".git").mkdir()
        (tmp_path / ".git" / "config").write_text("data")
        (tmp_path / "real.py").write_text("pass\n")
        found = discover_source_files(tmp_path)
        assert found == [tmp_path / "real.py"]


def test_classify_language_rejects_malformed_shebang():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        script = tmp_path / "malformed"
        script.write_text("#!/\n")
        assert classify_language(script, tmp_path) == "unsupported"


def test_shellcheck_bare_directive_allowed():
    assert match_directive("shell", "# shellcheck disable=SC2154")


def test_shellcheck_directive_with_trailing_prose_rejected():
    assert not match_directive(
        "shell", "# shellcheck disable=SC2154 # shared adapter state"
    )


def test_shellcheck_multi_code_directive_allowed():
    assert match_directive("shell", "# shellcheck disable=SC2154,SC2034")


def test_arbitrary_suppression_directive_rejected():
    assert not match_directive("shell", "# comment-policy: ignore")
    assert not match_directive("python", "# noqa")
    assert not match_directive("js", "// commentlint-disable")


def test_shebang_only_valid_at_line_one_col_zero():
    assert is_shebang_line("shell", 1, 0, "#!/usr/bin/env bash")
    assert not is_shebang_line("shell", 2, 0, "#!/usr/bin/env bash")
    assert not is_shebang_line("shell", 1, 4, "    #!/usr/bin/env bash")


def test_unsupported_extension_fails_closed():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / "weird.xyz").write_text("data\n")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = main(["prog", str(tmp_path)])
        captured = output.getvalue()
        assert exit_code == 1
        assert "unsupported maintained source language" in captured
        assert "weird.xyz" in captured


def test_clean_tree_exits_zero():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / "clean.py").write_text("x = 1\n")
        assert main(["prog", str(tmp_path)]) == 0


def test_markdown_never_scanned():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / "NOTES.md").write_text("# heading\nprose with // and /* */\n")
        assert main(["prog", str(tmp_path)]) == 0


def test_python_line_comment_rejected():
    assert _kinds(scan_python(Path("x.py"), "x = 1\n# a comment\n")) == {"narrative-comment"}


def test_python_trailing_comment_rejected():
    assert _kinds(scan_python(Path("x.py"), "x = 1  # trailing\n")) == {"narrative-comment"}


def test_python_module_docstring_rejected():
    assert _kinds(scan_python(Path("x.py"), '"""module doc."""\nx = 1\n')) == {"docstring"}


def test_python_class_docstring_rejected():
    src = 'class Foo:\n    """doc."""\n    pass\n'
    assert _kinds(scan_python(Path("x.py"), src)) == {"docstring"}


def test_python_function_docstring_rejected():
    src = 'def foo():\n    """doc."""\n    return 1\n'
    assert _kinds(scan_python(Path("x.py"), src)) == {"docstring"}


def test_python_hash_inside_string_accepted():
    assert scan_python(Path("x.py"), 'x = "# not a comment"\n') == []


def test_python_triple_quoted_non_docstring_accepted():
    src = 'def foo():\n    x = 1\n    y = """data, not a docstring"""\n    return y\n'
    assert scan_python(Path("x.py"), src) == []


def test_python_shebang_accepted():
    src = "#!/usr/bin/env python3\nx = 1\n"
    assert scan_python(Path("x.py"), src) == []


def test_python_directive_allowlist_empty():
    assert _kinds(scan_python(Path("x.py"), "x = 1  # type: ignore\n")) == {"narrative-comment"}


def test_python_no_directive_plus_trailing_prose_exception():
    assert _kinds(scan_python(Path("x.py"), "x = 1  # noqa: explanation\n")) == {"narrative-comment"}


def test_python_nested_method_docstring_rejected():
    src = 'class Foo:\n    def bar(self):\n        """method doc."""\n        return 1\n'
    violations = scan_python(Path("x.py"), src)
    assert len(violations) == 1
    assert _kinds(violations) == {"docstring"}


def test_shell_ordinary_comment_rejected():
    assert _kinds(scan_shell(Path("x.sh"), "x=1\n# comment\n")) == {"narrative-comment"}


def test_shell_trailing_comment_rejected():
    assert _kinds(scan_shell(Path("x.sh"), "x=1  # trailing\n")) == {"narrative-comment"}


def test_shell_shebang_accepted():
    assert scan_shell(Path("x.sh"), "#!/usr/bin/env bash\nx=1\n") == []


def test_shell_allowed_shellcheck_directive_accepted():
    assert scan_shell(Path("x.sh"), "# shellcheck disable=SC2154\nx=1\n") == []


def test_shell_shellcheck_directive_with_trailing_prose_rejected():
    src = "# shellcheck disable=SC2154 # shared state\nx=1\n"
    assert _kinds(scan_shell(Path("x.sh"), src)) == {"narrative-comment"}


def test_shell_param_prefix_removal_accepted():
    assert scan_shell(Path("x.sh"), 'y="${x#prefix}"\n') == []


def test_shell_bare_mid_word_hash_is_not_comment():
    assert scan_shell(Path("x.sh"), "echo foo#bar\n") == []


def test_shell_param_double_prefix_removal_accepted():
    assert scan_shell(Path("x.sh"), 'y="${x##prefix}"\n') == []


def test_shell_hash_in_single_quotes_accepted():
    assert scan_shell(Path("x.sh"), "y='# not a comment'\n") == []


def test_shell_hash_in_double_quotes_accepted():
    assert scan_shell(Path("x.sh"), 'y="# not a comment"\n') == []


def test_shell_malformed_unterminated_quote_fails_closed():
    try:
        scan_shell(Path("x.sh"), "y='unterminated\n")
    except ShellLexError:
        pass
    else:
        raise AssertionError("expected ShellLexError")


def test_shell_arith_inside_dquote_with_shift_accepted():
    assert scan_shell(Path("x.sh"), 'y="$((1 << 4))"\n') == []


def test_shell_arith_inside_dquote_does_not_leak_heredoc_state():
    src = 'y="$((1 << 4))"\n# real comment\n'
    assert _kinds(scan_shell(Path("x.sh"), src)) == {"narrative-comment"}


def test_shell_arith_inside_paramexp_accepted():
    assert scan_shell(Path("x.sh"), 'y="${x:-$((1+1))}"\n') == []


def test_shell_nested_cmdsub_accepted():
    lexer = _ShellLexer(Path("x.sh"), "x=$(echo $(echo hi))\n")
    violations = lexer.run()
    assert violations == []
    assert lexer.stack == ["NORMAL"]


def test_shell_case_pattern_paren_does_not_close_cmdsub():
    src = "x=$(case $y in a) echo hi;; esac\n"
    try:
        scan_shell(Path("x.sh"), src)
    except ShellLexError:
        pass
    else:
        raise AssertionError("expected ShellLexError")


def test_shell_case_pattern_leading_paren_does_not_leak_cmdsub_depth():
    src = "x=$(case $y in (a) echo hi;; esac)\n"
    assert scan_shell(Path("x.sh"), src) == []


def test_shell_heredoc_hash_is_data():
    src = "cat <<EOF\n# not a comment\nEOF\n"
    assert scan_shell(Path("x.sh"), src) == []


def test_shell_heredoc_quoted_delimiter_hash_is_data():
    src = "cat <<'EOF'\n# not a comment\nEOF\n"
    assert scan_shell(Path("x.sh"), src) == []


def test_shell_heredoc_dash_strips_tabs_for_delimiter_match():
    src = "cat <<-EOF\n\ttext\n\tEOF\n"
    assert scan_shell(Path("x.sh"), src) == []


def test_shell_unterminated_heredoc_fails_closed():
    try:
        scan_shell(Path("x.sh"), "cat <<EOF\nno terminator\n")
    except ShellLexError:
        pass
    else:
        raise AssertionError("expected ShellLexError")


def test_shell_arithmetic_hash_not_flagged_as_comment():
    assert scan_shell(Path("x.sh"), "y=$((1))\n") == []


def test_shell_backtick_command_sub_comment_rejected():
    src = "y=`echo hi # comment\n`\n"
    assert _kinds(scan_shell(Path("x.sh"), src)) == {"narrative-comment"}


def test_shell_dollar_paren_command_sub_comment_rejected():
    src = "y=$(echo hi # comment\n)\n"
    assert _kinds(scan_shell(Path("x.sh"), src)) == {"narrative-comment"}


def test_nix_line_comment_rejected():
    assert _kinds(scan_nix(Path("x.nix"), "{ }\n# comment\n")) == {"narrative-comment"}


def test_nix_block_comment_rejected():
    assert _kinds(scan_nix(Path("x.nix"), "{ /* comment */ }\n")) == {"narrative-comment"}


def test_nix_hash_inside_normal_string_accepted():
    assert scan_nix(Path("x.nix"), '{ x = "# not a comment"; }\n') == []


def test_nix_hash_inside_indented_string_data_accepted():
    assert scan_nix(Path("x.nix"), "{ x = ''\n# not a comment\n''; }\n") == []


def test_nix_comment_inside_interpolation_rejected():
    src = '{ x = "${ # comment\n builtins.toString 1 }"; }\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_unterminated_block_comment_fails_closed():
    try:
        scan_nix(Path("x.nix"), "{ /* unterminated\n")
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_comment_inside_indented_string_interpolation_rejected():
    src = "{ x = ''some ${ /* real comment */ 1 } text''; }\n"
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_indented_string_escaped_dollar_brace_accepted():
    src = "{ x = ''a''\\${b''; }\n"
    try:
        assert scan_nix(Path("x.nix"), src) == []
    except NixLexError as e:
        raise AssertionError(f"unexpected NixLexError: {e}")


def test_nix_hash_after_escaped_dollar_brace_accepted():
    src = "{ x = ''a''\\${# not a comment\nmore}''; }\n"
    assert scan_nix(Path("x.nix"), src) == []


def test_nix_executable_writeshellscript_comment_rejected():
    src = 'x = pkgs.writeShellScript "n" \'\'\n# narrative\necho hi\n\'\';\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_executable_runcommand_comment_rejected():
    src = 'x = pkgs.runCommand "n" { } \'\'\n# narrative\ntouch $out\n\'\';\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_install_phase_comment_rejected():
    src = 'x = stdenv.mkDerivation { installPhase = \'\'\n# narrative\nmkdir -p "$out"\n\'\'; };\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_writeshellapplication_text_binding_comment_rejected():
    src = 'x = pkgs.writeShellApplication { name = "n"; text = \'\'\n# narrative\necho hi\n\'\'; };\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_writetext_shell_suffix_recurses_and_rejects():
    src = 'x = pkgs.writeText "script.sh" \'\'\n# narrative\necho hi\n\'\';\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_writetext_non_source_suffix_is_data():
    src = 'x = pkgs.writeText "unit.service" \'\'\n# not a comment, systemd data\n\'\';\n'
    assert scan_nix(Path("x.nix"), src) == []


def test_nix_plain_binding_indented_string_is_data():
    src = 'x = \'\'\n# not a comment, ordinary data string\n\'\';\n'
    assert scan_nix(Path("x.nix"), src) == []


def test_nix_build_phase_binding_classifies_as_shell():
    src = 'buildPhase = \'\'\n# ambiguous, must fail closed if classifier is bypassed\necho hi\n\'\';\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_unregistered_binding_name_treated_as_data():
    src = 'someWeirdNewBuilderScriptBody = \'\'\n#!/bin/sh\necho hi\n\'\';\n'
    assert scan_nix(Path("x.nix"), src) == []


def test_nix_call_head_lookback_prefers_nearest_enclosing():
    src = 'x = pkgs.runCommand "n" (pkgs.writeShellScript "m" "unused") \'\'\n# narrative\n\'\';\n'
    assert _kinds(scan_nix(Path("x.nix"), src)) == {"narrative-comment"}


def test_nix_ambiguous_text_binding_outside_shell_application_fails_closed():
    src = (
        'x = { security.pam.services."omarchy-lock-password".text = \'\'\n'
        '    auth sufficient pam_permit.so\n'
        '\'\'; };\n'
    )
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_real_pam_service_text_binding_fails_closed():
    src = (
        '{ config, ... }:\n'
        '{\n'
        '  security.pam.services."omarchy-lock-password".text = \'\'\n'
        '    auth sufficient ${config.security.pam.package}/lib/security/pam_permit.so\n'
        '  \'\';\n'
        '}\n'
    )
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_ambiguous_text_binding_wrapped_in_mkforce_fails_closed():
    src = (
        'x = { security.pam.services."omarchy-lock-password".text = lib.mkForce \'\'\n'
        '    auth sufficient pam_permit.so\n'
        '\'\'; };\n'
    )
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_real_pam_service_text_binding_wrapped_in_mkforce_fails_closed():
    src = (
        '{ config, lib, ... }:\n'
        '{\n'
        '  security.pam.services."omarchy-lock-fingerprint".text = lib.mkForce \'\'\n'
        '    auth sufficient ${config.security.pam.package}/lib/security/pam_permit.so\n'
        '  \'\';\n'
        '}\n'
    )
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_text_binding_wrapped_in_mkdefault_fails_closed():
    src = 'x = { foo.text = lib.mkDefault \'\'\n# ambiguous\ndata\n\'\'; };\n'
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_nix_text_binding_wrapped_in_mkoverride_fails_closed():
    src = 'x = { foo.text = lib.mkOverride 100 \'\'\n# ambiguous\ndata\n\'\'; };\n'
    try:
        scan_nix(Path("x.nix"), src)
    except NixLexError:
        pass
    else:
        raise AssertionError("expected NixLexError")


def test_js_line_comment_rejected():
    assert _kinds(scan_js(Path("x.js"), "x = 1;\n// c\n")) == {"narrative-comment"}


def test_js_block_comment_rejected():
    assert _kinds(scan_js(Path("x.js"), "/* c */\nx = 1;\n")) == {"narrative-comment"}


def test_js_url_string_accepted():
    assert scan_js(Path("x.js"), 'x = "https://example.com";\n') == []


def test_js_regex_escaped_slash_accepted():
    assert scan_js(Path("x.js"), "x = /https?:\\/\\//;\n") == []


def test_js_template_raw_comment_like_text_accepted():
    assert scan_js(Path("x.js"), "x = `# text // not a comment`;\n") == []


def test_js_real_comment_inside_template_interpolation_rejected():
    src = "x = `${ // real comment\n 1 }`;\n"
    assert _kinds(scan_js(Path("x.js"), src)) == {"narrative-comment"}


def test_js_multiline_block_comment_rejected():
    assert _kinds(scan_js(Path("x.js"), "/*\nmultiline\n*/\nx = 1;\n")) == {"narrative-comment"}


def test_qml_dispatches_to_js_scanner():
    assert SCANNERS["qml"] is scan_js


def test_js_division_after_value_keyword_accepted():
    assert scan_js(Path("x.js"), "x = this / 2;\n") == []


def test_js_regex_after_return_keyword_accepted():
    assert scan_js(Path("x.js"), "function f() { return /pattern/; }\n") == []


def test_js_unterminated_regex_literal_fails_closed():
    try:
        scan_js(Path("x.js"), "x = /abc\n")
    except JsLexError:
        pass
    else:
        raise AssertionError("expected JsLexError")


def test_js_unterminated_template_literal_fails_closed():
    try:
        scan_js(Path("x.js"), "x = `abc\n")
    except JsLexError:
        pass
    else:
        raise AssertionError("expected JsLexError")


def test_js_regex_char_class_inside_template_interpolation_accepted():
    src = "x = `${ /[/*]/.test(y) }`;\n"
    assert scan_js(Path("x.js"), src) == []


def test_js_property_access_named_return_accepted():
    assert scan_js(Path("x.js"), "x = obj.return / 2;\n") == []


def test_js_property_access_named_in_accepted():
    assert scan_js(Path("x.js"), "x = obj.in / 2;\n") == []


def test_js_contextual_keyword_of_as_bare_identifier_known_limitation():
    src = "var of = 10;\nx = of / 10;\n"
    try:
        scan_js(Path("x.js"), src)
    except JsLexError:
        pass
    else:
        raise AssertionError("expected JsLexError (documented known limitation)")


def test_python_embedded_qml_assignment_recognized_and_not_fail_closed():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        scripts_dir = tmp_path / "scripts"
        scripts_dir.mkdir()
        script_path = scripts_dir / "generate-postpatch-runtime-surface"
        src = 'HEADLESS_KEYBOARD_PANEL = """\nimport QtQuick\nItem {}\n"""\n'
        script_path.write_text(src)
        assert scan_python(script_path, src, root=tmp_path) == []


def test_python_unregistered_code_shaped_assignment_fails_closed():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        scripts_dir = tmp_path / "scripts"
        scripts_dir.mkdir()
        script_path = scripts_dir / "generate-postpatch-runtime-surface"
        src = 'SOME_OTHER_EMBEDDED_THING = """\nimport os\nos.system("x")\n"""\n'
        script_path.write_text(src)
        try:
            scan_python(script_path, src, root=tmp_path)
        except PythonEmbeddedStringError:
            pass
        else:
            raise AssertionError("expected PythonEmbeddedStringError")


def test_python_code_shaped_assignment_without_root_not_scanned():
    src = 'X = """\nimport os\n"""\n'
    assert scan_python(Path("x.py"), src) == []


def test_python_unregistered_assignment_not_on_line_one_fails_closed():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        scripts_dir = tmp_path / "scripts"
        scripts_dir.mkdir()
        script_path = scripts_dir / "generate-postpatch-runtime-surface"
        src = (
            'import sys\n'
            '\n'
            'HEADLESS_KEYBOARD_PANEL = """\nimport QtQuick\nItem {}\n"""\n'
            '\n'
            'SOME_OTHER_EMBEDDED_THING = """\n'
            'import os\n'
            'os.system("x")\n'
            '"""\n'
        )
        script_path.write_text(src)
        try:
            scan_python(script_path, src, root=tmp_path)
        except PythonEmbeddedStringError:
            pass
        else:
            raise AssertionError("expected PythonEmbeddedStringError")


def test_python_is_triple_quoted_uses_correct_line_not_absolute_offset():
    src = 'x = 1\ny = 2\nZ = """\nimport os\n"""\n'
    tree = ast.parse(src)
    assignments = dict(_top_level_string_assignments(tree))
    assert _is_triple_quoted(src, assignments["Z"].value)
    assert not _is_triple_quoted(src, assignments["x"].value)


def test_python_unregistered_source_files_not_scanned_even_when_code_shaped():
    real_unrelated_files = {
        "scripts/patch-menu-font-provider": (
            'FONT_PROVIDER = \'\'\'    "fonts": {\n'
            '      script: "current=$(omarchy-font-current)",\n'
            '      actionFor: function(value) { return value }\n'
            '    },\n'
            "'''\n"
        ),
        "scripts/patch-menu-power-provider": (
            'POWER_PROVIDER = \'\'\'    "power-profiles": {\n'
            '      script: "current=$(powerprofilesctl get)",\n'
            '      actionFor: function(value) { return value }\n'
            '    }\n'
            "'''\n"
        ),
        "scripts/patch-transparent-foreground-process": (
            "import sys\n"
            "\n"
            "EXPECTED = '''  Process {\n"
            "    id: transparentForegroundProc\n"
            "  }\n"
            "'''\n"
            "\n"
            "EXPECTED_REFRESH = '''  function refreshTransparentForeground() {\n"
            "    return\n"
            "  }'''\n"
        ),
    }
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        for rel_path, src in real_unrelated_files.items():
            script_path = tmp_path / rel_path
            script_path.parent.mkdir(parents=True, exist_ok=True)
            script_path.write_text(src)
            assert scan_python(script_path, src, root=tmp_path) == []


def test_python_pinned_dict_shaped_assignment_does_not_crash():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        scripts_dir = tmp_path / "scripts"
        scripts_dir.mkdir()
        script_path = scripts_dir / "generate-postpatch-runtime-surface"
        src = (
            'HEADLESS_SOURCE_PATCHES = {\n'
            '    "h": (\n'
            '        """function foo() {}""",\n'
            '        """function bar() {}""",\n'
            '    ),\n'
            '}\n'
        )
        script_path.write_text(src)
        assert scan_python(script_path, src, root=tmp_path) == []


def test_docstring_owning_nodes_cover_all_four_kinds():
    src = (
        '"""m."""\n'
        'class C:\n'
        '    """c."""\n'
        '    def f(self):\n'
        '        """f."""\n'
        'async def g():\n'
        '    """g."""\n'
    )
    tree = ast.parse(src)
    owners = list(_docstring_owning_nodes(tree))
    kinds = {type(n).__name__ for n in owners}
    assert kinds == {"Module", "ClassDef", "FunctionDef", "AsyncFunctionDef"}


def test_yaml_real_comment_rejected():
    assert _kinds(scan_yaml(Path("x.yaml"), "key: value\n# comment\n")) == {"narrative-comment"}


def test_yaml_quoted_hash_accepted():
    assert scan_yaml(Path("x.yaml"), 'key: "# not a comment"\n') == []


def test_yaml_block_scalar_hash_is_data():
    src = "key: |\n  # not a comment\n  more data\nother: 1\n"
    assert scan_yaml(Path("x.yaml"), src) == []


def test_yaml_folded_block_scalar_hash_is_data():
    src = "key: >\n  # not a comment\nother: 1\n"
    assert scan_yaml(Path("x.yaml"), src) == []


def test_yaml_trailing_comment_after_value_rejected():
    assert _kinds(scan_yaml(Path("x.yaml"), "key: value  # trailing\n")) == {"narrative-comment"}


def test_yaml_hash_mid_word_not_comment_delimited():
    assert scan_yaml(Path("x.yaml"), "key: issue#4\n") == []


def test_yaml_single_quoted_hash_accepted():
    assert scan_yaml(Path("x.yaml"), "key: '# not a comment'\n") == []


def test_yaml_single_quoted_doubled_quote_escape_accepted():
    assert scan_yaml(Path("x.yaml"), "key: 'it''s # not a comment'\n") == []


def test_yaml_multiline_dquote_hash_before_close_not_comment():
    src = 'key: "line one\nline two # not a comment"\nother: 1\n'
    assert scan_yaml(Path("x.yaml"), src) == []


def test_yaml_multiline_squote_hash_before_close_not_comment():
    src = "key: 'line one\nline two # not a comment'\nother: 1\n"
    assert scan_yaml(Path("x.yaml"), src) == []


def test_yaml_multiline_dquote_real_trailing_comment_after_close_rejected():
    src = 'key: "abc\ndef" # real trailing comment\nother: 1\n'
    assert _kinds(scan_yaml(Path("x.yaml"), src)) == {"narrative-comment"}


def test_yaml_dquote_backslash_line_continuation_hash_not_comment():
    src = 'key: "abc\\\ndef # not a comment"\nother: 1\n'
    assert scan_yaml(Path("x.yaml"), src) == []


def test_yaml_unterminated_dquote_fails_closed():
    try:
        scan_yaml(Path("x.yaml"), 'key: "unterminated\n')
    except YamlLexError:
        pass
    else:
        raise AssertionError("expected YamlLexError")


def test_yaml_unterminated_squote_fails_closed():
    try:
        scan_yaml(Path("x.yaml"), "key: 'unterminated\n")
    except YamlLexError:
        pass
    else:
        raise AssertionError("expected YamlLexError")


def test_toml_real_comment_rejected():
    assert _kinds(scan_toml(Path("x.toml"), 'key = "v"\n# comment\n')) == {"narrative-comment"}


def test_toml_quoted_hash_accepted():
    assert scan_toml(Path("x.toml"), 'key = "# not a comment"\n') == []


def test_toml_multiline_string_hash_is_data():
    src = 'key = """\n# not a comment\n"""\n'
    assert scan_toml(Path("x.toml"), src) == []


def test_toml_literal_string_hash_accepted():
    assert scan_toml(Path("x.toml"), "key = '# not a comment'\n") == []


def test_toml_multiline_literal_string_hash_is_data():
    src = "key = '''\n# not a comment\n'''\n"
    assert scan_toml(Path("x.toml"), src) == []


def test_toml_multiline_basic_string_trailing_quote_before_close_accepted():
    src = 'key = """This is a "quoted word" and this trailing quote is data\""""\n'
    assert scan_toml(Path("x.toml"), src) == []


def test_toml_multiline_literal_string_trailing_quote_before_close_accepted():
    src = "key = '''trailing quote is data\''''\n"
    assert scan_toml(Path("x.toml"), src) == []


def test_toml_real_comment_after_multiline_string_rejected():
    src = 'key = """data\""""\n# real comment\n'
    assert _kinds(scan_toml(Path("x.toml"), src)) == {"narrative-comment"}


def test_toml_unterminated_basic_string_fails_closed():
    try:
        scan_toml(Path("x.toml"), 'key = "unterminated\n')
    except TomlLexError:
        pass
    else:
        raise AssertionError("expected TomlLexError")


def test_toml_unterminated_literal_string_fails_closed():
    try:
        scan_toml(Path("x.toml"), "key = 'unterminated\n")
    except TomlLexError:
        pass
    else:
        raise AssertionError("expected TomlLexError")


def test_toml_unterminated_multiline_basic_string_fails_closed():
    try:
        scan_toml(Path("x.toml"), 'key = """unterminated\n')
    except TomlLexError:
        pass
    else:
        raise AssertionError("expected TomlLexError")


def test_toml_unterminated_multiline_literal_string_fails_closed():
    try:
        scan_toml(Path("x.toml"), "key = '''unterminated\n")
    except TomlLexError:
        pass
    else:
        raise AssertionError("expected TomlLexError")


def test_toml_multiline_escaped_quote_adjacent_to_trailing_quotes_accepted():
    src = 'key = """abc\\""""""\n'
    assert scan_toml(Path("x.toml"), src) == []


def test_toml_multiline_escaped_quote_adjacent_to_trailing_quotes_does_not_corrupt_rest_of_scan():
    src = 'key = """abc\\""""""\nother = 1\n# real comment\n'
    assert _kinds(scan_toml(Path("x.toml"), src)) == {"narrative-comment"}


def test_toml_multiline_basic_string_two_trailing_quotes_before_close_accepted():
    src = 'key = """ends with two quotes: """""\n'
    assert scan_toml(Path("x.toml"), src) == []


def test_generic_unsupported_source_extension_under_source_dir_rejected():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / "scripts").mkdir()
        (tmp_path / "scripts" / "thing.xyz").write_text("data\n")
        assert main(["prog", str(tmp_path)]) == 1


def test_generic_markdown_prose_ignored_by_policy():
    with tempfile.TemporaryDirectory() as tmp_path_str:
        tmp_path = Path(tmp_path_str)
        (tmp_path / "README.md").write_text("# Heading\n// not code\n")
        assert main(["prog", str(tmp_path)]) == 0


def test_generic_exact_allowed_directive_accepted():
    assert scan_shell(Path("x.sh"), "# shellcheck disable=SC2154\nx=1\n") == []


def test_generic_almost_matching_directive_rejected():
    src = "# shellcheck disable SC2154\nx=1\n"
    assert _kinds(scan_shell(Path("x.sh"), src)) == {"narrative-comment"}


def test_generic_arbitrary_ignore_directive_rejected():
    assert _kinds(scan_nix(Path("x.nix"), "# comment-policy: ignore\n")) == {"narrative-comment"}


if __name__ == "__main__":
    passed = 0
    total = 0
    failed_tests = []

    for name in sorted(globals()):
        if not name.startswith("test_"):
            continue
        total += 1
        test_func = globals()[name]
        try:
            test_func()
            print(f"PASS: {name}")
            passed += 1
        except Exception as e:
            print(f"FAIL: {name}: {e}")
            failed_tests.append((name, e))

    print(f"\nsource-comment-policy self-test: {passed}/{total} passed")
    if failed_tests:
        sys.exit(1)

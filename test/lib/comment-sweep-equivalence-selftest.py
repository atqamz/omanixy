#!/usr/bin/env python3
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

import yaml

equivalence_path = Path(sys.argv[1])

ns = {"__file__": str(equivalence_path)}
with open(equivalence_path, encoding="utf-8") as f:
    exec(compile(f.read(), str(equivalence_path), "exec"), ns)

compare_python = ns["compare_python"]
_strip_docstrings = ns["_strip_docstrings"]
_leading_string_expr = ns["_leading_string_expr"]
compare_nix = ns["compare_nix"]
_nix_parse = ns["_nix_parse"]
compare_shell = ns["compare_shell"]
compare_js = ns["compare_js"]
compare_yaml = ns["compare_yaml"]
compare_toml = ns["compare_toml"]
compare_tree = ns["compare_tree"]
ShellLexError = ns["_check_source_comments"].ShellLexError
JsLexError = ns["_check_source_comments"].JsLexError


def test_python_docstring_only_removal_is_equivalent():
    before = 'def f():\n    """doc."""\n    return 1\n'
    after = 'def f():\n    return 1\n'
    assert compare_python(Path("x.py"), before, after)


def test_python_real_mutation_rejected():
    before = "x = 1\n"
    after = "x = 2\n"
    assert not compare_python(Path("x.py"), before, after)


def test_python_comment_only_removal_is_equivalent():
    before = "x = 1  # note\n"
    after = "x = 1\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_module_docstring_removal_is_equivalent():
    before = '"""module doc."""\nx = 1\n'
    after = "x = 1\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_class_and_method_docstring_removal_is_equivalent():
    before = 'class C:\n    """c."""\n    def m(self):\n        """m."""\n        return 1\n'
    after = "class C:\n    def m(self):\n        return 1\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_empty_class_docstring_removal_is_equivalent():
    before = 'class C:\n    """c."""\n'
    after = "class C:\n    pass\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_lambda_body_does_not_crash_comparator():
    before = "f = lambda x: x + 1\n"
    after = "f = lambda x: x + 1\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_ternary_body_does_not_crash_comparator():
    before = "y = 1 if True else 2\n"
    after = "y = 1 if True else 2\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_lambda_mutation_rejected():
    before = "f = lambda x: x + 1\n"
    after = "f = lambda x: x + 2\n"
    assert not compare_python(Path("x.py"), before, after)


def test_python_docstring_sibling_to_lambda_still_equivalent():
    before = 'def f():\n    """doc."""\n    g = lambda x: x\n    return g(1)\n'
    after = "def f():\n    g = lambda x: x\n    return g(1)\n"
    assert compare_python(Path("x.py"), before, after)


def test_python_non_docstring_string_statement_removal_is_rejected():
    before = 'if True:\n    "not a real docstring"\n    x = 1\n'
    after = "if True:\n    x = 1\n"
    assert not compare_python(Path("x.py"), before, after)


def test_python_non_docstring_string_statement_mutation_is_rejected():
    before = 'if True:\n    "KEEP"\n'
    after = 'if True:\n    "MUTATED"\n'
    assert not compare_python(Path("x.py"), before, after)


def test_python_syntax_error_propagates():
    try:
        compare_python(Path("x.py"), "def f(:\n", "def f():\n    pass\n")
    except SyntaxError:
        pass
    else:
        raise AssertionError("expected SyntaxError")


def test_leading_string_expr_ignores_non_docstring_first_statement():
    import ast
    tree = ast.parse("def f():\n    x = 1\n    return x\n")
    func = tree.body[0]
    assert _leading_string_expr(func) is None


def test_nix_comment_removal_is_equivalent():
    before = "{ enable = false; # narrative\n}\n"
    after = "{ enable = false;\n}\n"
    assert compare_nix(Path("x.nix"), before, after)


def test_nix_embedded_comment_removal_is_equivalent():
    before = "{ testScript = ''\n  # narrative\n  print(\"ok\")\n''; }\n"
    after = "{ testScript = ''\n  print(\"ok\")\n''; }\n"
    assert compare_nix(Path("test.nix"), before, after)


def test_nix_embedded_comment_after_string_removal_is_equivalent():
    before = '''{ testScript = ''
  print("# narrative")  # narrative
''; }
'''
    after = '''{ testScript = ''
  print("# narrative")
''; }
'''
    assert compare_nix(Path("test.nix"), before, after)


def test_nix_embedded_shell_continuation_comment_removal_is_rejected():
    continuation = "\\" + "\n"
    before = "{ buildPhase = ''\n  printf '%s\\n' " + continuation + "  # narrative\n  one\n''; }\n"
    after = "{ buildPhase = ''\n  printf '%s\\n' " + continuation + "  one\n''; }\n"
    assert not compare_nix(Path("test.nix"), before, after)


def test_nix_real_mutation_rejected():
    before = "{ enable = false; }\n"
    after = "{ enable = true; }\n"
    assert not compare_nix(Path("x.nix"), before, after)


def test_nix_block_comment_removal_is_equivalent():
    before = "{ /* narrative */ enable = false; }\n"
    after = "{ enable = false; }\n"
    assert compare_nix(Path("x.nix"), before, after)


def test_nix_whitespace_reflow_is_equivalent():
    before = "{ enable  =  false; }\n"
    after = "{\n  enable = false;\n}\n"
    assert compare_nix(Path("x.nix"), before, after)


def test_nix_string_content_mutation_rejected():
    before = '{ x = "before"; }\n'
    after = '{ x = "after"; }\n'
    assert not compare_nix(Path("x.nix"), before, after)


def test_nix_malformed_input_propagates_called_process_error():
    try:
        compare_nix(Path("x.nix"), "{ enable = ;\n", "{ enable = false; }\n")
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError("expected CalledProcessError")


def test_nix_parse_ignores_source_position_not_content():
    before = "{ x = 1; }\n"
    after = "\n\n{ x = 1; }\n"
    assert compare_nix(Path("x.nix"), before, after)


def test_shell_comment_only_removal_is_equivalent():
    before = "cmd  # narrative\n"
    after = "cmd\n"
    assert compare_shell(Path("x.sh"), before, after)


def test_shell_standalone_comment_removal_is_equivalent():
    before = "cmd\n  # narrative\necho ok\n"
    after = "cmd\necho ok\n"
    assert compare_shell(Path("x.sh"), before, after)


def test_shell_continuation_comment_removal_is_rejected():
    continuation = "\\" + "\n"
    before = "printf '%s\\n' " + continuation + "# narrative\none\n"
    after = "printf '%s\\n' " + continuation + "one\n"
    assert not compare_shell(Path("x.sh"), before, after)


def test_shell_backslash_with_trailing_spaces_is_not_continuation():
    previous = "printf '%s\\n' one " + "\\" + "  " + "\n"
    before = previous + "  # narrative\nprintf '%s\\n' two\n"
    after = previous + "printf '%s\\n' two\n"
    assert compare_shell(Path("x.sh"), before, after)


def test_shell_flag_mutation_rejected():
    assert not compare_shell(Path("x.sh"), "cmd --safe\n", "cmd --unsafe\n")


def test_shell_heredoc_body_whitespace_mutation_rejected():
    before = "cat <<EOF\nline with  double  space\nEOF\n"
    after = "cat <<EOF\nline with double space\nEOF\n"
    assert not compare_shell(Path("x.sh"), before, after)


def test_shell_dquote_string_internal_whitespace_mutation_rejected():
    before = 'cmd "a  b"\n'
    after = 'cmd "a b"\n'
    assert not compare_shell(Path("x.sh"), before, after)


def test_shell_heredoc_hash_is_not_a_comment():
    text = "cat <<EOF\n# not a comment\nEOF\n"
    assert compare_shell(Path("x.sh"), text, text)


def test_shell_unterminated_heredoc_propagates_lex_error():
    before = "cat <<EOF\n"
    after = "cat <<EOF\nfoo\nEOF\n"
    try:
        compare_shell(Path("x.sh"), before, after)
    except ShellLexError:
        pass
    else:
        raise AssertionError("expected ShellLexError")


def test_js_line_comment_only_removal_is_equivalent():
    before = "const x = 1; // note\n"
    after = "const x = 1;\n"
    assert compare_js(Path("x.js"), before, after)


def test_js_standalone_comment_removal_is_equivalent():
    before = "const x = 1;\n  // note\nconst y = 2;\n"
    after = "const x = 1;\nconst y = 2;\n"
    assert compare_js(Path("x.js"), before, after)


def test_js_block_comment_only_removal_is_equivalent():
    before = "const x /* note */ = 1;\n"
    after = "const x = 1;\n"
    assert compare_js(Path("x.js"), before, after)


def test_js_string_literal_internal_whitespace_mutation_rejected():
    before = 'let s = "a  b";\n'
    after = 'let s = "a b";\n'
    assert not compare_js(Path("x.js"), before, after)


def test_js_threshold_mutation_rejected():
    assert not compare_js(Path("x.js"), "if (attempts < 5) {}\n", "if (attempts < 6) {}\n")


def test_js_division_is_not_a_regex_literal():
    text = "let a = b / c / d;\n"
    assert compare_js(Path("x.js"), text, text)


def test_js_unterminated_block_comment_propagates_lex_error():
    try:
        compare_js(Path("x.js"), "/* unterminated\n", "/* unterminated */\n")
    except JsLexError:
        pass
    else:
        raise AssertionError("expected JsLexError")


def test_yaml_comment_only_removal_is_equivalent():
    before = "support: experimental  # note\n"
    after = "support: experimental\n"
    assert compare_yaml(Path("x.yaml"), before, after)


def test_yaml_value_mutation_rejected():
    assert not compare_yaml(Path("x.yaml"), "support: experimental\n", "support: supported\n")


def test_yaml_malformed_input_propagates_yaml_error():
    try:
        compare_yaml(Path("x.yaml"), "{ bad: [1, 2\n", "support: experimental\n")
    except yaml.YAMLError:
        pass
    else:
        raise AssertionError("expected YAMLError")


def test_toml_comment_only_removal_is_equivalent():
    before = 'support = "experimental"  # note\n'
    after = 'support = "experimental"\n'
    assert compare_toml(Path("x.toml"), before, after)


def test_toml_value_mutation_rejected():
    assert not compare_toml(Path("x.toml"), 'support = "experimental"\n', 'support = "supported"\n')


def test_toml_malformed_input_propagates_toml_decode_error():
    try:
        compare_toml(Path("x.toml"), "support = \n", 'support = "experimental"\n')
    except tomllib.TOMLDecodeError:
        pass
    else:
        raise AssertionError("expected TOMLDecodeError")


def test_tree_comparison_emits_equivalence_for_source_tree():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        before = root / "before"
        after = root / "after"
        before.mkdir()
        after.mkdir()
        (before / "x.py").write_text('"""doc"""\nx = 1\n', encoding="utf-8")
        (after / "x.py").write_text("x = 1\n", encoding="utf-8")
        entries = compare_tree(before, after)
    assert entries == [{"path": "x.py", "language": "python", "equivalent": True}]


def test_tree_comparison_rejects_executable_mutation():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        before = root / "before"
        after = root / "after"
        before.mkdir()
        after.mkdir()
        (before / "x.sh").write_text("printf '%s\\n' one\n", encoding="utf-8")
        (after / "x.sh").write_text("printf '%s\\n' two\n", encoding="utf-8")
        try:
            compare_tree(before, after)
        except ValueError as error:
            assert "executable semantics changed" in str(error)
        else:
            raise AssertionError("expected executable mutation to be rejected")


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

    print(f"\ncomment-sweep-equivalence self-test: {passed}/{total} passed")
    if failed_tests:
        sys.exit(1)

"""Line LB — S2 scoped-tool-task bank builder + auditor + sandbox emitter.

Builds the frozen 20-task bank for the completion@N loop-bench (MTP-GATES
Part 8). Each task is a slugify-shaped scoped coding task: the actor
authors ONE lib file in an isolated sandbox package; the frozen check runs
the BANK's own verify test (independent oracle — the actor never authors
the checker). Reference implementations exist for the AUDIT ONLY (a task
enters the bank only if: reference passes the verify test AND the empty
sandbox fails it — the oracle discriminates).

Modes:
  --build            write bank.json (deterministic; sha256 printed)
  --audit            per task: green with reference / red without; prints
                     the bank sha256 + per-task verify sha256
  --emit-sandbox T D emit task id T's sandbox into dir D (verify test +
                     pubspec; NO implementation — the actor authors it)

Law: this file is frozen material once Part 8 records the bank sha; a
changed bank is a NEW corpus requiring a NEW frozen Part (the SK-G0
refusal pattern).
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BANK_PATH = os.path.join(HERE, "bank.json")
DART = "/Users/antonio/fvm/default/bin/dart"

PUBSPEC = """name: lb_sandbox
environment:
  sdk: '>=3.0.0 <4.0.0'
dev_dependencies:
  test: any
"""

PROMPT_TEMPLATE = (
    "Create the file lib/{file} defining exactly one top-level function: "
    "{sig} — {spec} Use the write tool once to create the file, then use "
    "the run tool to run the verification command. Change no other file."
)

TEST_HEADER = """import 'package:test/test.dart';
import 'package:lb_sandbox/{file}';

void main() {{
  test('{name}', () {{
"""
TEST_FOOTER = """  });
}
"""


def t(name, file, sym, sig, spec, cases, ref):
    """cases: list of (dart expect expression body) lines."""
    body = "\n".join(f"    {c}" for c in cases)
    test = TEST_HEADER.format(file=file, name=name) + body + "\n" + TEST_FOOTER
    return {
        "id": name,
        "file": file,
        "symbol": sym,
        "sig": sig,
        "spec": spec,
        "prompt": PROMPT_TEMPLATE.format(file=file, sig=sig, spec=spec),
        "verify_test": test,
        "reference_impl": ref,
        "check": [DART, "test", "test/verify_test.dart"],
    }


TASKS = [
    t(
        "count_vowels", "count_vowels.dart", "countVowels",
        "int countVowels(String s)",
        "return the number of characters of s that are one of a, e, i, o, u "
        "(case-insensitive; y is NOT a vowel; empty string returns 0).",
        [
            "expect(countVowels(''), 0);",
            "expect(countVowels('rhythm'), 0);",
            "expect(countVowels('AEIOU'), 5);",
            "expect(countVowels('The quick brown fox'), 5);",
            "expect(countVowels('xyz'), 0);",
        ],
        "int countVowels(String s) {\n"
        "  const v = 'aeiouAEIOU';\n"
        "  var n = 0;\n"
        "  for (final c in s.split('')) { if (v.contains(c)) n++; }\n"
        "  return n;\n"
        "}\n",
    ),
    t(
        "extract_digits", "extract_digits.dart", "extractDigits",
        "String extractDigits(String s)",
        "return a string of every digit character ('0'-'9') of s, in order "
        "(no digits returns the empty string).",
        [
            "expect(extractDigits(''), '');",
            "expect(extractDigits('abc'), '');",
            "expect(extractDigits('a1b22c333'), '122333');",
            "expect(extractDigits('2026-11-04'), '20261104');",
        ],
        "String extractDigits(String s) =>\n"
        "    s.split('').where((c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0).join();\n",
    ),
    t(
        "normalize_ws", "normalize_ws.dart", "normalizeWhitespace",
        "String normalizeWhitespace(String s)",
        "collapse every run of one or more space/tab characters into a "
        "single space ' ' and trim leading and trailing spaces/tabs "
        "(other characters, including newlines, are ordinary characters "
        "and are kept).",
        [
            "expect(normalizeWhitespace(''), '');",
            "expect(normalizeWhitespace('   '), '');",
            "expect(normalizeWhitespace(' a  b\\tc '), 'a b c');",
            "expect(normalizeWhitespace('a\\nb'), 'a\\nb');",
        ],
        "String normalizeWhitespace(String s) =>\n"
        "    s.replaceAll(RegExp('[ \\t]+'), ' ').trim();\n",
    ),
    t(
        "reverse_words", "reverse_words.dart", "reverseWords",
        "String reverseWords(String s)",
        "first apply the normalizeWhitespace rule (runs of space/tab to one "
        "space, trim), then reverse the order of the space-separated words "
        "and join them with single spaces.",
        [
            "expect(reverseWords(''), '');",
            "expect(reverseWords('one'), 'one');",
            "expect(reverseWords('  the quick   brown '), 'brown quick the');",
        ],
        "String reverseWords(String s) {\n"
        "  final n = s.replaceAll(RegExp('[ \\t]+'), ' ').trim();\n"
        "  if (n.isEmpty) return '';\n"
        "  return n.split(' ').reversed.join(' ');\n"
        "}\n",
    ),
    t(
        "camel_to_snake", "camel_to_snake.dart", "camelToSnake",
        "String camelToSnake(String s)",
        "lowercase the whole string, inserting '_' before every uppercase "
        "letter EXCEPT when it is at position 0 (a leading uppercase letter "
        "produces no '_').",
        [
            "expect(camelToSnake(''), '');",
            "expect(camelToSnake('a'), 'a');",
            "expect(camelToSnake('camelToSnake'), 'camel_to_snake');",
            "expect(camelToSnake('CamelToSnake'), 'camel_to_snake');",
            "expect(camelToSnake('HTTPServer'), 'h_t_t_p_server');",
        ],
        "String camelToSnake(String s) {\n"
        "  final b = StringBuffer();\n"
        "  for (var i = 0; i < s.length; i++) {\n"
        "    final c = s[i];\n"
        "    final up = c.toUpperCase() == c && c.toLowerCase() != c;\n"
        "    if (up && i > 0) b.write('_');\n"
        "    b.write(c.toLowerCase());\n"
        "  }\n"
        "  return b.toString();\n"
        "}\n",
    ),
    t(
        "snake_to_camel", "snake_to_camel.dart", "snakeToCamel",
        "String snakeToCamel(String s)",
        "split s into segments on '_'; ignore empty segments; the first "
        "non-empty segment becomes all-lowercase; every later non-empty "
        "segment gets its first character uppercased and the rest "
        "lowercased; concatenate the segments (no separators). No non-empty "
        "segment returns the empty string.",
        [
            "expect(snakeToCamel(''), '');",
            "expect(snakeToCamel('single'), 'single');",
            "expect(snakeToCamel('snake_to_camel'), 'snakeToCamel');",
            "expect(snakeToCamel('_leading_and__double'), 'leadingAndDouble');",
            "expect(snakeToCamel('MIXED_case'), 'mixedCase');",
        ],
        "String snakeToCamel(String s) {\n"
        "  final segs = s.split('_').where((x) => x.isNotEmpty).toList();\n"
        "  if (segs.isEmpty) return '';\n"
        "  final b = StringBuffer(segs.first.toLowerCase());\n"
        "  for (final seg in segs.skip(1)) {\n"
        "    b.write(seg[0].toUpperCase());\n"
        "    b.write(seg.substring(1).toLowerCase());\n"
        "  }\n"
        "  return b.toString();\n"
        "}\n",
    ),
    t(
        "initials", "initials.dart", "initials",
        "String initials(String name)",
        "split on runs of space/tab; take the first character of each word, "
        "uppercased; join them with '.' between (no trailing dot). Empty or "
        "blank input returns the empty string.",
        [
            "expect(initials(''), '');",
            "expect(initials('   '), '');",
            "expect(initials('ada lovelace'), 'A.L');",
            "expect(initials('  Grace   B. Hopper '), 'G.B.H');",
        ],
        "String initials(String name) {\n"
        "  final words = name\n"
        "      .replaceAll(RegExp('[ \\t]+'), ' ')\n"
        "      .trim()\n"
        "      .split(' ')\n"
        "      .where((w) => w.isNotEmpty)\n"
        "      .toList();\n"
        "  return words.map((w) => w[0].toUpperCase()).join('.');\n"
        "}\n",
    ),
    t(
        "acronym", "acronym.dart", "acronym",
        "String acronym(String s)",
        "split on runs of space/tab; uppercase the first character of each "
        "word and concatenate them with no separator. Empty or blank input "
        "returns the empty string.",
        [
            "expect(acronym(''), '');",
            "expect(acronym('light emission diode'), 'LED');",
            "expect(acronym('  as   soon as possible '), ' ASAP'.trim());",
        ],
        "String acronym(String s) {\n"
        "  final words = s\n"
        "      .replaceAll(RegExp('[ \\t]+'), ' ')\n"
        "      .trim()\n"
        "      .split(' ')\n"
        "      .where((w) => w.isNotEmpty)\n"
        "      .toList();\n"
        "  return words.map((w) => w[0].toUpperCase()).join();\n"
        "}\n",
    ),
    t(
        "safe_filename", "safe_filename.dart", "safeFilename",
        "String safeFilename(String s)",
        "replace every character that is NOT an ASCII letter, digit, '.', "
        "'_' or '-' with '_'; then collapse every run of one or more '_' "
        "into a single '_'; then remove leading and trailing '_' "
        "characters.",
        [
            "expect(safeFilename(''), '');",
            "expect(safeFilename('plain.txt'), 'plain.txt');",
            "expect(safeFilename('my file (1).txt'), 'my_file_1_.txt');",
            "expect(safeFilename('///'), '');",
            "expect(safeFilename('a__b'), 'a_b');",
        ],
        "String safeFilename(String s) {\n"
        "  final replaced = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');\n"
        "  final collapsed = replaced.replaceAll(RegExp('_+'), '_');\n"
        "  return collapsed.replaceAll(RegExp('^_+|_+\\$'), '');\n"
        "}\n",
    ),
    t(
        "pad_zero", "pad_zero.dart", "padZero",
        "String padZero(String s, int w)",
        "if w <= 0 or s.length >= w return s unchanged; otherwise return s "
        "left-padded with '0' characters so the result has length exactly "
        "w.",
        [
            "expect(padZero('42', 5), '00042');",
            "expect(padZero('42', 2), '42');",
            "expect(padZero('42', 1), '42');",
            "expect(padZero('', 3), '000');",
            "expect(padZero('7', 0), '7');",
        ],
        "String padZero(String s, int w) =>\n"
        "    (w <= 0 || s.length >= w) ? s : '0' * (w - s.length) + s;\n",
    ),
    t(
        "mask_email", "mask_email.dart", "maskEmail",
        "String maskEmail(String s)",
        "if s contains no '@', return s unchanged. Otherwise split at the "
        "FIRST '@': if the local part (before it) is empty, return s "
        "unchanged; else return the first character of the local part, then "
        "'***', then '@' and the domain part exactly as they were.",
        [
            "expect(maskEmail('no-at-sign'), 'no-at-sign');",
            "expect(maskEmail('@domain.com'), '@domain.com');",
            "expect(maskEmail('ada@domain.com'), 'a***@domain.com');",
            "expect(maskEmail('a.b@x.y'), 'a***@x.y');",
        ],
        "String maskEmail(String s) {\n"
        "  final at = s.indexOf('@');\n"
        "  if (at < 1) return s;\n"
        "  return s[0] + '***' + s.substring(at);\n"
        "}\n",
    ),
    t(
        "redact_digits", "redact_digits.dart", "redactDigits",
        "String redactDigits(String s)",
        "replace every MAXIMAL run of six or more consecutive digit "
        "characters with a single '#'; runs of fewer than six digits stay "
        "unchanged; all other characters stay unchanged.",
        [
            "expect(redactDigits(''), '');",
            "expect(redactDigits('12345'), '12345');",
            "expect(redactDigits('123456'), '#');",
            "expect(redactDigits('id 1234567890 ok'), 'id # ok');",
            "expect(redactDigits('a123456b123'), 'a#b123');",
        ],
        "String redactDigits(String s) =>\n"
        "    s.replaceAll(RegExp(r'[0-9]{6,}'), '#');\n",
    ),
    t(
        "truncate", "truncate.dart", "truncateEnd",
        "String truncateEnd(String s, int n)",
        "if n <= 0 return ''; if s.length <= n return s unchanged; if n == 1 "
        "return '-'; otherwise return the first n-1 characters of s "
        "followed by '-'.",
        [
            "expect(truncateEnd('abcdef', 0), '');",
            "expect(truncateEnd('abc', 3), 'abc');",
            "expect(truncateEnd('abc', 5), 'abc');",
            "expect(truncateEnd('abcdef', 1), '-');",
            "expect(truncateEnd('abcdef', 4), 'abc-');",
        ],
        "String truncateEnd(String s, int n) {\n"
        "  if (n <= 0) return '';\n"
        "  if (s.length <= n) return s;\n"
        "  if (n == 1) return '-';\n"
        "  return s.substring(0, n - 1) + '-';\n"
        "}\n",
    ),
    t(
        "kebab", "kebab.dart", "kebab",
        "String kebab(String s)",
        "lowercase s; replace every maximal run of one or more characters "
        "that are NOT 'a'-'z' or '0'-'9' (after lowercasing) with a single "
        "'-'; then remove leading and trailing '-' characters.",
        [
            "expect(kebab(''), '');",
            "expect(kebab('Hello World'), 'hello-world');",
            "expect(kebab('  --a  B--c--  '), 'a-b-c');",
            "expect(kebab('already-kebab'), 'already-kebab');",
        ],
        "String kebab(String s) => s\n"
        "    .toLowerCase()\n"
        "    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')\n"
        "    .replaceAll(RegExp(r'^-+|-+$'), '');\n",
    ),
    t(
        "title_ascii", "title_ascii.dart", "titleAscii",
        "String titleAscii(String s)",
        "first apply the normalizeWhitespace rule (runs of space/tab to one "
        "space, trim); then for each word uppercase its first character and "
        "lowercase the rest; join the words with single spaces.",
        [
            "expect(titleAscii(''), '');",
            "expect(titleAscii('THE quick BROWN fox'), 'The Quick Brown Fox');",
            "expect(titleAscii('  a   b '), 'A B');",
        ],
        "String titleAscii(String s) {\n"
        "  final n = s.replaceAll(RegExp('[ \\t]+'), ' ').trim();\n"
        "  if (n.isEmpty) return '';\n"
        "  return n\n"
        "      .split(' ')\n"
        "      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())\n"
        "      .join(' ');\n"
        "}\n",
    ),
    t(
        "is_palindrome", "is_palindrome.dart", "isPalindromeAscii",
        "bool isPalindromeAscii(String s)",
        "remove every character that is NOT an ASCII letter or digit, "
        "lowercase the result, and return true when it reads the same "
        "backwards (the empty cleaned string returns true).",
        [
            "expect(isPalindromeAscii(''), isTrue);",
            "expect(isPalindromeAscii('A man, a plan, a canal: Panama'), isTrue);",
            "expect(isPalindromeAscii('abc'), isFalse);",
            "expect(isPalindromeAscii('No lemon, no melon'), isTrue);",
        ],
        "bool isPalindromeAscii(String s) {\n"
        "  final cleaned =\n"
        "      s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();\n"
        "  final rev = cleaned.split('').reversed.join();\n"
        "  return cleaned == rev;\n"
        "}\n",
    ),
    t(
        "join_unique", "join_unique.dart", "joinUnique",
        "String joinUnique(List<String> parts, String sep)",
        "keep the FIRST occurrence of each exact string in order, drop every "
        "later duplicate, and join the kept strings with sep (an empty list "
        "returns the empty string).",
        [
            "expect(joinUnique([], ','), '');",
            "expect(joinUnique(['a'], ','), 'a');",
            "expect(joinUnique(['a', 'b', 'a', 'c', 'b'], '-'), 'a-b-c');",
            "expect(joinUnique(['x', 'x', 'x'], ''), 'x');",
        ],
        "String joinUnique(List<String> parts, String sep) {\n"
        "  final seen = <String>{};\n"
        "  final kept = <String>[];\n"
        "  for (final p in parts) {\n"
        "    if (seen.add(p)) kept.add(p);\n"
        "  }\n"
        "  return kept.join(sep);\n"
        "}\n",
    ),
    t(
        "run_length_encode", "run_length_encode.dart", "runLengthEncode",
        "String runLengthEncode(String s)",
        "replace every maximal run of an identical character with that "
        "character followed by the run's length in decimal (a single "
        "character becomes e.g. 'a1'); the empty string returns the empty "
        "string.",
        [
            "expect(runLengthEncode(''), '');",
            "expect(runLengthEncode('a'), 'a1');",
            "expect(runLengthEncode('aabbbc'), 'a2b3c1');",
            "expect(runLengthEncode('abcd'), 'a1b1c1d1');",
        ],
        "String runLengthEncode(String s) {\n"
        "  if (s.isEmpty) return '';\n"
        "  final b = StringBuffer();\n"
        "  var cur = s[0];\n"
        "  var n = 1;\n"
        "  for (var i = 1; i < s.length; i++) {\n"
        "    if (s[i] == cur) {\n"
        "      n++;\n"
        "    } else {\n"
        "      b.write('$cur$n');\n"
        "      cur = s[i];\n"
        "      n = 1;\n"
        "    }\n"
        "  }\n"
        "  b.write('$cur$n');\n"
        "  return b.toString();\n"
        "}\n",
    ),
    t(
        "clamp_int", "clamp_int.dart", "clampInt",
        "int clampInt(int v, int lo, int hi)",
        "assume lo <= hi; return lo when v < lo, hi when v > hi, and v "
        "otherwise.",
        [
            "expect(clampInt(5, 0, 10), 5);",
            "expect(clampInt(-1, 0, 10), 0);",
            "expect(clampInt(11, 0, 10), 10);",
            "expect(clampInt(0, 0, 0), 0);",
        ],
        "int clampInt(int v, int lo, int hi) =>\n"
        "    v < lo ? lo : (v > hi ? hi : v);\n",
    ),
    t(
        "word_wrap", "word_wrap.dart", "wordWrap",
        "String wordWrap(String s, int w)",
        "assume w >= 1. First apply the normalizeWhitespace rule (runs of "
        "space/tab to one space, trim); split into words on single spaces; "
        "build lines greedily: append a word to the current line while the "
        "line's length plus (1 for the separating space when the line is "
        "not empty) plus the word's length is at most w; a word longer than "
        "w goes on a line of its own (words are never split); join the "
        "lines with '\\n'. Empty input returns the empty string.",
        [
            "expect(wordWrap('', 5), '');",
            "expect(wordWrap('one', 3), 'one');",
            "expect(wordWrap('aaa bb c', 3), 'aaa\\nbb\\nc');",
            "expect(wordWrap('short', 2), 'short');",
            "expect(wordWrap('the quick brown fox', 9), 'the quick\\nbrown fox');",
        ],
        "String wordWrap(String s, int w) {\n"
        "  final n = s.replaceAll(RegExp('[ \\t]+'), ' ').trim();\n"
        "  if (n.isEmpty) return '';\n"
        "  final words = n.split(' ');\n"
        "  final lines = <String>[];\n"
        "  var line = '';\n"
        "  for (final word in words) {\n"
        "    if (word.length > w) {\n"
        "      if (line.isNotEmpty) lines.add(line);\n"
        "      lines.add(word);\n"
        "      line = '';\n"
        "      continue;\n"
        "    }\n"
        "    final add = line.isEmpty ? word.length : line.length + 1 + word.length;\n"
        "    if (add <= w) {\n"
        "      line = line.isEmpty ? word : '$line $word';\n"
        "    } else {\n"
        "      lines.add(line);\n"
        "      line = word;\n"
        "    }\n"
        "  }\n"
        "  if (line.isNotEmpty) lines.add(line);\n"
        "  return lines.join('\\n');\n"
        "}\n",
    ),
]


def build_bank():
    bank = {"version": 1, "n_tasks": len(TASKS), "tasks": TASKS}
    blob = json.dumps(bank, indent=1, sort_keys=True).encode("utf-8")
    with open(BANK_PATH, "wb") as fh:
        fh.write(blob)
    sha = hashlib.sha256(blob).hexdigest()
    print(f"bank written: {BANK_PATH}")
    print(f"bank sha256: {sha}")
    for task in TASKS:
        vs = hashlib.sha256(task["verify_test"].encode()).hexdigest()
        print(f"  {task['id']}: verify_sha={vs[:16]}…")
    return sha


def emit_sandbox(task, dest, with_impl=False):
    os.makedirs(os.path.join(dest, "lib"), exist_ok=True)
    os.makedirs(os.path.join(dest, "test"), exist_ok=True)
    with open(os.path.join(dest, "pubspec.yaml"), "w") as fh:
        fh.write(PUBSPEC)
    with open(os.path.join(dest, "test", "verify_test.dart"), "w") as fh:
        fh.write(task["verify_test"])
    if with_impl:
        with open(os.path.join(dest, "lib", task["file"]), "w") as fh:
            fh.write(task["reference_impl"])


def run_check(dest):
    subprocess.run([DART, "pub", "get", "--offline"], cwd=dest,
                   check=True, capture_output=True)
    proc = subprocess.run([DART, "test", "test/verify_test.dart"], cwd=dest,
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout[-400:] + proc.stderr[-400:]


def audit():
    import tempfile
    results = []
    for task in TASKS:
        green_dir = tempfile.mkdtemp(prefix="lb-green-")
        red_dir = tempfile.mkdtemp(prefix="lb-red-")
        try:
            emit_sandbox(task, green_dir, with_impl=True)
            emit_sandbox(task, red_dir, with_impl=False)
            g_rc, g_out = run_check(green_dir)
            r_rc, r_out = run_check(red_dir)
            ok = (g_rc == 0 and r_rc != 0)
            results.append((task["id"], ok, g_rc, r_rc))
            print(f"{'PASS' if ok else 'FAIL'} {task['id']}: "
                  f"green_rc={g_rc} red_rc={r_rc}")
            if not ok:
                print((g_out if g_rc != 0 else r_out)[:600])
        finally:
            shutil.rmtree(green_dir, ignore_errors=True)
            shutil.rmtree(red_dir, ignore_errors=True)
    failed = [r for r in results if not r[1]]
    print(f"audit: {len(results) - len(failed)}/{len(results)} tasks "
          f"discriminate")
    if failed:
        sys.exit(1)
    build_bank()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--emit-sandbox", nargs=2, metavar=("TASK_ID", "DEST"))
    args = ap.parse_args()
    if args.audit:
        audit()
    elif args.build:
        build_bank()
    elif args.emit_sandbox:
        with open(BANK_PATH) as fh:
            bank = json.load(fh)
        task = next(t for t in bank["tasks"] if t["id"] == args.emit_sandbox[0])
        emit_sandbox(task, args.emit_sandbox[1], with_impl=False)
        print(json.dumps({
            "prompt": task["prompt"],
            "check": task["check"],
            "verify_sha256": hashlib.sha256(
                task["verify_test"].encode()).hexdigest(),
        }))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()

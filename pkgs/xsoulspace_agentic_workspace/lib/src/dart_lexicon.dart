// ignore_for_file: lines_longer_than_80_chars

/// Pure Dart lexical utilities for the span editor (ADR 0035 §4 extraction):
/// brace/paren matching, top-level comma splitting, whole-identifier
/// replacement, class-body location and the parsed member site. No I/O, no
/// world state — the caller owns the file bytes and the bounce semantics.
library;

/// Whole-identifier replacement on one line; null when the name does not
/// occur as a standalone identifier.
String? replaceWholeIdentifiers(String line, String from, String to) {
  if (!line.contains(from)) return null;
  final buf = StringBuffer();
  var changed = false;
  var i = 0;
  while (i < line.length) {
    if (line.startsWith(from, i)) {
      final before = i == 0 ? '' : line[i - 1];
      final after = i + from.length >= line.length ? '' : line[i + from.length];
      final boundaryBefore = !RegExp(r'[\w$]').hasMatch(before);
      final boundaryAfter = !RegExp(r'[\w$]').hasMatch(after);
      if (boundaryBefore && boundaryAfter) {
        buf.write(to);
        changed = true;
        i += from.length;
        continue;
      }
    }
    buf.write(line[i]);
    i++;
  }
  return changed ? buf.toString() : null;
}

int? findClassBodyOpen(List<String> lines, int declLine0, String className) {
  // The class body opens on the first line at/after the decl whose
  // trimmed content ends with '{' (dart-formatted: single-line decl head).
  for (var i = declLine0; i < lines.length && i <= declLine0 + 8; i++) {
    if (lines[i].trimRight().endsWith('{') && lines[i].contains(className)) {
      return i;
    }
    if (i > declLine0 && lines[i].trim() == '{') return i;
  }
  return null;
}

/// 0-based line of the '}' matching the '{' that opens on line
/// [openLine0] (strings respected).
int? matchBrace(List<String> lines, int openLine0) {
  final text = lines.join('\n');
  var offset = 0;
  for (var i = 0; i < openLine0; i++) {
    offset += lines[i].length + 1;
  }
  offset += lines[openLine0].indexOf('{');
  final close = matchBraceText(text, offset);
  if (close == null) return null;
  var acc = 0;
  for (var i = 0; i < lines.length; i++) {
    if (acc <= close && close <= acc + lines[i].length) return i;
    acc += lines[i].length + 1;
  }
  return null;
}

int? matchBraceText(String text, int openOffset) {
  var depth = 0;
  var inStr = false;
  var strCh = '';
  for (var i = openOffset; i < text.length; i++) {
    final c = text[i];
    if (inStr) {
      if (c == r'\') {
        i++;
      } else if (c == strCh) {
        inStr = false;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inStr = true;
      strCh = c;
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

int? matchParen(String text, int openOffset) {
  var depth = 0;
  var inStr = false;
  var strCh = '';
  for (var i = openOffset; i < text.length; i++) {
    final c = text[i];
    if (inStr) {
      if (c == r'\') {
        i++;
      } else if (c == strCh) {
        inStr = false;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inStr = true;
      strCh = c;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

List<String> topLevelCommas(String s) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var inStr = false;
  var strCh = '';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      buf.write(c);
      if (c == r'\' && i + 1 < s.length) {
        buf.write(s[i + 1]);
        i++;
      } else if (c == strCh) {
        inStr = false;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inStr = true;
      strCh = c;
      buf.write(c);
      continue;
    }
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.toString().trim().isNotEmpty || parts.isNotEmpty) {
    parts.add(buf.toString());
  }
  return parts;
}

/// Parsed member site (pure data; offsets resolved by the caller).
class MemberSite {
  MemberSite({
    required this.paramNames,
    required this.returnType,
    required this.declLine0,
    required this.closeLine0,
    required this.declIndent,
    required this.signatureText,
  });
  final Set<String> paramNames;
  final String returnType;
  final int declLine0;
  final int closeLine0;
  final String declIndent;

  /// Signature text INCLUDING the opening ' {' — re-emitted verbatim so
  /// the declared signature survives the body swap byte-for-byte (the
  /// integration fence validates against it before generation).
  final String signatureText;
}

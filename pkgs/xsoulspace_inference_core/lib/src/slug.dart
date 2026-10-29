/// Slug generation from free-form identifiers.
library;

/// Lowercases [input], keeps ASCII letters and digits, collapses every run
/// of one or more other characters into a single `-`, and trims leading
/// and trailing dashes. Empty or all-punctuation input returns the empty
/// string.
String slugify(String input) {
  final buffer = StringBuffer();
  var pendingSeparator = false;
  for (final code in input.codeUnits) {
    final lower = code >= 0x41 && code <= 0x5A ? code + 0x20 : code;
    final isLetter = (lower >= 0x61 && lower <= 0x7A);
    final isDigit = (lower >= 0x30 && lower <= 0x39);
    if (isLetter || isDigit) {
      if (pendingSeparator && buffer.isNotEmpty) buffer.write('-');
      pendingSeparator = false;
      buffer.writeCharCode(lower);
    } else {
      pendingSeparator = true;
    }
  }
  return buffer.toString();
}

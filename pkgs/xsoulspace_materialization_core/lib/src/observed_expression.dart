/// One host-resolved observed return expression.
class ObservedReturn {
  const ObservedReturn({
    required this.text,
    required this.kind,
    required this.precedence,
    required this.atomic,
    required this.simple,
    this.stringParts,
  });

  /// Exact source text of the expression (inserted verbatim by the
  /// compiler — behavior preservation is by construction).
  final String text;

  /// 'text' | 'numeric' | 'opaque'. Only proven classes compose; opaque
  /// expressions may be returned verbatim but never composed with `add`.
  final String kind;

  /// Compiler precedence of the expression ROOT (eq 1 < relational 2 <
  /// additive 3 < multiplicative 4 < unary 6 < primary 7).
  final int precedence;

  /// Usable under postfix/member access without extra parens.
  final bool atomic;

  /// Whole expression is one plain identifier (safe to interpolate `$x`).
  final bool simple;

  /// Present iff [kind] is text AND the expression is a string literal or
  /// interpolation: literal chunks ([String], UNESCAPED) and embedded
  /// expressions ([ObservedEmbed]) for interpolation folding.
  final List<Object>? stringParts;
}

/// One embedded expression inside an observed interpolation.
class ObservedEmbed {
  const ObservedEmbed(this.text, {required this.simple});
  final String text;
  final bool simple;
}

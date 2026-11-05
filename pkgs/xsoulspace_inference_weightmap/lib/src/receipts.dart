/// Keyed certifications: the identity a certification claim is bound to.
///
/// Implements PROGRAM.md Phase E / V-6: a certification is keyed to the base
/// digest, tokenizer digest, quant, sampler config, engine rev, and battery
/// digest; drift OUTSIDE the key is not a warning — it is a new claim that
/// re-runs certification. "Outside the key" must be mechanically nameable, so
/// [CertificationKey.matches] returns the exact list of NAMED drifted fields
/// (empty = same key), which can go verbatim into a ledger row or receipt.
///
/// Comparison law: [samplerConfig] is compared by canonical-json text (via
/// `ledger.dart`'s [canonicalJson]), so map insertion order is irrelevant but
/// numeric TYPE is significant — `0` vs `0.0` is drift. That strictness is
/// pre-registered: a config whose value types changed is not the frozen
/// config, and silently re-typing it would be exactly the kind of unrecorded
/// oracle edit the house laws forbid.
library;

import 'ledger.dart' show canonicalJson;

/// The six-field certification key (PROGRAM.md V-6). All fields are required;
/// a certification against an unknown digest or config does not exist.
final class CertificationKey {
  const CertificationKey({
    required this.baseDigest,
    required this.tokenizerDigest,
    required this.quant,
    required this.samplerConfig,
    required this.engineRev,
    required this.batteryDigest,
  });

  /// Rebuilds from json (e.g. a receipt file). Missing or wrongly typed fields
  /// throw a named [FormatException]: `MISSING_FIELD=<name>` /
  /// `MALFORMED_FIELD=<name>` — never a silent default.
  factory CertificationKey.fromJson(Map<String, Object?> json) {
    final sampler = json.containsKey('samplerConfig')
        ? json['samplerConfig']
        : (throw const FormatException('MISSING_FIELD=samplerConfig'));
    if (sampler is! Map || !sampler.keys.every((k) => k is String)) {
      throw FormatException(
        'MALFORMED_FIELD=samplerConfig expected=Map<String, Object?> '
        'found=${sampler.runtimeType}',
      );
    }
    return CertificationKey(
      baseDigest: _string(json, 'baseDigest'),
      tokenizerDigest: _string(json, 'tokenizerDigest'),
      quant: _string(json, 'quant'),
      samplerConfig: Map<String, Object?>.from(sampler),
      engineRev: _string(json, 'engineRev'),
      batteryDigest: _string(json, 'batteryDigest'),
    );
  }

  /// Canonical field labels, in the stable reporting order [matches] uses.
  static const List<String> fieldLabels = [
    'BASE_DIGEST',
    'TOKENIZER_DIGEST',
    'QUANT',
    'SAMPLER_CONFIG',
    'ENGINE_REV',
    'BATTERY_DIGEST',
  ];

  final String baseDigest;
  final String tokenizerDigest;
  final String quant;
  final Map<String, Object?> samplerConfig;
  final String engineRev;
  final String batteryDigest;

  /// The NAMED field mismatches between this key and [other], in the stable
  /// [fieldLabels] order. Empty list = same key = the certification still
  /// applies; any name = drift outside the key = re-run certification.
  List<String> matches(CertificationKey other) {
    final drifted = <String>[];
    if (baseDigest != other.baseDigest) drifted.add('BASE_DIGEST');
    if (tokenizerDigest != other.tokenizerDigest) {
      drifted.add('TOKENIZER_DIGEST');
    }
    if (quant != other.quant) drifted.add('QUANT');
    if (canonicalJson(samplerConfig) != canonicalJson(other.samplerConfig)) {
      drifted.add('SAMPLER_CONFIG');
    }
    if (engineRev != other.engineRev) drifted.add('ENGINE_REV');
    if (batteryDigest != other.batteryDigest) drifted.add('BATTERY_DIGEST');
    return drifted;
  }

  /// True when [matches] names nothing.
  bool sameKeyAs(CertificationKey other) => matches(other).isEmpty;

  Map<String, Object?> toJson() => {
    'baseDigest': baseDigest,
    'tokenizerDigest': tokenizerDigest,
    'quant': quant,
    'samplerConfig': samplerConfig,
    'engineRev': engineRev,
    'batteryDigest': batteryDigest,
  };

  /// Canonical text form — the string a receipt or ledger row can digest.
  String canonical() => canonicalJson(toJson());

  @override
  bool operator ==(Object other) =>
      other is CertificationKey && canonical() == other.canonical();

  @override
  int get hashCode => canonical().hashCode;

  @override
  String toString() => 'CertificationKey(${canonical()})';

  static String _string(Map<String, Object?> json, String field) {
    if (!json.containsKey(field)) {
      throw FormatException('MISSING_FIELD=$field');
    }
    final v = json[field];
    if (v is! String) {
      throw FormatException(
        'MALFORMED_FIELD=$field expected=String found=${v.runtimeType}',
      );
    }
    return v;
  }
}

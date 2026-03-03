import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

/// Canonical VK Play signer:
/// - sort top-level params alphabetically,
/// - preserve nested JSON order,
/// - append secret,
/// - MD5 digest.
final class VkPlaySigner {
  const VkPlaySigner({this.boolAsInt = true});

  final bool boolAsInt;

  String sign({
    required final Map<String, Object?> params,
    required final String secret,
    final Iterable<String> excludedKeys = const <String>{'sig', 'signature'},
  }) {
    return signWithDiagnostics(
      params: params,
      secret: secret,
      excludedKeys: excludedKeys,
    ).signature;
  }

  VkPlaySignatureResult signWithDiagnostics({
    required final Map<String, Object?> params,
    required final String secret,
    final Iterable<String> excludedKeys = const <String>{'sig', 'signature'},
  }) {
    final excluded = excludedKeys.toSet();
    final keys = params.keys.where((final k) => !excluded.contains(k)).toList()
      ..sort();

    final skippedNullKeys = <String>[];
    final payloadBuffer = StringBuffer();

    for (final key in keys) {
      final value = params[key];
      if (value == null) {
        skippedNullKeys.add(key);
        continue;
      }
      payloadBuffer
        ..write(key)
        ..write('=')
        ..write(_serializeValue(value));
    }
    payloadBuffer.write(secret);

    final canonicalPayload = payloadBuffer.toString();
    final signature = md5.convert(utf8.encode(canonicalPayload)).toString();

    return VkPlaySignatureResult(
      signature: signature,
      diagnostics: VkPlaySignatureDiagnostics(
        canonicalPayload: canonicalPayload,
        sortedKeys: List<String>.unmodifiable(keys),
        skippedNullKeys: List<String>.unmodifiable(skippedNullKeys),
      ),
    );
  }

  bool verify({
    required final Map<String, Object?> params,
    required final String secret,
    required final String expectedSignature,
    final Iterable<String> excludedKeys = const <String>{'sig', 'signature'},
  }) {
    final actual = sign(
      params: params,
      secret: secret,
      excludedKeys: excludedKeys,
    );
    return actual.toLowerCase() == expectedSignature.toLowerCase();
  }

  String _serializeValue(final Object value) {
    if (value is bool) {
      if (boolAsInt) {
        return value ? '1' : '0';
      }
      return value.toString();
    }
    if (value is num || value is String) {
      return value.toString();
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }
}

bool verifyVkPlayCallbackSignature({
  required final Map<String, Object?> payload,
  required final String secret,
  final String signatureKey = 'sig',
  final VkPlaySigner signer = const VkPlaySigner(),
}) {
  final provided = payload[signatureKey];
  if (provided == null) {
    return false;
  }

  final expected = provided.toString();
  final data = <String, Object?>{...payload}..remove(signatureKey);
  return signer.verify(
    params: data,
    secret: secret,
    expectedSignature: expected,
    excludedKeys: <String>{signatureKey},
  );
}

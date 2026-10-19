/// Offline, content-free context comparison. Eligibility is conditional on the
/// adapter's declared policy and representation; it is never a provider hit.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const contextCacheIntentMetadataKey = 'context_cache_intent';

const contextCacheComparisonMetadataKey = 'context_cache_comparison';

/// Optional provider-assisted comparison, separate from cache write policy.
final class ContextCacheComparisonRequest {
  ContextCacheComparisonRequest({required this.baselineResponseId}) {
    if (!RegExp(r'^[a-zA-Z0-9_.:/-]{1,160}$').hasMatch(baselineResponseId)) {
      throw const FormatException('cache_comparison_id_invalid');
    }
  }
  factory ContextCacheComparisonRequest.fromJson(Map<String, Object?> json) =>
      ContextCacheComparisonRequest(
        baselineResponseId: json['baselineResponseId']! as String,
      );
  final String baselineResponseId;
  Map<String, Object?> toJson() => {'baselineResponseId': baselineResponseId};
}

enum ContextCacheSupport { known, unknown }

enum ContextDiagnosticCoverage { complete, incomplete, unknown }

enum ContextCompatibilityStatus { compatible, incompatible, unknown }

enum ContextTransportDiagnosticStage { request, settled }

final class ContextCacheIntent {
  ContextCacheIntent({
    List<String> writeAfterSegmentIds = const [],
    List<String> lookupAfterSegmentIds = const [],
    this.policyId,
  }) : writeAfterSegmentIds = List.unmodifiable(writeAfterSegmentIds),
       lookupAfterSegmentIds = List.unmodifiable(lookupAfterSegmentIds);
  factory ContextCacheIntent.fromJson(Map<String, Object?> json) =>
      ContextCacheIntent(
        writeAfterSegmentIds: _strings(json['writeAfterSegmentIds']),
        lookupAfterSegmentIds: _strings(json['lookupAfterSegmentIds']),
        policyId: json['policyId'] as String?,
      );
  final List<String> writeAfterSegmentIds;
  final List<String> lookupAfterSegmentIds;
  final String? policyId;
  Map<String, Object?> toJson() => {
    'writeAfterSegmentIds': writeAfterSegmentIds,
    'lookupAfterSegmentIds': lookupAfterSegmentIds,
    if (policyId != null) 'policyId': policyId,
  };
}

/// These raw inputs never survive capture or appear in snapshot JSON.
final class ContextDiagnosticSegmentInput {
  ContextDiagnosticSegmentInput.text({
    required this.id,
    required this.kind,
    required String this.text,
  }) : excludedReason = null;
  const ContextDiagnosticSegmentInput.excluded({
    required this.id,
    required this.kind,
    required String reason,
  }) : text = null,
       excludedReason = reason;
  final String id;
  final String kind;
  final String? text;
  final String? excludedReason;
}

final class ContextRequestCompatibility {
  const ContextRequestCompatibility({
    this.configurationSha256,
    this.provider,
    this.model,
    this.realmCohort,
  });
  factory ContextRequestCompatibility.fromJson(Map<String, Object?> json) =>
      ContextRequestCompatibility(
        configurationSha256: _hash(json['configurationSha256']),
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        realmCohort: json['realmCohort'] as String?,
      );
  final String? configurationSha256;
  final String? provider;
  final String? model;
  final String? realmCohort;
  Map<String, Object?> toJson() => {
    if (configurationSha256 != null) 'configurationSha256': configurationSha256,
    if (provider != null) 'provider': provider,
    if (model != null) 'model': model,
    if (realmCohort != null) 'realmCohort': realmCohort,
  };
}

/// A declared write endpoint and a lookup endpoint are different observations.
/// Support defaults unknown: identical content alone creates no cache boundary.
final class CacheWriteEndpoint {
  CacheWriteEndpoint({
    required this.afterSegmentId,
    required this.policyId,
    this.support = ContextCacheSupport.unknown,
    List<String> provenanceRefs = const [],
  }) : provenanceRefs = List.unmodifiable(provenanceRefs);
  factory CacheWriteEndpoint.fromJson(Map<String, Object?> json) =>
      CacheWriteEndpoint(
        afterSegmentId: json['afterSegmentId']! as String,
        policyId: json['policyId']! as String,
        support: ContextCacheSupport.values.byName(json['support']! as String),
        provenanceRefs: _strings(json['provenanceRefs']),
      );
  final String afterSegmentId;
  final String policyId;
  final ContextCacheSupport support;
  final List<String> provenanceRefs;
  Map<String, Object?> toJson() =>
      _endpointJson(afterSegmentId, policyId, support, provenanceRefs);
}

final class CacheLookupEndpoint {
  CacheLookupEndpoint({
    required this.afterSegmentId,
    required this.policyId,
    this.support = ContextCacheSupport.unknown,
    List<String> provenanceRefs = const [],
  }) : provenanceRefs = List.unmodifiable(provenanceRefs);
  factory CacheLookupEndpoint.fromJson(Map<String, Object?> json) =>
      CacheLookupEndpoint(
        afterSegmentId: json['afterSegmentId']! as String,
        policyId: json['policyId']! as String,
        support: ContextCacheSupport.values.byName(json['support']! as String),
        provenanceRefs: _strings(json['provenanceRefs']),
      );
  final String afterSegmentId;
  final String policyId;
  final ContextCacheSupport support;
  final List<String> provenanceRefs;
  Map<String, Object?> toJson() =>
      _endpointJson(afterSegmentId, policyId, support, provenanceRefs);
}

final class ContextCacheUsage {
  const ContextCacheUsage({
    this.inputTokens,
    this.cachedTokens,
    this.cacheWriteTokens,
    this.outputTokens,
  });
  factory ContextCacheUsage.fromJson(Map<String, Object?> json) =>
      ContextCacheUsage(
        inputTokens: _count(json['inputTokens']),
        cachedTokens: _count(json['cachedTokens']),
        cacheWriteTokens: _count(json['cacheWriteTokens']),
        outputTokens: _count(json['outputTokens']),
      );
  final int? inputTokens;
  final int? cachedTokens;
  final int? cacheWriteTokens;
  final int? outputTokens;
  Map<String, Object?> toJson() => {
    if (inputTokens != null) 'inputTokens': inputTokens,
    if (cachedTokens != null) 'cachedTokens': cachedTokens,
    if (cacheWriteTokens != null) 'cacheWriteTokens': cacheWriteTokens,
    if (outputTokens != null) 'outputTokens': outputTokens,
  };
}

final class ContextDiagnosticInput {
  ContextDiagnosticInput({
    required List<ContextDiagnosticSegmentInput> segments,
    required this.representationId,
    this.coverage = ContextDiagnosticCoverage.complete,
    this.compatibility,
    List<CacheWriteEndpoint> writeEndpoints = const [],
    List<CacheLookupEndpoint> lookupEndpoints = const [],
    this.usage,
    this.exactWire = false,
  }) : segments = List.unmodifiable(segments),
       writeEndpoints = List.unmodifiable(writeEndpoints),
       lookupEndpoints = List.unmodifiable(lookupEndpoints);
  final List<ContextDiagnosticSegmentInput> segments;
  final String representationId;
  final ContextDiagnosticCoverage coverage;
  final ContextRequestCompatibility? compatibility;
  final List<CacheWriteEndpoint> writeEndpoints;
  final List<CacheLookupEndpoint> lookupEndpoints;
  final ContextCacheUsage? usage;
  final bool exactWire;
}

final class ContextDiagnosticSegment {
  const ContextDiagnosticSegment({
    required this.id,
    required this.kind,
    this.utf8Bytes,
    this.sha256,
    this.excludedReason,
  });
  factory ContextDiagnosticSegment.fromJson(Map<String, Object?> json) =>
      ContextDiagnosticSegment(
        id: json['id']! as String,
        kind: json['kind']! as String,
        utf8Bytes: _count(json['utf8Bytes']),
        sha256: _hash(json['sha256']),
        excludedReason: json['excludedReason'] as String?,
      );
  final String id;
  final String kind;
  final int? utf8Bytes;
  final String? sha256;
  final String? excludedReason;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'utf8Bytes': utf8Bytes,
    'sha256': sha256,
    if (excludedReason != null) 'excludedReason': excludedReason,
  };
}

/// Prefix evidence covers preceding bytes in the declared representation.
/// Legacy independent segment hashes cannot synthesize this evidence.
final class ContextPrefixBoundary {
  ContextPrefixBoundary({
    required this.afterSegmentId,
    this.prefixUtf8Bytes,
    this.prefixSha256,
    List<String> provenanceRefs = const [],
  }) : provenanceRefs = List.unmodifiable(provenanceRefs);
  factory ContextPrefixBoundary.fromJson(Map<String, Object?> json) =>
      ContextPrefixBoundary(
        afterSegmentId: json['afterSegmentId']! as String,
        prefixUtf8Bytes: _count(json['prefixUtf8Bytes']),
        prefixSha256: _hash(json['prefixSha256']),
        provenanceRefs: _strings(json['provenanceRefs']),
      );
  final String afterSegmentId;
  final int? prefixUtf8Bytes;
  final String? prefixSha256;
  final List<String> provenanceRefs;
  Map<String, Object?> toJson() => {
    'afterSegmentId': afterSegmentId,
    'prefixUtf8Bytes': prefixUtf8Bytes,
    'prefixSha256': prefixSha256,
    'provenanceRefs': provenanceRefs,
  };
}

final class ContextDiagnosticSnapshot {
  ContextDiagnosticSnapshot({
    required this.representationId,
    required this.coverage,
    required this.boundaryCoverage,
    required List<ContextDiagnosticSegment> segments,
    required List<ContextPrefixBoundary> boundaries,
    this.compatibility,
    List<CacheWriteEndpoint> writeEndpoints = const [],
    List<CacheLookupEndpoint> lookupEndpoints = const [],
    this.usage,
    this.exactWire = false,
  }) : segments = List.unmodifiable(segments),
       boundaries = List.unmodifiable(boundaries),
       writeEndpoints = List.unmodifiable(writeEndpoints),
       lookupEndpoints = List.unmodifiable(lookupEndpoints) {
    _unique(this.segments.map((s) => s.id));
    _unique(this.boundaries.map((s) => s.afterSegmentId));
    if (exactWire && coverage != ContextDiagnosticCoverage.complete) {
      throw ArgumentError(
        'Incomplete capture cannot claim exact wire coverage',
      );
    }
  }
  factory ContextDiagnosticSnapshot.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) throw const FormatException('snapshot_version');
    return ContextDiagnosticSnapshot(
      representationId: json['representationId']! as String,
      coverage: ContextDiagnosticCoverage.values.byName(
        json['coverage']! as String,
      ),
      boundaryCoverage: ContextDiagnosticCoverage.values.byName(
        json['boundaryCoverage']! as String,
      ),
      exactWire: json['exactWire'] == true,
      segments: _maps(json['segments'])
          .map(ContextDiagnosticSegment.fromJson)
          .toList(),
      boundaries: _maps(json['boundaries'])
          .map(ContextPrefixBoundary.fromJson)
          .toList(),
      compatibility: json['compatibility'] == null
          ? null
          : ContextRequestCompatibility.fromJson(_map(json['compatibility'])),
      writeEndpoints: _maps(json['writeEndpoints'])
          .map(CacheWriteEndpoint.fromJson)
          .toList(),
      lookupEndpoints: _maps(json['lookupEndpoints'])
          .map(CacheLookupEndpoint.fromJson)
          .toList(),
      usage: json['usage'] == null
          ? null
          : ContextCacheUsage.fromJson(_map(json['usage'])),
    );
  }
  final String representationId;
  final ContextDiagnosticCoverage coverage;
  final ContextDiagnosticCoverage boundaryCoverage;
  final List<ContextDiagnosticSegment> segments;
  final List<ContextPrefixBoundary> boundaries;
  final ContextRequestCompatibility? compatibility;
  final List<CacheWriteEndpoint> writeEndpoints;
  final List<CacheLookupEndpoint> lookupEndpoints;
  final ContextCacheUsage? usage;
  final bool exactWire;
  Map<String, Object?> toJson() => {
    'version': 1,
    'representationId': representationId,
    'coverage': coverage.name,
    'boundaryCoverage': boundaryCoverage.name,
    'exactWire': exactWire,
    'segments': segments.map((s) => s.toJson()).toList(),
    'boundaries': boundaries.map((s) => s.toJson()).toList(),
    if (compatibility != null) 'compatibility': compatibility!.toJson(),
    'writeEndpoints': writeEndpoints.map((e) => e.toJson()).toList(),
    'lookupEndpoints': lookupEndpoints.map((e) => e.toJson()).toList(),
    if (usage != null) 'usage': usage!.toJson(),
  };
}

final class ContextEligibleEndpoint {
  const ContextEligibleEndpoint({
    required this.writeAfterSegmentId,
    required this.lookupAfterSegmentId,
    required this.policyId,
    required this.prefixUtf8Bytes,
    required this.prefixSha256,
  });
  final String writeAfterSegmentId;
  final String lookupAfterSegmentId;
  final String policyId;
  final int prefixUtf8Bytes;
  final String prefixSha256;
  Map<String, Object?> toJson() => {
    'writeAfterSegmentId': writeAfterSegmentId,
    'lookupAfterSegmentId': lookupAfterSegmentId,
    'policyId': policyId,
    'prefixUtf8Bytes': prefixUtf8Bytes,
    'prefixSha256': prefixSha256,
  };
}

final class ContextCacheComparison {
  ContextCacheComparison({
    required this.compatibility,
    required this.firstDivergenceIndex,
    required this.divergenceKnown,
    required List<ContextEligibleEndpoint> eligibleSharedEndpoints,
    required List<String> unresolved,
    this.observedUsage,
  }) : eligibleSharedEndpoints = List.unmodifiable(eligibleSharedEndpoints),
       unresolved = List.unmodifiable(unresolved);
  final ContextCompatibilityStatus compatibility;
  final int? firstDivergenceIndex;
  final bool divergenceKnown;
  final List<ContextEligibleEndpoint> eligibleSharedEndpoints;
  final List<String> unresolved;

  /// Reported later-request usage is evidence separate from predicted reuse.
  final ContextCacheUsage? observedUsage;
  Map<String, Object?> toJson() => {
    'compatibility': compatibility.name,
    'firstDivergenceIndex': firstDivergenceIndex,
    'divergenceKnown': divergenceKnown,
    'eligibleSharedEndpoints': eligibleSharedEndpoints
        .map((e) => e.toJson())
        .toList(),
    'unresolved': unresolved,
    if (observedUsage != null) 'observedUsage': observedUsage!.toJson(),
    'eligibilityIsObservedHit': false,
  };
}

/// Optional single-event observer, not a history or another execution loop.
final class ContextTransportDiagnosticCapture {
  const ContextTransportDiagnosticCapture({
    required this.observer,
    this.includeEncodedBody = false,
  });
  final void Function(ContextTransportDiagnosticEvent) observer;
  final bool includeEncodedBody;
}

/// Safe transport comparison, without credential values or raw header values.
/// Fingerprints show equality only; edge/request IDs do not identify a worker.
Map<String, Object?> captureContextTransportMetadata({
  required Uri endpoint,
  required String method,
  required Map<String, String> requestHeaders,
  required Map<String, dynamic> requestBody,
  required String clientCohort,
  required bool followRedirects,
  Map<String, String>? responseHeaders,
}) {
  try {
    final headers = {
      for (final entry in requestHeaders.entries)
        entry.key.toLowerCase(): entry.value,
    };
    Map<String, Object?> fingerprint(Object? value, {required bool present}) =>
        Map.unmodifiable(
          present
              ? {
                  'state': 'present',
                  'sha256': sha256
                      .convert(utf8.encode(jsonEncode(value)))
                      .toString(),
                }
              : {'state': 'absent'},
        );
    const bodyKeys = [
      'session_id',
      'prompt_cache_key',
      'prompt_cache_options',
      'prompt_cache_retention',
      'cache_control',
      'provider',
      'models',
      'route',
      'service_tier',
    ];
    const routingHeaders = [
      'session-id',
      'thread-id',
      'x-codex-turn-state',
      'session_id',
      'conversation_id',
      'x-session-id',
      'x-conversation-id',
      'x-openai-session-id',
      'x-session-affinity',
    ];
    const responseKeys = [
      'session-id',
      'thread-id',
      'x-codex-turn-state',
      'x-request-id',
      'x-openai-request-id',
      'openai-version',
      'openai-model',
      'x-openai-model',
      'server',
      'via',
      'x-cache',
      'x-cache-status',
      'x-served-by',
      'x-backend',
      'x-openrouter-provider',
      'openrouter-provider',
      'cf-ray',
    ];
    final response = responseHeaders == null
        ? null
        : {
            for (final entry in responseHeaders.entries)
              entry.key.toLowerCase(): entry.value,
          };
    return Map.unmodifiable({
      'endpoint':
          '${endpoint.scheme}://${endpoint.authority.replaceFirst(RegExp('^.*@'), '')}${endpoint.path}',
      'method': method,
      'followRedirects': followRedirects,
      'clientCohort': clientCohort,
      'credentialCohort': 'unobserved',
      'backendWorker': 'unobserved',
      'connectionReuse': 'unobserved',
      'requestHeaderNames': (headers.keys.toList()..sort()),
      'requestControls': {
        for (final key in bodyKeys)
          'body.$key': fingerprint(
            requestBody[key],
            present: requestBody.containsKey(key),
          ),
        for (final key in routingHeaders)
          'header.$key': fingerprint(
            headers[key],
            present: headers.containsKey(key),
          ),
      },
      'responseHeaderFingerprints': {
        for (final key in responseKeys)
          key: response == null
              ? const {'state': 'unobserved'}
              : fingerprint(response[key], present: response.containsKey(key)),
      },
      'fingerprintsAreBackendIdentity': false,
    });
  } on Object {
    return const {
      'coverage': 'incomplete',
      'reason': 'transport_metadata_capture_failed',
    };
  }
}

/// Content-free hints from known HTTP rejection phrases, never remote prose.
/// Categories are lexical evidence, not a provider capability verdict. Both
/// adapters call this only after their bounded JSON/error-status checks.
Map<String, Object?> contextProviderErrorMessageHint(Object? decoded) {
  if (decoded is! Map) return const {};
  final error = decoded['error'];
  final candidates = <String, Object?>{
    'error.message': error is Map ? error['message'] : null,
    'detail': decoded['detail'],
    'error': error is String ? error : null,
  };
  for (final entry in candidates.entries) {
    final message = entry.value;
    if (message is! String || message.length > 16384) continue;
    final patterns = <String, String>{
      'extra_field':
          // Regex fragments concatenate without literal whitespace.
          // ignore: missing_whitespace_between_adjacent_strings
          'extra (?:inputs?|fields?).{0,30}'
          '(?:not permitted|not allowed|forbidden)|extra_forbidden',
      'unknown_parameter':
          '(?:unknown|unrecognized|unexpected).{0,30}'
          '(?:parameter|field|argument)|'
          '(?:parameter|field|argument).{0,30}'
          '(?:unknown|unrecognized|unexpected)',
      'unsupported_parameter':
          'unsupported.{0,30}(?:parameter|field|argument)|'
          '(?:parameter|field|argument).{0,30}(?:unsupported|not supported)',
      'not_supported': 'not supported|does not support|unsupported',
      'invalid_value': 'invalid value|invalid literal',
      'validation_error': 'validation error|validation failed',
      'invalid_type': 'invalid type|invalid content type',
      'missing_required': 'missing required|required field',
    };
    return Map.unmodifiable({
      'messageField': entry.key,
      'categories': List.unmodifiable([
        for (final entry in patterns.entries)
          if (RegExp(entry.value, caseSensitive: false).hasMatch(message))
            entry.key,
      ]),
      'mentionedParameters': List.unmodifiable([
        for (final key in const [
          'prompt_cache_breakpoint',
          'prompt_cache_options',
          'prompt_cache_key',
          'cache_control',
          'input',
          'messages',
          'model',
          'reasoning',
          'content',
          'role',
          'stream',
          'store',
        ])
          if (RegExp('\\b$key\\b').hasMatch(message)) key,
      ]),
    });
  }
  return const {};
}

final class ContextTransportDiagnosticEvent {
  ContextTransportDiagnosticEvent({
    required this.stage,
    required this.snapshot,
    this.exactEncodedBody,
    this.usageReported = false,
    Map<String, int> numericUsage = const {},
    this.responseId,
    this.model,
    this.serviceTier,
    this.outcome,
    this.httpStatus,
    Map<String, Object?> transport = const {},
    this.providerErrorCode,
    this.providerErrorType,
    this.providerErrorParam,
    Map<String, Object?> providerErrorMessageHint = const {},
    Map<String, bool> providerErrorFieldPresence = const {},
  }) : transport = Map.unmodifiable(transport),
       providerErrorMessageHint = Map.unmodifiable(providerErrorMessageHint),
       numericUsage = Map.unmodifiable(numericUsage),
       providerErrorFieldPresence = Map.unmodifiable(
         providerErrorFieldPresence,
       ) {
    if (exactEncodedBody != null && !snapshot.exactWire) {
      throw ArgumentError('Body requires complete exact-wire snapshot');
    }
  }
  factory ContextTransportDiagnosticEvent.fromJson(Map<String, Object?> json) =>
      ContextTransportDiagnosticEvent(
        stage: ContextTransportDiagnosticStage.values.byName(
          json['stage']! as String,
        ),
        snapshot: ContextDiagnosticSnapshot.fromJson(_map(json['snapshot'])),
        exactEncodedBody: json['exactEncodedBody'] as String?,
        usageReported: json['usageReported'] == true,
        numericUsage: _map(json['numericUsage'])
            .map((key, value) => MapEntry(key, _count(value)!)),
        responseId: json['responseId'] as String?,
        model: json['model'] as String?,
        serviceTier: json['serviceTier'] as String?,
        outcome: json['outcome'] as String?,
        httpStatus: _count(json['httpStatus']),
        transport: json['transport'] == null
            ? const {}
            : _map(json['transport']),
        providerErrorCode: json['providerErrorCode'] as String?,
        providerErrorType: json['providerErrorType'] as String?,
        providerErrorParam: json['providerErrorParam'] as String?,
        providerErrorMessageHint: json['providerErrorMessageHint'] == null
            ? const {}
            : _map(json['providerErrorMessageHint']),
        providerErrorFieldPresence: json['providerErrorFieldPresence'] == null
            ? const {}
            : _map(json['providerErrorFieldPresence'])
                  .map((key, value) => MapEntry(key, value! as bool)),
      );
  final ContextTransportDiagnosticStage stage;
  final ContextDiagnosticSnapshot snapshot;

  /// Explicit opt-in only, never headers, credentials or encrypted fields.
  final String? exactEncodedBody;
  final bool usageReported;
  final Map<String, int> numericUsage;
  final String? responseId;
  final String? model;
  final String? serviceTier;
  final String? outcome;
  final int? httpStatus;
  final Map<String, Object?> transport;
  final String? providerErrorCode;
  final String? providerErrorType;
  final String? providerErrorParam;
  final Map<String, Object?> providerErrorMessageHint;

  /// Presence only; adapters filter values before populating error fields.
  final Map<String, bool> providerErrorFieldPresence;
  Map<String, Object?> toJson() => {
    'stage': stage.name,
    'snapshot': snapshot.toJson(),
    if (exactEncodedBody != null) 'exactEncodedBody': exactEncodedBody,
    'usageReported': usageReported,
    'numericUsage': numericUsage,
    if (responseId != null) 'responseId': responseId,
    if (model != null) 'model': model,
    if (serviceTier != null) 'serviceTier': serviceTier,
    if (outcome != null) 'outcome': outcome,
    if (httpStatus != null) 'httpStatus': httpStatus,
    if (transport.isNotEmpty) 'transport': transport,
    if (providerErrorCode != null) 'providerErrorCode': providerErrorCode,
    if (providerErrorType != null) 'providerErrorType': providerErrorType,
    if (providerErrorParam != null) 'providerErrorParam': providerErrorParam,
    if (providerErrorMessageHint.isNotEmpty)
      'providerErrorMessageHint': providerErrorMessageHint,
    if (providerErrorFieldPresence.isNotEmpty)
      'providerErrorFieldPresence': providerErrorFieldPresence,
  };
}

/// Internal JSON/text divergence is diagnostic, never a cache endpoint.
final class ContextJsonDivergence {
  const ContextJsonDivergence({
    required this.coverage,
    this.incompleteReason,
    this.commonJsonPrefixUtf8Bytes,
    this.commonJsonPrefixSha256,
    this.firstChangedJsonPath,
    this.commonTextPrefixUtf8Bytes,
    this.commonTextPrefixCodeUnits,
    this.earlierTextSuffixUtf8Bytes,
    this.laterTextSuffixUtf8Bytes,
  });
  factory ContextJsonDivergence.fromJson(Map<String, Object?> json) =>
      ContextJsonDivergence(
        coverage: ContextDiagnosticCoverage.values.byName(
          json['coverage']! as String,
        ),
        incompleteReason: json['incompleteReason'] as String?,
        commonJsonPrefixUtf8Bytes: _count(json['commonJsonPrefixUtf8Bytes']),
        commonJsonPrefixSha256: _hash(json['commonJsonPrefixSha256']),
        firstChangedJsonPath: json['firstChangedJsonPath'] as String?,
        commonTextPrefixUtf8Bytes: _count(json['commonTextPrefixUtf8Bytes']),
        commonTextPrefixCodeUnits: _count(json['commonTextPrefixCodeUnits']),
        earlierTextSuffixUtf8Bytes: _count(json['earlierTextSuffixUtf8Bytes']),
        laterTextSuffixUtf8Bytes: _count(json['laterTextSuffixUtf8Bytes']),
      );
  final ContextDiagnosticCoverage coverage;
  final String? incompleteReason;
  final int? commonJsonPrefixUtf8Bytes;
  final String? commonJsonPrefixSha256;
  final String? firstChangedJsonPath;
  final int? commonTextPrefixUtf8Bytes;
  final int? commonTextPrefixCodeUnits;
  final int? earlierTextSuffixUtf8Bytes;
  final int? laterTextSuffixUtf8Bytes;
  Map<String, Object?> toJson() => {
    'coverage': coverage.name,
    if (incompleteReason != null) 'incompleteReason': incompleteReason,
    'commonJsonPrefixUtf8Bytes': commonJsonPrefixUtf8Bytes,
    'commonJsonPrefixSha256': commonJsonPrefixSha256,
    'firstChangedJsonPath': firstChangedJsonPath,
    'commonTextPrefixUtf8Bytes': commonTextPrefixUtf8Bytes,
    'commonTextPrefixCodeUnits': commonTextPrefixCodeUnits,
    'earlierTextSuffixUtf8Bytes': earlierTextSuffixUtf8Bytes,
    'laterTextSuffixUtf8Bytes': laterTextSuffixUtf8Bytes,
    'internalPrefixIsCacheEndpoint': false,
  };
}

// Static facade keeps capture and comparison discoverable as one offline API.
// ignore: avoid_classes_with_only_static_members
abstract final class ContextCacheAnalyzer {
  /// Compares actual jsonEncode UTF-8 sequences, without exporting their text.
  /// Byte prefixes may end inside a multibyte character; code units are UTF-16.
  /// Missing lists, encrypted fields and non-JSON objects refuse hashes.
  static ContextJsonDivergence compareJsonRequests(
    Map<String, Object?> earlier,
    Map<String, Object?> later, {
    required List<String> messageListPath,
    int? maxEncodedBytes,
    int? maxDepth,
  }) {
    bool hasMessages(Map<String, Object?> request) {
      Object? value = request;
      for (final key in messageListPath) {
        if (value is! Map || !value.containsKey(key)) return false;
        value = value[key];
      }
      return messageListPath.isNotEmpty && value is List;
    }

    if ((maxEncodedBytes != null && maxEncodedBytes < 0) ||
        (maxDepth != null && maxDepth < 0)) {
      throw ArgumentError('invalid_diagnostic_budget');
    }
    final problem = !hasMessages(earlier) || !hasMessages(later)
        ? 'message_list_missing'
        : _jsonProblem(earlier, maxDepth: maxDepth) ??
              _jsonProblem(later, maxDepth: maxDepth);
    if (problem != null) {
      return ContextJsonDivergence(
        coverage: ContextDiagnosticCoverage.incomplete,
        incompleteReason: problem,
      );
    }
    final a = utf8.encode(jsonEncode(earlier));
    final b = utf8.encode(jsonEncode(later));
    if (maxEncodedBytes != null &&
        (a.length > maxEncodedBytes || b.length > maxEncodedBytes)) {
      return const ContextJsonDivergence(
        coverage: ContextDiagnosticCoverage.incomplete,
        incompleteReason: 'max_encoded_bytes_exceeded',
      );
    }
    final prefix = _commonPrefix(a, b);
    final change = _firstJsonChange(earlier, later, r'$');
    final leftText = change?.leftText;
    final rightText = change?.rightText;
    final textA = leftText == null ? null : utf8.encode(leftText);
    final textB = rightText == null ? null : utf8.encode(rightText);
    final textPrefix = textA == null || textB == null
        ? null
        : _commonPrefix(textA, textB);
    return ContextJsonDivergence(
      coverage: ContextDiagnosticCoverage.complete,
      commonJsonPrefixUtf8Bytes: prefix,
      commonJsonPrefixSha256: _digest(a.sublist(0, prefix)),
      firstChangedJsonPath: change?.path,
      commonTextPrefixUtf8Bytes: textPrefix,
      commonTextPrefixCodeUnits: leftText == null || rightText == null
          ? null
          : _commonPrefix(leftText.codeUnits, rightText.codeUnits),
      earlierTextSuffixUtf8Bytes: textPrefix == null
          ? null
          : textA!.length - textPrefix,
      laterTextSuffixUtf8Bytes: textPrefix == null
          ? null
          : textB!.length - textPrefix,
    );
  }

  static ContextDiagnosticSnapshot capture(ContextDiagnosticInput input) {
    if (input.segments.length > 4096) {
      throw ArgumentError('diagnostic_segment_limit');
    }
    final segments = <ContextDiagnosticSegment>[];
    final boundaries = <ContextPrefixBoundary>[];
    final prefix = <int>[];
    var prefixKnown = true;
    var coverage = input.coverage;
    for (final segment in input.segments) {
      final text = segment.text;
      if (text == null) {
        prefixKnown = false;
        coverage = ContextDiagnosticCoverage.incomplete;
        segments.add(
          ContextDiagnosticSegment(
            id: segment.id,
            kind: segment.kind,
            excludedReason: segment.excludedReason,
          ),
        );
      } else {
        final bytes = utf8.encode(text);
        segments.add(
          ContextDiagnosticSegment(
            id: segment.id,
            kind: segment.kind,
            utf8Bytes: bytes.length,
            sha256: _digest(bytes),
          ),
        );
        if (prefixKnown) prefix.addAll(bytes);
      }
      boundaries.add(
        ContextPrefixBoundary(
          afterSegmentId: segment.id,
          prefixUtf8Bytes: prefixKnown ? prefix.length : null,
          prefixSha256: prefixKnown ? _digest(prefix) : null,
        ),
      );
    }
    return ContextDiagnosticSnapshot(
      representationId: input.representationId,
      coverage: coverage,
      boundaryCoverage: prefixKnown
          ? input.coverage
          : ContextDiagnosticCoverage.incomplete,
      segments: segments,
      boundaries: boundaries,
      compatibility: input.compatibility,
      writeEndpoints: input.writeEndpoints,
      lookupEndpoints: input.lookupEndpoints,
      usage: input.usage,
      exactWire:
          input.exactWire && coverage == ContextDiagnosticCoverage.complete,
    );
  }

  /// Pure raw-structure adapter. It fingerprints jsonEncode's UTF-8 sequence,
  /// not a provider's hidden token rendering. No field names are cache policy.
  /// Message/configuration ordering is preserved, never sorted or padded.
  static ContextDiagnosticSnapshot captureJsonRequest(
    Map<String, Object?> request, {
    required List<String> messageListPath,
    String representationId = 'json-utf8-v1',
    ContextRequestCompatibility? compatibility,
    List<CacheWriteEndpoint> writeEndpoints = const [],
    List<CacheLookupEndpoint> lookupEndpoints = const [],
    ContextCacheUsage? usage,
    bool exactWire = false,
    List<List<String>> configurationIgnoredPaths = const [],
  }) {
    if (messageListPath.isEmpty) {
      throw ArgumentError('message_list_path_required');
    }
    Object? messages = request;
    for (final key in messageListPath) {
      if (messages is! Map || !messages.containsKey(key)) {
        throw ArgumentError('message_list_path_missing');
      }
      messages = messages[key];
    }
    if (messages is! List) throw ArgumentError('message_list_required');
    final builder = _JsonSegments(messageListPath);
    builder.emit(request, const [], 'request');
    final omitted = Object();
    Object? configuration(Object? value, List<String> path) {
      if (value is! Map) return value;
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final childPath = [...path, entry.key as String];
        if (_samePath(childPath, messageListPath) ||
            configurationIgnoredPaths.any((p) => _samePath(p, childPath))) {
          continue;
        }
        final child = configuration(entry.value, childPath);
        if (!identical(child, omitted)) result[entry.key as String] = child;
      }
      if (path.isNotEmpty &&
          result.isEmpty &&
          value.isNotEmpty &&
          configurationIgnoredPaths.any(
            (p) =>
                p.length > path.length &&
                _samePath(p.take(path.length).toList(), path),
          )) {
        return omitted;
      }
      return result;
    }

    final config = configuration(request, const []);
    return capture(
      ContextDiagnosticInput(
        segments: builder.segments,
        representationId: representationId,
        compatibility: ContextRequestCompatibility(
          configurationSha256: _encrypted(config)
              ? null
              : _digest(utf8.encode(jsonEncode(config))),
          provider: compatibility?.provider,
          model: compatibility?.model,
          realmCohort: compatibility?.realmCohort,
        ),
        writeEndpoints: writeEndpoints,
        lookupEndpoints: lookupEndpoints,
        usage: usage,
        exactWire: exactWire,
      ),
    );
  }

  /// Independent hashes do not establish request order or cumulative prefixes.
  /// An explicitly attributed sidecar can supply prefix evidence.
  static ContextDiagnosticSnapshot importLegacyFingerprints(
    Map<String, Object?> fingerprints, {
    String representationId = 'legacy-independent-segments-v1',
    ContextRequestCompatibility? compatibility,
    List<ContextPrefixBoundary> boundaryEvidence = const [],
    List<CacheWriteEndpoint> writeEndpoints = const [],
    List<CacheLookupEndpoint> lookupEndpoints = const [],
    ContextCacheUsage? usage,
  }) {
    for (final boundary in boundaryEvidence) {
      if (boundary.provenanceRefs.isEmpty ||
          boundary.prefixSha256 == null ||
          boundary.prefixUtf8Bytes == null) {
        throw ArgumentError('legacy_boundary_provenance_required');
      }
    }
    return ContextDiagnosticSnapshot(
      representationId: representationId,
      coverage: ContextDiagnosticCoverage.unknown,
      boundaryCoverage: ContextDiagnosticCoverage.unknown,
      segments: [
        for (final e in fingerprints.entries)
          ContextDiagnosticSegment(
            id: e.key,
            kind: 'legacy',
            utf8Bytes: _count(_map(e.value)['bytes']),
            sha256: _hash(_map(e.value)['sha256']),
          ),
      ],
      boundaries: boundaryEvidence,
      compatibility: compatibility,
      writeEndpoints: writeEndpoints,
      lookupEndpoints: lookupEndpoints,
      usage: usage,
    );
  }

  static ContextCacheComparison compare(
    ContextDiagnosticSnapshot earlier,
    ContextDiagnosticSnapshot later,
  ) {
    var compatible = ContextCompatibilityStatus.compatible;
    final unresolved = <String>[];
    if (earlier.representationId != later.representationId) {
      compatible = ContextCompatibilityStatus.incompatible;
    }
    final a = earlier.compatibility;
    final b = later.compatibility;
    if (a?.configurationSha256 == null || b?.configurationSha256 == null) {
      if (compatible != ContextCompatibilityStatus.incompatible) {
        compatible = ContextCompatibilityStatus.unknown;
      }
      unresolved.add('configuration_compatibility_unknown');
    } else if (a!.configurationSha256 != b!.configurationSha256) {
      compatible = ContextCompatibilityStatus.incompatible;
    }
    final dimsA = [a?.provider, a?.model, a?.realmCohort];
    final dimsB = [b?.provider, b?.model, b?.realmCohort];
    for (var i = 0; i < dimsA.length; i++) {
      if (dimsA[i] != dimsB[i]) {
        if (dimsA[i] != null && dimsB[i] != null) {
          compatible = ContextCompatibilityStatus.incompatible;
        } else if (compatible != ContextCompatibilityStatus.incompatible) {
          compatible = ContextCompatibilityStatus.unknown;
        }
      }
    }
    int? divergence;
    var divergenceKnown = true;
    final length = earlier.segments.length < later.segments.length
        ? earlier.segments.length
        : later.segments.length;
    for (var i = 0; i < length; i++) {
      final left = earlier.segments[i];
      final right = later.segments[i];
      if (left.sha256 == null || right.sha256 == null) {
        divergenceKnown = false;
        break;
      }
      if (left.id != right.id ||
          left.sha256 != right.sha256 ||
          left.utf8Bytes != right.utf8Bytes) {
        divergence = i;
        break;
      }
    }
    if (divergence == null &&
        divergenceKnown &&
        earlier.segments.length != later.segments.length) {
      divergence = length;
    }
    if (!divergenceKnown) unresolved.add('first_divergence_unknown');
    final leftBoundaries = {
      for (final e in earlier.boundaries) e.afterSegmentId: e,
    };
    final rightBoundaries = {
      for (final e in later.boundaries) e.afterSegmentId: e,
    };
    final eligible = <ContextEligibleEndpoint>[];
    if (earlier.writeEndpoints.isEmpty || later.lookupEndpoints.isEmpty) {
      unresolved.add('write_or_lookup_endpoints_not_declared');
    }
    for (final write in earlier.writeEndpoints) {
      for (final lookup in later.lookupEndpoints) {
        if (write.policyId != lookup.policyId) continue;
        if (write.support != ContextCacheSupport.known ||
            lookup.support != ContextCacheSupport.known) {
          unresolved.add('endpoint_support_unknown');
          continue;
        }
        final left = leftBoundaries[write.afterSegmentId];
        final right = rightBoundaries[lookup.afterSegmentId];
        if (left?.prefixSha256 == null ||
            right?.prefixSha256 == null ||
            left?.prefixUtf8Bytes == null ||
            right?.prefixUtf8Bytes == null) {
          unresolved.add('endpoint_prefix_unknown');
          continue;
        }
        if (compatible == ContextCompatibilityStatus.compatible &&
            left!.prefixSha256 == right!.prefixSha256 &&
            left.prefixUtf8Bytes == right.prefixUtf8Bytes) {
          eligible.add(
            ContextEligibleEndpoint(
              writeAfterSegmentId: write.afterSegmentId,
              lookupAfterSegmentId: lookup.afterSegmentId,
              policyId: write.policyId,
              prefixUtf8Bytes: left.prefixUtf8Bytes!,
              prefixSha256: left.prefixSha256!,
            ),
          );
        }
      }
    }
    return ContextCacheComparison(
      compatibility: compatible,
      firstDivergenceIndex: divergence,
      divergenceKnown: divergenceKnown,
      eligibleSharedEndpoints: eligible,
      unresolved: unresolved.toSet().toList(),
      observedUsage: later.usage,
    );
  }

  /// Directional [writer][lookup] matrix; each cell remains conditional reuse.
  static List<List<ContextCacheComparison>> reuseMatrix(
    List<ContextDiagnosticSnapshot> snapshots,
  ) => [
    for (final writer in snapshots)
      [for (final lookup in snapshots) compare(writer, lookup)],
  ];
}

final class _JsonSegments {
  _JsonSegments(this.messagePath);
  final List<String> messagePath;
  final List<ContextDiagnosticSegmentInput> segments = [];
  int sequence = 0;
  void add(String id, String kind, Object? value, {bool encoded = false}) {
    if (_encrypted(value)) {
      segments.add(
        ContextDiagnosticSegmentInput.excluded(
          id: id,
          kind: kind,
          reason: 'encrypted_content_excluded',
        ),
      );
      return;
    }
    segments.add(
      ContextDiagnosticSegmentInput.text(
        id: id,
        kind: kind,
        text: encoded ? value! as String : jsonEncode(value),
      ),
    );
  }

  void envelope(String text) =>
      add('json:${sequence++}', 'envelope', text, encoded: true);
  void emit(
    Object? value,
    List<String> path,
    String id, {
    bool message = false,
  }) {
    if (_samePath(path, messagePath)) {
      envelope('[');
      final list = value! as List;
      for (var i = 0; i < list.length; i++) {
        if (i > 0) envelope(',');
        emitMessage(list[i], '$id[$i]');
      }
      envelope(']');
      return;
    }
    if (value is Map &&
        path.length < messagePath.length &&
        _prefixPath(path, messagePath)) {
      envelope('{');
      var first = true;
      for (final e in value.entries) {
        if (!first) envelope(',');
        first = false;
        envelope('${jsonEncode(e.key)}:');
        emit(e.value, [
          ...path,
          e.key as String,
        ], path.isEmpty ? e.key as String : '$id.${e.key}');
      }
      envelope('}');
      return;
    }
    add(id, 'field', value);
  }

  void emitMessage(Object? message, String id) {
    if (message is! Map) {
      add(id, 'message', message);
      return;
    }
    envelope('{');
    var first = true;
    for (final e in message.entries) {
      if (!first) envelope(',');
      first = false;
      envelope('${jsonEncode(e.key)}:');
      if (e.key == 'content' && e.value is List) {
        envelope('[');
        final list = e.value as List;
        for (var i = 0; i < list.length; i++) {
          if (i > 0) envelope(',');
          add('$id.content[$i]', 'content', list[i]);
        }
        envelope(']');
      } else if (e.key == 'encrypted_content') {
        segments.add(
          ContextDiagnosticSegmentInput.excluded(
            id: '$id.encrypted_content',
            kind: 'field',
            reason: 'encrypted_content_excluded',
          ),
        );
      } else {
        add('$id.${e.key}', e.key == 'content' ? 'content' : 'field', e.value);
      }
    }
    add(id, 'message', '}', encoded: true);
  }
}

Map<String, Object?> _endpointJson(
  String id,
  String policy,
  ContextCacheSupport support,
  List<String> refs,
) => {
  'afterSegmentId': id,
  'policyId': policy,
  'support': support.name,
  'provenanceRefs': refs,
};
String _digest(List<int> bytes) => sha256.convert(bytes).toString();
Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);
List<Map<String, Object?>> _maps(Object? value) =>
    (value as List? ?? const []).map(_map).toList();
List<String> _strings(Object? value) =>
    (value as List? ?? const []).cast<String>();
int? _count(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0) throw const FormatException('invalid_count');
  return value;
}

String? _hash(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('invalid_sha256');
  }
  return value;
}

void _unique(Iterable<String> ids) {
  final all = ids.toList();
  if (all.any((s) => s.isEmpty) || all.toSet().length != all.length) {
    throw ArgumentError('diagnostic_ids_must_be_unique');
  }
}

bool _encrypted(Object? value) {
  if (value is Map) {
    return value.containsKey('encrypted_content') ||
        value.values.any(_encrypted);
  }
  if (value is List) return value.any(_encrypted);
  return false;
}

bool _samePath(List<String> a, List<String> b) =>
    a.length == b.length && _prefixPath(a, b);
bool _prefixPath(List<String> a, List<String> b) {
  if (a.length > b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _commonPrefix(List<int> a, List<int> b) {
  var index = 0;
  while (index < a.length && index < b.length && a[index] == b[index]) {
    index++;
  }
  return index;
}

String? _jsonProblem(
  Object? value, {
  int? maxDepth,
  int depth = 0,
  Set<Object>? ancestors,
}) {
  if (maxDepth != null && depth > maxDepth) return 'max_depth_exceeded';
  if (value == null || value is String || value is bool) return null;
  if (value is num) return value.isFinite ? null : 'non_finite_json_number';
  if (value is! List && value is! Map) return 'unsupported_json_value';
  final active = ancestors ?? Set<Object>.identity();
  if (!active.add(value)) return 'cyclic_json_structure';
  try {
    if (value is Map) {
      if (value.containsKey('encrypted_content')) {
        return 'encrypted_content_excluded';
      }
      if (value.keys.any((key) => key is! String)) return 'non_string_json_key';
    }
    final values = value is Map ? value.values : value as List;
    for (final child in values) {
      final problem = _jsonProblem(
        child,
        maxDepth: maxDepth,
        depth: depth + 1,
        ancestors: active,
      );
      if (problem != null) return problem;
    }
    return null;
  } finally {
    active.remove(value);
  }
}

typedef _JsonChange = ({String path, String? leftText, String? rightText});
_JsonChange? _firstJsonChange(Object? a, Object? b, String path) {
  _JsonChange changed() => (
    path: path,
    leftText: a is String ? a : null,
    rightText: b is String ? b : null,
  );
  if (a is Map && b is Map) {
    final keysA = a.keys.toList();
    final keysB = b.keys.toList();
    final length = keysA.length < keysB.length ? keysA.length : keysB.length;
    for (var i = 0; i < length; i++) {
      if (keysA[i] != keysB[i]) return changed();
      final child = _firstJsonChange(
        a[keysA[i]],
        b[keysB[i]],
        '$path[${jsonEncode(keysA[i])}]',
      );
      if (child != null) return child;
    }
    return keysA.length == keysB.length ? null : changed();
  }
  if (a is List && b is List) {
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final child = _firstJsonChange(a[i], b[i], '$path[$i]');
      if (child != null) return child;
    }
    return a.length == b.length ? null : changed();
  }
  return jsonEncode(a) == jsonEncode(b) ? null : changed();
}

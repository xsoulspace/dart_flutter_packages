import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

ContextDiagnosticSnapshot request(
  String suffix, {
  String boundary = 'messages[0].content[0]',
  String tool = 'read',
  String policy = 'declared-policy',
  ContextCacheSupport support = ContextCacheSupport.known,
  ContextCacheUsage? usage,
}) => ContextCacheAnalyzer.captureJsonRequest(
  {
    'model': 'example',
    'tools': [tool],
    'messages': [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'stable λ'},
          {'type': 'text', 'text': suffix},
        ],
      },
    ],
  },
  messageListPath: ['messages'],
  writeEndpoints: [
    CacheWriteEndpoint(
      afterSegmentId: boundary,
      policyId: policy,
      support: support,
    ),
  ],
  lookupEndpoints: [
    CacheLookupEndpoint(
      afterSegmentId: boundary,
      policyId: policy,
      support: support,
    ),
  ],
  usage: usage,
);

void main() {
  test('diagnostic-only config paths do not mask cache policy changes', () {
    ContextDiagnosticSnapshot capture(Map<String, dynamic> extra) =>
        ContextCacheAnalyzer.captureJsonRequest(
          {
            'model': 'same',
            'input': [
              {'role': 'user', 'content': 'same'},
            ],
            ...extra,
          },
          messageListPath: ['input'],
          configurationIgnoredPaths: const [
            ['prompt_cache_options', 'comparison_response_id'],
          ],
        );
    final plain = capture({});
    final compared = capture({
      'prompt_cache_options': {'comparison_response_id': 'resp_test'},
    });
    expect(
      compared.compatibility!.configurationSha256,
      plain.compatibility!.configurationSha256,
    );
    final changedPolicy = capture({
      'prompt_cache_options': {
        'comparison_response_id': 'resp_test',
        'mode': 'explicit',
      },
    });
    expect(
      changedPolicy.compatibility!.configurationSha256,
      isNot(plain.compatibility!.configurationSha256),
    );
    expect(
      compared.boundaries.last.prefixSha256,
      isNot(plain.boundaries.last.prefixSha256),
    );
  });

  test(
    'cache comparison is optional, finite and separate from cache intent',
    () {
      final option = ContextCacheComparisonRequest(
        baselineResponseId: 'resp_test',
      );
      expect(
        ContextCacheComparisonRequest.fromJson(option.toJson())
            .baselineResponseId,
        'resp_test',
      );
      expect(
        () => ContextCacheComparisonRequest(baselineResponseId: ''),
        throwsFormatException,
      );
    },
  );

  test(
    'transport controls compare without credential or raw header values',
    () {
      Map<String, Object?> capture(String credential, {String? key}) =>
          captureContextTransportMetadata(
            endpoint: Uri.parse(
              'https://private-user:private-pass@example.test/v1/responses?private-query=secret',
            ),
            method: 'POST',
            clientCohort: 'test-client-1',
            followRedirects: false,
            requestHeaders: {
              'Authorization': credential,
              'Content-Type': 'application/json',
            },
            requestBody: {'prompt_cache_key': ?key},
            responseHeaders: {
              'x-request-id': 'private-request-id',
              'set-cookie': 'private-cookie',
            },
          );
      final first = capture('private-token-a');
      expect(capture('private-token-b'), first);
      expect(first['endpoint'], 'https://example.test/v1/responses');
      expect((first['requestControls']! as Map)['body.prompt_cache_key'], {
        'state': 'absent',
      });
      final keyed = capture('private-token-a', key: 'private-cache-key');
      expect(
        (keyed['requestControls']! as Map)['body.prompt_cache_key'],
        containsPair('state', 'present'),
      );
      expect(jsonEncode(keyed), isNot(contains('private-')));
      expect(first['backendWorker'], 'unobserved');
      expect(first['fingerprintsAreBackendIdentity'], false);
      final event = ContextTransportDiagnosticEvent(
        stage: ContextTransportDiagnosticStage.settled,
        snapshot: request('one'),
        transport: first,
      );
      expect(
        ContextTransportDiagnosticEvent.fromJson(event.toJson()).transport,
        first,
      );
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      final refused = captureContextTransportMetadata(
        endpoint: Uri.parse('https://example.test'),
        method: 'POST',
        clientCohort: 'test',
        followRedirects: false,
        requestHeaders: {},
        requestBody: {'provider': cyclic},
      );
      expect(refused['reason'], 'transport_metadata_capture_failed');
    },
  );

  test(
    'shared rejection hints classify phrases without exporting remote prose',
    () {
      for (final body in [
        {
          'error': {
            'message':
                "Unknown parameter: 'prompt_cache_breakpoint'. "
                'private-secret',
          },
        },
        {
          'detail':
              'Unrecognized request argument supplied: '
              'prompt_cache_breakpoint private-secret',
        },
      ]) {
        final hint = contextProviderErrorMessageHint(body);
        expect(hint['categories'], contains('unknown_parameter'));
        expect(
          hint['mentionedParameters'],
          contains('prompt_cache_breakpoint'),
        );
        expect(jsonEncode(hint), isNot(contains('private-secret')));
      }
      final forbidden = contextProviderErrorMessageHint({
        'error': {
          'message':
              'prompt_cache_breakpoint: '
              'Extra inputs are not permitted private-source',
        },
      });
      expect(forbidden['categories'], contains('extra_field'));
      expect(
        contextProviderErrorMessageHint({
          'detail': {'private': 'source'},
        }),
        isEmpty,
      );
    },
  );

  test('large internal text prefix is measured but is not an endpoint', () {
    final stable = List.filled(253000, 'a').join();
    Map<String, Object?> body(String suffix) => {
      'messages': [
        {'role': 'user', 'content': '$stable$suffix'},
      ],
    };
    final result = ContextCacheAnalyzer.compareJsonRequests(
      body('old'),
      body('new'),
      messageListPath: ['messages'],
    );
    expect(result.coverage, ContextDiagnosticCoverage.complete);
    expect(result.commonTextPrefixUtf8Bytes, 253000);
    expect(result.commonTextPrefixCodeUnits, 253000);
    expect(result.earlierTextSuffixUtf8Bytes, 3);
    expect(result.laterTextSuffixUtf8Bytes, 3);
    expect(result.firstChangedJsonPath, r'$["messages"][0]["content"]');
    expect(result.toJson()['internalPrefixIsCacheEndpoint'], isFalse);
    expect(jsonEncode(result.toJson()), isNot(contains(stable)));
    expect(
      ContextJsonDivergence.fromJson(result.toJson()).toJson(),
      result.toJson(),
    );
  });

  test('large raw requests have no default byte cap or silent truncation', () {
    final text = 'a' * (8 * 1024 * 1024 + 1);
    final body = <String, Object?>{
      'messages': [text],
    };
    final full = ContextCacheAnalyzer.compareJsonRequests(
      body,
      body,
      messageListPath: ['messages'],
    );
    expect(full.coverage, ContextDiagnosticCoverage.complete);
    expect(
      full.commonJsonPrefixUtf8Bytes,
      utf8.encode(jsonEncode(body)).length,
    );
    final bounded = ContextCacheAnalyzer.compareJsonRequests(
      body,
      body,
      messageListPath: ['messages'],
      maxEncodedBytes: 10,
    );
    expect(bounded.incompleteReason, 'max_encoded_bytes_exceeded');
    expect(bounded.commonJsonPrefixSha256, isNull);
  });

  test('internal text prefix distinguishes UTF8 bytes from UTF16 units', () {
    Map<String, Object?> body(String text) => {
      'messages': [text],
    };
    final result = ContextCacheAnalyzer.compareJsonRequests(
      body('λ😀x'),
      body('λ😀y'),
      messageListPath: ['messages'],
    );
    expect(result.commonTextPrefixUtf8Bytes, 6);
    expect(result.commonTextPrefixCodeUnits, 3);
    expect(result.earlierTextSuffixUtf8Bytes, 1);
    final a = utf8.encode(jsonEncode(body('λ😀x')));
    expect(
      result.commonJsonPrefixSha256,
      sha256.convert(a.sublist(0, result.commonJsonPrefixUtf8Bytes)).toString(),
    );
  });

  test('missing encrypted and opaque raw structures refuse prefix hashes', () {
    for (final body in <Map<String, Object?>>[
      {},
      {
        'messages': [
          {'encrypted_content': 'secret'},
        ],
      },
      {
        'messages': [Object()],
      },
    ]) {
      final result = ContextCacheAnalyzer.compareJsonRequests(
        body,
        body,
        messageListPath: ['messages'],
      );
      expect(result.coverage, ContextDiagnosticCoverage.incomplete);
      expect(result.commonJsonPrefixSha256, isNull);
      expect(result.commonTextPrefixUtf8Bytes, isNull);
    }
  });

  test('map order changes are observable even when values are equal', () {
    final result = ContextCacheAnalyzer.compareJsonRequests(
      {
        'messages': ['same'],
        'model': 'm',
      },
      {
        'model': 'm',
        'messages': ['same'],
      },
      messageListPath: ['messages'],
    );
    expect(result.firstChangedJsonPath, r'$');
    expect(result.commonJsonPrefixUtf8Bytes, lessThan(10));
  });

  test('changed whole first message cannot reuse its stable internal text', () {
    final result = ContextCacheAnalyzer.compare(
      request('one', boundary: 'messages[0]'),
      request('two', boundary: 'messages[0]'),
    );
    expect(result.firstDivergenceIndex, isNotNull);
    expect(result.divergenceKnown, isTrue);
    expect(result.eligibleSharedEndpoints, isEmpty);
  });

  test(
    'explicit stable boundary yields conditional eligibility, not a hit',
    () {
      final result = ContextCacheAnalyzer.compare(
        request('one'),
        request('two', usage: const ContextCacheUsage(cachedTokens: 0)),
      );
      expect(result.eligibleSharedEndpoints, hasLength(1));
      expect(result.observedUsage!.cachedTokens, 0);
      expect(result.toJson()['eligibilityIsObservedHit'], isFalse);
      expect(
        ContextCacheAnalyzer.reuseMatrix([request('one'), request('two')]),
        hasLength(2),
      );
    },
  );

  test('tools and declared policy independently constrain compatibility', () {
    expect(
      ContextCacheAnalyzer.compare(
        request('one'),
        request('two', tool: 'write'),
      ).compatibility,
      ContextCompatibilityStatus.incompatible,
    );
    expect(
      ContextCacheAnalyzer.compare(
        request('one'),
        request('two', policy: 'other'),
      ).eligibleSharedEndpoints,
      isEmpty,
    );
    final unknown = ContextCacheAnalyzer.compare(
      request('one'),
      request('two', support: ContextCacheSupport.unknown),
    );
    expect(unknown.eligibleSharedEndpoints, isEmpty);
    expect(unknown.unresolved, contains('endpoint_support_unknown'));
  });

  test('write and lookup roles cannot substitute for each other', () {
    final snapshot = ContextCacheAnalyzer.captureJsonRequest(
      {
        'messages': ['same'],
      },
      messageListPath: ['messages'],
      writeEndpoints: [
        CacheWriteEndpoint(
          afterSegmentId: 'messages[0]',
          policyId: 'p',
          support: ContextCacheSupport.known,
        ),
      ],
    );
    expect(
      ContextCacheAnalyzer.compare(snapshot, snapshot).eligibleSharedEndpoints,
      isEmpty,
    );
  });

  test('JSON prefix hashes cover exact UTF8 including punctuation', () {
    final body = <String, Object?>{
      'model': 'm',
      'input': [
        {'role': 'user', 'content': 'λ\n"'},
      ],
    };
    final snapshot = ContextCacheAnalyzer.captureJsonRequest(
      body,
      messageListPath: ['input'],
      exactWire: true,
    );
    final bytes = utf8.encode(jsonEncode(body));
    expect(snapshot.boundaries.last.prefixUtf8Bytes, bytes.length);
    expect(
      snapshot.boundaries.last.prefixSha256,
      sha256.convert(bytes).toString(),
    );
    expect(snapshot.exactWire, isTrue);
    final encoded = jsonEncode(snapshot.toJson());
    expect(encoded, isNot(contains('λ')));
    expect(
      ContextDiagnosticSnapshot.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      ).toJson(),
      snapshot.toJson(),
    );
  });

  test('encrypted content never fingerprints or exports payload', () {
    final snapshot = ContextCacheAnalyzer.captureJsonRequest(
      {
        'input': [
          {'role': 'assistant', 'encrypted_content': 'secretciphertext'},
          {'role': 'user', 'content': 'later'},
        ],
      },
      messageListPath: ['input'],
      exactWire: true,
    );
    expect(snapshot.coverage, ContextDiagnosticCoverage.incomplete);
    expect(snapshot.exactWire, isFalse);
    expect(snapshot.boundaries.last.prefixSha256, isNull);
    expect(jsonEncode(snapshot.toJson()), isNot(contains('secretciphertext')));
    expect(
      ContextCacheAnalyzer.compare(snapshot, snapshot).divergenceKnown,
      isFalse,
    );
    expect(
      () => ContextTransportDiagnosticEvent(
        stage: ContextTransportDiagnosticStage.request,
        snapshot: snapshot,
        exactEncodedBody: 'must refuse',
      ),
      throwsArgumentError,
    );
  });

  test('legacy independent hashes retain unknown coverage and usage', () {
    final legacy = ContextCacheAnalyzer.importLegacyFingerprints({
      'input[0]': {
        'bytes': 3,
        'sha256': sha256.convert([1, 2, 3]).toString(),
      },
    });
    expect(legacy.boundaries, isEmpty);
    expect(legacy.boundaryCoverage, ContextDiagnosticCoverage.unknown);
    expect(legacy.usage, isNull);
    expect(
      ContextCacheAnalyzer.compare(legacy, legacy).compatibility,
      ContextCompatibilityStatus.unknown,
    );
    expect(
      () => ContextCacheAnalyzer.importLegacyFingerprints({
        'input': {'bytes': 1.2, 'sha256': 'invalid'},
      }),
      throwsFormatException,
    );
    expect(
      () => ContextCacheAnalyzer.importLegacyFingerprints({
        'input': {'bytes': 3, 'sha256': 'invalid'},
      }),
      throwsFormatException,
    );
    expect(
      () => ContextCacheAnalyzer.importLegacyFingerprints(
        {},
        boundaryEvidence: [ContextPrefixBoundary(afterSegmentId: 'x')],
      ),
      throwsArgumentError,
    );
    expect(
      () => ContextCacheAnalyzer.capture(
        ContextDiagnosticInput(
          representationId: 'raw',
          segments: [
            ContextDiagnosticSegmentInput.text(
              id: 'x',
              kind: 'text',
              text: 'a',
            ),
            ContextDiagnosticSegmentInput.text(
              id: 'x',
              kind: 'text',
              text: 'b',
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('attributed legacy evidence supports only the declared direction', () {
    final digest = sha256.convert(utf8.encode('proven prefix')).toString();
    ContextDiagnosticSnapshot imported({required bool writer}) =>
        ContextCacheAnalyzer.importLegacyFingerprints(
          {
            'opaque': {'bytes': 900, 'sha256': digest},
          },
          compatibility: ContextRequestCompatibility(
            configurationSha256: digest,
          ),
          boundaryEvidence: [
            ContextPrefixBoundary(
              afterSegmentId: 'internal-proof',
              prefixUtf8Bytes: 13,
              prefixSha256: digest,
              provenanceRefs: ['proof:captured-prefix'],
            ),
          ],
          writeEndpoints: writer
              ? [
                  CacheWriteEndpoint(
                    afterSegmentId: 'internal-proof',
                    policyId: 'p',
                    support: ContextCacheSupport.known,
                  ),
                ]
              : [],
          lookupEndpoints: writer
              ? []
              : [
                  CacheLookupEndpoint(
                    afterSegmentId: 'internal-proof',
                    policyId: 'p',
                    support: ContextCacheSupport.known,
                  ),
                ],
        );
    final matrix = ContextCacheAnalyzer.reuseMatrix([
      imported(writer: true),
      imported(writer: false),
    ]);
    expect(matrix[0][1].eligibleSharedEndpoints, hasLength(1));
    expect(matrix[1][0].eligibleSharedEndpoints, isEmpty);
    expect(matrix[0][1].observedUsage, isNull);
    expect(imported(writer: true).coverage, ContextDiagnosticCoverage.unknown);
  });

  test('settings after messages still invalidate compatibility', () {
    ContextDiagnosticSnapshot configured(int setting) =>
        ContextCacheAnalyzer.captureJsonRequest(
          {
            'messages': ['same'],
            'temperature': setting,
          },
          messageListPath: ['messages'],
        );
    expect(
      ContextCacheAnalyzer.compare(configured(0), configured(1)).compatibility,
      ContextCompatibilityStatus.incompatible,
    );
  });

  test('safe HTTP failure fields roundtrip with immutable presence flags', () {
    final presence = <String, bool>{'code': true, 'type': true, 'param': true};
    final event = ContextTransportDiagnosticEvent(
      stage: ContextTransportDiagnosticStage.settled,
      snapshot: request('two'),
      outcome: 'http_error',
      httpStatus: 400,
      providerErrorCode: 'invalid_request_error',
      providerErrorType: 'invalid_request_error',
      providerErrorParam: 'input[0].content[0].cache_control',
      providerErrorFieldPresence: presence,
    );
    presence['code'] = false;
    expect(event.providerErrorFieldPresence['code'], isTrue);
    expect(
      () => event.providerErrorFieldPresence['code'] = false,
      throwsUnsupportedError,
    );
    expect(
      ContextTransportDiagnosticEvent.fromJson(event.toJson()).toJson(),
      event.toJson(),
    );
    final legacy = ContextTransportDiagnosticEvent(
      stage: ContextTransportDiagnosticStage.settled,
      snapshot: request('two'),
    );
    expect(
      ContextTransportDiagnosticEvent.fromJson(legacy.toJson()).httpStatus,
      isNull,
    );
    expect(legacy.toJson().containsKey('providerErrorFieldPresence'), isFalse);
  });

  test('transport event and intent roundtrip preserve absence versus zero', () {
    final event = ContextTransportDiagnosticEvent(
      stage: ContextTransportDiagnosticStage.settled,
      snapshot: request('two'),
      usageReported: true,
      numericUsage: {'cached_tokens': 0},
      responseId: 'r',
    );
    expect(
      ContextTransportDiagnosticEvent.fromJson(event.toJson()).toJson(),
      event.toJson(),
    );
    expect(event.toJson().containsKey('exactEncodedBody'), isFalse);
    expect(ContextCacheUsage.fromJson({}).cachedTokens, isNull);
    expect(ContextCacheUsage.fromJson({'cachedTokens': 0}).cachedTokens, 0);
    expect(
      ContextCacheIntent.fromJson(ContextCacheIntent().toJson())
          .writeAfterSegmentIds,
      isEmpty,
    );
  });
}

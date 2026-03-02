import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

void main() {
  group('StorageProfileSchemaValidator', () {
    const validator = StorageProfileSchemaValidator();

    test('parseYaml supports snake_case policy values', () {
      const source = '''
version: 1
name: test_profile
metadata:
  owner: qa
namespaces:
  - namespace: settings
    policy: local_only
    local_engine_id: files
  - namespace: projects
    policy: optimistic_sync
    local_engine_id: files
    remote_engine_id: github
    sync_interaction_level: complex
    required_capabilities:
      supports_diff: true
      supports_history: true
      supports_revision_metadata: true
      supports_manual_conflict_resolution: true
''';

      final profile = validator.parseYaml(source);
      expect(profile.name, 'test_profile');
      expect(profile.version, 1);
      expect(profile.namespaces.length, 2);
      expect(
        profile.namespaceProfile(StorageNamespace.settings).policy,
        StoragePolicy.localOnly,
      );
      expect(
        profile.namespaceProfile(StorageNamespace.projects).policy,
        StoragePolicy.optimisticSync,
      );
      expect(
        profile
            .namespaceProfile(StorageNamespace.projects)
            .syncInteractionLevel,
        SyncInteractionLevel.complex,
      );
    });

    test(
      'validateMap reports error when remote policy has no remote engine',
      () {
        final result = validator.validateMap(<String, dynamic>{
          'version': 1,
          'name': 'invalid_profile',
          'namespaces': <Map<String, dynamic>>[
            <String, dynamic>{
              'namespace': 'projects',
              'policy': 'optimistic_sync',
              'local_engine_id': 'files',
            },
          ],
        });

        expect(result.isValid, isFalse);
        expect(
          result.errors.any(
            (final issue) => issue.code == 'remote_engine_required',
          ),
          isTrue,
        );
      },
    );

    test('validateMap allows warnings without failing schema', () {
      final result = validator.validateMap(<String, dynamic>{
        'version': 2,
        'name': 'warning_profile',
        'unknown_key': 'kept_for_future',
        'namespaces': <Map<String, dynamic>>[
          <String, dynamic>{
            'namespace': 'settings',
            'policy': 'local_only',
            'local_engine_id': 'files',
          },
        ],
      });

      expect(result.isValid, isTrue);
      expect(
        result.warnings.any(
          (final issue) => issue.code == 'unknown_top_level_key',
        ),
        isTrue,
      );
      expect(
        result.warnings.any((final issue) => issue.code == 'version_mismatch'),
        isTrue,
      );
    });

    test('validateMap validates queue_policy payload', () {
      final invalid = validator.validateMap(<String, dynamic>{
        'version': 1,
        'name': 'queue_profile_invalid',
        'namespaces': <Map<String, dynamic>>[
          <String, dynamic>{
            'namespace': 'projects',
            'policy': 'optimistic_sync',
            'local_engine_id': 'files',
            'remote_engine_id': 'github',
            'queue_policy': <String, dynamic>{'max_retries': 0},
          },
        ],
      });
      expect(invalid.isValid, isFalse);
      expect(
        invalid.errors.any(
          (final issue) => issue.code == 'queue_policy_value_invalid',
        ),
        isTrue,
      );

      final valid = validator.validateMap(<String, dynamic>{
        'version': 1,
        'name': 'queue_profile_valid',
        'namespaces': <Map<String, dynamic>>[
          <String, dynamic>{
            'namespace': 'projects',
            'policy': 'optimistic_sync',
            'local_engine_id': 'files',
            'remote_engine_id': 'github',
            'queue_policy': <String, dynamic>{
              'max_retries': '4',
              'initial_backoff_ms': 100,
              'max_backoff_ms': 1000,
              'max_entry_age_ms': 30000,
            },
          },
        ],
      });
      expect(valid.isValid, isTrue);
      final namespace =
          (valid.normalizedMap?['namespaces'] as List).single as Map;
      final queuePolicy = namespace['queue_policy'] as Map;
      expect(queuePolicy['max_retries'], 4);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

void main() {
  group('RepositoryManager.cloneRepositoryToLocal', () {
    test('blocks clone when provider capabilities do not allow it', () async {
      final service = _FakeVersionControlService(
        capabilities: VersionControlCapabilities.none,
      );
      final ui = _FakeRepositorySelectionUiDelegate();
      final manager = RepositoryManager(service: service, ui: ui);

      await expectLater(
        () => manager.cloneRepositoryToLocal(
          repository: const VcRepository(id: '1', name: 'repo'),
          localPath: '/tmp/repo',
        ),
        throwsA(isA<CapabilityMismatchException>()),
      );

      expect(service.cloneCallCount, 0);
      expect(ui.errorTitles, contains('Clone Not Supported'));
    });

    test('clones when provider capabilities allow it', () async {
      final service = _FakeVersionControlService(
        capabilities: const VersionControlCapabilities(
          supportsCloneToLocal: true,
        ),
      );
      final ui = _FakeRepositorySelectionUiDelegate();
      final manager = RepositoryManager(service: service, ui: ui);

      await manager.cloneRepositoryToLocal(
        repository: const VcRepository(id: '1', name: 'repo'),
        localPath: '/tmp/repo',
      );

      expect(service.cloneCallCount, 1);
      expect(service.lastClonePath, '/tmp/repo');
      expect(ui.errorTitles, isEmpty);
    });

    test('rejects empty local path before clone flow starts', () async {
      final service = _FakeVersionControlService(
        capabilities: const VersionControlCapabilities(
          supportsCloneToLocal: true,
        ),
      );
      final ui = _FakeRepositorySelectionUiDelegate();
      final manager = RepositoryManager(service: service, ui: ui);

      await expectLater(
        () => manager.cloneRepositoryToLocal(
          repository: const VcRepository(id: '1', name: 'repo'),
          localPath: '  ',
        ),
        throwsA(isA<RepositorySelectionException>()),
      );

      expect(ui.showProgressCalls, 0);
      expect(ui.hideProgressCalls, 0);
      expect(service.cloneCallCount, 0);
    });
  });
}

final class _FakeVersionControlService implements VersionControlService {
  _FakeVersionControlService({required this.capabilities});

  final VersionControlCapabilities capabilities;
  int cloneCallCount = 0;
  String? lastClonePath;

  @override
  VersionControlCapabilities get declaredVersionControlCapabilities =>
      capabilities;

  @override
  Future<VersionControlCapabilities>
  resolveVersionControlCapabilities() async => capabilities;

  @override
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  ) async {
    cloneCallCount++;
    lastClonePath = localPath;
  }

  @override
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  ) async => const VcRepository(id: '1', name: 'repo');

  @override
  Future<VcRepository> getRepositoryInfo() async =>
      const VcRepository(id: '1', name: 'repo');

  @override
  Future<List<VcBranch>> listBranches() async => const <VcBranch>[];

  @override
  Future<List<VcRepository>> listRepositories() async => const <VcRepository>[];

  @override
  Future<void> setRepository(final VcRepositoryName repositoryId) async {}
}

final class _FakeRepositorySelectionUiDelegate
    implements RepositorySelectionUIDelegate {
  int showProgressCalls = 0;
  int hideProgressCalls = 0;
  final List<String> errorTitles = <String>[];

  @override
  Future<VcCreateRepositoryRequest?> getRepositoryCreationDetails(
    final RepositorySelectionConfig config,
  ) async => null;

  @override
  Future<void> hideProgress() async {
    hideProgressCalls++;
  }

  @override
  Future<VcRepository?> selectRepository(
    final List<VcRepository> repositories, {
    final String? suggestedName,
  }) async => null;

  @override
  Future<void> showError(final String title, final String message) async {
    errorTitles.add(title);
  }

  @override
  Future<void> showProgress(final String message) async {
    showProgressCalls++;
  }
}

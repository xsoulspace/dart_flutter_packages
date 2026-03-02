import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  group('OfflineGitStorageProvider', () {
    late OfflineGitStorageProvider provider;
    late Directory tempDirectory;
    late String tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      tempDirectory = await Directory.systemTemp.createTemp(
        'git_storage_test_',
      );
      tempDir = tempDirectory.path;
      provider = OfflineGitStorageProvider();
    });

    test('implements LocalEngine role for kernel profile routing', () {
      expect(provider, isA<LocalEngine>());
      expect(provider, isNot(isA<RemoteEngine>()));
    });

    test('declares clone-to-local capability as unsupported', () async {
      expect(
        provider.declaredVersionControlCapabilities.supportsCloneToLocal,
        isFalse,
      );
      final resolved = await provider.resolveVersionControlCapabilities();
      expect(resolved.supportsCloneToLocal, isFalse);
    });

    tearDown(() async {
      // Clean up temporary directory
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    group('Repository Initialization', () {
      test('should initialize new repository with required config', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);

        // Verify .git directory exists
        final gitDir = Directory('$tempDir/.git');
        expect(gitDir.existsSync(), isTrue);
      });

      test('should handle existing repository', () async {
        // Initialize repository first time
        final config = OfflineGitConfig(localPath: tempDir);
        await provider.initWithConfig(config);

        // Initialize again with same path
        final provider2 = OfflineGitStorageProvider();
        await provider2.initWithConfig(config);

        expect(await provider2.isAuthenticated(), isTrue);
      });

      test('should throw exception for missing localPath', () {
        expect(
          () => OfflineGitConfig(localPath: ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw exception for missing branchName', () {
        expect(
          () => OfflineGitConfig(
            localPath: tempDir,
            branchName: VcBranchName.empty,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should configure Git user settings when provided', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('File Operations', () {
      setUp(() async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        await provider.initWithConfig(config);
      });

      test('should create file with Git commit', () async {
        const filePath = 'test.txt';
        const content = 'Hello, World!';

        final result = await provider.createFile(
          filePath,
          content,
          commitMessage: 'Add test file',
        );

        expect(result.revisionId, isNotEmpty);
        expect(result.revisionId.length, equals(40)); // Git SHA-1 hash length
        expect(result.metadata['durability_protocol'], 'git_commit_v1');
        expect(result.metadata['durability_operation_type'], 'create');
        expect(result.metadata['durability_namespace'], '_root');
        expect(result.metadata['durability_commit'], result.revisionId);

        // Verify file exists and has correct content
        final readContent = await provider.getFile(filePath);
        expect(readContent, equals(content));
      });

      test('should update existing file with Git commit', () async {
        const filePath = 'test.txt';
        const initialContent = 'Initial content';
        const updatedContent = 'Updated content';

        // Create file first
        await provider.createFile(filePath, initialContent);

        // Update file
        final result = await provider.updateFile(
          filePath,
          updatedContent,
          commitMessage: 'Update test file',
        );

        expect(result.revisionId, isNotEmpty);
        expect(result.metadata['durability_protocol'], 'git_commit_v1');
        expect(result.metadata['durability_operation_type'], 'update');
        expect(result.metadata['durability_namespace'], '_root');
        expect(result.metadata['durability_commit'], result.revisionId);

        // Verify updated content
        final readContent = await provider.getFile(filePath);
        expect(readContent, equals(updatedContent));
      });

      test('should delete file with Git commit', () async {
        const filePath = 'test.txt';
        const content = 'Content to be deleted';

        // Create file first
        await provider.createFile(filePath, content);

        // Verify file exists
        expect(await provider.getFile(filePath), equals(content));

        // Delete file
        final result = await provider.deleteFile(
          filePath,
          commitMessage: 'Delete test file',
        );
        expect(result.metadata['durability_protocol'], 'git_commit_v1');
        expect(result.metadata['durability_operation_type'], 'delete');
        expect(result.metadata['durability_namespace'], '_root');
        expect(result.metadata['durability_commit'], result.revisionId);

        // Verify file is gone
        expect(await provider.getFile(filePath), isNull);
      });

      test('should read file from working directory', () async {
        const filePath = 'test.txt';
        const content = 'Test content';

        await provider.createFile(filePath, content);
        final readContent = await provider.getFile(filePath);

        expect(readContent, equals(content));
      });

      test('should return null for non-existent file', () async {
        final content = await provider.getFile('non_existent.txt');
        expect(content, isNull);
      });

      test('should list files respecting .git directory', () async {
        // Create some test files
        await provider.createFile('file1.txt', 'Content 1');
        await provider.createFile('file2.txt', 'Content 2');
        await provider.createFile('subdir/file3.txt', 'Content 3');

        // List files in root directory
        final entries = await provider.listDirectory('.');

        final names = entries.map((final e) => e.name).toList();
        expect(names, contains('file1.txt'));
        expect(names, contains('file2.txt'));
        expect(names, contains('subdir'));
        expect(names, isNot(contains('.git')));
        expect(names, isNot(contains('.gitkeep')));
      });

      test('should handle nested directory creation', () async {
        const filePath = 'deep/nested/directory/file.txt';
        const content = 'Nested content';

        await provider.createFile(filePath, content);

        final readContent = await provider.getFile(filePath);
        expect(readContent, equals(content));
      });

      test('should use default commit messages when none provided', () async {
        const filePath = 'test.txt';
        const content = 'Test content';

        // Create without commit message
        final commitRes = await provider.createFile(filePath, content);
        expect(commitRes.revisionId, isNotEmpty);

        // Update without commit message
        final updateRes = await provider.updateFile(filePath, 'Updated');
        expect(updateRes.revisionId, isNotEmpty);

        // Delete without commit message (separate test file)
        const filePath2 = 'test2.txt';
        await provider.createFile(filePath2, content);
        await provider.deleteFile(filePath2);
      });

      test(
        'should throw FileNotFoundException for non-existent file operations',
        () {
          const filePath = 'non-existent.txt';

          // Update non-existent file
          expect(
            () => provider.updateFile(filePath, 'content'),
            throwsA(isA<FileNotFoundException>()),
          );

          // Delete non-existent file
          expect(
            () => provider.deleteFile(filePath),
            throwsA(isA<FileNotFoundException>()),
          );
        },
      );
    });

    group('Version Control Operations', () {
      setUp(() async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        await provider.initWithConfig(config);
      });

      test('cloneRepository should fail with capability mismatch', () async {
        await expectLater(
          () => provider.cloneRepository(
            const VcRepository(id: '1', name: 'repo'),
            path.join(tempDir, 'clone-target'),
          ),
          throwsA(isA<CapabilityMismatchException>()),
        );
      });

      test('should restore file to HEAD', () async {
        const filePath = 'versioned.txt';
        const originalContent = 'Original content';
        const modifiedContent = 'Modified content';

        // Create and commit original version
        await provider.createFile(filePath, originalContent);

        // Modify the file directly (simulating external change)
        final file = File('$tempDir/$filePath');
        await file.writeAsString(modifiedContent);

        // Verify file is modified
        expect(await provider.getFile(filePath), equals(modifiedContent));

        // Restore to HEAD
        await provider.restore(filePath);

        // Verify file is restored
        expect(await provider.getFile(filePath), equals(originalContent));
      });

      test('should restore file to specific commit', () async {
        const filePath = 'versioned.txt';
        const version1 = 'Version 1';
        const version2 = 'Version 2';

        // Create first version
        final commit1 = await provider.createFile(filePath, version1);

        // Create second version
        final commit2 = await provider.updateFile(filePath, version2);
        expect(commit2.revisionId, isNotEmpty);

        // Verify current version
        expect(await provider.getFile(filePath), equals(version2));

        // Restore to first commit
        await provider.restore(filePath, versionId: commit1.revisionId);

        // Verify restored version
        expect(await provider.getFile(filePath), equals(version1));
      });

      test(
        'should return repository info for current local repository',
        () async {
          final info = await provider.getRepositoryInfo();

          expect(info.id, equals(path.normalize(path.absolute(tempDir))));
          expect(info.name, equals(path.basename(path.normalize(tempDir))));
          expect(info.defaultBranch, equals('main'));
        },
      );

      test('should list branches for local repository', () async {
        final branches = await provider.listBranches();

        expect(branches, isNotEmpty);
        final names = branches
            .map((final branch) => branch.name.value)
            .toList();
        expect(names, contains('main'));
        expect(branches.any((final branch) => branch.isDefault), isTrue);
      });

      test('should list sibling git repositories', () async {
        final siblingRepoPath = path.join(
          path.dirname(tempDir),
          'git_storage_sibling_${DateTime.now().microsecondsSinceEpoch}',
        );
        final siblingDirectory = await Directory(siblingRepoPath).create();
        addTearDown(() async {
          if (siblingDirectory.existsSync()) {
            await siblingDirectory.delete(recursive: true);
          }
        });

        final siblingProvider = OfflineGitStorageProvider();
        await siblingProvider.initWithConfig(
          OfflineGitConfig(localPath: siblingDirectory.path),
        );
        await siblingProvider.dispose();

        final repositories = await provider.listRepositories();
        final repoNames = repositories
            .map((final repository) => repository.name)
            .toList();

        expect(repoNames, contains(path.basename(tempDir)));
        expect(repoNames, contains(path.basename(siblingDirectory.path)));
      });

      test(
        'should switch repository context to a sibling repository',
        () async {
          final siblingRepoPath = path.join(
            path.dirname(tempDir),
            'git_storage_switch_${DateTime.now().microsecondsSinceEpoch}',
          );
          final siblingDirectory = await Directory(siblingRepoPath).create();
          addTearDown(() async {
            if (siblingDirectory.existsSync()) {
              await siblingDirectory.delete(recursive: true);
            }
          });

          final siblingProvider = OfflineGitStorageProvider();
          await siblingProvider.initWithConfig(
            OfflineGitConfig(
              localPath: siblingDirectory.path,
              authorName: 'Test User',
              authorEmail: 'test@example.com',
            ),
          );
          await siblingProvider.createFile('seed.txt', 'seed');
          await siblingProvider.dispose();

          await provider.setRepository(
            VcRepositoryName(path.basename(siblingDirectory.path)),
          );
          final info = await provider.getRepositoryInfo();
          expect(info.name, equals(path.basename(siblingDirectory.path)));

          await provider.createFile('switched.txt', 'ok');
          expect(
            File(path.join(siblingDirectory.path, 'switched.txt')).existsSync(),
            isTrue,
          );
          expect(
            File(path.join(tempDir, 'switched.txt')).existsSync(),
            isFalse,
          );
        },
      );
    });

    group('Remote Sync Configuration', () {
      test('should configure remote URL', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
        );

        await provider.initWithConfig(config);
        expect(provider.supportsSync, isTrue);
      });

      test('should not support sync without remote URL', () async {
        final config = OfflineGitConfig(localPath: tempDir);

        await provider.initWithConfig(config);
        expect(provider.supportsSync, isFalse);
      });

      test('should configure authentication options', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
          httpsToken: 'test-token',
        );

        await provider.initWithConfig(config);
        expect(provider.supportsSync, isTrue);
      });
    });
  });
}

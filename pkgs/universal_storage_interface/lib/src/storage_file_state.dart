import 'models/file_models.dart';

/// Qualified POSIX rwx bits only; not ACL, ownership or other file metadata.
const String storagePosixRwxProfile = 'posix-rwx-v1';

/// Complete text/presence and permission state within a declared profile.
/// This description grants no authority to inspect or change a filesystem.
class StorageFileState {
  /// Describes a state; [validatePosix] checks its declared profile at runtime.
  const StorageFileState({required this.content, required this.mode});

  /// Null means the path is absent; empty text remains a present file.
  final String? content;

  /// POSIX rwx bits, decimal integer 0..511 (octal 0000..0777).
  /// Null is valid only for an absent path.
  final int? mode;

  /// Runtime validation, retained when assertions are disabled.
  void validatePosix() {
    if (content == null) {
      if (mode != null) {
        throw const FormatException('absent file state cannot carry a mode');
      }
    } else if (mode == null || mode! < 0 || mode! > 0x1ff) {
      throw const FormatException(
        'present file requires POSIX rwx mode 0..0777',
      );
    }
  }
}

/// Optional provider facet. Mandatory StorageProvider methods stay unchanged.
/// The provider owns native publication and recovery; these methods grant no
/// policy, lock, consent or transaction authority to their eventual caller.
abstract interface class StorageFileStatePort {
  /// Null explicitly means this provider cannot serve the file-state profile.
  String? get fileStateProfile;

  /// Observes the complete supported state without mutating the provider.
  Future<StorageFileState> readFileState(String path);

  /// Pure declaration before dispatch; no filesystem mutation or guessed
  /// historical metadata. The initial native profile preserves existing mode
  /// on updates and explicitly declares 0644 for a newly created text file.
  StorageFileState intendedFileState(StorageFileState before, String? content);

  /// Native restoration publishes the declared content and mode together.
  /// Implementations refuse unsupported publication/metadata rather than
  /// reporting a byte-only restoration as complete file-state recovery.
  Future<FileOperationResult> restoreFileState(
    String path,
    StorageFileState state,
  );
}

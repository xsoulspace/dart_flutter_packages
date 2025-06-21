// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';
import 'dart:developer';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../exceptions/oauth_exceptions.dart';
import '../models/git_platform.dart';
import 'credential_storage.dart';

/// Secure credential storage using platform keychain/keystore
class SecureCredentialStorage implements CredentialStorage {
  /// Creates a new secure credential storage.
  ///
  /// Parameters:
  /// - [storage]: The FlutterSecureStorage instance to use.
  SecureCredentialStorage([final FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// Get the key for the credentials.
  String _getKey(final GitPlatform platform) =>
      'oauth_credentials_${platform.name}';

  @override
  Future<void> storeCredentials(
    final GitPlatform platform,
    final StoredCredentials credentials,
  ) async {
    try {
      final key = _getKey(platform);
      final value = jsonEncode(credentials.toJson());
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw StorageException(
        'Failed to store credentials for ${platform.displayName}',
        e.toString(),
      );
    }
  }

  @override
  Future<StoredCredentials?> getCredentials(final GitPlatform platform) async {
    try {
      final key = _getKey(platform);
      final value = await _storage.read(key: key);

      if (value == null) return null;

      final json = jsonDecode(value) as Map<String, dynamic>;
      return StoredCredentials.fromJson(json);
    } catch (e, stackTrace) {
      log(
        'Failed to get credentials for ${platform.displayName}: $e',
        stackTrace: stackTrace,
      );
      // Invalid stored data, clear it and return null
      try {
        await clearCredentials(platform);
      } catch (e, stackTrace) {
        log(
          'Failed to clear credentials for ${platform.displayName}: $e',
          stackTrace: stackTrace,
        );
        // Ignore clear errors
      }
      throw StorageException.corruptedData(
        'credentials for ${platform.displayName}',
      );
    }
  }

  @override
  Future<void> clearCredentials(final GitPlatform platform) async {
    try {
      final key = _getKey(platform);
      await _storage.delete(key: key);
    } catch (e, stackTrace) {
      log(
        'Failed to clear credentials for ${platform.displayName}: $e',
        stackTrace: stackTrace,
      );
      throw StorageException(
        'Failed to clear credentials for ${platform.displayName}',
        e.toString(),
      );
    }
  }

  @override
  Future<void> clearAllCredentials() async {
    final errors = <String>[];

    for (final platform in GitPlatform.values) {
      try {
        await clearCredentials(platform);
      } catch (e, stackTrace) {
        log(
          'Failed to clear credentials for ${platform.displayName}: $e',
          stackTrace: stackTrace,
        );
        errors.add('${platform.displayName}: $e');
      }
    }

    if (errors.isNotEmpty) {
      throw StorageException(
        'Failed to clear some credentials',
        errors.join(', '),
      );
    }
  }

  @override
  Future<bool> hasCredentials(final GitPlatform platform) async {
    try {
      final credentials = await getCredentials(platform);
      return credentials != null && !credentials.isExpired;
    } catch (e, stackTrace) {
      log(
        'Failed to check if credentials exist for ${platform.displayName}: $e',
        stackTrace: stackTrace,
      );
      // If there's an error reading credentials, assume they don't exist
      return false;
    }
  }

  /// Check if secure storage is available on this platform
  Future<bool> isSecureStorageAvailable() async {
    try {
      await _storage.containsKey(key: 'test_key');
      return true;
    } catch (e, stackTrace) {
      log(
        'Failed to check if secure storage is available: $e',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get all stored platforms that have credentials
  Future<List<GitPlatform>> getStoredPlatforms() async {
    final platforms = <GitPlatform>[];

    for (final platform in GitPlatform.values) {
      if (await hasCredentials(platform)) {
        platforms.add(platform);
      }
    }

    return platforms;
  }
}

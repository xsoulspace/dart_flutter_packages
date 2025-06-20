import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../exceptions/oauth_exceptions.dart';
import '../models/git_platform.dart';
import 'credential_storage.dart';

/// Secure credential storage using platform keychain/keystore
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  String _getKey(GitPlatform platform) => 'oauth_credentials_${platform.name}';

  @override
  Future<void> storeCredentials(
      GitPlatform platform, StoredCredentials credentials) async {
    try {
      final key = _getKey(platform);
      final value = jsonEncode(credentials.toJson());
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw StorageException(
          'Failed to store credentials for ${platform.displayName}',
          e.toString());
    }
  }

  @override
  Future<StoredCredentials?> getCredentials(GitPlatform platform) async {
    try {
      final key = _getKey(platform);
      final value = await _storage.read(key: key);

      if (value == null) return null;

      final json = jsonDecode(value) as Map<String, dynamic>;
      return StoredCredentials.fromJson(json);
    } catch (e) {
      // Invalid stored data, clear it and return null
      try {
        await clearCredentials(platform);
      } catch (_) {
        // Ignore clear errors
      }
      throw StorageException.corruptedData(
          'credentials for ${platform.displayName}');
    }
  }

  @override
  Future<void> clearCredentials(GitPlatform platform) async {
    try {
      final key = _getKey(platform);
      await _storage.delete(key: key);
    } catch (e) {
      throw StorageException(
          'Failed to clear credentials for ${platform.displayName}',
          e.toString());
    }
  }

  @override
  Future<void> clearAllCredentials() async {
    final errors = <String>[];

    for (final platform in GitPlatform.values) {
      try {
        await clearCredentials(platform);
      } catch (e) {
        errors.add('${platform.displayName}: $e');
      }
    }

    if (errors.isNotEmpty) {
      throw StorageException(
          'Failed to clear some credentials', errors.join(', '));
    }
  }

  @override
  Future<bool> hasCredentials(GitPlatform platform) async {
    try {
      final credentials = await getCredentials(platform);
      return credentials != null && !credentials.isExpired;
    } catch (e) {
      // If there's an error reading credentials, assume they don't exist
      return false;
    }
  }

  /// Check if secure storage is available on this platform
  Future<bool> isSecureStorageAvailable() async {
    try {
      await _storage.containsKey(key: 'test_key');
      return true;
    } catch (e) {
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

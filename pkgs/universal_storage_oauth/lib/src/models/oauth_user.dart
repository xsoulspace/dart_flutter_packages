import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents an authenticated OAuth user.
///
/// Wraps user information from OAuth providers like GitHub, GitLab, etc.
/// Provides type-safe access to user data with graceful handling of missing fields.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const OAuthUser(Map<String, dynamic> value) {
  factory OAuthUser.fromJson(final jsonData) {
    final map = jsonDecodeMap(jsonData);
    return OAuthUser(map);
  }

  /// Unique identifier for the user
  String get id => jsonDecodeString(value['id']);

  /// Username/login handle
  String get login => jsonDecodeString(value['login']);

  /// Email address (may be null if not public/accessible)
  String? get email {
    final str = jsonDecodeString(value['email']);
    return str.isEmpty ? null : str;
  }

  /// Display name (may be null if not set)
  String? get name {
    final str = jsonDecodeString(value['name']);
    return str.isEmpty ? null : str;
  }

  /// URL to user's avatar image (may be null)
  String? get avatarUrl {
    final str = jsonDecodeString(value['avatar_url']);
    return str.isEmpty ? null : str;
  }

  /// User's bio/description (may be null)
  String? get bio {
    final str = jsonDecodeString(value['bio']);
    return str.isEmpty ? null : str;
  }

  /// User's location (may be null)
  String? get location {
    final str = jsonDecodeString(value['location']);
    return str.isEmpty ? null : str;
  }

  /// User's company (may be null)
  String? get company {
    final str = jsonDecodeString(value['company']);
    return str.isEmpty ? null : str;
  }

  /// URL to user's profile page (may be null)
  String? get htmlUrl {
    final str = jsonDecodeString(value['html_url']);
    return str.isEmpty ? null : str;
  }

  /// Number of public repositories
  int get publicRepos => jsonDecodeInt(value['public_repos']);

  /// Number of followers
  int get followers => jsonDecodeInt(value['followers']);

  /// Number of users being followed
  int get following => jsonDecodeInt(value['following']);

  /// Account creation date (may be null if not available)
  DateTime? get createdAt {
    final dateStr = jsonDecodeString(value['created_at']);
    return dateStr.isEmpty ? null : dateTimeFromIso8601String(dateStr);
  }

  Map<String, dynamic> toJson() => value;

  static const empty = OAuthUser({});
}

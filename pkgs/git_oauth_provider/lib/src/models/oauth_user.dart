/// Represents an authenticated OAuth user
class OAuthUser {
  const OAuthUser({
    required this.id,
    required this.login,
    this.email,
    this.name,
    this.avatarUrl,
    this.bio,
    this.location,
    this.company,
    this.htmlUrl,
    this.publicRepos,
    this.followers,
    this.following,
    this.createdAt,
  });

  factory OAuthUser.fromJson(final Map<String, dynamic> json) => OAuthUser(
    id: json['id'].toString(),
    login: json['login'] as String,
    email: json['email'] as String?,
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    bio: json['bio'] as String?,
    location: json['location'] as String?,
    company: json['company'] as String?,
    htmlUrl: json['htmlUrl'] as String?,
    publicRepos: json['publicRepos'] as int?,
    followers: json['followers'] as int?,
    following: json['following'] as int?,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
  );

  final String id;
  final String login;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final String? bio;
  final String? location;
  final String? company;
  final String? htmlUrl;
  final int? publicRepos;
  final int? followers;
  final int? following;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'login': login,
    'email': email,
    'name': name,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'location': location,
    'company': company,
    'htmlUrl': htmlUrl,
    'publicRepos': publicRepos,
    'followers': followers,
    'following': following,
    'createdAt': createdAt?.toIso8601String(),
  };

  @override
  String toString() => 'OAuthUser(id: $id, login: $login, name: $name)';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is OAuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          login == other.login;

  @override
  int get hashCode => id.hashCode ^ login.hashCode;
}

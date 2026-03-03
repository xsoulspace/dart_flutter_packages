import 'package:test/test.dart';
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_crazygames/xsoulspace_platform_crazygames.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

void main() {
  test('non-web init returns notAvailable', () async {
    final client = CrazyGamesPlatformClient(
      config: const CrazyGamesPlatformConfig(),
      initClient: CrazyGames.init,
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isNotAvailable, isTrue);
  });

  test('user absent/present mapping and auth listener flow', () async {
    final fake = _FakeCrazyGamesClient();
    final client = CrazyGamesPlatformClient(
      config: const CrazyGamesPlatformConfig(),
      initClient: () async => fake,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    final identity = client.require<IdentityCapability>();

    expect(await identity.currentPlayer(), isNull);

    fake.userClient.currentUser = const User(
      id: 'u-1',
      username: 'PlayerOne',
      profilePictureUrl: 'https://example.com/u1.png',
    );

    final current = await identity.currentPlayer();
    expect(current?.id, 'u-1');
    expect(current?.displayName, 'PlayerOne');
    expect(current?.isAnonymous, isFalse);

    final changes = <String?>[];
    final sub = identity.authChanges.listen(
      (final value) => changes.add(value?.displayName),
    );

    fake.userClient.emitAuth(
      const User(
        id: 'u-2',
        username: 'PlayerTwo',
        profilePictureUrl: 'https://example.com/u2.png',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(changes, contains('PlayerTwo'));
    await sub.cancel();
  });

  test('score submit mapping', () async {
    final fake = _FakeCrazyGamesClient();
    final client = CrazyGamesPlatformClient(
      config: const CrazyGamesPlatformConfig(),
      initClient: () async => fake,
    );

    await client.init(const PlatformInitOptions());

    final leaderboard = client.require<LeaderboardWriteCapability>();
    await leaderboard.submitScore('lb-main', 100);
    expect(fake.userClient.lastAddScore, 100);

    await leaderboard.submitScore('lb-main', 200, extraData: 'encrypted');
    expect(fake.userClient.lastEncryptedScore, 'encrypted');
  });

  test('friends pagination mapping', () async {
    final fake = _FakeCrazyGamesClient();
    final client = CrazyGamesPlatformClient(
      config: const CrazyGamesPlatformConfig(),
      initClient: () async => fake,
    );

    await client.init(const PlatformInitOptions());

    final friendsCapability = client.require<FriendsCapability>();
    final friends = await friendsCapability.listFriends(limit: 2, offset: 1);

    expect(friends, hasLength(2));
    expect(friends[0].id, 'f-2');
    expect(friends[1].id, 'f-3');
  });
}

final class _FakeCrazyGamesClient extends CrazyGamesClient {
  _FakeCrazyGamesClient();

  final _FakeUserClient userClient = _FakeUserClient();

  @override
  UserClient get user => userClient;
}

final class _FakeUserClient extends UserClient {
  User? currentUser;
  int? lastAddScore;
  String? lastEncryptedScore;
  Object? _listener;

  final List<Friend> _friends = const <Friend>[
    Friend(id: 'f-1', username: 'Friend 1', profilePictureUrl: ''),
    Friend(id: 'f-2', username: 'Friend 2', profilePictureUrl: ''),
    Friend(id: 'f-3', username: 'Friend 3', profilePictureUrl: ''),
  ];

  @override
  Future<User?> getUser() async => currentUser;

  @override
  Future<FriendsPage> listFriends({
    final int page = 1,
    final int size = 10,
  }) async {
    final start = (page - 1) * size;
    final end = (start + size).clamp(0, _friends.length);
    final pageItems = _friends.sublist(start.clamp(0, _friends.length), end);
    return FriendsPage(
      friends: pageItems,
      page: page,
      size: size,
      hasMore: end < _friends.length,
      total: _friends.length,
    );
  }

  @override
  void addScore(final int score) {
    lastAddScore = score;
  }

  @override
  void addScoreEncrypted(final int score, final String encryptedScore) {
    lastAddScore = score;
    lastEncryptedScore = encryptedScore;
  }

  @override
  Object addAuthListener(final void Function(User? user) listener) {
    _listener = listener;
    return listener;
  }

  @override
  void removeAuthListener(final Object listener) {
    if (identical(_listener, listener)) {
      _listener = null;
    }
  }

  void emitAuth(final User? user) {
    final listener = _listener;
    if (listener is void Function(User? user)) {
      listener(user);
    }
  }
}

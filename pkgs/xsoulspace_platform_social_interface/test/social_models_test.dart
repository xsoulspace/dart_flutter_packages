import 'package:test/test.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

void main() {
  group('InviteRequest defaults', () {
    test('provides deterministic empty collections', () {
      const request = InviteRequest();

      expect(request.message, isNull);
      expect(request.recipientIds, isEmpty);
      expect(request.metadata, isEmpty);
    });
  });

  group('identity and share models', () {
    test('store player identity and social metadata', () {
      const identity = PlayerIdentity(
        id: 'user-1',
        displayName: 'Alice',
        isAnonymous: false,
        metadata: <String, Object?>{'tier': 'gold'},
      );
      const share = FeedShareRequest(
        message: 'hello',
        linkUrl: 'https://example.com',
      );
      const result = FeedShareResult(
        shared: true,
        postId: 'post-1',
      );

      expect(identity.id, 'user-1');
      expect(identity.metadata['tier'], 'gold');
      expect(share.linkUrl, 'https://example.com');
      expect(result.shared, isTrue);
      expect(result.postId, 'post-1');
    });
  });
}

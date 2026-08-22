import 'package:github/github.dart';
import 'package:test/test.dart';
import 'fake_github_api.dart';

void main() {
  test('debug repo get with fixed fake', () async {
    final api = FakeGitHubApi();
    await api.ready;
    final github = GitHub(
      auth: Authentication.withToken('fake-token'),
      endpoint: api.endpoint,
    );
    try {
      final repo = await github.repositories.getRepository(
        RepositorySlug('conformance', 'conformance-repo'),
      );
      // ignore: avoid_print
      print('REPO=${repo.name}');
    } catch (e) {
      // ignore: avoid_print
      print('ERR $e');
    }
    await api.close();
  });
}

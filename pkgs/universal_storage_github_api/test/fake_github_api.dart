import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Minimal in-process fake of the GitHub Contents API sufficient for the
/// conformance suite: repo metadata, get contents, create/update/delete file.
class FakeGitHubApi {
  final Completer<void> _ready = Completer<void>();
  HttpServer? _boundServer;
  String _endpoint = '';

  /// Base URL of the fake API once bound; empty until ready.
  String get endpoint => _endpoint;

  Future<void> get ready => _ready.future;

  FakeGitHubApi() {
    unawaited(
      HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
        _boundServer = server;
        _endpoint = 'http://127.0.0.1:${server.port}/';
        server.listen(
          (final request) {
            unawaited(_handle(request));
          },
          onDone: () {
            if (!_ready.isCompleted) {
              _ready.complete();
            }
          },
        );
        if (!_ready.isCompleted) {
          _ready.complete();
        }
      }),
    );
  }

  GitHubApiStorageProvider createProvider() {
    final provider = GitHubApiStorageProvider(
      githubClient: GitHub(
        auth: Authentication.withToken('fake-token'),
        endpoint: _endpoint,
      ),
    );
    return provider;
  }

  Future<void> close() async {
    await _boundServer?.close(force: true);
  }

  final Map<String, _FakeFile> _files = <String, _FakeFile>{};
  var _shaCounter = 0;

  Future<void> _handle(final HttpRequest request) async {
    // The github client may produce a double leading slash when the endpoint
    // ends with '/'; drop empty segments before routing.
    final segments = request.uri.pathSegments
        .where((final segment) => segment.isNotEmpty)
        .toList();
    final response = request.response;

    // GET /repos/{owner}/{name}
    if (request.method == 'GET' &&
        segments.length == 3 &&
        segments[0] == 'repos') {
      response.statusCode = 200;
      response.write(jsonEncode(<String, dynamic>{'name': segments[2]}));
      await response.close();
      return;
    }

    // GET/PUT/DELETE /repos/{owner}/{name}/contents/{path...}
    if (segments.length > 4 &&
        segments[0] == 'repos' &&
        segments[3] == 'contents') {
      final filePath = segments.sublist(4).join('/');
      switch (request.method) {
        case 'GET':
          await _handleGet(request, filePath);
        case 'PUT':
          await _handlePut(request, filePath);
        case 'DELETE':
          await _handleDelete(request, filePath);
        default:
          response.statusCode = 405;
          await response.close();
      }
      return;
    }

    response.statusCode = 404;
    response.write(jsonEncode(<String, dynamic>{'message': 'Not Found'}));
    await response.close();
  }

  Future<void> _handleGet(
    final HttpRequest request,
    final String filePath,
  ) async {
    final file = _files[filePath];
    final response = request.response;
    if (file == null) {
      response.statusCode = 404;
      response.write(jsonEncode(<String, dynamic>{'message': 'Not Found'}));
      await response.close();
      return;
    }
    response.statusCode = 200;
    response.write(
      jsonEncode(<String, dynamic>{
        'name': filePath.split('/').last,
        'path': filePath,
        'sha': file.sha,
        'type': 'file',
        'size': file.content.length,
        'content': base64Encode(utf8.encode(file.content)),
        'encoding': 'base64',
      }),
    );
    await response.close();
  }

  Future<void> _handlePut(
    final HttpRequest request,
    final String filePath,
  ) async {
    final body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    final existing = _files[filePath];
    if (existing == null && body['sha'] != null) {
      request.response.statusCode = 422;
      await request.response.close();
      return;
    }
    _shaCounter++;
    final sha = 'sha$_shaCounter';
    _files[filePath] = _FakeFile(
      sha: sha,
      content: utf8.decode(base64Decode((body['content'] ?? '').toString())),
    );
    request.response.statusCode = existing == null ? 201 : 200;
    request.response.write(
      jsonEncode(<String, dynamic>{
        'content': <String, dynamic>{'path': filePath, 'sha': sha},
        'commit': <String, dynamic>{'sha': 'commit$sha'},
      }),
    );
    await request.response.close();
  }

  Future<void> _handleDelete(
    final HttpRequest request,
    final String filePath,
  ) async {
    final body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    final existing = _files[filePath];
    if (existing == null || existing.sha != body['sha']) {
      request.response.statusCode = 422;
      await request.response.close();
      return;
    }
    _files.remove(filePath);
    request.response.statusCode = 200;
    await request.response.close();
  }
}

class _FakeFile {
  _FakeFile({required this.sha, required this.content});
  final String sha;
  final String content;
}

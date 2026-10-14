import 'dart:convert';

import 'http_transport.dart';
import 'models.dart';
import 'signer.dart';

final class VkPlayServerApiClient {
  VkPlayServerApiClient({
    required this.baseUri,
    required this.secret,
    required this.transport,
    this.signer = const VkPlaySigner(),
    this.appId,
    this.signatureField = 'sig',
    this.defaultParams = const <String, Object?>{},
  });

  final Uri baseUri;
  final String secret;
  final VkPlayTransport transport;
  final VkPlaySigner signer;
  final String? appId;
  final String signatureField;
  final Map<String, Object?> defaultParams;

  Future<VkPlayApiResponse> getCommunityProfile({
    required String communityId,
  }) {
    return _sendSigned(
      endpointPath: 'community/profile',
      params: <String, Object?>{'community_id': communityId},
    );
  }

  Future<VkPlayApiResponse> getUserProfile({required String userId}) {
    return _sendSigned(
      endpointPath: 'profile/get',
      params: <String, Object?>{'user_id': userId},
    );
  }

  Future<VkPlayApiResponse> sendInvite({
    required String userId,
    required String message,
    String? payload,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _sendSigned(
      endpointPath: 'invite/send',
      params: <String, Object?>{
        'user_id': userId,
        'message': message,
        'payload': ?payload,
        ...extra,
      },
    );
  }

  Future<VkPlayApiResponse> shareToFeed({
    required String userId,
    required String message,
    String? linkUrl,
    String? imageUrl,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _sendSigned(
      endpointPath: 'feed/share',
      params: <String, Object?>{
        'user_id': userId,
        'message': message,
        'link_url': ?linkUrl,
        'image_url': ?imageUrl,
        ...extra,
      },
    );
  }

  Future<VkPlayApiResponse> getInventory({required String userId}) {
    return _sendSigned(
      endpointPath: 'inventory/get',
      params: <String, Object?>{'user_id': userId},
    );
  }

  Uri buildBillingUrl({
    required String userId,
    required String itemId,
    String? orderId,
    Map<String, Object?> extra = const <String, Object?>{},
    String endpointPath = 'billing/frame',
  }) {
    final params = _baseParams(<String, Object?>{
      'user_id': userId,
      'item_id': itemId,
      'order_id': ?orderId,
      ...extra,
    });
    final signature = signer.sign(params: params, secret: secret);

    final query = _stringifyParams(<String, Object?>{
      ...params,
      signatureField: signature,
    });

    return baseUri.resolve(endpointPath).replace(queryParameters: query);
  }

  bool verifyBillingCallback({
    required Map<String, Object?> payload,
    String? signatureKey,
  }) {
    return verifyVkPlayCallbackSignature(
      payload: payload,
      secret: secret,
      signatureKey: signatureKey ?? signatureField,
      signer: signer,
    );
  }

  VkPlaySignatureDiagnostics describeCanonicalization({
    required Map<String, Object?> params,
    Iterable<String> excludedKeys = const <String>{'sig', 'signature'},
  }) {
    return signer
        .signWithDiagnostics(
          params: params,
          secret: secret,
          excludedKeys: excludedKeys,
        )
        .diagnostics;
  }

  Future<VkPlayApiResponse> _sendSigned({
    required String endpointPath,
    required Map<String, Object?> params,
  }) async {
    final payload = _baseParams(params);
    final signature = signer.sign(params: payload, secret: secret);
    final requestParams = <String, Object?>{
      ...payload,
      signatureField: signature,
    };

    final request = VkPlayTransportRequest(
      method: 'POST',
      uri: baseUri.resolve(endpointPath),
      form: _stringifyParams(requestParams),
    );

    final response = await transport.send(request);
    final decoded = _decodeBody(response.body);

    return VkPlayApiResponse(
      statusCode: response.statusCode,
      data: decoded,
      rawBody: response.body,
      headers: response.headers,
    );
  }

  Map<String, Object?> _baseParams(Map<String, Object?> params) {
    return <String, Object?>{
      ...defaultParams,
      if (appId != null) 'app_id': appId,
      ...params,
    };
  }

  Map<String, String> _stringifyParams(Map<String, Object?> params) {
    return params.map((key, value) {
      if (value == null) {
        return MapEntry<String, String>(key, '');
      }
      if (value is Map || value is List) {
        return MapEntry<String, String>(key, jsonEncode(value));
      }
      return MapEntry<String, String>(key, value.toString());
    });
  }

  Map<String, Object?> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<Object?, Object?>) {
        return decoded.map(
          (key, value) => MapEntry(key?.toString() ?? '', value),
        );
      }
      return <String, Object?>{'data': decoded};
    } on FormatException {
      return <String, Object?>{'raw': body};
    }
  }
}

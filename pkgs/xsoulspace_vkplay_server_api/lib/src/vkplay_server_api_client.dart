import 'dart:convert';

import 'models.dart';
import 'signer.dart';
import 'http_transport.dart';

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
    required final String communityId,
  }) {
    return _sendSigned(
      endpointPath: 'community/profile',
      params: <String, Object?>{'community_id': communityId},
    );
  }

  Future<VkPlayApiResponse> getUserProfile({required final String userId}) {
    return _sendSigned(
      endpointPath: 'profile/get',
      params: <String, Object?>{'user_id': userId},
    );
  }

  Future<VkPlayApiResponse> sendInvite({
    required final String userId,
    required final String message,
    final String? payload,
    final Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _sendSigned(
      endpointPath: 'invite/send',
      params: <String, Object?>{
        'user_id': userId,
        'message': message,
        if (payload != null) 'payload': payload,
        ...extra,
      },
    );
  }

  Future<VkPlayApiResponse> shareToFeed({
    required final String userId,
    required final String message,
    final String? linkUrl,
    final String? imageUrl,
    final Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _sendSigned(
      endpointPath: 'feed/share',
      params: <String, Object?>{
        'user_id': userId,
        'message': message,
        if (linkUrl != null) 'link_url': linkUrl,
        if (imageUrl != null) 'image_url': imageUrl,
        ...extra,
      },
    );
  }

  Future<VkPlayApiResponse> getInventory({required final String userId}) {
    return _sendSigned(
      endpointPath: 'inventory/get',
      params: <String, Object?>{'user_id': userId},
    );
  }

  Uri buildBillingUrl({
    required final String userId,
    required final String itemId,
    final String? orderId,
    final Map<String, Object?> extra = const <String, Object?>{},
    final String endpointPath = 'billing/frame',
  }) {
    final params = _baseParams(<String, Object?>{
      'user_id': userId,
      'item_id': itemId,
      if (orderId != null) 'order_id': orderId,
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
    required final Map<String, Object?> payload,
    final String? signatureKey,
  }) {
    return verifyVkPlayCallbackSignature(
      payload: payload,
      secret: secret,
      signatureKey: signatureKey ?? signatureField,
      signer: signer,
    );
  }

  VkPlaySignatureDiagnostics describeCanonicalization({
    required final Map<String, Object?> params,
    final Iterable<String> excludedKeys = const <String>{'sig', 'signature'},
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
    required final String endpointPath,
    required final Map<String, Object?> params,
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

  Map<String, Object?> _baseParams(final Map<String, Object?> params) {
    return <String, Object?>{
      ...defaultParams,
      if (appId != null) 'app_id': appId,
      ...params,
    };
  }

  Map<String, String> _stringifyParams(final Map<String, Object?> params) {
    return params.map((final key, final value) {
      if (value == null) {
        return MapEntry<String, String>(key, '');
      }
      if (value is Map || value is List) {
        return MapEntry<String, String>(key, jsonEncode(value));
      }
      return MapEntry<String, String>(key, value.toString());
    });
  }

  Map<String, Object?> _decodeBody(final String body) {
    if (body.trim().isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<Object?, Object?>) {
        return decoded.map(
          (final key, final value) => MapEntry(key?.toString() ?? '', value),
        );
      }
      return <String, Object?>{'data': decoded};
    } on FormatException {
      return <String, Object?>{'raw': body};
    }
  }
}

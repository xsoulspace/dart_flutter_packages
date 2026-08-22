import 'dart:async';

import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Broadcast hub for kernel observation events.
///
/// Owns event correlation-id assignment and namespace/path-prefix filtering.
final class ObservationHub {
  final StreamController<StorageObservationEvent> _controller =
      StreamController<StorageObservationEvent>.broadcast(sync: true);

  int _sequence = 0;

  /// Emits one observation event, assigning a correlation id when missing.
  void emit({
    required final StorageObservationType type,
    required final StorageNamespace namespace,
    required final String path,
    final StorageOperationOrigin origin = StorageOperationOrigin.system,
    final StorageOperationResult? result,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    if (_controller.isClosed) {
      return;
    }

    final requestedCorrelationId =
        metadata['correlation_id']?.toString().trim() ?? '';
    final resolvedCorrelationId = requestedCorrelationId.isEmpty
        ? _nextCorrelationId(type: type, namespace: namespace)
        : requestedCorrelationId;
    final eventMetadata = <String, dynamic>{
      'correlation_id': resolvedCorrelationId,
      ...metadata,
    };

    _controller.add(
      StorageObservationEvent(
        type: type,
        namespace: namespace,
        path: path,
        timestamp: DateTime.now().toUtc(),
        origin: origin,
        result: result,
        metadata: eventMetadata,
      ),
    );
  }

  /// Returns a filtered stream of observation events.
  Stream<StorageObservationEvent> observe({
    final StorageNamespace? namespace,
    final String? pathPrefix,
  }) {
    final normalizedPrefix = (pathPrefix ?? '').trim();

    return _controller.stream.where((final event) {
      if (namespace != null && event.namespace != namespace) {
        return false;
      }
      if (normalizedPrefix.isNotEmpty &&
          !event.path.startsWith(normalizedPrefix)) {
        return false;
      }
      return true;
    });
  }

  /// Closes the underlying broadcast stream.
  Future<void> close() => _controller.close();

  String _nextCorrelationId({
    required final StorageObservationType type,
    required final StorageNamespace namespace,
  }) {
    _sequence++;
    return '${type.name}_${namespace.value}_'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
        '$_sequence';
  }
}

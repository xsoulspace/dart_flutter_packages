import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'uia_sidecar_client.dart';

/// Windows UI Automation driver over `uia-sidecar/1`.
///
/// The Windows control tree maps onto the family's snapshot model
/// (control-type ids → lowercase roles); clicks go through
/// `InvokePattern` — the semantic path Windows' own Narrator uses.
///
/// The sidecar is Windows-only: [connect] refuses loudly elsewhere
/// (typed exception, no dlopen attempt), matching the family rule that
/// unsupported surfaces fail loudly, never silently.
class UiaDriver implements AutomationDriver {
  /// Creates a driver over a connected [client].
  UiaDriver(this.client);

  /// Convenience: connects to the sidecar [binary] (or `XS_UIA_SIDECAR`)
  /// and hands back a ready driver. Refuses off Windows.
  static Future<UiaDriver> connect({String? binary}) async {
    if (!Platform.isWindows) {
      throw DriverUnsupportedException(
        'UiaDriver requires Windows; see universal_driver_linux for the '
        'Linux accessibility tier',
      );
    }
    final transport = await ProcessUiaSidecarTransport.start(
      binary: binary,
    );
    final client = UiaSidecarClient(transport);
    await client.handshake;
    return UiaDriver(client);
  }

  /// The underlying sidecar client.
  final UiaSidecarClient client;
  bool _closed = false;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
        a11yTree: true,
        inputSynthesis: true,
      );

  @override
  Future<Snapshot> snapshot() async {
    _ensureOpen();
    final result = await client.request('snapshot');
    final root = result['root'];
    if (root is! Map<String, Object?>) {
      throw const ProtocolException('sidecar returned no tree root');
    }
    return Snapshot(
      roots: [_mapNode(root)],
      capturedAt: DateTime.now().toUtc(),
      revision: 0,
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    _ensureOpen();
    switch (action) {
      case ClickAction(:final name):
        if (name == null) {
          throw DriverUnsupportedException(
            'UiaDriver.click needs a name locator; CSS selectors are '
            'browser-only',
          );
        }
        await client.request('invoke', {'name': name});
      case NavigateAction(:final url):
        throw DriverUnsupportedException(
          'UIA has no navigation surface (target: $url)',
        );
      case TypeAction(:final text):
        throw DriverUnsupportedException(
          'typing ${text.length} chars needs ValuePattern support, '
          'planned for the next sidecar revision',
        );
      case ScrollAction():
        throw const DriverUnsupportedException(
          'surface scrolling is not part of this driver\'s protocol; '
          'it refuses loudly instead of silently dropping it',
        );
      case KeyPressAction(:final key):
        throw const DriverUnsupportedException(
          'UIA exposes patterns on nodes, not surface scrolling; this driver refuses scroll loudly '
          'instead of silently dropping it',
        );
        throw DriverUnsupportedException(
          'key "$key" needs SendInput support, planned for the next '
          'sidecar revision',
        );
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'UIA has no script surface (got ${expression.length} chars)',
        );
      case ClickAtAction():
      case MoveAction():
      case DragAction():
        throw const DriverUnsupportedException(
          'coordinate pointer verbs (ADR 0053) are not wired for this '
          'tier yet; use locator verbs',
        );
      case InvokeAction(:final name):
        throw DriverUnsupportedException(
          'the UIA tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
        );
    }
  }

  @override
  Future<Uint8List> screenshot() async {
    _ensureOpen();
    throw DriverUnsupportedException(
      'UIA exposes semantics, not pixels; use a capture source for '
      'frames',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await client.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('UiaDriver is closed');
  }
}

/// Windows UIA control-type ids mapped onto the family role vocabulary
/// (subset of UIA_ControlTypeIds).
AxNode mapControlType({required int controlTypeId, required AxNode node}) {
  const table = <int, String>{
    50000: 'button', // UIA_ButtonControlTypeId
    50004: 'combobox',
    50025: 'checkbox',
    50007: 'textbox', // UIA_EditControlTypeId
    50037: 'heading',
    50043: 'hyperlink', // link
    50021: 'listitem',
    50033: 'menuitem',
    50010: 'image',
    50026: 'radio', // radio button
    50032: 'menu',
  };
  final role = table[controlTypeId];
  if (role == null) return node;
  return AxNode(
    role: role,
    name: node.name,
    value: node.value,
    bounds: node.bounds,
    attributes: node.attributes,
    children: node.children,
  );
}

AxNode _mapNode(Map<String, Object?> json) {
  final children = (json['children'] as List<Object?>? ?? const [])
      .whereType<Map<String, Object?>>()
      .map(_mapNode)
      .toList(growable: false);
  final controlType = json['controlType'];
  final node = AxNode(
    role: 'generic',
    name: json['name'] as String?,
    children: children,
  );
  return controlType is int
      ? mapControlType(controlTypeId: controlType, node: node)
      : node;
}

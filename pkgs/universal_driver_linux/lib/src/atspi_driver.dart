import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'atspi_bus.dart';

/// [AutomationDriver] over the Linux AT-SPI2 accessibility tree.
///
/// Observe: the D-Bus tree mapped to the family's [Snapshot]. Act:
/// semantic clicks through the AT-SPI `Action` interface (the trusted
/// path screen readers use — no synthetic X events); semantic writes
/// (ADR 0064) via `EditableText.SetTextContents`, laddering to the
/// numeric `Value` interface, and named advertised actions through
/// `Action.DoAction`. Verify: snapshot deltas. Navigation, keyboard
/// synthesis, and free-form script evaluation have no AT-SPI equivalent
/// and are refused loudly.
class AtspiDriver implements AutomationDriver {
  /// Creates a driver over [bus].
  AtspiDriver(this.bus);

  final AtspiBus bus;
  bool _closed = false;
  int _revision = 0;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    a11yTree: true,
    inputSynthesis: true,
    semanticWrite: true,
  );

  @override
  Future<Snapshot> snapshot() async {
    _ensureOpen();
    final rootRef = await bus.root();
    final nodes = await _walk(rootRef, 0);
    return Snapshot(
      roots: nodes,
      capturedAt: DateTime.now().toUtc(),
      revision: _revision,
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    _ensureOpen();
    switch (action) {
      case ClickAction(:final name):
        final node = await _findActionable(name);
        if (node == null) {
          throw DriverUnsupportedException(
            'no AT-SPI action target found${name == null ? '' : ' for "$name"'}',
          );
        }
        await bus.doAction(node, 0);
      case NavigateAction(:final url):
        throw DriverUnsupportedException(
          'AT-SPI has no navigation surface (target: $url); navigation '
          'is a browser-protocol capability',
        );
      case TypeAction(:final text):
        throw DriverUnsupportedException(
          'typing ${text.length} chars needs keyboard synthesis, which '
          'AT-SPI does not provide; use an input-tier driver',
        );
      case ScrollAction():
        throw const DriverUnsupportedException(
          'surface scrolling is not part of this driver\'s protocol; '
          'it refuses loudly instead of silently dropping it',
        );
      case KeyPressAction(:final key):
        throw DriverUnsupportedException(
          'key "$key" needs keyboard synthesis, which AT-SPI does not '
          'provide; use an input-tier driver',
        );
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'AT-SPI has no script surface (got ${expression.length} chars)',
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
          'the AT-SPI tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
        );
      case SetValueAction(:final value, :final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'AT-SPI has no css locator; set the value by role or name '
            '(resolved against the live tree)',
          );
        }
        await _setValue(value, role: role, name: name);
      case ElementAction(:final action, :final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'AT-SPI has no css locator; act by role or name (resolved '
            'against the live tree)',
          );
        }
        await _elementAction(action, role: role, name: name);
    }
  }

  @override
  Future<Uint8List> screenshot() async {
    _ensureOpen();
    throw DriverUnsupportedException(
      'AT-SPI exposes semantics, not pixels; use a capture source '
      '(universal_capture_macos, screencast polling) for frames',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await bus.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('AtspiDriver is closed');
  }

  Future<AtspiNodeRef?> _findActionable(String? name) async {
    final rootRef = await bus.root();
    final queue = <AtspiNodeRef>[rootRef];
    var visited = 0;
    while (queue.isNotEmpty && visited < _maxNodes) {
      final ref = queue.removeAt(0);
      visited++;
      if (await bus.hasActions(ref)) {
        final nodeName = await bus.name(ref);
        if (name == null || nodeName == name) return ref;
      }
      queue.addAll(await bus.children(ref));
    }
    return null;
  }

  /// The semantic-write locator walk (ADR 0064): first node whose mapped
  /// role and name match every locator given (both must match when
  /// present). Unlike [_findActionable] this does not require exposed
  /// actions — writable fields often carry none.
  Future<AtspiNodeRef?> _findWritable({String? role, String? name}) async {
    final rootRef = await bus.root();
    final queue = <AtspiNodeRef>[rootRef];
    var visited = 0;
    while (queue.isNotEmpty && visited < _maxNodes) {
      final ref = queue.removeAt(0);
      visited++;
      final roleMatches =
          role == null || _mapRole(await bus.roleName(ref)) == role;
      final nameMatches = name == null || await bus.name(ref) == name;
      if (roleMatches && nameMatches) return ref;
      queue.addAll(await bus.children(ref));
    }
    return null;
  }

  Future<void> _setValue(String value, {String? role, String? name}) async {
    final ref = await _findWritable(role: role, name: name);
    if (ref == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name ?? '',
      );
    }
    try {
      await bus.setContents(ref, value);
      return;
    } on AtspiInterfaceUnsupported {
      // Fall through to the numeric Value interface.
    }
    final numeric = double.tryParse(value);
    if (numeric == null) {
      throw DriverUnsupportedException(
        'the AT-SPI target exposes no EditableText and "$value" is not a '
        'number for the Value interface; setValue refused',
      );
    }
    try {
      await bus.setCurrentValue(ref, numeric);
    } on AtspiInterfaceUnsupported {
      throw const DriverUnsupportedException(
        'the AT-SPI target exposes neither EditableText nor Value; '
        'setValue refused loudly',
      );
    }
  }

  Future<void> _elementAction(
    String action, {
    String? role,
    String? name,
  }) async {
    final ref = await _findWritable(role: role, name: name);
    if (ref == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name ?? '',
      );
    }
    final advertised = await bus.actionNames(ref);
    var index = advertised.indexOf(action);
    if (index < 0) {
      index = advertised.indexWhere(
        (advertisedName) =>
            advertisedName.toLowerCase() == action.toLowerCase(),
      );
    }
    if (index < 0) {
      throw ProtocolException(
        'element action "$action" is not advertised by the target '
        '(advertised: ${advertised.isEmpty ? 'none' : advertised.join(', ')})',
      );
    }
    await bus.doAction(ref, index);
  }

  Future<List<AxNode>> _walk(AtspiNodeRef ref, int depth) async {
    if (depth > _maxDepth) return const [];
    final role = await bus.roleName(ref);
    final name = await bus.name(ref);
    final childRefs = await bus.children(ref);
    final children = <AxNode>[];
    for (final child in childRefs) {
      children.addAll(await _walk(child, depth + 1));
    }
    return [
      AxNode(
        role: _mapRole(role),
        name: name.isEmpty ? null : name,
        children: children,
      ),
    ];
  }
}

const int _maxDepth = 12;
const int _maxNodes = 500;

/// Maps AT-SPI role names onto the family's lowercase role vocabulary.
String _mapRole(String atspiRole) {
  final role = atspiRole.trim().toLowerCase();
  const table = {
    'push button': 'button',
    'button': 'button',
    'text': 'textbox',
    'entry': 'textbox',
    'password text': 'textbox',
    'frame': 'root',
    'window': 'root',
    'application': 'root',
    'check box': 'checkbox',
    'check box menu item': 'checkbox',
    'radio button': 'radio',
    'menu item': 'menuitem',
    'menu': 'menu',
    'label': 'label',
    'heading': 'heading',
    'image': 'image',
    'link': 'link',
    'list': 'list',
    'list item': 'listitem',
    'combo box': 'combobox',
    'page tab': 'tab',
    'scroll pane': 'generic',
  };
  return table[role] ?? (role.isEmpty ? 'generic' : role);
}

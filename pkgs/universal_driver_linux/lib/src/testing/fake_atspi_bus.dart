import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_driver_linux/universal_driver_linux.dart';

/// In-memory AT-SPI bus serving a canned tree - lets the driver's D-Bus
/// mapping be tested on any platform without a live session bus.
class FakeAtspiBus implements AtspiBus {
  FakeAtspiBus({Map<String, FakeAtspiNode>? nodes})
      : nodes = nodes ??
            {
              '$_rootPath': FakeAtspiNode(
                path: _rootPath,
                name: 'app window',
                role: 'frame',
              ),
              '$_rootPath/1': FakeAtspiNode(
                path: '$_rootPath/1',
                name: 'Save',
                role: 'push button',
                actions: 1,
              ),
              '$_rootPath/2': FakeAtspiNode(
                path: '$_rootPath/2',
                name: 'Email',
                role: 'text',
              ),
            };

  static const String _destination = 'org.a11y.atspi.Registry';
  static const String _rootPath = '/org/a11y/atspi/accessible/root';

  final Map<String, FakeAtspiNode> nodes;
  final List<String> invoked = [];

  AtspiNodeRef get rootRef => AtspiNodeRef(
        destination: _destination,
        path: _rootPath,
      );

  AtspiNodeRef ref(String path) => AtspiNodeRef(
        destination: _destination,
        path: path,
      );

  @override
  Future<AtspiNodeRef> root() async => rootRef;

  @override
  Future<String> name(AtspiNodeRef ref) async =>
      nodes[ref.path]?.name ?? '';

  @override
  Future<String> roleName(AtspiNodeRef ref) async =>
      nodes[ref.path]?.role ?? '';

  @override
  Future<List<AtspiNodeRef>> children(AtspiNodeRef ref) async {
    final prefix = '${ref.path}/';
    return nodes.keys
        .where((key) => key.startsWith(prefix))
        .map(refWithPath)
        .toList(growable: false);
  }

  AtspiNodeRef refWithPath(String path) => AtspiNodeRef(
        destination: _destination,
        path: path,
      );

  @override
  Future<bool> hasActions(AtspiNodeRef ref) async =>
      (nodes[ref.path]?.actions ?? 0) > 0;

  @override
  Future<void> doAction(AtspiNodeRef ref, int index) async {
    invoked.add('${ref.path}#$index');
  }

  @override
  Future<void> close() async {}
}

/// One canned AT-SPI node for [FakeAtspiBus].
@immutable
class FakeAtspiNode {
  /// Creates a node.
  FakeAtspiNode({
    required this.path,
    required this.name,
    required this.role,
    this.actions = 0,
  });

  /// Object path under the fake registry destination.
  final String path;

  /// Accessible name.
  final String name;

  /// AT-SPI role name.
  final String role;

  /// Number of exposed AT-SPI actions.
  final int actions;
}

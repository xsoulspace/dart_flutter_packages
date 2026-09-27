import 'package:dbus/dbus.dart';

import 'atspi_bus.dart';

/// The registry well-known name on the accessibility bus.
const String atspiRegistryName = 'org.a11y.atspi.Registry';

/// The registry tree root path.
const String atspiRootPath = '/org/a11y/atspi/accessible/root';

/// Production [AtspiBus] over the session bus: resolves the
/// accessibility bus address through `org.a11y.Bus`, then speaks
/// AT-SPI2's D-Bus interfaces on it.
class DBusAtspiBus implements AtspiBus {
  /// Creates an unconnected bus. [a11yAddress] overrides the
  /// `org.a11y.Bus.GetAddress` lookup (tests, or a bus on another
  /// display session).
  DBusAtspiBus({this.a11yAddress});

  /// Well-known a11y bus address override.
  final String? a11yAddress;
  DBusClient? _client;
  bool _closed = false;

  Future<DBusClient> _connect() async {
    if (_closed) {
      throw StateError('DBusAtspiBus is closed');
    }
    final existing = _client;
    if (existing != null) return existing;
    var address = a11yAddress;
    if (address == null || address.isEmpty) {
      final session = DBusClient.session();
      final reply = await session.callMethod(
        destination: 'org.a11y.Bus',
        path: DBusObjectPath('/org/a11y/bus'),
        interface: 'org.a11y.Bus',
        name: 'GetAddress',
        replySignature: DBusSignature('s'),
      );
      address = reply.returnValues.first.asString();
    }
    return _client = DBusClient(DBusAddress(address));
  }

  DBusRemoteObject _object(AtspiNodeRef ref) {
    final client = _client;
    if (client == null) {
      throw StateError('connect first: call root() before other methods');
    }
    return DBusRemoteObject(client, name: ref.destination, path: DBusObjectPath(ref.path));
  }

  @override
  Future<AtspiNodeRef> root() async {
    await _connect();
    return const AtspiNodeRef(
      destination: atspiRegistryName,
      path: atspiRootPath,
    );
  }

  @override
  Future<String> name(AtspiNodeRef ref) async {
    final object = _object(ref);
    final value = await object
        .getProperty('org.a11y.atspi.Accessible', 'Name')
        .catchError((Object _) => const DBusString(''));
    return value.asString();
  }

  @override
  Future<String> roleName(AtspiNodeRef ref) async {
    final object = _object(ref);
    final reply = await object.client.callMethod(
      destination: ref.destination,
      path: DBusObjectPath(ref.path),
      interface: 'org.a11y.atspi.Accessible',
      name: 'GetRoleName',
      replySignature: DBusSignature('s'),
    );
    return reply.returnValues.first.asString();
  }

  @override
  Future<List<AtspiNodeRef>> children(AtspiNodeRef ref) async {
    final object = _object(ref);
    try {
      final reply = await object.client.callMethod(
        destination: ref.destination,
        path: DBusObjectPath(ref.path),
        interface: 'org.a11y.atspi.Accessible',
        name: 'GetChildren',
        replySignature: DBusSignature('ao'),
      );
      return reply.returnValues.first
          .asObjectPathArray()
          .map(
            (path) => AtspiNodeRef(
              destination: ref.destination,
              path: path.value,
            ),
          )
          .toList(growable: false);
    } on DBusMethodResponseException {
      return _childrenLegacy(ref, object);
    }
  }

  Future<List<AtspiNodeRef>> _childrenLegacy(
    AtspiNodeRef ref,
    DBusRemoteObject object,
  ) async {
    final count = await object
        .getProperty('org.a11y.atspi.Accessible', 'ChildCount')
        .catchError((Object _) => const DBusInt32(0));
    final result = <AtspiNodeRef>[];
    for (var index = 0; index < count.asInt32(); index++) {
      final reply = await object.client.callMethod(
        destination: ref.destination,
        path: DBusObjectPath(ref.path),
        interface: 'org.a11y.atspi.Accessible',
        name: 'GetChildAtIndex',
        values: [DBusInt32(index)],
        replySignature: DBusSignature('o'),
      );
      result.add(
        AtspiNodeRef(
          destination: ref.destination,
          path: reply.returnValues.first.asObjectPath().value,
        ),
      );
    }
    return result;
  }

  @override
  Future<bool> hasActions(AtspiNodeRef ref) async {
    final object = _object(ref);
    final value = await object
        .getProperty('org.a11y.atspi.Action', 'NActions')
        .catchError((Object _) => const DBusInt32(0));
    return value.asInt32() > 0;
  }

  @override
  Future<void> doAction(AtspiNodeRef ref, int index) async {
    final object = _object(ref);
    await object.client.callMethod(
      destination: ref.destination,
      path: DBusObjectPath(ref.path),
      interface: 'org.a11y.atspi.Action',
      name: 'DoAction',
      values: [DBusInt32(index)],
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client?.close();
    _client = null;
  }
}

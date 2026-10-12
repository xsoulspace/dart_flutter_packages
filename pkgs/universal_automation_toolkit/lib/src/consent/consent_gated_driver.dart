import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

/// A policy refused an OS-consent surface (`consentRequired`). Distinct
/// from the drivers' typed TCC exceptions: those mean the OS lacks the
/// grant; this one means the composition's permission chain said no —
/// the driver call was never made.
class ConsentRequiredException extends AutomationException {
  /// Creates the exception for [permissionKind].
  ConsentRequiredException(this.permissionKind, {String? reason})
    : super(
        'consent denied for ${permissionKind.wireName}'
        '${reason == null ? '' : ': $reason'}',
        details: {
          'permissionKind': permissionKind.wireName,
          if (reason != null) 'reason': reason,
        },
      );

  @override
  String get kind => 'consentRequired';

  /// The refused OS-consent kind (`accessibility`, `screenRecording`).
  final PermissionKind permissionKind;
}

/// Which OS-consent surface [action] rides: every driver verb acts
/// through the accessibility layer (tree reads, AX writes, input
/// injection); pixels need the separate screen-recording grant.
PermissionKind consentKindFor(AutomationAction action) =>
    PermissionKind.accessibility;

/// The OS-consent half of the shared permission contract
/// ([permission-core]), composed onto any [AutomationDriver].
///
/// Automation owns the consent FACTS — the drivers' typed TCC
/// exceptions — while the permission package owns the DECISIONS. This
/// decorator is the seam: before each guarded call it asks the
/// [PermissionGate] (`accessibility` for snapshot/perform,
/// `screenRecording` for screenshots); an [PermissionAllow] lets the
/// call through (per kind, for the decorator's lifetime), a
/// [PermissionDeny] refuses before the driver is touched
/// ([ConsentRequiredException]), and escalates resolve through the
/// gate's sink or deny structurally.
///
/// An [PermissionAllow] is not a TCC grant: if the OS lacks the grant,
/// the driver's own typed exception surfaces untouched — the policy
/// said yes, the operating system is the authority that matters.
final class ConsentGatedDriver implements AutomationDriver {
  /// Wraps [inner]. [requestOrigin] attributes the requests (tool name,
  /// composition root); [subject] names the automation target when the
  /// composition knows it (an anchored app, an endpoint).
  ConsentGatedDriver(
    this._inner, {
    required PermissionGate gate,
    String requestOrigin = 'automation',
    String? subject,
  }) : _gate = gate,
       _origin = requestOrigin,
       _subject = subject;

  final AutomationDriver _inner;
  final PermissionGate _gate;
  final String _origin;
  final String? _subject;
  var _sequence = 0;
  final _allowed = <PermissionKind>{};

  @override
  DriverCapabilities get capabilities => _inner.capabilities;

  @override
  Future<Snapshot> snapshot() async {
    await _authorize(
      PermissionKind.accessibility,
      title: 'Read the accessibility tree of the automated surface',
    );
    return _inner.snapshot();
  }

  @override
  Future<void> perform(AutomationAction action) async {
    await _authorize(
      consentKindFor(action),
      title:
          'Act on the automated surface '
          '(${action.runtimeType.toString()})',
    );
    return _inner.perform(action);
  }

  @override
  Future<Uint8List> screenshot() async {
    await _authorize(
      PermissionKind.screenRecording,
      title: 'Capture pixels of the automated surface',
    );
    return _inner.screenshot();
  }

  @override
  Future<void> close() => _inner.close();

  Future<void> _authorize(PermissionKind kind, {required String title}) async {
    if (_allowed.contains(kind)) return;
    final decision = await _gate.resolve(
      PermissionRequest(
        id: 'consent-${++_sequence}',
        title: title,
        kind: kind,
        origin: _origin,
        subject: _subject,
        requestedAt: DateTime.now().toUtc(),
      ),
    );
    switch (decision) {
      case PermissionAllow(scope: PermissionGrantScope.once):
        // Authorized for this call only; the next call re-asks (the
        // transport's grant store records the spend).
        return;
      case PermissionAllow():
        _allowed.add(kind);
        return;
      case PermissionDeny(:final reason):
        throw ConsentRequiredException(kind, reason: reason);
      case PermissionEscalate(:final reason):
        // The gate resolves escalates through its sink; an escaped one
        // means a miscomposed sink — refuse rather than guess.
        throw ConsentRequiredException(
          kind,
          reason: reason ?? 'unresolved escalation',
        );
    }
  }
}

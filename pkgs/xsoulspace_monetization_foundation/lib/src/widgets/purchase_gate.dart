import 'package:flutter/widgets.dart';

import 'purchase_list_view.dart';

/// Signature for building the locked (no access) representation.
///
/// [onPurchase] is the gate's purchase callback; attach it to the
/// interactive part of the returned widget.
typedef GateLockedBuilder = Widget Function(
  BuildContext context,
  VoidCallback onPurchase,
);

/// {@template purchase_gate}
/// Material-free access gate for premium features.
///
/// Shows [child] when [hasAccess] is `true`; otherwise hands
/// [lockedBuilder] the [onPurchase] callback so the app renders its own
/// upgrade prompt. State precedence: [loadError] first, then [isLoading],
/// then the access check.
///
/// The access lifecycle (checking, refreshing after a purchase) stays with
/// the caller and is expressed through [isLoading], [loadError] and
/// [hasAccess] — the gate is stateless.
/// {@endtemplate}
class PurchaseGate extends StatelessWidget {
  /// {@macro purchase_gate}
  const PurchaseGate({
    required this.isLoading,
    required this.loadError,
    required this.hasAccess,
    required this.onPurchase,
    required this.child,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.lockedBuilder,
    super.key,
  });

  /// Whether the access check is still in flight.
  final bool isLoading;

  /// The error thrown by the access check, if any.
  final Object? loadError;

  /// Whether the user has access to the guarded feature.
  final bool hasAccess;

  /// Callback invoked when the user chooses to purchase access.
  final VoidCallback onPurchase;

  /// The guarded feature content.
  final Widget child;

  /// Builds the visual shown while [isLoading].
  final WidgetBuilder loadingBuilder;

  /// Builds the visual shown when [loadError] is set.
  final ProductsErrorBuilder errorBuilder;

  /// Builds the visual shown when access is denied.
  final GateLockedBuilder lockedBuilder;

  @override
  Widget build(BuildContext context) {
    final error = loadError;
    if (error != null) return errorBuilder(context, error);
    if (isLoading) return loadingBuilder(context);
    if (hasAccess) return child;
    return lockedBuilder(context, onPurchase);
  }
}

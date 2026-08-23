import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_storage_oauth/universal_storage_oauth.dart';

/// {@template default_device_flow_delegate}
/// Ready-made [OAuthFlowDelegate] for the GitHub device flow.
///
/// Opens the verification URL with `url_launcher`, shows a dialog with the
/// one-time user code (copyable), and completes when the user dismisses it
/// after authorizing. The provider's polling continues in the background —
/// dismissing the dialog early is harmless; cancelling aborts the flow.
/// {@endtemplate}
class DefaultDeviceFlowDelegate implements OAuthFlowDelegate {
  /// {@macro default_device_flow_delegate}
  const DefaultDeviceFlowDelegate({required this.context});

  /// Context used to show dialogs and look up theming.
  final BuildContext context;

  @override
  Future<String> getAuthorizationCode(
    final Uri authorizationUrl,
    final Uri redirectUrl, {
    final String? state,
  }) async {
    throw UnsupportedError(
      'DefaultDeviceFlowDelegate only supports the device flow. '
      'Provide a redirect-based delegate if you need authorization codes.',
    );
  }

  @override
  Future<void> handleDeviceFlow({
    required final String deviceCode,
    required final String userCode,
    required final Uri verificationUrl,
    required final int expiresIn,
    required final int interval,
    final Uri? verificationUrlComplete,
  }) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (final dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Connect GitHub'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter this code on github.com:'),
              const SizedBox(height: 12),
              Center(
                child: SelectableText(
                  userCode,
                  style: Theme.of(dialogContext).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Expires in ${(expiresIn / 60).ceil()} minutes.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open github.com'),
              onPressed: () async {
                await launchUrl(
                  verificationUrlComplete ?? verificationUrl,
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
              },
            ),
          ],
        ),
      ),
    );

    if (confirmed == null) return; // Dialog dismissed by flow completion.
    if (!confirmed) throw const OAuthFlowCancelledException();
  }

  @override
  Future<void> onAuthorizationSuccess({
    required final String maskedToken,
    required final List<String> scopes,
  }) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GitHub connected.')),
    );
  }

  @override
  Future<void> onAuthorizationError({
    required final String error,
    final String? description,
  }) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GitHub connection failed: ${description ?? error}'),
      ),
    );
  }
}

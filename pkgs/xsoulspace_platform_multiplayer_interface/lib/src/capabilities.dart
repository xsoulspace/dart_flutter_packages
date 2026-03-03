import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

import 'models.dart';

abstract interface class MultiplayerSessionCapability
    implements PlatformCapability {
  Future<MultiplayerSessionInitResult> initSession(
    MultiplayerSessionInitRequest request,
  );

  Future<void> commitState(MultiplayerCommitPayload payload);

  Future<MultiplayerPushResult> push(MultiplayerMeta meta);
}

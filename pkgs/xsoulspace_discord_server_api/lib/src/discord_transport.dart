import 'models.dart';

abstract interface class DiscordTransport {
  Future<DiscordTransportResponse> send(DiscordTransportRequest request);
}

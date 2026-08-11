import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/dynamic_scheme/event_channel_messages.g.dart',
    // dartOptions: DartOptions(ignoreLints: false),
    // cppOptions: CppOptions(namespace: 'pigeon_example'),
    // kotlinOut:
    //     'android/app/src/main/kotlin/dev/flutter/pigeon_example_app/EventChannelMessages.g.kt',
    // kotlinOptions: KotlinOptions(includeErrorClass: false),
    // swiftOut: 'macos/Runner/EventChannelMessages.g.swift',
    // swiftOptions: SwiftOptions(includeErrorClass: false),
    // copyrightHeader: 'pigeons/copyright.txt',
    // dartPackageName: 'pigeon_example_package',
  ),
)
// #docregion sealed-definitions
sealed class PlatformEvent {}

class IntEvent extends PlatformEvent {
  IntEvent(this.data);
  int data;
}

class StringEvent extends PlatformEvent {
  StringEvent(this.data);
  String data;
}

@EventChannelApi()
abstract class EventChannelMethods {
  PlatformEvent streamEvents();
}

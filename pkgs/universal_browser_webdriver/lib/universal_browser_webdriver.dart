/// Pure-Dart W3C WebDriver client.
///
/// Speaks classic WebDriver over HTTP: sessions, navigation, element
/// lookup, clicks, typing, key actions, and screenshots. The headline
/// target is Safari through the bundled `safaridriver` — no Java, no
/// Node — but any WebDriver endpoint (geckodriver, chromedriver,
/// msedgedriver, remote grids) speaks the same protocol.
///
/// Lifecycle note mirrors the family contract: [SafariDriverEndpoint]
/// spawns the driver binary for development and tests; production
/// composition hands an already-published endpoint URI to
/// [WebDriverClient].
library;

export 'src/safari_endpoint.dart';
export 'src/webdriver_bidi.dart';
export 'src/webdriver_client.dart';
export 'src/webdriver_driver.dart';
export 'src/webdriver_exceptions.dart';

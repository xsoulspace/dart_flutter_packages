/// Linux accessibility driver for the universal automation family.
///
/// Speaks AT-SPI2 — the accessibility tree Linux desktop apps expose
/// over D-Bus (GNOME/Kitty-style screen readers consume the same tree).
/// Pure Dart via `package:dbus`: observe the semantic tree and act
/// through the AT-SPI `Action` interface. No X11, no Wayland tools, no
/// native binary.
///
/// Driver tier: **OS-native** — works on any application that exposes
/// AT-SPI (GTK/Qt/LibreOffice/Chromium with `--force-renderer-accessibility`),
/// regardless of whether it opted into any agent protocol.
library;

export 'src/atspi_bus.dart';
export 'src/atspi_driver.dart';
export 'src/dbus_atspi_bus.dart';

# xsoulspace_ysdk_games_js

Generated `dart:js_interop` bindings and ergonomic Dart wrappers for the
[Yandex Games SDK](https://yandex.com/dev/games/doc/en/sdk/typescript).

This package provides two API layers:

- `package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart`
  - high-level wrapper API for app code
- `package:xsoulspace_ysdk_games_js/raw.dart`
  - generated low-level JS interop layer, version-coupled to `@types/ysdk`

## Platform support

- Web: full support
- Non-web: package compiles, but runtime calls throw `UnsupportedError`

## Installation

```yaml
dependencies:
  xsoulspace_ysdk_games_js: ^0.1.0
```

## Prerequisite in `web/index.html`

Load Yandex Games SDK script before using this package.

```html
<script src="https://yandex.ru/games/sdk/v2"></script>
```

## Quick start

```dart
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

Future<void> bootstrapGame() async {
  if (!YandexGames.isAvailable()) {
    return;
  }

  final ysdk = await YandexGames.init();

  final player = await ysdk.getPlayerUnsigned();
  final flags = await ysdk.getFlags(
    defaultFlags: <String, String>{'difficulty': 'normal'},
  );

  print('playerId=${player.getUniqueId()}');
  print('difficulty=${flags['difficulty']}');
}
```

`YandexGames.init` and `YandexGames.isAvailable` both support
`expectedGlobal` for custom global names.

## Signed and unsigned APIs

Some Yandex APIs have conditional signed/unsigned return types in TypeScript.
This package exposes explicit Dart methods to avoid ambiguous runtime casts:

- `getPlayerUnsigned()` and `getPlayerSigned()`
- `getPaymentsUnsigned()` and `getPaymentsSigned()`
- `purchaseUnsigned()` and `purchaseSigned()`
- `getPurchasesUnsigned()` and `getPurchasesSigned()`

## Wrapped SDK modules

`YsdkClient` includes typed wrappers for:

- `adv`
- `auth`
- `clipboard`
- `features`
- `feedback`
- `leaderboards`
- `multiplayer`
- `payments`
- `screen`
- `shortcut`
- `deviceInfo`
- `environment`

## Raw interop layer

Use raw generated types when you need direct JS-level access or newly added SDK
APIs before wrapper coverage:

```dart
import 'package:xsoulspace_ysdk_games_js/raw.dart';
```

The raw layer is generated from pinned upstream typings and may change when
`@types/ysdk` is bumped.

## Generator workflow

```bash
cd pkgs/xsoulspace_ysdk_games_js
just generate
```

Check generated files are up to date:

```bash
just generate-check
```

Bump upstream typings and regenerate:

```bash
just generate-bump 1.2.0
```

## Validation commands

Run all verification steps before publishing:

```bash
just verify
```

This runs:

- generator check
- `dart analyze`
- `dart test`
- browser tests (`dart test -p chrome`)

## Versioning policy

- Wrapper API follows semantic versioning.
- Raw API is coupled to `@types/ysdk`; minor upstream type shifts can affect
  generated symbol signatures.
- Upstream pin is stored in `tool/upstream_lock.json`.

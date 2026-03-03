# xsoulspace_crazygames_js

Generated `dart:js_interop` bindings and an ergonomic Dart wrapper for the CrazyGames HTML5 SDK v3.

## What this package provides

- Wrapper-first API for common SDK modules (`ad`, `banner`, `game`, `user`, `data`, `analytics`)
- Raw interop access for advanced use cases
- Experimental `sdk/game-v2` APIs are available in raw bindings only
- Web-only implementation with a clear non-web `UnsupportedError`

## Installation

```yaml
dependencies:
  xsoulspace_crazygames_js: ^0.1.0-dev.1
```

Load the CrazyGames SDK script in your web host page according to the official CrazyGames documentation.

## Quick start

```dart
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';

Future<void> bootstrapGame() async {
  final sdk = await CrazyGames.init();

  sdk.game.loadingStart();
  // load your game assets
  sdk.game.loadingStop();

  final user = await sdk.user.getUser();
  if (user != null) {
    // user is authenticated
  }

  final hasAdblock = await sdk.ad.hasAdblock();
  if (!hasAdblock) {
    await sdk.ad.requestAd(AdType.midgame);
  }
}
```

## Raw interop

```dart
import 'package:xsoulspace_crazygames_js/raw.dart' as raw;
```

Use the raw layer when you need direct JS-level access. The raw API is version-coupled and less stable than the wrapper API. Experimental `game-v2` APIs are intentionally raw-only.

## Source of truth

Generation uses a hybrid pipeline:
- Prefer official CrazyGames `.d.ts` when available.
- Otherwise synthesize declarations from CrazyGames docs pages plus runtime SDK surface extraction.
- Lock all upstream inputs in `tool/upstream_lock.json` (SDK hash, docs hash, declaration hash, version).

## Regeneration workflow

```bash
just generate
just generate-check
just generate-bump
```

- `generate`: refresh generated files against current lock.
- `generate-check`: fail if lock or generated files are stale.
- `generate-bump`: refresh upstream lock + regenerate snapshots/diff for intentional upstream updates.

## Platform behavior

- `web`: full functionality
- non-web: methods throw `UnsupportedError`

## License

MIT (see [LICENSE](LICENSE)).

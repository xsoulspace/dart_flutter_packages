# xsoulspace_discord_js

Generated `dart:js_interop` bindings and Dart wrapper for Discord Embedded App SDK.

## Exports

- `package:xsoulspace_discord_js/xsoulspace_discord_js.dart` - high-level wrapper API.
- `package:xsoulspace_discord_js/raw.dart` - low-level generated bindings.

## Host bridge requirement

Load the Discord Embedded SDK script in your web host before calling `Discord.init`.

```html
<script src="https://cdn.jsdelivr.net/npm/@discord/embedded-app-sdk@2.4.0/dist/index.js"></script>
```

## OAuth scope requirements

For social/auth flows in this wrapper, configure your app OAuth scopes accordingly:

- `identify` for user identity
- `relationships.read` for relationships/friends
- additional scopes as needed by your own commands

Missing scopes will surface as command-level failures.

## Quick start

```dart
import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';

Future<void> bootstrapDiscord() async {
  final discord = await Discord.init(clientId: '1234567890');

  final authCode = await discord.authorize(
    const DiscordAuthorizeRequest(
      clientId: '1234567890',
      scope: <String>['identify', 'relationships.read'],
    ),
  );

  // Exchange code on your backend, then authenticate in SDK:
  final accessToken = 'server-issued-access-token';
  final auth = await discord.authenticate(accessToken: accessToken);

  final relationships = await discord.getRelationships();
  final currentUserSubscription = await discord.onCurrentUserUpdate((final user) {
    // react to CURRENT_USER_UPDATE
  });

  await currentUserSubscription.cancel();
}
```

## Generation

```bash
just generate
just generate-check
just generate-bump
```

Generator inputs are locked in `tool/upstream_lock.json` against `@discord/embedded-app-sdk@2.4.0` integrity/hash.

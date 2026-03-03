# xsoulspace_discord_server_api

Server-only Discord API package for OAuth and generic REST v10 execution.

## Includes

- `DiscordTransport` abstraction + default HTTP transport.
- `DiscordOAuthClient` for authorization code exchange, refresh, and revoke.
- `DiscordServerApiClient` generic JSON-first request executor.
- Generated metadata coverage artifacts from `discord-api-types@0.38.40` (`rest/v10` routes + exported type index).
- Structured error model with status/code/message and retry/rate-limit metadata.

## Security

This package is intended for backend environments only.
Do not expose Discord client secrets or OAuth exchanges in Flutter/web/mobile clients.

## Generation

```bash
dart run tool/generate.dart
dart run tool/generate.dart --check
```

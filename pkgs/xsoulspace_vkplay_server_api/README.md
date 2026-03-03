# xsoulspace_vkplay_server_api

Server-only VK Play API package for signed endpoints.

## Includes

- Canonical VK Play signer (`MD5`) with diagnostics.
- Signature verification helpers for callbacks.
- Typed REST client wrappers for profile/community/invite/share/inventory.
- Billing URL builder with server-side signing.

## Security

This package is intended for backend environments only.
Do not ship your VK Play secret in Flutter/web/mobile clients.

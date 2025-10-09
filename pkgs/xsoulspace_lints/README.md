# Intro

Hi!

This is a set of rules which I use for my personal and commercial projects.

Usually, I review these rules once a year and update them based on the latest Flutter and Dart releases.

Hope this helps! :)

## Agentic Executable (AE) Support

This package is now an **Agentic Executable** - meaning AI agents can autonomously install, configure, update, and manage it in your projects.

See the `ae_use/` directory for:

- `ae_install.md` - AI-guided installation with automatic project type detection
- `ae_uninstall.md` - Complete removal with state restoration
- `ae_update.md` - Version migration handling
- `ae_use.md` - Generate AI agent usage rules for ongoing assistance

AI agents can use these files to provide seamless integration and ongoing development support.

# Available rules:

- `app.yaml` - useful for developing application or its parts.
- `library.yaml` - useful for monorepos.
- `public_library.yaml` - the purpose to use this lint if you developing a library which will be published to pub.dev.

# Usage:

1. Add dependecies for pubspec:

```yaml
dev_dependencies:
  lints: [latest_version]
  xsoulspace_lints: [latest_version]
```

2. Then place in the `analysis_options.yaml`

```yaml
include: package:xsoulspace_lints/[filename].yaml
```

For example:

```yaml
include: package:xsoulspace_lints/app.yaml
```

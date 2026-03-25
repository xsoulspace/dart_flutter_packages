# xsoulspace_js_interop_codegen

Shared code generation core used by `dart:js_interop` packages in this monorepo.

## Scope

This package contains reusable generator building blocks:

- npm tarball download and lockfile helpers
- TypeScript declaration parsing pipeline integration
- deterministic Dart emitter utilities

## Intended use

This is primarily an infrastructure package consumed by other packages in this repository (for example, SDK binding packages).

## License

MIT (see [LICENSE](LICENSE)).

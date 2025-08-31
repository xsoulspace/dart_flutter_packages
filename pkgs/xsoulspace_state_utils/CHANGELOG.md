## Versioning

This project follows [Semantic Versioning](https://semver.org/) (semver).  
Breaking changes will increment the major version, new features the minor, and bugfixes the patch.  
Always review the changelog before upgrading to a new version.

# Changelog

## 0.3.0

BREAKING CHANGES:

- `ImmutableOrderedMap` and `MutableOrderedMap` now use the `toKey` function to generate keys from values.
- `key` parameter is now optional for `upsert` method in `ImmutableOrderedMap` and `MutableOrderedMap`.
- added update method for `ImmutableOrderedMap` and `MutableOrderedMap`.

## 0.2.0

- Added `ImmutableOrderedSet` and `MutableOrderedSet` collections.

## 0.1.0

- Initial release of `xsoulspace_state_utils`.
- Added `OrderedList`, `OrderedListNotifier`, `OrderedMap`, and `OrderedMapNotifier` collections.
- Added `lib_ai_use` folder with AI Agent usage patterns.

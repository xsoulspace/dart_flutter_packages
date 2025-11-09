## Versioning

This project follows [Semantic Versioning](https://semver.org/) (semver).  
Breaking changes will increment the major version, new features the minor, and bugfixes the patch.  
Always review the changelog before upgrading to a new version.

# Changelog

## 0.5.2

- added: `update` method for `MutableOrderedMap` and `ImmutableOrderedMap` now returns the updated value.

## 0.5.1

- chore: xsoulspace_foundation 0.3.0

## 0.5.0

- added: `upsertAll` method for `MutableOrderedMap` with optional `toKey` parameter for efficient batch operations.
- added: `upsertAll` method for `ImmutableOrderedMap` with optional `putFirst` and `toKey` parameters for efficient batch operations.
- added: `upsertAll` method for `OrderedMapNotifier` with single notification for efficient reactive batch operations.

## 0.4.0

- chore: xsoulspace_foundation 0.2.2
- added: `assignAll` and `assignAllOrdered` for `MutableOrderedMap`.

## 0.3.2

- added: `operator []` and `operator []=` for `MutableOrderedList` and `ImmutableOrderedList`.

## 0.3.1

- fix: `ImmutableOrderedMap` and `MutableOrderedMap` toKey is now optional.
- fix: `ImmutableOrderedMap` and `MutableOrderedMap` and `OrderedMapNotifier` assignAllOrdered now accepts Iterable.

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

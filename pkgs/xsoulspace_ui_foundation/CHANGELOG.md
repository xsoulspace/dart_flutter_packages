## Versioning

This project follows [Semantic Versioning](https://semver.org/) (semver).  
Breaking changes will increment the major version, new features the minor, and bugfixes the patch.  
Always review the changelog before upgrading to a new version.

## 0.2.1

- Fixed:
  - `HashPagingController` now correctly merges new pages with existing pages

## 0.2.0

- **BREAKING**: Updated `infinite_scroll_pagination` from 4.1.0 to 5.1.1
  - `infinite_scroll_pagination_utils` module has been refactored to work with the new API
  - `HashPagingController` constructor now requires `getNextPageKey` and `fetchPage` callbacks
  - `BasePagingController` usage remains backward compatible - no changes required for existing implementations
  - Internal pagination state structure changed from `itemList` to `pages` (list of lists)
  - Removed deprecated listener-based pattern in favor of callback-based approach
- Changed:

  - `HashPagingController`: Now automatically applies hash-based deduplication during pagination
  - `BasePagingController.onLoad()`: Simplified to directly call `loadFirstPage()`
  - Updated `infinite_scroll_pagination_utils` README with corrected API examples and comprehensive method documentation

- Fixed:
  - Item count listeners now work correctly with the new pages structure
  - Proper end-of-pagination detection using `hasNextPage` boolean

## 0.1.0

- chore: sdk: ">=3.8.1 <4.0.0"

## 0.0.11

- Updated:
  - freezed_annotation: ^3.0.0
  - freezed: ^3.0.3
  - json_serializable: ^6.9.4

## 0.0.10

- Updated:
  - dart sdk 3.7.0
  - collection 1.19.0
  - collection: ^1.19.0
  - shared_preferences: ^2.5.2
  - store_checker: ^1.8.0
  - lints: ^5.1.1
  - xsoulspace_lints: ^0.0.14

## 0.0.9

- Fixed:
  - export `infinite_scroll_pagination_utils`

## 0.0.8

- Added:
  - `infinite_scroll_pagination_utils` module with Readme documentation.
- Changed:
  - Improved some of Readme documentation.

## 0.0.7

- Fixed:
  - `set_x.dart` and `map_x.dart` exports

## 0.0.6

- Added:
  - `whenZeroUse` extension for `int` and `double`
  - `whenEmptyUse` extension for `Set`, `List`, `Map`
  - `unmodifiable` extension for `Set`, `List`, `Map`
  - Bumped Dart SDK to 3.6.0 and dependency versions
  - Updated extension names for consistency (now all ends with `X`, and starts with `XS`)

## 0.0.5

- Added:
  - `whenZeroUse` extension for `int` and `double`
- Chore:
  - updated `xsoulspace_lints` to 0.0.12

## 0.0.4

- Changed:
  - Names of the extensions to exclude conflicts with other packages
  - Added `context.viewPadding` extension to simplify getting specific to view padding

## 0.0.3

- Added:
  - AppStoreUtils with StoreChecker package

## 0.0.2

- Added:
  - Loadable, Disposable
- Removed:
  - hooks moved to life_hooks package.
  - dependecies flutter_hooks and flutter_keyboard_visibility removed

## 0.0.1

- Initial release with basic utils.

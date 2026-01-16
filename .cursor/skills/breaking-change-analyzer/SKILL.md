---
name: breaking-change-analyzer
description: Analyze impact of API changes across the monorepo, identify breaking changes, and generate migration guides. Use when making API changes, updating core packages, planning breaking changes, or when user mentions breaking changes, API updates, or migration.
---

# Breaking Change Impact Analyzer

Analyze the impact of API changes and guide migration across dependent packages.

## Quick Start

When making breaking changes:

1. Identify the change type
2. Find all affected packages
3. Assess impact level
4. Plan migration strategy
5. Generate migration guide

## Change Classification

### Breaking Changes

Changes that require code updates in dependent packages:

**API Changes:**
- Renamed classes, methods, or properties
- Removed public APIs
- Changed method signatures
- Changed return types
- Modified constructor parameters

**Behavioral Changes:**
- Changed default values
- Modified error handling
- Altered side effects
- Changed execution order

**Dependency Changes:**
- Bumped minimum SDK version
- Updated major dependency versions
- Removed dependencies

### Non-Breaking Changes

Changes that don't affect dependent packages:

- Added new APIs (backward compatible)
- Deprecated APIs (with alternatives)
- Internal implementation changes
- Documentation updates
- Bug fixes (no API changes)

## Impact Analysis Workflow

### Step 1: Identify the Change

Document what's changing:

```markdown
Package: <package_name>
Version: <old_version> → <new_version>

Changes:
- [ ] Renamed: OldClass → NewClass
- [ ] Removed: deprecatedMethod()
- [ ] Modified: method(old) → method(new, required)
- [ ] Changed behavior: method() now throws Exception
```

### Step 2: Find Affected Packages

Search for usage across monorepo:

```bash
# Search for class usage
grep -r "OldClassName" pkgs/*/lib/ pkgs/*/test/

# Search for method usage
grep -r "\.oldMethodName(" pkgs/*/lib/ pkgs/*/test/

# Search for import statements
grep -r "import.*old_file.dart" pkgs/*/lib/ pkgs/*/test/
```

**For renamed APIs:**
```bash
# Find all references to old name
old_name="OldClass"
grep -r "\b$old_name\b" pkgs/*/lib/ pkgs/*/test/ \
  | grep -v "^pkgs/<current_package>/" \
  | cut -d: -f1 \
  | sort -u
```

### Step 3: Categorize Impact

**High Impact:**
- Core interface packages (e.g., `*_interface`)
- Foundation packages (e.g., `xsoulspace_foundation`)
- 5+ dependent packages

**Medium Impact:**
- Mid-level packages
- 2-4 dependent packages
- Platform-specific implementations

**Low Impact:**
- Leaf packages (no dependents)
- Example apps only
- 0-1 dependent packages

### Step 4: Create Migration Plan

**For each affected package:**

```markdown
## Migration Plan

### Package: <affected_package>

**Current usage:**
```dart
// Old code
import 'package:core/old_api.dart';

final instance = OldClass();
instance.oldMethod();
```

**Required changes:**
```dart
// New code
import 'package:core/new_api.dart';

final instance = NewClass();
instance.newMethod();
```

**Estimated effort:** <low/medium/high>
```

### Step 5: Determine Version Bump

Follow semantic versioning:

**Major version bump (X.0.0):**
- Breaking API changes
- Removed public APIs
- Changed behavior of existing APIs

**Minor version bump (0.X.0):**
- New features (backward compatible)
- Deprecations (with alternatives)
- Non-breaking additions

**Patch version bump (0.0.X):**
- Bug fixes
- Internal changes
- Documentation updates

## Migration Strategies

### Strategy 1: Deprecation Path (Recommended)

Provide transition period:

```dart
// In the package being updated

/// Old API - deprecated
@Deprecated('Use NewClass instead. Will be removed in v2.0.0')
class OldClass {
  // Keep old implementation
}

/// New API
class NewClass {
  // New implementation
}
```

**Timeline:**
1. Release v1.X.0 with deprecation warnings
2. Update dependent packages to use new API
3. Release v2.0.0 removing deprecated APIs

### Strategy 2: Direct Migration

For smaller changes or internal packages:

1. Update the core package
2. Update all dependent packages immediately
3. Release all packages together

### Strategy 3: Adapter Pattern

Provide compatibility layer:

```dart
// In the package being updated

/// New API
class NewClass {
  void newMethod() { }
}

/// Adapter for backward compatibility
@Deprecated('Use NewClass directly')
class OldClass extends NewClass {
  @override
  void newMethod() => oldMethod();
  
  @Deprecated('Use newMethod instead')
  void oldMethod() => super.newMethod();
}
```

## Migration Guide Template

```markdown
# Migration Guide: <package_name> v<old> → v<new>

## Overview

This guide helps you migrate from v<old> to v<new> of <package_name>.

## Breaking Changes

### 1. Renamed Class: OldClass → NewClass

**Before:**
```dart
import 'package:<package_name>/old_api.dart';

final instance = OldClass();
```

**After:**
```dart
import 'package:<package_name>/new_api.dart';

final instance = NewClass();
```

**Reason:** <Explanation of why the change was made>

### 2. Modified Method Signature

**Before:**
```dart
instance.method(param);
```

**After:**
```dart
instance.method(param, required: newParam);
```

**Reason:** <Explanation>

## Deprecated APIs

The following APIs are deprecated and will be removed in v<next_major>:

- `OldClass` → Use `NewClass`
- `oldMethod()` → Use `newMethod()`

## Migration Steps

1. Update `pubspec.yaml`:
   ```yaml
   dependencies:
     <package_name>: ^<new_version>
   ```

2. Run `dart pub get`

3. Fix deprecation warnings:
   ```bash
   dart analyze
   ```

4. Update imports and usage as shown above

5. Test your changes:
   ```bash
   dart test
   ```

## Need Help?

- [API Documentation](link)
- [GitHub Issues](link)
- [Migration Examples](link)
```

## Automated Detection

### Find Breaking Changes with Git

```bash
# Compare API changes between versions
git diff v1.0.0..v2.0.0 -- lib/

# Find removed public APIs
git diff v1.0.0..v2.0.0 -- lib/ | grep "^-" | grep "class\|void\|Future"

# Find renamed files
git diff v1.0.0..v2.0.0 --name-status -- lib/
```

### Analyze Public API Surface

```bash
# List all public classes
grep -r "^class " pkgs/<package>/lib/ | grep -v "^lib/src/"

# List all public functions
grep -r "^[A-Z].*(" pkgs/<package>/lib/ | grep -v "^lib/src/"

# Find exports
grep -r "^export " pkgs/<package>/lib/
```

## Impact Assessment Matrix

| Change Type | Impact Level | Version Bump | Migration Effort |
|-------------|--------------|--------------|------------------|
| Rename class | High | Major | Medium |
| Remove method | High | Major | High |
| Add parameter (required) | High | Major | Medium |
| Add parameter (optional) | Low | Minor | Low |
| Deprecate API | Low | Minor | Low |
| Change behavior | Medium-High | Major | Medium-High |
| Internal refactor | None | Patch | None |

## Communication Plan

### For Major Breaking Changes

1. **Announce in advance**
   - Create GitHub issue
   - Update CHANGELOG with migration guide
   - Add deprecation warnings in code

2. **Provide migration period**
   - Release deprecated APIs first
   - Allow time for dependent packages to update
   - Monitor adoption

3. **Release breaking changes**
   - Bump major version
   - Remove deprecated APIs
   - Update all examples

### For Minor Changes

1. **Document in CHANGELOG**
2. **Update dependent packages**
3. **Release new version**

## Dependency Update Order

When making breaking changes to core packages:

```
1. Core package (e.g., universal_storage_interface)
   ↓
2. Direct dependents (e.g., universal_storage_filesystem)
   ↓
3. Transitive dependents (e.g., universal_storage_sync)
   ↓
4. Applications and examples
```

## Testing Strategy

### Before Release

```bash
# 1. Test the updated package
cd pkgs/<updated_package>
dart test

# 2. Test direct dependents
for pkg in <dependent_packages>; do
  cd "pkgs/$pkg"
  dart test
  cd ../..
done

# 3. Run analyzer on all packages
for dir in pkgs/*/; do
  cd "$dir"
  dart analyze
  cd ../..
done
```

### After Release

```bash
# Monitor for issues
# Check GitHub issues
# Review pub.dev feedback
# Update migration guide based on feedback
```

## Common Breaking Change Patterns

### Pattern 1: Interface Expansion

**Before:**
```dart
abstract class Storage {
  Future<void> save(String data);
}
```

**After (Breaking):**
```dart
abstract class Storage {
  Future<void> save(String data);
  Future<void> delete(String id);  // New required method
}
```

**Migration:** All implementations must add `delete` method.

### Pattern 2: Parameter Addition

**Before:**
```dart
void process(String data);
```

**After (Breaking):**
```dart
void process(String data, {required Format format});
```

**Migration:** All callers must provide `format` parameter.

### Pattern 3: Type Change

**Before:**
```dart
String getId();
```

**After (Breaking):**
```dart
int getId();
```

**Migration:** All callers must handle `int` instead of `String`.

## Rollback Plan

If breaking changes cause major issues:

1. **Immediate:** Publish patch with bug fixes
2. **Short-term:** Restore deprecated APIs in new minor version
3. **Long-term:** Plan better migration path

## Checklist Template

Copy this for breaking changes:

```
Package: <name>
Version: <old> → <new>

Analysis:
- [ ] Identified all breaking changes
- [ ] Found all affected packages
- [ ] Assessed impact level
- [ ] Created migration plan

Communication:
- [ ] Updated CHANGELOG
- [ ] Created migration guide
- [ ] Announced changes (if major)
- [ ] Added deprecation warnings (if applicable)

Implementation:
- [ ] Updated core package
- [ ] Updated dependent packages
- [ ] Updated examples
- [ ] Updated documentation

Testing:
- [ ] Core package tests pass
- [ ] Dependent package tests pass
- [ ] Integration tests pass
- [ ] Manual testing complete

Release:
- [ ] Version bumped correctly
- [ ] Published to pub.dev
- [ ] Tagged in git
- [ ] Announced release
```

## Quick Reference

```bash
# Find usages of API
grep -r "ApiName" pkgs/*/lib/ pkgs/*/test/

# Find packages that depend on a package
grep -r "path:.*package_name" pkgs/*/pubspec.yaml

# List all public APIs
grep -r "^class\|^enum\|^typedef" pkgs/<package>/lib/ | grep -v "/src/"

# Check for breaking changes
git diff v1.0.0..HEAD -- lib/ | grep "^-" | grep "class\|void\|Future"
```

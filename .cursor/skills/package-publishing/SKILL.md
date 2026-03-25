---
name: package-publishing
description: Automate Dart/Flutter package publishing to pub.dev with version validation, changelog updates, and dependency checks. Use when publishing packages, updating versions, preparing releases, or when user mentions pub.dev, publishing, or version bumps.
---

# Package Publishing & Versioning

Automate the complex workflow of publishing Dart/Flutter packages to pub.dev across the monorepo.

## Quick Start

When publishing packages:

1. Validate package state
2. Update versions and changelogs
3. Run dry-run validation
4. Publish to pub.dev

## Publishing Workflow

### Step 1: Pre-publish Validation

Run validation checks:

```bash
# Check package structure
cd pkgs/<package-name>
dart pub get
dart analyze
dart test

# Validate pubspec.yaml
dart pub publish --dry-run
```

**Validation checklist:**
- [ ] All tests pass
- [ ] No analyzer warnings
- [ ] pubspec.yaml is valid
- [ ] CHANGELOG.md is updated
- [ ] README.md is complete
- [ ] LICENSE file exists
- [ ] Version follows semver

### Step 2: Version Update Strategy

Determine version bump type:

**Patch (0.0.X)**: Bug fixes, no API changes
**Minor (0.X.0)**: New features, backward compatible
**Major (X.0.0)**: Breaking changes

Update `pubspec.yaml`:
```yaml
version: 1.2.3  # Update this line
```

### Step 3: Changelog Update

Add entry to `CHANGELOG.md`:

```markdown
## [1.2.3] - 2026-01-16

### Added
- New feature description

### Fixed
- Bug fix description

### Changed
- Breaking change description (if major version)
```

### Step 4: Dependency Version Checks

Verify dependencies across monorepo:

```bash
# Find all packages that depend on this one
grep -r "path: ../.*<package-name>" pkgs/*/pubspec.yaml
```

**If this is a core package** (e.g., `universal_storage_interface`):
- List all dependent packages
- Note which need version updates
- Plan update order (dependencies first)

### Step 5: Dry Run

Always run dry-run first:

```bash
cd pkgs/<package-name>
dart pub publish --dry-run
```

Review output for:
- Files that will be published
- Files that are excluded
- Package size
- Any warnings

### Step 6: Publish

If dry-run succeeds:

```bash
dart pub publish
```

Follow prompts to confirm.

## Multi-Package Publishing

When publishing multiple related packages:

### Order of Operations

1. **Core interfaces first**: Publish base packages (e.g., `*_interface`)
2. **Implementations next**: Publish packages that depend on interfaces
3. **Examples last**: Publish example apps if needed

### Batch Publishing Script

For coordinated releases:

```bash
# List packages in dependency order
packages=(
  "universal_storage_interface"
  "universal_storage_filesystem"
  "universal_storage_db"
  "universal_storage_sync"
)

for pkg in "${packages[@]}"; do
  echo "Publishing $pkg..."
  cd "pkgs/$pkg"
  dart pub publish --dry-run
  # Review output, then:
  # dart pub publish
  cd ../..
done
```

## Common Issues

### Issue: Version Conflict

**Symptom**: Dependent packages reference old version

**Solution**:
1. Update dependent packages' pubspec.yaml
2. Publish in dependency order
3. Update version constraints

### Issue: Missing Files

**Symptom**: Important files not included in package

**Solution**: Check `.gitignore` - pub.dev respects it
Add explicit includes in `pubspec.yaml`:

```yaml
# Rarely needed, but available:
# include:
#   - lib/**
#   - README.md
#   - CHANGELOG.md
```

### Issue: Package Too Large

**Symptom**: Package exceeds size limits

**Solution**:
- Remove unnecessary assets
- Add files to `.gitignore`
- Move examples to separate package

## Version Constraint Guidelines

Use these patterns in `pubspec.yaml`:

```yaml
dependencies:
  # For stable packages
  package_name: ^1.0.0
  
  # For pre-release packages
  package_name: ">=0.1.0 <1.0.0"
  
  # For local development (path dependencies)
  local_package:
    path: ../local_package
```

## Makefile Integration

Standard Makefile targets for publishing:

```makefile
publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish
```

Use these targets:
```bash
make publish-dry  # Always run first
make publish      # After reviewing dry-run
```

## Checklist Template

Copy this for each publish:

```
Package: <name>
Version: <old> → <new>

Pre-publish:
- [ ] Tests pass
- [ ] Analyzer clean
- [ ] CHANGELOG updated
- [ ] Version bumped
- [ ] Dependencies checked
- [ ] Dry-run successful

Publish:
- [ ] Published to pub.dev
- [ ] Verified on pub.dev
- [ ] Tagged in git (optional)

Post-publish:
- [ ] Update dependent packages
- [ ] Announce if major version
```

## Git Tagging (Optional)

Tag releases for tracking:

```bash
git tag v1.2.3
git push origin v1.2.3
```

## Resources

- [Pub.dev Publishing Guide](https://dart.dev/tools/pub/publishing)
- [Semantic Versioning](https://semver.org/)
- Project Makefiles in `pkgs/*/Makefile`

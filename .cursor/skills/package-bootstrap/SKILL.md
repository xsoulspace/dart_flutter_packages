---
name: package-bootstrap
description: Scaffold new Dart/Flutter packages with monorepo conventions including pubspec.yaml, Makefile, analysis_options.yaml, LICENSE, and README. Use when creating new packages, setting up package structure, or when user mentions new package, scaffold, or bootstrap.
---

# Package Bootstrap & Setup

Scaffold new packages with consistent structure and conventions for the monorepo.

## Quick Start

When creating a new package:

1. Choose package type (Dart library or Flutter package)
2. Generate directory structure
3. Create standard files (pubspec.yaml, README, etc.)
4. Initialize git and run initial setup

## Package Types

### Dart Library (Pure Dart)
- No Flutter dependencies
- Can run on any Dart platform
- Example: `xsoulspace_foundation`, `universal_storage_interface`

### Flutter Package
- Requires Flutter SDK
- May include platform-specific code
- Example: `xsoulspace_ui_foundation`, `universal_storage_sync`

## Bootstrap Workflow

### Step 1: Create Package Directory

```bash
# Navigate to packages directory
cd pkgs

# Create package directory (use snake_case)
mkdir <package_name>
cd <package_name>
```

**Naming conventions:**
- Use `snake_case` for package names
- Prefix with family name (e.g., `universal_storage_*`, `xsoulspace_*`)
- Use descriptive names (e.g., `*_interface`, `*_foundation`)

### Step 2: Create Directory Structure

Standard structure:

```
<package_name>/
├── lib/
│   ├── src/
│   │   └── (implementation files)
│   └── <package_name>.dart
├── test/
│   └── <package_name>_test.dart
├── example/
│   └── (optional example files)
├── .gitignore
├── analysis_options.yaml
├── CHANGELOG.md
├── LICENSE
├── Makefile
├── pubspec.yaml
└── README.md
```

Create directories:
```bash
mkdir -p lib/src test example
```

### Step 3: Create pubspec.yaml

**For Dart Library:**

```yaml
name: <package_name>
description: <Brief description of the package>
version: 0.1.0-dev.1
homepage: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/<package_name>
repository: https://github.com/xsoulspace/dart_flutter_packages
issue_tracker: https://github.com/xsoulspace/dart_flutter_packages/issues
documentation: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/<package_name>

environment:
  sdk: ^3.9.0

dependencies:
  meta: ^1.16.0

dev_dependencies:
  lints: ^6.0.0
  xsoulspace_lints: ^0.1.2
  test: ^1.25.0
```

**For Flutter Package:**

```yaml
name: <package_name>
description: <Brief description of the package>
version: 0.1.0-dev.1
homepage: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/<package_name>
repository: https://github.com/xsoulspace/dart_flutter_packages
issue_tracker: https://github.com/xsoulspace/dart_flutter_packages/issues
documentation: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/<package_name>

environment:
  sdk: ^3.9.0

dependencies:
  flutter:
    sdk: flutter
  meta: ^1.16.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^6.0.0
  xsoulspace_lints: ^0.1.2
```

**Version numbering:**
- Start with `0.1.0-dev.1` for new packages
- Use `-dev.X` suffix during development
- Remove `-dev` when ready for first stable release

### Step 4: Create analysis_options.yaml

```yaml
include: package:xsoulspace_lints/library.yaml

analyzer:

linter:
  rules:
    # Add custom rule overrides if needed
    # avoid_annotating_with_dynamic: false
```

**For Flutter packages**, use:
```yaml
include: package:xsoulspace_lints/app.yaml
```

### Step 5: Create LICENSE

```
MIT License

Copyright (c) 2026 Anton Malofeev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Step 6: Create Makefile

```makefile
publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish

gen-rewrite:
	dart pub run build_runner build --delete-conflicting-outputs

gen:
	dart pub run build_runner build
```

**For Flutter packages**, use `flutter pub` instead of `dart pub`.

### Step 7: Create README.md

```markdown
# <Package Name>

<Brief description of what this package does>

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  <package_name>: ^0.1.0
```

## Usage

```dart
import 'package:<package_name>/<package_name>.dart';

// Example usage
```

## API Reference

### Main Classes

#### ClassName

Description of the class.

**Example:**
```dart
// Usage example
```

## Additional Information

- [API Documentation](https://pub.dev/documentation/<package_name>/latest/)
- [GitHub Repository](https://github.com/xsoulspace/dart_flutter_packages)
- [Issue Tracker](https://github.com/xsoulspace/dart_flutter_packages/issues)

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting PRs.

## License

This package is licensed under the MIT License. See [LICENSE](LICENSE) for details.
```

### Step 8: Create CHANGELOG.md

```markdown
## [0.1.0-dev.1] - 2026-01-16

### Added
- Initial release
- Basic functionality
```

### Step 9: Create .gitignore

```
# Files and directories created by pub
.dart_tool/
.packages
build/
pubspec.lock

# Coverage
coverage/

# IDE
.idea/
.vscode/
*.iml
*.ipr
*.iws

# OS
.DS_Store
```

### Step 10: Create Main Library File

Create `lib/<package_name>.dart`:

```dart
/// <Package description>
///
/// {@category <Category>}
library;

export 'src/<package_name>.dart';
```

### Step 11: Create Implementation File

Create `lib/src/<package_name>.dart`:

```dart
/// {@template <package_name>}
/// Main class for <package_name>.
/// {@endtemplate}
class <ClassName> {
  /// {@macro <package_name>}
  const <ClassName>();
}
```

### Step 12: Create Test File

Create `test/<package_name>_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:<package_name>/<package_name>.dart';

void main() {
  group('<ClassName>', () {
    test('can be instantiated', () {
      expect(<ClassName>(), isNotNull);
    });
  });
}
```

### Step 13: Initialize Package

```bash
# Get dependencies
dart pub get  # or: flutter pub get

# Run analyzer
dart analyze

# Run tests
dart test  # or: flutter test

# Verify package structure
dart pub publish --dry-run
```

## Package Families

### Interface Package Pattern

For core interface packages:

```yaml
name: <family>_interface
description: Core interfaces and contracts for <family> packages.

dependencies:
  meta: ^1.16.0
```

### Implementation Package Pattern

For implementation packages:

```yaml
name: <family>_<platform>
description: <Platform> implementation of <family>.

dependencies:
  <family>_interface:
    path: ../<family>_interface
```

### Foundation Package Pattern

For shared utilities:

```yaml
name: <family>_foundation
description: Shared utilities and helpers for <family> packages.

dependencies:
  flutter:
    sdk: flutter
```

## Common Patterns

### Platform-Specific Package

For packages with platform-specific code:

```
<package_name>/
├── lib/
│   ├── src/
│   │   ├── <package_name>_io.dart      # Mobile/Desktop
│   │   ├── <package_name>_web.dart     # Web
│   │   └── <package_name>_stub.dart    # Fallback
│   └── <package_name>.dart
```

Main export file with conditional imports:

```dart
library;

export 'src/<package_name>_stub.dart'
    if (dart.library.io) 'src/<package_name>_io.dart'
    if (dart.library.html) 'src/<package_name>_web.dart';
```

### Package with Code Generation

If using `build_runner`:

Add to `pubspec.yaml`:
```yaml
dependencies:
  freezed_annotation: ^3.0.0
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.15
  freezed: ^3.0.6
  json_serializable: ^6.9.5
```

Add `build.yaml`:
```yaml
targets:
  $default:
    builders:
      freezed:
        enabled: true
```

## Quick Bootstrap Script

For rapid package creation:

```bash
#!/bin/bash
# Usage: ./bootstrap_package.sh <package_name> <type>
# type: dart or flutter

PACKAGE_NAME=$1
TYPE=${2:-dart}

cd pkgs
mkdir -p "$PACKAGE_NAME"/{lib/src,test,example}
cd "$PACKAGE_NAME"

# Create files using templates above
# (Implementation would go here)

echo "Package $PACKAGE_NAME created!"
echo "Next steps:"
echo "1. Edit pubspec.yaml description"
echo "2. Implement lib/src/$PACKAGE_NAME.dart"
echo "3. Write tests in test/"
echo "4. Update README.md"
echo "5. Run: dart pub get && dart analyze && dart test"
```

## Checklist Template

Copy this when bootstrapping a package:

```
Package: <name>
Type: [ ] Dart Library  [ ] Flutter Package

Structure:
- [ ] Directory created in pkgs/
- [ ] lib/src/ directory
- [ ] test/ directory
- [ ] example/ directory (if needed)

Files:
- [ ] pubspec.yaml (with correct metadata)
- [ ] analysis_options.yaml
- [ ] LICENSE
- [ ] Makefile
- [ ] README.md
- [ ] CHANGELOG.md
- [ ] .gitignore
- [ ] lib/<package_name>.dart
- [ ] lib/src/<package_name>.dart
- [ ] test/<package_name>_test.dart

Validation:
- [ ] dart pub get succeeds
- [ ] dart analyze passes
- [ ] dart test passes
- [ ] dart pub publish --dry-run succeeds

Documentation:
- [ ] README has usage examples
- [ ] API documentation complete
- [ ] CHANGELOG has initial entry
```

## Post-Bootstrap Tasks

After creating the package:

1. **Implement core functionality**
2. **Write comprehensive tests**
3. **Add usage examples**
4. **Update README with real examples**
5. **Run full validation**
6. **Add to monorepo documentation**
7. **Consider adding to CI/CD**

## Common Dependencies

Frequently used dependencies in this monorepo:

**Core:**
- `meta` - Annotations
- `collection` - Collection utilities

**Serialization:**
- `freezed_annotation` + `freezed` - Immutable classes
- `json_annotation` + `json_serializable` - JSON serialization
- `from_json_to_json` - Custom serialization

**Testing:**
- `test` - Dart testing
- `flutter_test` - Flutter testing
- `mocktail` - Mocking

**Utilities:**
- `path` - Path manipulation
- `uuid` - UUID generation
- `crypto` - Cryptographic functions

**Linting:**
- `lints` - Dart lints
- `xsoulspace_lints` - Custom lints (always include)

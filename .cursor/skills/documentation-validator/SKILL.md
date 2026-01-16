---
name: documentation-validator
description: Validate and generate dartdoc documentation for packages, ensure API documentation completeness, and verify README quality. Use when documenting code, checking documentation coverage, generating API docs, or when user mentions documentation, dartdoc, or API reference.
---

# Documentation Generator & Validator

Ensure consistent, high-quality documentation across all packages.

## Quick Start

When validating documentation:

1. Check dartdoc completeness
2. Validate README structure
3. Generate API documentation
4. Verify examples exist

## Documentation Standards

### Dartdoc Requirements

All public APIs must have:
- Class-level documentation with `{@template}`
- Constructor documentation with `{@macro}`
- Parameter documentation
- Return value documentation
- Usage examples
- Related class references

### README Requirements

Every package must have:
- Clear description
- Features list
- Installation instructions
- Usage examples
- API reference link
- Contributing guidelines
- License information

## Validation Workflow

### Step 1: Check Dartdoc Completeness

```bash
cd pkgs/<package_name>

# Generate documentation
dart doc

# Check for warnings
dart doc 2>&1 | grep -i "warning\|error"
```

**Common issues:**
- Missing documentation on public APIs
- Broken references `[ClassName]`
- Invalid code examples
- Missing `{@template}` tags

### Step 2: Validate Public API Coverage

```bash
# Find public classes without documentation
grep -r "^class " lib/ | grep -v "lib/src/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  class=$(echo "$line" | grep -o "class [A-Za-z0-9_]*" | cut -d' ' -f2)
  
  # Check if class has documentation
  if ! grep -B 5 "class $class" "$file" | grep -q "///"; then
    echo "Missing docs: $file - $class"
  fi
done
```

### Step 3: Check README Completeness

Required sections:
- [ ] Package name and description
- [ ] Features list
- [ ] Installation instructions
- [ ] Usage examples
- [ ] API reference
- [ ] Contributing guidelines
- [ ] License

```bash
# Check README exists and has minimum content
if [ ! -f README.md ]; then
  echo "ERROR: README.md missing"
elif [ $(wc -l < README.md) -lt 20 ]; then
  echo "WARNING: README.md too short"
fi

# Check for required sections
for section in "Features" "Installation" "Usage" "License"; do
  if ! grep -qi "## $section" README.md; then
    echo "WARNING: Missing section: $section"
  fi
done
```

### Step 4: Validate Code Examples

```bash
# Extract code examples from dartdoc
grep -r "```dart" lib/ | wc -l

# Check if examples compile (manual review needed)
```

## Documentation Templates

### Class Documentation Template

```dart
/// {@template class_name}
/// Brief one-line description of the class.
///
/// More detailed description explaining:
/// - What the class does
/// - When to use it
/// - How it relates to other classes
///
/// Example usage:
/// ```dart
/// final instance = ClassName(
///   parameter: value,
/// );
/// instance.method();
/// ```
///
/// See also:
/// * [RelatedClass], which provides similar functionality
/// * [AnotherClass], used in conjunction with this class
///
/// @ai When using this class, ensure proper initialization
/// and consider error handling for edge cases.
/// {@endtemplate}
class ClassName {
  /// {@macro class_name}
  ///
  /// Creates a new instance of [ClassName].
  ///
  /// The [parameter] must not be null and should be...
  const ClassName({
    required this.parameter,
  });

  /// Brief description of the parameter.
  ///
  /// More details about what values are valid,
  /// what the parameter affects, etc.
  final String parameter;

  /// Brief description of what the method does.
  ///
  /// Detailed explanation of:
  /// - Method behavior
  /// - Parameters
  /// - Return value
  /// - Exceptions thrown
  ///
  /// Example:
  /// ```dart
  /// final result = instance.method(input);
  /// print(result); // Output: ...
  /// ```
  String method(String input) {
    // Implementation
    return '';
  }
}
```

### Interface Documentation Template

```dart
/// {@template interface_name}
/// Core interface for [feature] functionality.
///
/// Implementations of this interface provide [specific capability].
/// Use this interface to [describe use case].
///
/// Available implementations:
/// * [Implementation1] - for [platform/use case]
/// * [Implementation2] - for [platform/use case]
///
/// Example:
/// ```dart
/// final provider = Implementation1();
/// await provider.method();
/// ```
/// {@endtemplate}
abstract class InterfaceName {
  /// {@macro interface_name}
  const InterfaceName();

  /// Abstract method description.
  ///
  /// Implementations should [describe expected behavior].
  ///
  /// Returns [description of return value].
  /// Throws [ExceptionType] if [condition].
  Future<void> method();
}
```

### Extension Documentation Template

```dart
/// {@template extension_name}
/// Extension on [Type] providing [functionality].
///
/// Adds convenient methods for [use case].
/// {@endtemplate}
extension ExtensionName on Type {
  /// Brief description of extension method.
  ///
  /// Example:
  /// ```dart
  /// final value = instance.extensionMethod();
  /// ```
  ReturnType extensionMethod() {
    // Implementation
    return null;
  }
}
```

## README Template

```markdown
# Package Name

Brief description of what this package does (1-2 sentences).

## Features

- Feature 1: Description
- Feature 2: Description
- Feature 3: Description

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  package_name: ^0.1.0
```

Then run:

```bash
dart pub get
```

## Usage

### Basic Usage

```dart
import 'package:package_name/package_name.dart';

void main() {
  // Example code
  final instance = ClassName();
  instance.method();
}
```

### Advanced Usage

```dart
// More complex example
```

## API Reference

### Core Classes

#### ClassName

Brief description.

**Constructor:**
```dart
ClassName({required String param})
```

**Methods:**
- `method()` - Description

**Example:**
```dart
final instance = ClassName(param: 'value');
```

### Utilities

[Document utility functions/classes]

## Platform Support

- ✅ Android
- ✅ iOS
- ✅ Web
- ✅ macOS
- ✅ Linux
- ✅ Windows

## Examples

See the [example](example/) directory for complete examples:

- [Basic Example](example/basic_example.dart)
- [Advanced Example](example/advanced_example.dart)

## Additional Information

### Related Packages

- [related_package](link) - Description
- [another_package](link) - Description

### Resources

- [API Documentation](https://pub.dev/documentation/package_name/latest/)
- [GitHub Repository](https://github.com/xsoulspace/dart_flutter_packages)
- [Issue Tracker](https://github.com/xsoulspace/dart_flutter_packages/issues)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidelines.

## License

This package is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.
```

## Generating Documentation

### Generate API Documentation

```bash
cd pkgs/<package_name>

# Generate documentation
dart doc

# Output is in doc/api/
# Open in browser
open doc/api/index.html  # macOS
xdg-open doc/api/index.html  # Linux
```

### Generate for All Packages

```bash
#!/bin/bash
# generate_all_docs.sh

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  echo "Generating docs for $pkg..."
  
  cd "$dir"
  dart doc 2>&1 | grep -i "error\|warning" || echo "✓ $pkg: OK"
  cd ../..
done
```

### Host Documentation Locally

```bash
# Serve documentation
cd pkgs/<package_name>/doc/api
python3 -m http.server 8000

# Open http://localhost:8000 in browser
```

## Documentation Quality Checks

### Check 1: Public API Coverage

```bash
# Count public classes
public_classes=$(grep -r "^class " lib/ | grep -v "lib/src/" | wc -l)

# Count documented classes
documented=$(grep -r "^class " lib/ | grep -v "lib/src/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  class=$(echo "$line" | grep -o "class [A-Za-z0-9_]*" | cut -d' ' -f2)
  grep -B 5 "class $class" "$file" | grep -q "///" && echo "1"
done | wc -l)

coverage=$((documented * 100 / public_classes))
echo "Documentation coverage: $coverage%"
```

### Check 2: Example Completeness

```bash
# Check if examples exist
if [ ! -d example/ ]; then
  echo "WARNING: No example directory"
elif [ $(find example/ -name "*.dart" | wc -l) -eq 0 ]; then
  echo "WARNING: No example files"
fi
```

### Check 3: README Quality

```bash
# Check README length
lines=$(wc -l < README.md)
if [ $lines -lt 50 ]; then
  echo "WARNING: README too short ($lines lines)"
fi

# Check for code examples
examples=$(grep -c "```dart" README.md)
if [ $examples -lt 2 ]; then
  echo "WARNING: Not enough code examples ($examples found)"
fi
```

## Common Documentation Issues

### Issue: Missing {@template} Tags

**Problem:** Class lacks reusable documentation template

**Solution:**
```dart
/// {@template class_name}
/// Class description
/// {@endtemplate}
class ClassName {
  /// {@macro class_name}
  const ClassName();
}
```

### Issue: Broken References

**Problem:** `[ClassName]` references don't resolve

**Solution:**
- Ensure class is imported or in same file
- Use full path: `[package:name/file.dart]`
- Check spelling and capitalization

### Issue: Invalid Code Examples

**Problem:** Code examples don't compile

**Solution:**
- Test examples in actual code
- Use valid imports
- Ensure examples are complete

### Issue: Missing Parameter Documentation

**Problem:** Constructor parameters lack documentation

**Solution:**
```dart
/// Creates a new instance.
///
/// The [param1] specifies...
/// The [param2] controls...
const ClassName({
  required this.param1,
  this.param2,
});
```

## Automated Documentation Tools

### dartdoc_json

Extract documentation as JSON:

```bash
dart doc --output json
```

### Documentation Linter

Check documentation quality:

```bash
# Add to analysis_options.yaml
linter:
  rules:
    - public_member_api_docs
    - package_api_docs
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Documentation

on: [push, pull_request]

jobs:
  docs:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - uses: dart-lang/setup-dart@v1
      
      - name: Generate documentation
        run: |
          for dir in pkgs/*/; do
            cd "$dir"
            dart doc || echo "::warning::Docs failed for $(basename $dir)"
            cd ../..
          done
      
      - name: Check documentation coverage
        run: |
          # Run coverage check script
```

## Documentation Checklist

Copy this for each package:

```
Package: <name>

Dartdoc:
- [ ] All public classes documented
- [ ] All public methods documented
- [ ] {@template} tags used
- [ ] {@macro} tags used
- [ ] Code examples included
- [ ] Related classes referenced
- [ ] No broken references
- [ ] No dartdoc warnings

README:
- [ ] Clear description
- [ ] Features list
- [ ] Installation instructions
- [ ] Basic usage example
- [ ] Advanced usage example
- [ ] API reference section
- [ ] Platform support listed
- [ ] Contributing guidelines
- [ ] License information

Examples:
- [ ] Example directory exists
- [ ] At least one example file
- [ ] Examples are runnable
- [ ] Examples are documented

Quality:
- [ ] dart doc generates without errors
- [ ] README is comprehensive (50+ lines)
- [ ] At least 2 code examples in README
- [ ] All public APIs have examples
```

## Quick Reference

```bash
# Generate documentation
dart doc

# Check for warnings
dart doc 2>&1 | grep -i "warning"

# Find undocumented classes
grep -r "^class " lib/ | grep -v "lib/src/" | grep -v "///"

# Count documentation coverage
# (See "Documentation Quality Checks" section)

# Validate README
grep -c "##" README.md  # Count sections
grep -c "```dart" README.md  # Count examples
```

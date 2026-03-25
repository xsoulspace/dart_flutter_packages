---
name: cross-package-test-runner
description: Run tests across multiple packages intelligently, execute tests in dependency order, and generate coverage reports. Use when running tests, checking test coverage, validating changes, or when user mentions testing, test suite, or coverage.
---

# Cross-Package Test Runner

Run tests across multiple packages efficiently with dependency-aware execution.

## Quick Start

When running tests:

1. Identify affected packages
2. Determine test execution order
3. Run tests (parallel or sequential)
4. Collect and report results

## Test Execution Strategies

### Strategy 1: All Packages

Run tests for all packages in the monorepo:

```bash
# Simple approach - run sequentially
for dir in pkgs/*/; do
  echo "Testing $(basename "$dir")..."
  cd "$dir"
  dart test || echo "Tests failed for $(basename "$dir")"
  cd ../..
done
```

### Strategy 2: Changed Packages Only

Run tests only for packages with changes:

```bash
# Get changed packages since last commit
changed_files=$(git diff --name-only HEAD~1)
changed_packages=$(echo "$changed_files" | grep "^pkgs/" | cut -d/ -f2 | sort -u)

for pkg in $changed_packages; do
  echo "Testing $pkg (has changes)..."
  cd "pkgs/$pkg"
  dart test
  cd ../..
done
```

### Strategy 3: Affected Packages

Run tests for changed packages AND their dependents:

```bash
# 1. Find changed packages
# 2. Find packages that depend on changed packages
# 3. Run tests for all affected packages
```

### Strategy 4: Dependency Order

Run tests in dependency order (dependencies first):

```bash
# Define order based on dependencies
packages=(
  "xsoulspace_foundation"
  "universal_storage_interface"
  "universal_storage_filesystem"
  "universal_storage_sync"
)

for pkg in "${packages[@]}"; do
  echo "Testing $pkg..."
  cd "pkgs/$pkg"
  dart test
  cd ../..
done
```

## Test Commands

### Dart Package Tests

```bash
cd pkgs/<package_name>

# Run all tests
dart test

# Run specific test file
dart test test/<file>_test.dart

# Run with coverage
dart test --coverage=coverage

# Format coverage to lcov
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib
```

### Flutter Package Tests

```bash
cd pkgs/<package_name>

# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Coverage is automatically in coverage/lcov.info
```

### Test with Specific Platforms

```bash
# Test on Chrome (web)
flutter test --platform chrome

# Test on specific device
flutter test -d <device-id>
```

## Parallel Test Execution

Run tests in parallel for faster execution:

```bash
# Using GNU parallel (if installed)
find pkgs -name pubspec.yaml -not -path "*/example/*" \
  | xargs -n1 dirname \
  | parallel -j4 'cd {} && dart test'

# Using xargs (more portable)
find pkgs -name pubspec.yaml -not -path "*/example/*" \
  | xargs -n1 dirname \
  | xargs -P4 -I{} sh -c 'cd {} && dart test'
```

## Test Result Collection

### Collect Test Results

```bash
#!/bin/bash
# collect_test_results.sh

results_file="test_results.txt"
> "$results_file"  # Clear file

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  echo "Testing $pkg..." | tee -a "$results_file"
  
  cd "$dir"
  if dart test 2>&1 | tee -a "../../$results_file"; then
    echo "✓ $pkg: PASSED" >> "../../$results_file"
  else
    echo "✗ $pkg: FAILED" >> "../../$results_file"
  fi
  cd ../..
  echo "" >> "$results_file"
done

echo "Results saved to $results_file"
```

### Generate Test Summary

```bash
# Count passing/failing packages
echo "Test Summary:"
echo "Passed: $(grep -c "PASSED" test_results.txt)"
echo "Failed: $(grep -c "FAILED" test_results.txt)"
echo ""
echo "Failed packages:"
grep "FAILED" test_results.txt | cut -d: -f1 | sed 's/✗ //'
```

## Coverage Reports

### Generate Coverage for Single Package

```bash
cd pkgs/<package_name>

# Dart package
dart test --coverage=coverage
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib

# Flutter package
flutter test --coverage
```

### Generate Combined Coverage

```bash
#!/bin/bash
# generate_coverage.sh

# Create coverage directory
mkdir -p coverage_combined

# Collect coverage from all packages
for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  echo "Generating coverage for $pkg..."
  
  cd "$dir"
  
  # Check if it's Flutter or Dart package
  if grep -q "flutter:" pubspec.yaml; then
    flutter test --coverage 2>/dev/null || true
  else
    dart test --coverage=coverage 2>/dev/null || true
    dart pub global run coverage:format_coverage \
      --lcov \
      --in=coverage \
      --out=coverage/lcov.info \
      --report-on=lib 2>/dev/null || true
  fi
  
  # Copy coverage file
  if [ -f coverage/lcov.info ]; then
    cp coverage/lcov.info "../../coverage_combined/$pkg.lcov"
  fi
  
  cd ../..
done

# Merge coverage files
cat coverage_combined/*.lcov > coverage_combined/lcov.info

echo "Combined coverage saved to coverage_combined/lcov.info"
```

### View Coverage Report

```bash
# Install lcov (if not installed)
# macOS: brew install lcov
# Linux: apt-get install lcov

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html

# Open in browser
open coverage/html/index.html  # macOS
xdg-open coverage/html/index.html  # Linux
```

## Smart Test Selection

### Test Only Affected Packages

```bash
#!/bin/bash
# test_affected.sh

# Get changed files
changed_files=$(git diff --name-only main...HEAD)

# Extract package names
affected_packages=$(echo "$changed_files" \
  | grep "^pkgs/" \
  | cut -d/ -f2 \
  | sort -u)

if [ -z "$affected_packages" ]; then
  echo "No packages affected"
  exit 0
fi

echo "Affected packages:"
echo "$affected_packages"
echo ""

# Test each affected package
for pkg in $affected_packages; do
  echo "Testing $pkg..."
  cd "pkgs/$pkg"
  
  if [ -f pubspec.yaml ]; then
    if grep -q "flutter:" pubspec.yaml; then
      flutter test
    else
      dart test
    fi
  fi
  
  cd ../..
done
```

### Test Dependents

```bash
#!/bin/bash
# test_dependents.sh <package_name>

package_name=$1

# Find packages that depend on this package
dependents=$(grep -r "path:.*$package_name" pkgs/*/pubspec.yaml \
  | cut -d: -f1 \
  | xargs dirname \
  | xargs basename -a \
  | sort -u)

echo "Testing $package_name and its dependents..."
echo "Dependents: $dependents"
echo ""

# Test the package itself
echo "Testing $package_name..."
cd "pkgs/$package_name"
dart test
cd ../..

# Test dependents
for dep in $dependents; do
  echo "Testing dependent: $dep..."
  cd "pkgs/$dep"
  dart test
  cd ../..
done
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test Packages

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      
      - name: Install dependencies
        run: |
          for dir in pkgs/*/; do
            cd "$dir"
            dart pub get
            cd ../..
          done
      
      - name: Run tests
        run: |
          for dir in pkgs/*/; do
            pkg=$(basename "$dir")
            echo "Testing $pkg..."
            cd "$dir"
            dart test || echo "::error::Tests failed for $pkg"
            cd ../..
          done
      
      - name: Generate coverage
        run: |
          # Coverage generation script here
```

## Test Filtering

### Run Specific Test Groups

```bash
# Run tests matching a name pattern
dart test --name "ClassName"

# Run tests with specific tags
dart test --tags "integration"

# Exclude tests with specific tags
dart test --exclude-tags "slow"
```

### Run Tests by File Pattern

```bash
# Run all unit tests
dart test test/*_test.dart

# Run integration tests
dart test test/integration/*_test.dart

# Run specific feature tests
dart test test/**/feature_*_test.dart
```

## Performance Optimization

### Skip Slow Tests in Development

```dart
// In test file
@Tags(['slow'])
test('expensive operation', () {
  // Long-running test
});
```

```bash
# Skip slow tests during development
dart test --exclude-tags slow

# Run all tests (including slow) in CI
dart test
```

### Cache Dependencies

```bash
# Cache pub dependencies in CI
# GitHub Actions example:
# - uses: actions/cache@v3
#   with:
#     path: |
#       ~/.pub-cache
#     key: ${{ runner.os }}-pub-${{ hashFiles('**/pubspec.yaml') }}
```

## Test Quality Metrics

### Calculate Test Coverage

```bash
# After generating coverage
total_lines=$(grep -c "^DA:" coverage/lcov.info)
covered_lines=$(grep "^DA:" coverage/lcov.info | grep -c ",0$")
coverage=$((100 - (covered_lines * 100 / total_lines)))

echo "Test coverage: $coverage%"
```

### Count Tests

```bash
# Count test files
find pkgs -name "*_test.dart" | wc -l

# Count test cases (approximate)
grep -r "test(" pkgs/*/test/ | wc -l
```

## Common Test Patterns

### Test Package Structure

```
test/
├── unit/
│   ├── models_test.dart
│   └── utils_test.dart
├── integration/
│   └── workflow_test.dart
└── <package_name>_test.dart
```

### Test Naming Convention

```dart
void main() {
  group('ClassName', () {
    test('methodName returns expected value', () {
      // Test implementation
    });
    
    test('methodName throws when invalid input', () {
      // Test implementation
    });
  });
}
```

## Troubleshooting

### Issue: Tests Fail in CI but Pass Locally

**Solution:**
- Check for timing issues (add timeouts)
- Verify environment variables
- Check file path differences (Windows vs Unix)
- Ensure deterministic test data

### Issue: Slow Test Execution

**Solution:**
- Run tests in parallel
- Use test tags to skip slow tests
- Mock external dependencies
- Optimize test setup/teardown

### Issue: Flaky Tests

**Solution:**
- Add proper async/await handling
- Increase timeouts for async operations
- Remove dependencies on external services
- Use mocks for non-deterministic behavior

## Checklist Template

Copy this for test runs:

```
Test Run: <date>
Scope: [ ] All packages  [ ] Changed only  [ ] Specific packages

Execution:
- [ ] Dependencies installed
- [ ] Tests executed
- [ ] Results collected
- [ ] Coverage generated

Results:
- Packages tested: <count>
- Passed: <count>
- Failed: <count>
- Coverage: <percentage>%

Failed packages:
- <list>

Next steps:
- [ ] Fix failing tests
- [ ] Improve coverage
- [ ] Update documentation
```

## Quick Reference

```bash
# Test single package
cd pkgs/<package> && dart test

# Test all packages
for d in pkgs/*/; do cd "$d" && dart test && cd ../..; done

# Test with coverage
flutter test --coverage

# Test changed packages
git diff --name-only | grep "^pkgs/" | cut -d/ -f2 | sort -u

# Parallel test execution
find pkgs -name pubspec.yaml | xargs -n1 dirname | xargs -P4 -I{} sh -c 'cd {} && dart test'
```

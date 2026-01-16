---
name: makefile-orchestrator
description: Execute and manage Makefile commands across packages, standardize build targets, and orchestrate multi-package operations. Use when running make commands, managing build scripts, or when user mentions Makefile, make targets, or build automation.
---

# Makefile Command Orchestrator

Standardize and execute Makefile commands across all packages in the monorepo.

## Quick Start

When working with Makefiles:

1. List available targets
2. Execute commands across packages
3. Validate Makefile consistency
4. Add new standard targets

## Standard Makefile Targets

### Publishing Targets

```makefile
publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish
```

**Usage:**
```bash
cd pkgs/<package>
make publish-dry  # Validate before publishing
make publish      # Publish to pub.dev
```

### Code Generation Targets

```makefile
gen-rewrite:
	dart pub run build_runner build --delete-conflicting-outputs

gen:
	dart pub run build_runner build
```

**Usage:**
```bash
make gen          # Generate code (incremental)
make gen-rewrite  # Generate code (clean rebuild)
```

### Testing Targets (Optional)

```makefile
test:
	dart test

test-coverage:
	dart test --coverage=coverage
	dart pub global run coverage:format_coverage \
		--lcov \
		--in=coverage \
		--out=coverage/lcov.info \
		--report-on=lib
```

### Cleaning Targets (Optional)

```makefile
clean:
	rm -rf .dart_tool build coverage

clean-all: clean
	rm -rf pubspec.lock
```

## Executing Commands Across Packages

### Run Single Command

```bash
# Run in one package
cd pkgs/<package>
make <target>
```

### Run Across All Packages

```bash
# Sequential execution
for dir in pkgs/*/; do
  echo "Running make <target> in $(basename "$dir")..."
  cd "$dir"
  if [ -f Makefile ]; then
    make <target>
  fi
  cd ../..
done
```

### Run in Specific Packages

```bash
# Define package list
packages=(
  "universal_storage_interface"
  "universal_storage_filesystem"
  "universal_storage_sync"
)

for pkg in "${packages[@]}"; do
  echo "Running make <target> in $pkg..."
  cd "pkgs/$pkg"
  make <target>
  cd ../..
done
```

## Common Make Operations

### Operation 1: Publish All Packages

```bash
#!/bin/bash
# publish_all.sh

# Packages in dependency order
packages=(
  "xsoulspace_foundation"
  "xsoulspace_lints"
  "universal_storage_interface"
  "universal_storage_filesystem"
  "universal_storage_db"
  "universal_storage_sync"
)

for pkg in "${packages[@]}"; do
  echo "=========================================="
  echo "Publishing: $pkg"
  echo "=========================================="
  
  cd "pkgs/$pkg"
  
  # Dry run first
  echo "Running dry-run..."
  make publish-dry
  
  # Ask for confirmation
  read -p "Proceed with publishing $pkg? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    make publish
  else
    echo "Skipped $pkg"
  fi
  
  cd ../..
done
```

### Operation 2: Generate Code for All Packages

```bash
#!/bin/bash
# generate_all.sh

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  
  cd "$dir"
  
  # Check if package uses build_runner
  if grep -q "build_runner" pubspec.yaml; then
    echo "Generating code for $pkg..."
    make gen-rewrite
  else
    echo "Skipping $pkg (no build_runner)"
  fi
  
  cd ../..
done
```

### Operation 3: Run Tests with Make

```bash
#!/bin/bash
# test_all.sh

failed_packages=()

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  
  cd "$dir"
  
  if [ -f Makefile ] && grep -q "^test:" Makefile; then
    echo "Testing $pkg with make..."
    if ! make test; then
      failed_packages+=("$pkg")
    fi
  else
    echo "Testing $pkg with dart test..."
    if ! dart test; then
      failed_packages+=("$pkg")
    fi
  fi
  
  cd ../..
done

if [ ${#failed_packages[@]} -gt 0 ]; then
  echo ""
  echo "Failed packages:"
  printf '%s\n' "${failed_packages[@]}"
  exit 1
fi
```

## Makefile Validation

### Check Makefile Exists

```bash
# List packages without Makefile
for dir in pkgs/*/; do
  if [ ! -f "$dir/Makefile" ]; then
    echo "Missing Makefile: $(basename "$dir")"
  fi
done
```

### Validate Standard Targets

```bash
#!/bin/bash
# validate_makefiles.sh

required_targets=("publish-dry" "publish")

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  
  if [ ! -f "$dir/Makefile" ]; then
    echo "❌ $pkg: No Makefile"
    continue
  fi
  
  missing_targets=()
  for target in "${required_targets[@]}"; do
    if ! grep -q "^$target:" "$dir/Makefile"; then
      missing_targets+=("$target")
    fi
  done
  
  if [ ${#missing_targets[@]} -gt 0 ]; then
    echo "⚠️  $pkg: Missing targets: ${missing_targets[*]}"
  else
    echo "✅ $pkg: All required targets present"
  fi
done
```

### Check Makefile Consistency

```bash
# Compare Makefiles across packages
for dir in pkgs/*/; do
  echo "=== $(basename "$dir") ==="
  grep "^[a-z-]*:" "$dir/Makefile" 2>/dev/null | cut -d: -f1
  echo ""
done
```

## Adding Standard Targets

### Add Target to Single Package

```bash
cd pkgs/<package>

# Add new target to Makefile
cat >> Makefile << 'EOF'

test:
	dart test

test-coverage:
	dart test --coverage=coverage
EOF
```

### Add Target to All Packages

```bash
#!/bin/bash
# add_test_target.sh

target_content='
test:
	dart test

test-coverage:
	dart test --coverage=coverage
'

for dir in pkgs/*/; do
  makefile="$dir/Makefile"
  
  if [ -f "$makefile" ]; then
    # Check if target already exists
    if ! grep -q "^test:" "$makefile"; then
      echo "Adding test target to $(basename "$dir")..."
      echo "$target_content" >> "$makefile"
    else
      echo "Target already exists in $(basename "$dir")"
    fi
  fi
done
```

## Flutter vs Dart Packages

### Detect Package Type

```bash
#!/bin/bash
# detect_package_type.sh

for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  
  if grep -q "flutter:" "$dir/pubspec.yaml"; then
    echo "$pkg: Flutter package"
  else
    echo "$pkg: Dart package"
  fi
done
```

### Generate Appropriate Makefile

**For Dart packages:**
```makefile
.PHONY: publish-dry publish gen gen-rewrite test clean

publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish

gen-rewrite:
	dart pub run build_runner build --delete-conflicting-outputs

gen:
	dart pub run build_runner build

test:
	dart test

clean:
	rm -rf .dart_tool build coverage
```

**For Flutter packages:**
```makefile
.PHONY: publish-dry publish gen gen-rewrite test clean

publish-dry:
	flutter pub publish --dry-run

publish:
	flutter pub publish

gen-rewrite:
	flutter pub run build_runner build --delete-conflicting-outputs

gen:
	flutter pub run build_runner build

test:
	flutter test

clean:
	flutter clean
	rm -rf coverage
```

## Advanced Makefile Patterns

### Pattern 1: Conditional Targets

```makefile
# Check if build_runner is available
gen:
	@if grep -q "build_runner" pubspec.yaml; then \
		dart pub run build_runner build; \
	else \
		echo "build_runner not configured"; \
	fi
```

### Pattern 2: Dependency Targets

```makefile
# Target depends on another target
build: gen
	dart compile exe bin/main.dart

publish: test
	dart pub publish
```

### Pattern 3: Variables

```makefile
PACKAGE_NAME := $(shell grep "^name:" pubspec.yaml | cut -d' ' -f2)
VERSION := $(shell grep "^version:" pubspec.yaml | cut -d' ' -f2)

info:
	@echo "Package: $(PACKAGE_NAME)"
	@echo "Version: $(VERSION)"
```

### Pattern 4: Help Target

```makefile
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  publish-dry    - Dry run publish"
	@echo "  publish        - Publish to pub.dev"
	@echo "  gen            - Generate code"
	@echo "  gen-rewrite    - Generate code (clean)"
	@echo "  test           - Run tests"
	@echo "  clean          - Clean build artifacts"
```

## Makefile Templates

### Minimal Makefile

```makefile
.PHONY: publish-dry publish

publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish
```

### Standard Makefile

```makefile
.PHONY: publish-dry publish gen gen-rewrite test clean help

publish-dry:
	dart pub publish --dry-run

publish:
	dart pub publish

gen-rewrite:
	dart pub run build_runner build --delete-conflicting-outputs

gen:
	dart pub run build_runner build

test:
	dart test

clean:
	rm -rf .dart_tool build coverage

help:
	@echo "Available targets:"
	@echo "  publish-dry    - Validate package before publishing"
	@echo "  publish        - Publish package to pub.dev"
	@echo "  gen            - Generate code (incremental)"
	@echo "  gen-rewrite    - Generate code (clean rebuild)"
	@echo "  test           - Run all tests"
	@echo "  clean          - Remove build artifacts"
```

### Comprehensive Makefile

```makefile
.PHONY: all publish-dry publish gen gen-rewrite test test-coverage analyze format clean help

PACKAGE_NAME := $(shell grep "^name:" pubspec.yaml | cut -d' ' -f2)

all: format analyze test

publish-dry:
	dart pub publish --dry-run

publish: test
	dart pub publish

gen-rewrite:
	dart pub run build_runner build --delete-conflicting-outputs

gen:
	dart pub run build_runner build

test:
	dart test

test-coverage:
	dart test --coverage=coverage
	dart pub global run coverage:format_coverage \
		--lcov \
		--in=coverage \
		--out=coverage/lcov.info \
		--report-on=lib

analyze:
	dart analyze

format:
	dart format lib test

clean:
	rm -rf .dart_tool build coverage

help:
	@echo "$(PACKAGE_NAME) - Available targets:"
	@echo ""
	@echo "Publishing:"
	@echo "  publish-dry    - Validate package before publishing"
	@echo "  publish        - Publish package to pub.dev (runs tests first)"
	@echo ""
	@echo "Code Generation:"
	@echo "  gen            - Generate code (incremental)"
	@echo "  gen-rewrite    - Generate code (clean rebuild)"
	@echo ""
	@echo "Testing:"
	@echo "  test           - Run all tests"
	@echo "  test-coverage  - Run tests with coverage report"
	@echo ""
	@echo "Quality:"
	@echo "  analyze        - Run Dart analyzer"
	@echo "  format         - Format Dart code"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean          - Remove build artifacts"
	@echo "  all            - Format, analyze, and test"
```

## Orchestration Scripts

### Master Makefile (Root Level)

Create a root-level Makefile to orchestrate all packages:

```makefile
# Makefile (root level)
.PHONY: test-all publish-all gen-all clean-all list-packages help

PACKAGES := $(shell find pkgs -maxdepth 1 -type d -not -path pkgs | xargs -n1 basename)

test-all:
	@for pkg in $(PACKAGES); do \
		echo "Testing $$pkg..."; \
		cd pkgs/$$pkg && make test || exit 1; \
		cd ../..; \
	done

publish-all:
	@echo "This will publish all packages. Are you sure? (y/n)"
	@read -r confirm; \
	if [ "$$confirm" = "y" ]; then \
		for pkg in $(PACKAGES); do \
			echo "Publishing $$pkg..."; \
			cd pkgs/$$pkg && make publish; \
			cd ../..; \
		done; \
	fi

gen-all:
	@for pkg in $(PACKAGES); do \
		if grep -q "build_runner" pkgs/$$pkg/pubspec.yaml 2>/dev/null; then \
			echo "Generating code for $$pkg..."; \
			cd pkgs/$$pkg && make gen-rewrite; \
			cd ../..; \
		fi; \
	done

clean-all:
	@for pkg in $(PACKAGES); do \
		echo "Cleaning $$pkg..."; \
		cd pkgs/$$pkg && make clean 2>/dev/null || true; \
		cd ../..; \
	done

list-packages:
	@echo "Packages in monorepo:"
	@for pkg in $(PACKAGES); do \
		echo "  - $$pkg"; \
	done

help:
	@echo "Monorepo Makefile Commands:"
	@echo ""
	@echo "  test-all       - Run tests for all packages"
	@echo "  publish-all    - Publish all packages (with confirmation)"
	@echo "  gen-all        - Generate code for all packages"
	@echo "  clean-all      - Clean all packages"
	@echo "  list-packages  - List all packages"
```

## Troubleshooting

### Issue: Make Target Not Found

**Symptom:** `make: *** No rule to make target 'xyz'`

**Solution:**
```bash
# List available targets
grep "^[a-z-]*:" Makefile

# Or use help target
make help
```

### Issue: Command Fails Silently

**Symptom:** Make doesn't report errors

**Solution:** Add error handling
```makefile
test:
	dart test || exit 1
```

### Issue: Inconsistent Makefiles

**Symptom:** Different packages have different targets

**Solution:** Run validation script
```bash
./validate_makefiles.sh
```

## Best Practices

1. **Use .PHONY** for targets that don't create files
2. **Add help target** for documentation
3. **Use variables** for repeated values
4. **Add error handling** with `|| exit 1`
5. **Keep targets simple** - one action per target
6. **Use consistent naming** across packages
7. **Document targets** in help or comments

## Checklist Template

Copy this when working with Makefiles:

```
Package: <name>

Validation:
- [ ] Makefile exists
- [ ] publish-dry target present
- [ ] publish target present
- [ ] gen targets present (if needed)
- [ ] test targets present (if needed)
- [ ] help target present
- [ ] .PHONY declarations present

Testing:
- [ ] make publish-dry works
- [ ] make gen works (if applicable)
- [ ] make test works (if applicable)
- [ ] All targets execute successfully

Consistency:
- [ ] Matches standard template
- [ ] Uses correct command (dart vs flutter)
- [ ] Follows naming conventions
```

## Quick Reference

```bash
# List all Makefiles
find pkgs -name Makefile

# List targets in a Makefile
grep "^[a-z-]*:" pkgs/<package>/Makefile

# Run target in one package
cd pkgs/<package> && make <target>

# Run target in all packages
for d in pkgs/*/; do cd "$d" && make <target> && cd ../..; done

# Validate Makefiles
./validate_makefiles.sh

# Add target to all packages
./add_target_to_all.sh
```

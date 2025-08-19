.PHONY: help info format analyze test clean publish-dry publish

DART := dart
PUB := $(DART) pub
TEST_CMD := $(DART) test
ANALYZE_CMD := $(DART) analyze
FORMAT_CMD := $(DART) format .

help:
	@echo "Available targets: help info format analyze test clean publish-dry publish"

info:
	@echo "Package: $$(sed -n 's/^name: //p' pubspec.yaml | head -n1)"
	@echo "Version: $$(sed -n 's/^version: //p' pubspec.yaml | head -n1)"

format:
	@echo "Running formatter..."
	@$(FORMAT_CMD)

analyze:
	@echo "Running analyzer..."
	@$(ANALYZE_CMD)

test:
	@echo "Running tests..."
	@$(TEST_CMD)

clean:
	@echo "Cleaning build/artifacts..."
	@rm -rf .dart_tool .packages build

publish-dry:
	@echo "Dry-run publish (no changes will be made)"
	@$(PUB) publish --dry-run

publish:
	@echo "Publishing package to pub.dev"
	@$(PUB) publish
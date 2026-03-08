# Unit tests (no model required).
test-unit:
	flutter test

# Integration test on macOS (skip when no model is OK).
test-integration:
	cd example && flutter test integration_test -d macos

# Run unit tests; on macOS also run example integration test.
test: test-unit
	@if [ "$$(uname)" = "Darwin" ]; then $(MAKE) test-integration || true; fi

.PHONY: test test-unit test-integration

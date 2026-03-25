# Unit tests (no native engine).
test-unit:
	flutter test

# Integration test on macOS (real plugin; engine unavailable is OK).
test-integration:
	cd example && flutter test integration_test -d macos

# Run unit tests; on macOS also run integration test (failure does not fail test target).
test: test-unit
	@if [ "$$(uname)" = "Darwin" ]; then -$(MAKE) test-integration || true; fi

.PHONY: test test-unit test-integration

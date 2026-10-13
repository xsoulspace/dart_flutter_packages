# Native hook dependency recovery — 2026-10-11

The Flutter consumer repeatedly reported `File modified during build. Build must be rerun.` The native hook recorded two relative Swift dependency URIs. Consumers resolved them from their own working directory; missing inputs acquired sentinel hash `1` and a current timestamp. The actual Swift inputs had not changed.

The production correction resolves both declarations through `input.packageRoot`. Swift input bytes, compiler flags, compiler working directory, asset identity and dynamic loading mode remain unchanged. No inference transport or harness policy was moved into this package.

## Reproduction and independent control

[Actual SDK reproduction](sdk-repro.log) uses the installed hooks runner from a different consumer directory. Relative paths reproduce the modified-input diagnosis; package-root absolute paths produce stable content hashes. [Reproduction source](sdk-repro.dart.fixture).

The independent regression executes the actual hook and Swift compiler against a copied package with byte-identical inputs and a different consumer directory. It failed before the production correction on `dependency.isAbsolute`, then passed unchanged after it. [Red](native-red.log), [green](native-green.log), [final replay](native-final-green.log). It checks both dependency paths, emitted native asset identity/loading mode and unchanged input SHA256 values. No model session is exercised.

## Validation and limits

The new regression's [focused analyzer](focused-test-analyzer.log) is clean. The owning package [test lane](provider-tests.log) passes all 18 tests without the build warning. Provider FFI unit tests use fakes; the new hook regression performs real Swift compilation.

The complete owning `just check xsoulspace_inference_apple_foundation` gate is **not clean**: its [analyzer](provider-analyzer-existing-infos.log) reports 56 existing informational diagnostics outside the new test. The initial analyzer had also caught test-only lint issues, which were corrected without changing assertions; [initial analyzer](owning-analyzer-before-test-lints.log). No fatal-info override was used and unrelated diagnostic cleanup is outside this recovery correction.

These results qualify dependency declaration and native build behavior on this machine. They do not establish a live Foundation Models session, clean-machine packaging, or loaded-daemon revision acceptance.

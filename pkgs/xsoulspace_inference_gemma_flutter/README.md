# xsoulspace_inference_gemma_flutter

Flutter Gemma-backed implementation of [xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core) for desktop/mobile. Uses [flutter_gemma](https://pub.dev/packages/flutter_gemma) (on-device Gemma via LiteRT/MediaPipe).

Implements both `InferenceClient` and `ProvisionableInferenceClient` — purpose-driven model provisioning with constraint checks, progress streaming, and cancellation.

## Install

Add to your app `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_inference_gemma_flutter:
    path: ../xsoulspace_inference_gemma_flutter # or version from pub
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

Then run `flutter pub get`.

## Quick start — production path

One enum, one await, one progress stream. Everything else stays behind the
harness.

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_gemma_flutter/xsoulspace_inference_gemma_flutter.dart';

final client = GemmaFlutterInferenceClient();

// Show provisioning UI while downloading (Wi-Fi policy, consent, size caps
// are enforced by constraints — defaults are conservative).
final sub = client.provisionProgress.listen((p) => print('${p.phase} ${p.percent}%'));

final ready = await client.ensureReady(
  const ModelPurpose('structured_tool_use'),
  constraints: ProvisionConstraints(
    maxDownloadBytes: 3 * 1024 * 1024 * 1024, // 3 GB cap
    requireUserConsent: true,
    userConsentGranted: userAcceptedDialog,
    isNetworkAllowed: () => isWifiOrEthernet(),
  ),
);
if (!ready.success) {
  // codes: user_consent_required | network_not_allowed | model_too_large |
  //        model_not_found | provision_failed
}

// Register in the harness as usual:
// ModelRouter(inferenceClientsBuilders: {const GemmaModelName(): () => client})
```

## Purposes and catalog

`GemmaPurpose` maps intents to curated catalog entries; `bestFor` picks the
smallest entry serving the purpose:

| Purpose             | Default entry                        | Size        | Min RAM |
| ------------------- | ------------------------------------ | ----------- | ------- |
| `structuredToolUse` | Gemma 3n E2B-it (int4 .task)         | ~2.3 GB     | 4 GB    |
| `chatNarrative`     | E2B (falls through to E4B if capped) | ~2.3 GB     | 4 GB    |
| `summarization`     | E2B / E4B                            | ~2.3–4.4 GB | 4–6 GB  |

Apps can ship their own catalog: `GemmaModelSetup(catalog: myEntries)`.

## Supported tasks

- `InferenceTask.text` — plain completion; raw output returned unmodified.
- `InferenceTask.implicitlyStructuredText` — JSON via prompt engineering with
  schema validation and **one automatic repair attempt** (the validation error
  is fed back to the model once).
- `nativelyStructuredText`, STT, TTS — not supported (no constrained decoding
  in MediaPipe).

## Failure behavior

All failures return `InferenceResult.fail` with a `code`:

| Code                                            | Meaning                                                       |
| ----------------------------------------------- | ------------------------------------------------------------- |
| `task_unsupported`                              | Requested task not in `supportedTasks`.                       |
| `request_prompt_empty` / `request_schema_empty` | Core request validation.                                      |
| `engine_unavailable`                            | No active model or inference error. Call `ensureReady` first. |
| `output_empty`                                  | Model produced no output.                                     |
| `json_parse_failed`                             | Structured output was not valid JSON.                         |
| `schema_validation_failed`                      | Output failed schema validation after repair attempt.         |
| `user_consent_required`                         | Download blocked until consent granted.                       |
| `network_not_allowed`                           | Network policy rejected the download.                         |
| `model_too_large`                               | Entry exceeds `maxDownloadBytes`.                             |
| `model_not_found`                               | No catalog entry serves the requested purpose.                |
| `provision_failed` / `model_install_failed`     | Download/install error.                                       |

## Advanced: explicit installs

```dart
final setup = GemmaModelSetup();
await setup.installFromUrl(url: myUrl, modelType: ModelType.gemmaIt);
await setup.installFromFile(path: filePath, modelType: ModelType.gemmaIt);
setup.cancel(); // cancels an in-flight download
await setup.getStatus();
```

## Example app

The `example/` app provides availability check, consent-based install via
`ensureReady`, and a single structured inference run.

Run: `cd example && flutter run -d macos`.

## Tests

```bash
cd pkgs/xsoulspace_inference_gemma_flutter
flutter test          # unit tests (no model needed)
make test             # + example integration test on macOS
```

Full e2e with a downloaded model is manual or CI-with-install.

## License

MIT

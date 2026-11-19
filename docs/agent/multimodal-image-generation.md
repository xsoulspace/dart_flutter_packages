# Multimodal image generation (T2I / I2I) — analysis, 2026-11-15

Question: how do text-to-image and image-to-image models (Qwen-Image,
Stable Diffusion, FLUX, Nano-Banana-class chat image models) enter this
stack? Proposed landing order: **dfp inference packages first**, then the
harness palette declaration, then a Last Answer product surface.

Status: **IMPLEMENTED 2026-11-15 → [ADR 0072](../decisions/0072_multimodal_image_generation_on_the_inference_contract.md).**
Waves I–III landed (core contract, OpenRouter images transport, palette
capability binding), plus the consumer seam in Last Answer (budget-wire
images lane + `ImageGenerationService`). Wave V (local loopback lane) is
configuration work, not code. The ⚠ probes below stay OPEN — live-curl
work, recorded as evidence when run.

## 1. What exists today (grounded)

**dfp** — the inference family has zero image support, but the contract
already answered this exact question once, for speech:

- `xsoulspace_inference_core` `inference_models.dart`: `InferenceTask` =
  {text, implicitlyStructuredText, nativelyStructuredText, speechToText,
  textToSpeech}. The audio precedent is the template: a dedicated
  `InferenceAudioInput` (filePath / base64 bytes / mimeType, JSON
  round-trips) rides `InferenceRequest` through the `?field` nullable-map
  pattern, and `InferenceAudioArtifact` (filePath + mimeType) rides
  `InferenceResponse`. Task gating is `InferenceClient.supportedTasks`
  with the honest `task_unsupported` refusal.
- `xsoulspace_inference_openrouter` `openrouter_inference_client.dart`:
  pure transport over a caller-supplied `baseUrl`; the operation path is
  DERIVED from the root (`chatCompletionsUri`), which is exactly how
  ModelScope rides the same client as an `openai_compatible` provider
  today. Response parsing reads `content` as a plain String — a
  multipart/image-bearing chat response would land `output_empty` today.
- `xsoulspace_inference_openai`: Responses API only, no images.
  `xsoulspace_inference_mlx` / `mlx_native`: local TEXT lane via the
  chat-wire server; no diffusion engine.

**Harness** — the palette wire already carries the vocabulary seam:
providers declare `models[{id, …, capabilities}]` where `capabilities`
is "the Zed-style capability map (`tools`, `images`, `chat_completions`,
…)" — parsed and carried, but DECLARATION ONLY (palette_config.dart
header comment). Roles are strictly `generative` | `decision` (the
parser refuses a third, line ~563). Transports: `openrouter`,
`openai_compatible`, `system_one`.

**Last Answer** — the wave-M models surface already edits per-model
`capabilities` maps and carries undeclared keys through ("an edit never
silently drops one"), so new capability keys round-trip with ZERO UI
schema work. Lanes are `local` / `afm` / `open_router` families.

## 2. The API landscape (2026-11-15)

Three live wire shapes matter:

1. **OpenRouter dedicated Images API** — `POST /api/v1/images`
   (note: NOT `/images/generations`). Request: `model`, `prompt`,
   optional `input_references: [{type: "image_url", image_url: {url}}]`
   (HTTP **or** base64 data URLs — this IS the I2I lane), `resolution`
   (512…4K tiers) / `aspect_ratio` / `size`, `quality`, `output_format`
   (png/jpeg/webp/svg/gif), `seed`, `n` 1–10. Response: images are
   **base64 only** — `{"data": [{b64_json, media_type}], "usage": {…,
   "cost"}}`. SSE streaming (`image_generation.partial_image` /
   `.completed`). Billing is per-image, all-or-nothing (failed
   generations bill nothing). Model discovery:
   `GET /v1/models?output_modalities=image`.
   Separately, chat-completions image OUTPUT exists for multimodal chat
   models (`modalities: ["text","image"]` — the Nano Banana / Seedream
   line), but the same models are reachable through the dedicated
   endpoint, so chat-multipart support is not on the critical path.
2. **OpenAI-images-compatible** — `POST {root}/images/generations`
   (`/images/edits` for I2I in OpenAI's own API; multipart there, JSON
   elsewhere). This is the common denominator ModelScope serves:
   `https://api-inference.modelscope.cn/v1/images/generations` with
   `Qwen/Qwen-Image` — ⚠ response returns **expiring URLs** (~24h), not
   b64; must download promptly. ⚠ ModelScope I2I (Qwen-Image-Edit)
   exact parameter shape did not surface fully in docs — probe live
   before wiring (likely an `image`/`input_image` field on generations,
   or a separate edits path).
3. **DashScope-native** (Alibaba) — Qwen-Image-Edit runs on
   `multimodal-generation/generation` with a `contents` array (base64 or
   URL) — a different wire family. Skip for v1; it would justify its own
   transport later if the owner wants DashScope directly. ModelScope
   already exposes the Qwen-Image family.

**Local lane** — `mflux` (MLX port) runs Qwen-Image T2I **and I2I**
natively on Apple Silicon at several quantization levels; `mlx-gen` and
friends expose local server shapes. The palette already accepts `http`
base URLs **for loopback hosts** — so a local, OpenAI-images-compatible
loopback server makes any local diffusion backend ride the SAME
`openai_compatible` transport with zero new transport code (the
system_one loopback precedent). `xsoulspace_inference_local_serve`
already exists as the host for such adapters.

## 3. Design

**Follow the audio precedent; add nothing speculative.**

### Wave I — core contract (`xsoulspace_inference_core`), purely additive

- `InferenceTask.textToImage`, `InferenceTask.imageToImage` (defer
  `imageToText`/vision-chat: it needs multipart `ChatMessage` and is a
  different problem — see §5).
- `InferenceImageInput` mirroring `InferenceAudioInput`:
  `{filePath?, bytesBase64?, mimeType}` (data-URL form on the wire).
  Keep it a separate type — do NOT unify with audio now; a shared
  `InferenceMediaInput` is a consolidation to make only if a third
  media type (video) actually arrives.
- `InferenceImageArtifact` on `InferenceResponse.imageArtifacts`
  (a LIST — APIs return n images): `{mimeType, bytesBase64?, url?,
  filePath?}` — exactly one carrier. Law: pure HTTP clients never
  write files, so bytes/URL only; `filePath` stays the local-engine
  form (audio precedent). Expiring URLs (ModelScope) produce a NAMED
  warning, and callers download immediately.
- `InferenceImageOptions`: `n`, `size`, `aspectRatio`, `quality`,
  `outputFormat`, `negativePrompt`, `strength` (I2I denoise),
  `providerExtras` map (the `InferenceVoiceOptions.providerExtras`
  escape hatch). Carried on `InferenceRequest` as `image_options` via
  the same `?field` pattern → absent = byte-identical old bodies.
  `seed` already exists on the request; image tasks map it like chat
  does (map-or-report, never silently drop).
- `imageArtifacts` rides `InferenceResponse.toJson/fromJson` like
  `audioArtifact` does today.

### Wave II — OpenRouter client becomes the images transport

- `imagesUri(baseUrl)` mirroring `chatCompletionsUri`: a root already
  ending `/images` rides verbatim (OpenRouter); otherwise append
  `/images/generations` (OpenAI-style). The style is chosen by a
  constructor flag set from the DECLARED transport — `openrouter` →
  `/images`, `openai_compatible` → `/images/generations` — never by
  sniffing the host.
- Extend `supportedTasks` with the two image tasks when the images
  endpoint is configured; keep the honest `task_unsupported` refusal
  otherwise (a chat-only base URL must keep refusing image tasks).
- Parse `data[]` → `InferenceImageArtifact`s (b64_json or url +
  media_type); `usage.cost` → `meta`; reuse the existing outcome
  diagnostics so palette runtime health marks image entries ok/failed
  like any other dispatch.
- **Diagnostics size law**: image b64 must never ride request diagnostics
  (the existing captures include encoded bodies) — strip image fields to
  a size marker before observing.
- Byte goldens for both endpoint styles, fake-`http.Client` tests — the
  house style.

### Wave III — harness palette declaration (no new role, no new transport)

- Capability keys land for real: `image_generation`, `image_edit` on
  model rows. The parser already carries the map; the binding composes
  the endpoint style + capability into the client the way it composes
  `GenerationOptions` today.
- NO third cast role. An image brain is not a conversational mover;
  casting an actor onto a diffusion model has no meaning for chat
  dispatch, and a new role would drag lane-truth, escalation and health
  machinery with it. Image models stay per-provider model rows
  consumable by whatever surface asks.
- NO new transport: images ride `openrouter` and `openai_compatible`.
- LA models surface: the catalog lens offers the two toggles; the wire
  document needs zero schema change (capabilities already round-trip).

### Wave IV — a consumer (owner product decision)

- A thin service over the routed client; artifacts materialize to app
  documents (privacy-first, local-first law). Candidate surfaces: Notes
  attachment, Boards cover art, Ideas illustration. NOT part of this
  analysis's claim — owner picks.
- If actors should generate images, that is a tool-contract wave
  (`tool_contracts`) + budget work, not a palette one.
- **Budget catch (paid attention here):** LA's `ProductCloudBudget`
  wire (`product_cloud_resource.dart`) hard-requires `max_tokens` on
  every body — an image request through it throws
  `bounded_output_required`. Image billing is per-image; the wire needs
  an image branch (a per-image price bound) before any cloud image
  request rides it.

### Wave V — the local lane

- Local diffusion enters as a LOOPBACK images server (mflux adapter,
  or `local_serve`-hosted) + an `openai_compatible` provider with a
  `http://127.0.0.1:…` base URL — zero new transport code, honest
  `local` lane chip, offline. A native diffusion backend inside
  `mlx_native` (ADR 0051/0057 lineage) is the bigger, later version of
  the same seam.

## 4. Fastest real-world path

The owner's ModelScope key is already wired as `openai_compatible`.
Waves I–II make `Qwen/Qwen-Image` (T2I) and the Qwen-Image-Edit family
(I2I, ⚠ after the parameter probe) reachable with one palette row:
add the model id, tick `image_generation`. OpenRouter's images API then
adds the hosted frontier models (Seedream, gpt-image-2, Nano Banana
line) with the same two waves.

## 5. Explicit non-goals (this analysis)

- `ChatMessage` multipart content and vision INPUT to chat models
  (`imageToText`) — a separate wave with its own contract decision; it
  destabilizes every provider renderer and is not needed for T2I/I2I.
- Chat-completions image OUTPUT (`modalities:["image"]`) parsing — the
  dedicated endpoint covers those models.
- DashScope-native transport, SSE streaming of partial images, image
  animation (`frame_count`) — later, on demand.
- Any LA product UI claim — owner decision, Wave IV.

## 6. Open items before implementation

1. ⚠ Probe ModelScope I2I parameter shape and URL-expiry headers live
   (one curl with the existing key; record as evidence).
2. Confirm OpenRouter image-model ids differ from chat ids (separate
   namespace per `GET /v1/images/models`) and how `model` routing
   interacts with `provider.only`.
3. Decide whether `strength`/`steps`/`guidance` belong in
   `InferenceImageOptions` v1 or stay `providerExtras` (recommend:
   extras only — diffusion tuning knobs vary per backend; the honest
   carrier passes them, the typed surface stays small).

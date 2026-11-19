# ADR 0072: Multimodal image generation on the inference contract

- Status: Accepted. Waves I–III landed in this repository and the harness
  palette; the consumer wave (Last Answer) rides the same contract.
- Date: 2026-11-15
- North Star impact: `clarifies` [0059](0059_native_casts_in_palette_and_composable_requests.md)
  — the composable request surface gains the image tasks the audio tasks
  already modelled. No existing decision's centre moves: `InferenceClient`,
  the palette, and the provider seam are unchanged. Image generation is a
  **task**, not a new plane.
- Builds on: 0058 (unified inference interface), 0059 (composable request
  surface), 0071 (per-request seed — image bodies map it or refuse, same
  honesty law)
- Measured on: the contract and transports as landed 2026-11-15 —
  184 core tests (10 image-contract), 106 openrouter tests (21 image-lane),
  18 harness registry tests (5 image-binding). Provider wire facts read
  from live docs 2026-11-15; the two marked ⚠ stay open probes.

## Context

Text-to-image and image-to-image models (Qwen-Image, Stable Diffusion,
FLUX, the Nano-Banana-class chat image models) had no path into this
stack: `InferenceTask` covered text, structure, speech; the OpenRouter
client spoke only `/chat/completions`; the palette's per-model
`capabilities` map was declaration-only prose with no consumer.

The contract had already answered this exact question once — for speech.
`InferenceTask.speechToText`/`textToSpeech` carry a dedicated
`InferenceAudioInput` and `InferenceAudioArtifact` through the nullable
`?field` map pattern, gate on `supportedTasks`, and refuse honestly. Image
generation is the same move, and the API landscape rewards it: the live
wire shapes differ per provider but all three reduce to "prompt in,
pixels (or a link) out".

The wire facts (2026-11-15):

- **OpenRouter** dedicated Images API: `POST /api/v1/images` (NOT
  `/images/generations`); I2I rides `input_references`
  (`{type: image_url, image_url: {url}}`, HTTP or data URLs); responses
  are base64-only; billing is per-image, all-or-nothing; `usage.cost`
  rides the response.
- **OpenAI-images-compatible** (`{root}/images/generations`) — the shape
  ModelScope serves with `Qwen/Qwen-Image`; responses return expiring
  URLs (~24 h), not pixels. ⚠ The ModelScope I2I parameter shape needs a
  live probe before a real edit dispatch; this ADR's `image` data-URL
  mapping is the convention, not a verified fact.
- **Local** (mflux on Apple Silicon, ComfyUI-style servers): enters as a
  LOOPBACK images-compatible server behind the existing
  `openai_compatible` transport — the palette already accepts `http`
  base URLs for loopback hosts, so the local lane needs NO new transport
  code.

## Decision

### 1. The contract: two tasks, three types, zero speculative fields

`InferenceTask.textToImage` and `InferenceTask.imageToImage` join the
enum. The audio precedent is followed exactly:

- `InferenceImageInput` (`filePath` xor `bytes`, `mimeType`) mirrors
  `InferenceAudioInput` minus the audio-only fields; `source` is its own
  two-value enum (an image has no microphone lane). JSON round-trips via
  `bytes_base64`, same as audio.
- `InferenceImageArtifact` rides `InferenceResponse.imageArtifacts` (a
  LIST — providers return n images). The carrier law: **exactly one** of
  `bytesBase64` / `url` / `filePath`. Pure HTTP clients never write
  files — bytes or url only; `filePath` stays the local-engine form. A
  url carrier is recorded with the `image_url_expiring` warning; callers
  download promptly.
- `InferenceImageOptions`: `n`, `size`, `aspectRatio`, `quality`,
  `outputFormat`, `negativePrompt`, `strength`, `providerExtras`. The
  typed surface stays small — diffusion tuning knobs vary per backend
  and ride `providerExtras` verbatim. `seed` is the existing request
  seed (0071's law applies: map or refuse, never a silent drop).
- Validation: prompt non-empty for both tasks; image-to-image requires
  an unambiguous input (the `source_mismatch` / `ambiguous_source` /
  `source_missing` refusal vocabulary mirrors audio).

Absent fields are ABSENT on the wire map (`?field` markers) — a request
without image keys is byte-identical to before.

### 2. The transport: one client, two declared endpoint styles

`OpenRouterInferenceClient` gains `imageEndpointStyle`
(`openAiGenerations` → `{root}/images/generations`, `openRouterImages` →
`{root}/images`). The style is **declared** (the palette knows the
transport it named) — never sniffed from the host. Undeclared (the
default), image tasks refuse at the existing `task_unsupported` gate;
`supportedTasks` carries the image tasks only when the style is
declared.

The image lane shares the chat lane's transport, timeout, HTTP-error
mapping and **outcome diagnostics** (`openrouter.result` with a
`lane: images` discriminator), so palette runtime health marks image
dispatches like any other. Two laws it adds:

- **The diagnostics size law**: image payloads (data URLs, b64 outputs)
  are replaced with size markers before any diagnostic stores them.
- **The cache-intent refusal**: cache intent is a chat-lane concept; a
  non-empty intent on an image request refuses by name
  (`cache_intent_unsupported_for_task`), never silently drops.

Provider-specific params surface as that provider's error — mapped or
refused, never silently dropped. `providerExtras` passes verbatim and
overrides typed fields (a deliberate caller choice, not a collision).

### 3. The palette: capability keys consumed, no new role, no new transport

`image_generation` / `image_edit` on a model row are the
binding-consumed capability keys: the composition root derives the
endpoint style from the declared transport **and** the row's declared
capability (`declaredImageEndpointStyle` in the afm model registry).
Absent or false, the binding serves chat only.

NO third cast role: an image brain is not a conversational mover;
casting an actor onto a diffusion model has no meaning for chat
dispatch, and a new role would drag lane-truth, escalation and health
machinery along. NO new transport: images ride `openrouter` and
`openai_compatible`.

### 4. The consumer seam (Last Answer)

A thin `ImageGenerationService` over the routed client: artifacts
materialize to app documents (privacy-first: generated pixels stay
local), expiring URLs download promptly, download failures refuse by
name. The comparison budget wire gained the images lane: per-image
all-or-nothing reservation (count × ceiling, settle on the provider's
`usage.cost`), an absent count defaults to 1, an explicitly invalid
count refuses, and the chat price injection (`provider.max_price`) never
rides an image body.

## Alternatives considered

- **Multipart `ChatMessage` + vision chat first** — rejected for this
  wave: it destabilizes every provider renderer, and the dedicated
  images endpoint already covers the image-output models. Vision INPUT
  to chat (`imageToText`) is a separate contract decision, not this one.
- **A third palette role (`image`)** — rejected: see §3.
- **A dedicated `ImageGenerationClient` interface** — rejected:
  `supportedTasks` is the established capability probe; a second probe
  would split the honest-refusal path.
- **DashScope-native transport** — deferred: ModelScope already exposes
  the Qwen-Image family over the compatible shape; a DashScope adapter
  would justify itself only if the owner wants Alibaba directly.

## Consequences

- Any hosted image request rides the budget wire only after the
  images lane landed there (it did — the chat wire's
  `bounded_output_required` guard would otherwise refuse every image
  body).
- The two ⚠ probes stay open: ModelScope I2I parameters, and the
  OpenRouter image-model id namespace vs chat ids. Both are live-curl
  work recorded as evidence, not code.
- A local lane arrives as a loopback images server (mflux adapter) +
  an `openai_compatible` provider row with a loopback base URL — zero
  new transport code.

## Amendment 1 — the vision (imageToText) multipart lane (2026-11-16)

This ADR originally DECLARED as a non-goal: "no multimodal INPUT
(ChatMessage gains parts)… deferred until a justified need." The need
arrived one day later: the harness's native-image-assets waves
(ecsai_harness ADR 0142) gave actors hands that create images, and
hands need eyes — a vision-capable row must be able to SEE an image
and answer in text. This amendment lands the input lane.

- **`InferenceTask.imageToText`** joins the enum. Validation mirrors
  `imageToImage`: the image input is REQUIRED (`image_input_missing` /
  `image_input_invalid`) and the prompt must be non-empty.
- **`ChatMessage` gains typed `parts`** (`ChatMessagePart`: `text` /
  `image_url` data-URL — the OpenAI-vision shape every
  chat-completions-compatible vision model serves). The String
  content path is BYTE-IDENTICAL when parts are absent; multipart
  messages render `content` as the part array on the wire and parse
  it back on `fromJson`.
- **The OpenRouter chat lane renders vision turns** as the content
  array (text part first, then the image data URL). The codec path
  never carries an image (vision forces the plain user-content
  path). `imageToText` is supported unconditionally on the chat
  endpoint — unlike the images tasks it needs no declared endpoint
  style; the caller's palette (`vision` capability key) decides who
  gets eyes, not the transport.
- **The size law covers the chat lane too**: a body that carries a
  data URL is sanitized to `[[data-url:N chars]]` markers in EVERY
  diagnostic copy (context-transport capture, transport post events);
  text-only bodies keep their byte-identical diagnostics.
- **`ModelRuntime.generate`** (harness model_router) carries an
  optional `imageInput` through both request-build sites.

Still open (unchanged): the ModelScope I2I parameter shape probe; the
OpenRouter image-model id namespace; and now also a LIVE vision-input
probe against a qwen-vl-class model before dispatch-path multipart
turns land (the renderer already speaks the documented shape).

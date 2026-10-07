// ignore_for_file: lines_longer_than_80_chars

/// OpenRouter `SchemaBundle` → JSON Schema conversion.
///
/// The conversion itself moved to `xsoulspace_inference_core` once the
/// Anthropic Messages package needed the same standard-JSON-Schema mapping
/// (`input_schema`); this file keeps the OpenRouter public API stable by
/// delegating to the shared implementation.
library;

export 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show bundleToJsonSchema, schemaToJsonSchema;

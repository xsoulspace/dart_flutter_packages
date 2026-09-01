// ignore_for_file: lines_longer_than_80_chars

/// J1.2 — context budget metering (ADR 0018: the window is the hard wall).
///
/// `overheadTokens` measures what a decision costs BEFORE any content: the
/// system prompt + tool names/descriptions/schemas. Published beside every
/// benchmark column so the working-memory claim is honest. Target: ≤ 1500
/// of AFM's 4096-token window (leave ~2.5k working memory).
library;

import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Estimated tokens a decision spends on fixed overhead (≈4 chars/token —
/// the same estimator the projection law uses).
int overheadTokens({
  required String systemPrompt,
  required List<ToolDef> tools,
}) {
  var chars = systemPrompt.length;
  for (final t in tools) {
    chars += t.name.value.length + t.description.length;
    try {
      chars += jsonEncode(t.argsSchema.toJson()).length;
    } on Exception {
      // A schema that cannot serialize counts via its description alone.
    }
  }
  return (chars / 4).ceil();
}

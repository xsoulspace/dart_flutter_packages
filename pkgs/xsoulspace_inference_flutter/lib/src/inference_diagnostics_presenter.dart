import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'inference_preflight_panel.dart';
import 'inference_status_strip.dart';
import 'inference_transcript_panel.dart';

final class InferenceDiagnosticsPresenter extends StatelessWidget {
  const InferenceDiagnosticsPresenter({
    super.key,
    required this.readiness,
    required this.transcript,
  });

  final InferenceReadinessSnapshot readiness;
  final InferenceTranscriptSnapshot transcript;

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InferencePreflightPanel(snapshot: readiness),
        const SizedBox(height: 12),
        InferenceStatusStrip(snapshot: transcript),
        const SizedBox(height: 12),
        InferenceTranscriptPanel(snapshot: transcript),
      ],
    );
  }
}

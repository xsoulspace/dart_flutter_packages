import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final class InferenceStatusStrip extends StatelessWidget {
  const InferenceStatusStrip({required this.snapshot, super.key});

  final InferenceTranscriptSnapshot snapshot;

  @override
  Widget build(final BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        'State: ${snapshot.sessionState.name} | '
        'Last: ${snapshot.lastTranscript ?? '…'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
}

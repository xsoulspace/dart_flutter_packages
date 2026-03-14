import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final class InferenceTranscriptPanel extends StatelessWidget {
  const InferenceTranscriptPanel({super.key, required this.snapshot});

  final InferenceTranscriptSnapshot snapshot;

  @override
  Widget build(final BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Live Transcript',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(snapshot.partialTranscript ?? snapshot.finalTranscript ?? '…'),
            if (snapshot.error != null) const SizedBox(height: 8),
            if (snapshot.error != null)
              Text(
                snapshot.error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

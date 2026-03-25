import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final class InferencePreflightPanel extends StatelessWidget {
  const InferencePreflightPanel({
    super.key,
    required this.snapshot,
    this.title = 'Inference Readiness',
  });

  final InferenceReadinessSnapshot snapshot;
  final String title;

  @override
  Widget build(final BuildContext context) {
    final issues = formatInferenceReadinessIssues(snapshot);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(formatInferenceReadinessSummary(snapshot)),
            if (issues.isNotEmpty) const SizedBox(height: 8),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $issue'),
              ),
          ],
        ),
      ),
    );
  }
}

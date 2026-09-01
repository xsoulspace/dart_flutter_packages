// ignore_for_file: lines_longer_than_80_chars

/// The harness profiler (PLAN J1.5.4): a live, "Flutter profiler"-style view
/// of the whole agentic harness — what's in the work, which policy opened
/// the current decision, what's causing a loop, and the meaning cut the
/// model sees.
///
/// Polls [sampleHarness] on a Timer (no subscriptions needed — the world is
/// plain state). Optionally records every poll into a [FlightRecorder] so
/// an attached profiler doubles as the flight recorder of record.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// Live profiler view over a harness [World].
///
/// Provide EITHER [world] (sampled directly) OR [pulseLoader] (custom
/// sampling — e.g. over an isolate or after combining pulses). When
/// [recorder] is given, every poll is recorded (ring buffer + endless-loop
/// detector), so an attached profiler is the flight recorder of record.
class HarnessProfilerView extends StatefulWidget {
  const HarnessProfilerView({
    super.key,
    this.world,
    this.pulseLoader,
    this.recorder,
    this.meaningCutBuilder,
    this.pollInterval = const Duration(milliseconds: 500),
  }) : assert(
          world != null || pulseLoader != null,
          'Provide world or pulseLoader',
        );

  /// The world to sample. Mutually exclusive with [pulseLoader].
  final World? world;

  /// Custom pulse source (isolate hosts, remote debugging).
  final HarnessPulse Function()? pulseLoader;

  /// When set, every poll is recorded (dump on exit / SIGINT).
  final FlightRecorder? recorder;

  /// Optional builder for the "what the model sees" pane — typically
  /// `() => meaningCut(world, query: '', maxNodes: 24)`. Rendered as text.
  final String Function()? meaningCutBuilder;

  final Duration pollInterval;

  @override
  State<HarnessProfilerView> createState() => _HarnessProfilerViewState();
}

class _HarnessProfilerViewState extends State<HarnessProfilerView> {
  Timer? _timer;
  HarnessPulse? _pulse;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(widget.pollInterval, (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    if (!mounted) return;
    final HarnessPulse pulse;
    try {
      pulse = widget.pulseLoader != null
          ? widget.pulseLoader!()
          : sampleHarness(widget.world!);
    } catch (_) {
      return; // world mid-flush or cleared — try again next tick
    }
    widget.recorder?.record(pulse);
    setState(() => _pulse = pulse);
  }

  @override
  Widget build(BuildContext context) {
    final pulse = _pulse;
    if (pulse == null) {
      return const Center(child: Text('harness profiler: sampling…'));
    }
    final theme = Theme.of(context);
    return DefaultTextStyle(
      style: theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _Header(pulse: pulse),
          for (final warning in pulse.loopWarnings)
            _WarningBanner(text: warning),
          for (final actor in pulse.actors) _ActorCard(actor: actor),
          if (widget.meaningCutBuilder != null)
            _MeaningCutPane(builder: widget.meaningCutBuilder!),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pulse});
  final HarnessPulse pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        'tick ${pulse.tick} · decisions ${pulse.openDecisions} · '
        'in-flight ${pulse.inFlightTasks} · pending ${pulse.pendingToolResults}',
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        '⚠ $text',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ActorCard extends StatelessWidget {
  const _ActorCard({required this.actor});
  final ActorPulse actor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = actor.goalAttemptsExhausted
        ? theme.colorScheme.error
        : actor.loopStuckStreak != null
            ? theme.colorScheme.tertiary
            : actor.hasOpenDecision
                ? theme.colorScheme.primary
                : theme.colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${actor.agentId}  '
                    '${actor.hasOpenDecision ? 'DECISION OPEN via ${actor.decisionOrigin}' : 'idle'}'
                    '${actor.awaitingResponse ? ' · generating…' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'rounds ${actor.toolRounds}/${actor.maxToolRounds} '
              '(Σ${actor.totalRounds})'
              '${actor.retryCount > 0 ? ' · retries ${actor.retryCount}' : ''}'
              '${actor.attemptCount > 0 ? ' · attempts ${actor.attemptCount}/${actor.maxGoalAttempts}${actor.goalAttemptsExhausted ? ' EXHAUSTED' : ''}' : ''}'
              '${actor.goalVerified == null ? '' : actor.goalVerified! ? ' · goal PASS' : ' · goal FAIL'}'
              '${actor.loopStuckStreak != null ? ' · ⚠ LOOP STUCK ×${actor.loopStuckStreak}' : ''}',
            ),
            if (actor.lastToolName != null)
              Text(
                'last: ${actor.lastToolSignature} → '
                '${actor.lastToolOk == null ? '?' : actor.lastToolOk! ? 'ok' : 'FAILED'}',
                style: TextStyle(
                  color: actor.lastToolOk == false
                      ? theme.colorScheme.error
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            if (actor.lastToolError != null)
              Text(
                'error: ${actor.lastToolError}',
                style: TextStyle(color: theme.colorScheme.error),
                overflow: TextOverflow.ellipsis,
              ),
            if (actor.decisionPrompt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'prompt: ${actor.decisionPrompt}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MeaningCutPane extends StatelessWidget {
  const _MeaningCutPane({required this.builder});
  final String Function() builder;

  @override
  Widget build(BuildContext context) {
    String cut;
    try {
      cut = builder();
    } catch (e) {
      cut = 'meaning cut unavailable: $e';
    }
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'what the model sees (meaning cut)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(cut, maxLines: 24, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

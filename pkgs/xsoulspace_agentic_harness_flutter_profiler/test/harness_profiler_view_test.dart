// ignore_for_file: lines_longer_than_80_chars

/// J1.5.4 — the profiler view renders the live pulse: header counts, loop
/// warning banners, per-actor stack cards, and the meaning-cut pane.
/// LLM-free widget test over a hand-built pulse (no World needed).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness_flutter_profiler/xsoulspace_agentic_harness_flutter_profiler.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

HarnessPulse _stuckPulse() => HarnessPulse(
      tick: 42,
      openDecisions: 1,
      inFlightTasks: 1,
      pendingToolResults: 1,
      loopWarnings: const [
        'ENDLESS-LOOP SUSPECT: actor a1 opened the identical decision 3× '
            'in a row (origin: run_graded_goal).',
      ],
      actors: [
        ActorPulse(
          agentId: 'a1',
          hasOpenDecision: true,
          decisionOrigin: 'run_graded_goal',
          decisionPrompt: 'Fix the meaning tree, re-materialize…',
          toolRounds: 12,
          maxToolRounds: 12,
          totalRounds: 31,
          retryCount: 1,
          attemptCount: 3,
          maxGoalAttempts: 3,
          goalAttemptsExhausted: true,
          goalVerified: false,
          goalDetail: 'intents failed: save_url → {error: …}',
          loopStuckStreak: 3,
          awaitingResponse: false,
          threadStatuses: const ['suspended'],
          lastToolName: 'intent_call',
          lastToolSignature: 'intent_call:{"intent":"save_url"}',
          lastToolOk: false,
          lastToolError: 'intent not implemented: save_url',
        ),
      ],
    );

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders the whole decision stack + loop warnings', (tester) async {
    await tester.pumpWidget(
      _app(HarnessProfilerView(pulseLoader: _stuckPulse, pollInterval: const Duration(hours: 1))),
    );
    await tester.pump();

    expect(find.textContaining('tick 42'), findsOneWidget);
    expect(find.textContaining('DECISION OPEN via run_graded_goal'), findsOneWidget);
    expect(find.textContaining('rounds 12/12 (Σ31)'), findsOneWidget);
    expect(find.textContaining('attempts 3/3 EXHAUSTED'), findsOneWidget);
    expect(find.textContaining('goal FAIL'), findsOneWidget);
    expect(find.textContaining('LOOP STUCK ×3'), findsWidgets);
    expect(find.textContaining('ENDLESS-LOOP SUSPECT'), findsOneWidget);
    expect(find.textContaining('intent_call:{\"intent\":\"save_url\"}'), findsOneWidget);
    expect(find.textContaining('intent not implemented'), findsOneWidget);
    // The prompt the actor is cycling on — the "what's in the work" answer.
    expect(find.textContaining('Fix the meaning tree'), findsOneWidget);
  });

  testWidgets('meaning-cut pane renders the model view via the builder',
      (tester) async {
    await tester.pumpWidget(
      _app(
        HarnessProfilerView(
          pulseLoader: _stuckPulse,
          pollInterval: const Duration(hours: 1),
          meaningCutBuilder: () => 'intent save_url · op_1 load_arg(url) …',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('what the model sees (meaning cut)'), findsOneWidget);
    expect(find.textContaining('op_1 load_arg(url)'), findsOneWidget);
  });

  testWidgets('flight recorder receives every poll', (tester) async {
    final recorder = FlightRecorder(capacity: 8, promptRepeatThreshold: 2);
    await tester.pumpWidget(
      _app(
        HarnessProfilerView(
          pulseLoader: _stuckPulse,
          recorder: recorder,
          pollInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();

    expect(recorder.length, 1);
    expect(recorder.dump(), contains('a1'));
  });
}

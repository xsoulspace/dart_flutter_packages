import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

import '../plan/checks.dart';
import '../plan/plan.dart';
import '../plan/steps.dart';
import 'registry.dart';

/// The runner's report schema identifier.
const runReportSchemaId = 'automation.run/v1';

/// One executed step's record in a [RunReport].
final class StepResult {
  StepResult._({
    required this.index,
    required this.kind,
    required this.session,
    required this.ok,
    required this.durationMs,
    this.errorKind,
    this.errorMessage,
    this.detail = const {},
  }) : skipped = false;

  /// Creates a skipped-step record (after an aborting failure).
  StepResult.skipped({required this.index, required this.kind})
    : session = null,
      ok = false,
      durationMs = 0,
      errorKind = 'skipped',
      errorMessage = 'not run: an earlier step failed',
      detail = const {},
      skipped = true;

  /// 0-based position in the effective step list.
  final int index;

  /// Step kind (`observe`, `act`, `verify`, `wait`, `screenshot`,
  /// `intent`).
  final String kind;

  /// Session the step drove, when it ran.
  final String? session;

  /// Whether the step succeeded.
  final bool ok;

  /// Wall-clock duration of the step.
  final int durationMs;

  /// Machine-readable error category, when failed.
  final String? errorKind;

  /// Human-readable error message, when failed.
  final String? errorMessage;

  /// Step-specific structured detail (snapshot summary, checks, outcome).
  final Map<String, Object?> detail;

  /// Whether the step was skipped because an earlier step aborted.
  final bool skipped;

  /// Report shape.
  Map<String, Object?> toJson() => {
    'index': index,
    'kind': kind,
    if (session != null) 'session': session,
    'ok': ok,
    'durationMs': durationMs,
    if (errorKind != null) 'errorKind': errorKind,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (detail.isNotEmpty) 'detail': detail,
    if (skipped) 'skipped': true,
  };
}

/// The structured outcome of one scenario run.
final class RunReport {
  RunReport._({
    required this.scenario,
    required this.startedAt,
    required this.finishedAt,
    required this.ok,
    required this.steps,
    required this.receipts,
  });

  /// The scenario that ran.
  final String scenario;

  /// Run start.
  final DateTime startedAt;

  /// Run end.
  final DateTime finishedAt;

  /// Whether every executed step passed.
  final bool ok;

  /// Per-step records.
  final List<StepResult> steps;

  /// Behavior receipt artifact paths written during the run.
  final List<String> receipts;

  /// Report shape.
  Map<String, Object?> toJson() => {
    'schema': runReportSchemaId,
    'scenario': scenario,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'ok': ok,
    'steps': [for (final step in steps) step.toJson()],
    if (receipts.isNotEmpty) 'receipts': receipts,
  };

  /// Compact JSON encoding.
  String encode() => jsonEncode(toJson());
}

/// Executes a [Scenario] of an [AutomationPlan] against live sessions.
///
/// Fail-closed order: the plan validates first (all violations at once,
/// nothing attaches), then sessions attach lazily on first use, then
/// steps run in order and stop at the first failure unless the step is
/// marked continue-on-failure. Sessions are detached in every exit path.
final class PlanRunner {
  /// Creates a runner; [attachTimeout] bounds each session attach.
  PlanRunner({this.attachTimeout = const Duration(seconds: 10)});

  /// Attach deadline per session.
  final Duration attachTimeout;

  /// Runs [scenarioName] (default: the plan's only scenario) and returns
  /// the structured report.
  Future<RunReport> run(
    AutomationPlan plan, {
    String? scenarioName,
    Map<String, String> sessionOverrides = const {},
    String? outDir,
  }) async {
    final violations = plan.validate();
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
    final name = scenarioName ?? plan.onlyScenario?.name;
    if (name == null || !plan.scenarios.containsKey(name)) {
      throw SpecViolationException([
        'scenario ${scenarioName == null ? 'not given and the plan declares '
            'several' : '"$scenarioName"'} does not exist',
      ]);
    }
    final steps = plan.effectiveSteps(name);
    final registry = SessionRegistry(
      bindings: plan.sessions,
      overrides: sessionOverrides,
      attachTimeout: attachTimeout,
    );
    final startedAt = DateTime.now();
    final results = <StepResult>[];
    final receipts = <String>[];
    var ok = true;
    try {
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        if (!ok && !step.continueOnFailure) {
          results.add(StepResult.skipped(index: i, kind: step.kind));
          continue;
        }
        final result = await _runStep(
          plan,
          registry,
          step,
          index: i,
          outDir: outDir,
          receipts: receipts,
        );
        results.add(result);
        if (!result.ok && !step.continueOnFailure) ok = false;
      }
    } finally {
      await registry.detachAll();
    }
    return RunReport._(
      scenario: name,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      ok: ok,
      steps: results,
      receipts: receipts,
    );
  }

  Future<StepResult> _runStep(
    AutomationPlan plan,
    SessionRegistry registry,
    PlanStep step, {
    required int index,
    required String? outDir,
    required List<String> receipts,
  }) async {
    final watch = Stopwatch()..start();
    String? sessionName;
    try {
      final sessionBindingName = step.session ??
          (plan.sessions.length == 1 ? plan.sessions.keys.single : null);
      final session = await registry.attach(sessionBindingName!);
      sessionName = sessionBindingName;
      final detail = await switch (step) {
        ObserveStep() => _observe(session, step),
        ActStep() => _act(plan, session, step, index, outDir, receipts),
        IntentStep() => _actIntent(plan, session, step, index, outDir, receipts),
        VerifyStep() => _verify(session, step.checks),
        WaitStep() => _wait(session, step),
        ScreenshotStep() => _screenshot(session, step, outDir),
      };
      return StepResult._(
        index: index,
        kind: step.kind,
        session: sessionName,
        ok: true,
        durationMs: watch.elapsedMilliseconds,
        detail: detail,
      );
    } on AutomationException catch (error) {
      return StepResult._(
        index: index,
        kind: step.kind,
        session: sessionName,
        ok: false,
        durationMs: watch.elapsedMilliseconds,
        errorKind: error.kind,
        errorMessage: error.message,
      );
    } on FormatException catch (error) {
      return StepResult._(
        index: index,
        kind: step.kind,
        session: sessionName,
        ok: false,
        durationMs: watch.elapsedMilliseconds,
        errorKind: 'format',
        errorMessage: error.message,
      );
    } on FileSystemException catch (error) {
      return StepResult._(
        index: index,
        kind: step.kind,
        session: sessionName,
        ok: false,
        durationMs: watch.elapsedMilliseconds,
        errorKind: 'io',
        errorMessage: error.message,
      );
    }
  }

  Future<Map<String, Object?>> _observe(
    ResolvedSession session,
    ObserveStep step,
  ) async {
    final snapshot = await session.driver.snapshot();
    return {
      'nodeCount': snapshot.nodes.length,
      'revision': snapshot.revision,
      'capturedAt': snapshot.capturedAt.toIso8601String(),
      if (step.save != null) step.save!: snapshot.toJson(),
    };
  }

  Future<Map<String, Object?>> _act(
    AutomationPlan plan,
    ResolvedSession session,
    ActStep step,
    int index,
    String? outDir,
    List<String> receipts,
  ) => _dispatch(
    plan,
    session,
    step.action,
    profileName: step.profile,
    seed: step.seed,
    index: index,
    outDir: outDir,
    receipts: receipts,
  );

  Future<Map<String, Object?>> _actIntent(
    AutomationPlan plan,
    ResolvedSession session,
    IntentStep step,
    int index,
    String? outDir,
    List<String> receipts,
  ) {
    final intent = plan.intents.intent(step.app, step.name);
    if (intent == null) {
      throw SpecViolationException([
        'intent "${step.app}/${step.name}" is not declared',
      ]);
    }
    final action = intent.hint.lowerToAction(
      args: step.args,
      label: 'intent ${step.app}/${step.name}',
    );
    return _dispatch(
      plan,
      session,
      action,
      profileName: step.profile,
      seed: step.seed,
      index: index,
      outDir: outDir,
      receipts: receipts,
    );
  }

  Future<Map<String, Object?>> _dispatch(
    AutomationPlan plan,
    ResolvedSession session,
    AutomationAction action, {
    required String? profileName,
    required int? seed,
    required int index,
    required String? outDir,
    required List<String> receipts,
  }) async {
    final profile = profileName == null ? null : plan.profiles[profileName];
    if (profile == null) {
      await session.driver.perform(action);
      return {};
    }
    final behavioral = session.asBehavioral();
    if (behavioral == null) {
      throw DriverUnsupportedException(
        'transport "${session.binding.transport.name}" cannot honor '
        'behavior profiles (step ${index + 1} requested "$profileName")',
      );
    }
    final effectiveSeed = seed ?? DateTime.now().microsecondsSinceEpoch;
    final outcome = await behavioral.performWith(action, profile, seed: effectiveSeed);
    final directory = outDir ?? Directory.current.path;
    final writer = CdpBehaviorReceiptWriter(
      directory: directory,
      base: 'step-${index + 1}',
    );
    await writer.write(
      profile: profile,
      seed: effectiveSeed,
      driverId: 'universal-automation-toolkit',
      transport: session.binding.transport.name,
      outcome: outcome,
    );
    receipts.addAll([writer.streamPath, writer.receiptsPath]);
    return {
      'profile': profileName,
      'verdict': outcome.verdict.name,
      if (outcome.cause != null) 'cause': outcome.cause!.name,
      'dispatchedSteps': outcome.dispatched.length,
      'plannedSteps': outcome.plan.steps.length,
    };
  }

  Future<Map<String, Object?>> _verify(
    ResolvedSession session,
    List<VerifyCheck> checks,
  ) async {
    final snapshot = await session.driver.snapshot();
    final failures = [
      for (final check in checks)
        if (check.evaluate(snapshot, url: session.url) case final reason?)
          reason,
    ];
    if (failures.isNotEmpty) {
      throw AutomationVerificationException(failures);
    }
    return {'checks': checks.length, 'revision': snapshot.revision};
  }

  Future<Map<String, Object?>> _wait(
    ResolvedSession session,
    WaitStep step,
  ) async {
    final deadline = DateTime.now().add(step.timeout);
    List<String> failures = [];
    var polls = 0;
    while (true) {
      polls++;
      final snapshot = await session.driver.snapshot();
      failures = [
        for (final check in step.checks)
          if (check.evaluate(snapshot, url: session.url) case final reason?)
            reason,
      ];
      if (failures.isEmpty) {
        return {'checks': step.checks.length, 'polls': polls};
      }
      if (DateTime.now().isAfter(deadline)) {
        throw AutomationVerificationException(failures, timedOut: true);
      }
      await Future<void>.delayed(step.pollInterval);
    }
  }

  Future<Map<String, Object?>> _screenshot(
    ResolvedSession session,
    ScreenshotStep step,
    String? outDir,
  ) async {
    if (!session.driver.capabilities.screenshot) {
      throw DriverUnsupportedException(
        'transport "${session.binding.transport.name}" cannot capture '
        'screenshots',
      );
    }
    final requested = File(step.out);
    final path = requested.isAbsolute || outDir == null
        ? step.out
        : '$outDir/${step.out}';
    final file = File(path);
    await file.parent.create(recursive: true);
    final bytes = await session.driver.screenshot();
    await file.writeAsBytes(bytes, flush: true);
    return {'path': file.path, 'bytes': bytes.length};
  }
}

/// One or more verify/wait checks failed against the live surface.
class AutomationVerificationException extends AutomationException {
  /// Creates the exception from the failed-check reasons.
  AutomationVerificationException(this.failures, {this.timedOut = false})
    : super(
        timedOut
            ? 'wait timed out: ${failures.join('; ')}'
            : 'verification failed: ${failures.join('; ')}',
        details: {'failures': failures, if (timedOut) 'timedOut': true},
      );

  @override
  String get kind => timedOut ? 'waitTimeout' : 'verificationFailed';

  /// Why each failed check failed.
  final List<String> failures;

  /// Whether this came from a [WaitStep] deadline.
  final bool timedOut;
}

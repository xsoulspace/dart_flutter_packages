import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

import 'src/plan/checks.dart';
import 'src/plan/plan.dart';
import 'src/plan/steps.dart';

export 'package:universal_automation_interface/universal_automation_interface.dart';
export 'package:universal_automation_semantics/universal_automation_semantics.dart';
export 'src/plan/checks.dart';
export 'src/plan/intents.dart';
export 'src/plan/plan.dart';
export 'src/plan/steps.dart';

/// The Dart composition grammar — the primary face of the declarative
/// harness.
///
/// Plans are typed values composed in Dart (the mcp_flutter harness and
/// oka precedent; flutter's own builder shape): lowercase builders return
/// step and check values, scenarios are lists of them, composition is
/// ordinary Dart (loops, `if`, spreads, `Scenario.extend`). The same
/// values round-trip through the YAML/JSON wire form, so agents and MCP
/// clients compose the identical runner input textually.
///
/// ```dart
/// final plan = AutomationPlan(
///   sessions: [cdp('browser', uri: Uri.parse('http://127.0.0.1:9222'))],
///   scenarios: [
///     scenario('checkout', steps: [
///       navigate(Uri.parse('http://127.0.0.1:9222/#form')),
///       waitFor([exists(role: 'button', name: 'Submit')]),
///       typeText('antonio@example.com', css: '#email', submit: true),
///       verifyThat([absent(name: 'Error')]),
///     ]),
///   ],
/// );
/// final report = await PlanRunner().run(plan, scenario: 'checkout');
/// ```

// — Steps ———————————————————————————————————————————————————————————————

/// Observe: capture one semantic snapshot — through a [view]
/// ([SemanticView], ADR 0052) the report carries the rendered text and
/// ref index; without one, only counts.
ObserveStep observe({String? save, String? session, SemanticView? view}) =>
    ObserveStep(save: save, session: session, view: view);

/// Act: navigate the surface to [url].
ActStep navigate(Uri url, {String? session, String? profile, int? seed}) =>
    ActStep(
      action: NavigateAction(url),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: click at surface coordinates ([x], [y]) — the fallback tier for
/// canvas/games and pixel-grounded agents (ADR 0053). CDP tier today;
/// other tiers refuse loudly.
ActStep clickAt(
  double x,
  double y, {
  String button = 'left',
  int clickCount = 1,
  String? session,
  String? profile,
  int? seed,
  bool returnState = false,
}) =>
    ActStep(
      action: ClickAtAction(x, y, button: button, clickCount: clickCount),
      session: session,
      profile: profile,
      seed: seed,
      returnState: returnState,
    );

/// Act: move the pointer to ([x], [y]) without pressing — hover
/// affordances and drag pre-positioning (ADR 0053).
ActStep moveTo(
  double x,
  double y, {
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(
      action: MoveAction(x, y),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: press at (fromX, fromY), move to (toX, toY), release — drag and
/// drop, sliders, canvas gestures (ADR 0053). Under a behavior profile
/// the whole carried path humanizes.
ActStep dragTo(
  double fromX,
  double fromY,
  double toX,
  double toY, {
  String button = 'left',
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(
      action: DragAction(fromX, fromY, toX, toY, button: button),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: click an element by [css], [role], or accessible [name].
/// [returnState] attaches the post-action state render to the result
/// (the act loop's closing read in one round trip).
ActStep click({
  String? css,
  String? role,
  String? name,
  String? session,
  String? profile,
  int? seed,
  bool returnState = false,
}) =>
    ActStep(
      action: ClickAction(css: css, role: role, name: name),
      session: session,
      profile: profile,
      seed: seed,
      returnState: returnState,
    );

/// Act: focus [css] (or the current caret) and type [text].
ActStep typeText(
  String text, {
  String? css,
  bool submit = false,
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(
      action: TypeAction(text, css: css, submit: submit),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: press a named key.
ActStep keyPress(String key, {String? session, String? profile, int? seed}) =>
    ActStep(
      action: KeyPressAction(key),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: scroll by logical pixels.
ActStep scrollBy({
  String direction = 'down',
  double? distance,
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(
      action: ScrollAction(direction: direction, distance: distance),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act: evaluate a read-only expression in the live surface.
ActStep evaluateExpr(
  String expression, {
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(action: EvaluateAction(expression), session: session, profile: profile);

/// Act: invoke a named surface action from the driver's action catalog.
ActStep invokeAction(
  String name, {
  Map<String, Object?> args = const {},
  String? session,
  String? profile,
  int? seed,
}) =>
    ActStep(
      action: InvokeAction(name, args: args),
      session: session,
      profile: profile,
      seed: seed,
    );

/// Act through an app intent (ADR 0038): the plan's intent registry
/// resolves the hint; runtime [args] carry the operands.
IntentStep intent(
  String app,
  String name, {
  Map<String, Object?> args = const {},
  String? session,
  String? profile,
  int? seed,
}) =>
    IntentStep(
      app: app,
      name: name,
      args: args,
      session: session,
      profile: profile,
      seed: seed,
    );

/// Verify: assert post-conditions against one fresh snapshot.
VerifyStep verifyThat(
  List<VerifyCheck> checks, {
  String? session,
  bool soft = false,
}) =>
    VerifyStep(checks: checks, session: session, continueOnFailure: soft);

/// Wait: poll the checks until they hold or [timeout] elapses — the
/// auto-wait form of [verifyThat].
WaitStep waitFor(
  List<VerifyCheck> checks, {
  Duration timeout = const Duration(seconds: 10),
  Duration poll = const Duration(milliseconds: 250),
  String? session,
  bool soft = false,
}) =>
    WaitStep(
      checks: checks,
      timeout: timeout,
      pollInterval: poll,
      session: session,
      continueOnFailure: soft,
    );

/// Screenshot: capture one PNG frame to [out].
ScreenshotStep shot(String out, {String? session}) =>
    ScreenshotStep(out: out, session: session);

/// Returns [step] marked continue-on-failure: a failure is recorded and
/// the scenario proceeds.
PlanStep soft(PlanStep step) =>
    step.withCommon(session: step.session, continueOnFailure: true);

/// Rebinds every step in [steps] to [session] (multi-session scenarios).
List<PlanStep> onSession(String session, Iterable<PlanStep> steps) => [
  for (final step in steps)
    step.withCommon(session: session, continueOnFailure: step.continueOnFailure),
];

/// Scope a step tree through [view] (ADR 0052): the scope opens with an
/// observation rendered through the view, the [steps] run, and the
/// closing observation's delta is the scope's evidence. Composition
/// nests the view tree AND the call tree; scopes nest.
ScopeStep scope(
  SemanticView view,
  List<PlanStep> steps, {
  String? session,
  bool soft = false,
}) => ScopeStep(
  view: view,
  steps: steps,
  session: session,
  continueOnFailure: soft,
);

// — Checks ———————————————————————————————————————————————————————————————

/// A node with [role] and/or accessible [name]/[nameContains] exists.
ExistsCheck exists({String? role, String? name, String? nameContains}) =>
    ExistsCheck(
      locator: CheckLocator(role: role, name: name, nameContains: nameContains),
    );

/// No node with [role] and/or accessible [name]/[nameContains] exists.
AbsentCheck absent({String? role, String? name, String? nameContains}) =>
    AbsentCheck(
      locator: CheckLocator(role: role, name: name, nameContains: nameContains),
    );

/// A node matching the locator carries a value satisfying the comparator.
ValueCheck value(
  String? name, {
  String? role,
  String? nameContains,
  String? equals,
  String? contains,
}) =>
    ValueCheck(
      locator: CheckLocator(role: role, name: name, nameContains: nameContains),
      equals: equals,
      contains: contains,
    );

/// The surface URL contains [fragment] (transports that expose a URL).
UrlContainsCheck urlContains(String fragment) => UrlContainsCheck(fragment);

// — Composition ——————————————————————————————————————————————————————————

/// Declares a scenario; [extend] names a parent whose steps run first.
Scenario scenario(
  String name, {
  List<PlanStep> steps = const [],
  String? extend,
}) =>
    Scenario(name: name, parent: extend, steps: List.of(steps));

/// Declares an attach-only CDP session binding.
SessionBinding cdp(String name, {Uri? uri, String? handle}) =>
    SessionBinding(
      name: name,
      transport: AutomationTransport.cdp,
      uri: uri,
      handle: handle,
    );


// — First-class code (the oka posture) ———————————————————————————————————

/// A step whose body is Dart: terminal commands, oka calls, arbitrary
/// checks — everything a document cannot express. Dart-only by design:
/// snapshots ([planDocument]) refuse to carry code steps.
CodeStep code(
  Future<Object?> Function(CodeStepContext context) run, {
  String? label,
  String? session,
  bool soft = false,
}) =>
    CodeStep(run: run, label: label, session: session, continueOnFailure: soft);

/// A [code] step running a terminal command; non-zero exit fails the
/// step (unless [allowNonZeroExit]) with the output tails attached.
CodeStep exec(
  String executable, {
  List<String> args = const [],
  String? workingDirectory,
  Map<String, String> environment = const {},
  bool allowNonZeroExit = false,
  bool runInShell = false,
  String? session,
  bool soft = false,
}) =>
    code(
      (context) async {
        final result = await Process.run(
          executable,
          args,
          workingDirectory: workingDirectory,
          environment: environment,
          runInShell: runInShell,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        final ok = result.exitCode == 0 || allowNonZeroExit;
        final detail = {
          'command': '$executable ${args.join(' ')}'.trim(),
          'exitCode': result.exitCode,
          'stdoutTail': _tail(result.stdout as String),
          'stderrTail': _tail(result.stderr as String),
        };
        if (!ok) {
          throw CodeStepException(
            '$executable',
            'command "$executable ${args.join(' ')}" exited '
                '${result.exitCode}',
            details: detail,
          );
        }
        return detail;
      },
      label: '$executable ${args.join(' ')}'.trim(),
      session: session,
      soft: soft,
    );

String _tail(String text, [int limit = 800]) {
  final trimmed = text.trim();
  return trimmed.length <= limit ? trimmed : '…${trimmed.substring(trimmed.length - limit)}';
}

/// Record the frame stream for [duration] into [out] (the screencast
/// plane; CDP tier).
RecordStep record(
  Duration duration,
  String out, {
  String base = 'frames',
  String? session,
  bool soft = false,
}) =>
    RecordStep(
      duration: duration,
      out: out,
      base: base,
      session: session,
      continueOnFailure: soft,
    );

// — Snapshot export ———————————————————————————————————————————————————————

/// The plan's snapshot (wire) form — for agents, MCP tools, and keeping
/// existing scattered configs in sync. Dart is the source of truth; a
/// snapshot carrying Dart-only [CodeStep]s is refused loudly (the code
/// cannot cross the boundary).
Map<String, Object?> planDocument(AutomationPlan plan) {
  final codeSteps = [
    for (final scenario in plan.scenarios.values)
      for (final step in scenario.steps)
        if (step is CodeStep)
          '${scenario.name}/${step.label ?? 'unlabeled code step'}',
  ];
  if (codeSteps.isNotEmpty) {
    throw SpecViolationException([
      'plan contains Dart-only code steps and cannot be exported to a '
      'snapshot: ${codeSteps.join(', ')}',
    ]);
  }
  return plan.toJson();
}

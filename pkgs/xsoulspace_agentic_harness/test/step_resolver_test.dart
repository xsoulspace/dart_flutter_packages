// ignore_for_file: lines_longer_than_80_chars

/// The STEP RESOLVER gate — ADR 0009 Amendment (2026-09-08): mechanical
/// resolution lives IN the frontier (repair (a)). Gates:
///
/// - the wave rows' prompt classes resolve mechanically (md section,
///   yaml keypath, trusted symbol+executable — the measured 100%
///   mechanically-resolvable surface) at ZERO model tokens;
/// - resolution is TOTAL or bounces with REAL candidate ids (the
///   locate-hints law) — never a guess, never an invented id;
/// - no-pattern sentences project TIER-ROUTED (named data — the (b)
///   property; the routing machinery stays named-not-built);
/// - the zero-token mechanical actor works CONSENTED ready steps
///   (deny-by-default) and records outcomes as step data.
library;

import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/data_models/data_models.dart'
    show StepAction, StepStatus;
import 'package:xsoulspace_agentic_harness/src/decisions/step_resolver.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/capability_nodes.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_agentic_harness/src/narrative/narrative.dart'
    show Step, StepLifecycle;
import 'package:xsoulspace_agentic_harness/src/tooling/mechanical_actor.dart';

World _treeWorld() {
  final world = World()..addPlugin(AgentPlugin());
  // md file + sections (the wave_md row's fixture shape).
  addMeaningNode(
    world,
    kind: 'file',
    label: 'docs/README.md',
    id: 'f_docs_README.md',
  );
  addMeaningNode(
    world,
    kind: 'section',
    label: 'Usage',
    id: 'f_docs_README.md_2',
  );
  addMeaningNode(
    world,
    kind: 'section',
    label: 'Install',
    id: 'f_docs_README.md_3',
  );
  // yaml file + keys (the wave_yaml row's fixture shape).
  addMeaningNode(world, kind: 'file', label: 'config.yaml', id: 'f_config.yaml');
  addMeaningNode(
    world,
    kind: 'key',
    label: 'retry.max_attempts',
    id: 'f_config.yaml_retry_max_attempts',
  );
  addMeaningNode(
    world,
    kind: 'key',
    label: 'retry.backoff_ms',
    id: 'f_config.yaml_retry_backoff_ms',
  );
  // dart file + symbol (the wave_trusted row's fixture shape).
  addMeaningNode(
    world,
    kind: 'file',
    label: 'lib/geometry.dart',
    id: 'f_lib_geometry.dart',
  );
  addMeaningNode(
    world,
    kind: 'symbol',
    label: 'area',
    id: 'sym_lib_geometry.dart_area',
  );
  reconcileCapabilityNodes(world, const [
    CapabilityEntry(
      executableId: 'dart/author_area',
      kind: 'authored_body',
      params: ['symbolId'],
    ),
  ]);
  return world;
}

void main() {
  group('resolveTaskPrompt — the wave-row prompt classes resolve at zero '
      'tokens', () {
    test('md row: the section prompt resolves to the replace_section move',
        () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'Replace the Usage section of docs/README.md with EXACTLY this '
            'body (the host preserves the `## Usage` heading line itself): '
            'Call `dart run bin/app.dart --serve` to start the gateway.\n'
            'Drive it as ONE edit_symbol call. Never read or write files.',
      );
      expect(r, isA<ReadyStep>(), reason: '${(r as dynamic).runtimeType}');
      final ready = r as ReadyStep;
      expect(ready.source, 'prompt_named_anchor');
      expect(ready.args['action'], 'replace_section');
      expect(ready.args['symbolId'], 'f_docs_README.md_2');
      final directive = readyStepDirective(ready);
      expect(directive, startsWith('READY MOVE'));
      expect(directive, contains('"symbolId":"f_docs_README.md_2"'));
    });

    test('yaml row: the keypath prompt resolves to the replace_value move',
        () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'Set retry.max_attempts to 5 in config.yaml (its inline comment '
            'must survive). Drive it as ONE edit_symbol call with body "5".',
      );
      expect(r, isA<ReadyStep>(), reason: '${(r as dynamic).runtimeType}');
      final ready = r as ReadyStep;
      expect(ready.args['action'], 'replace_value');
      expect(ready.args['symbolId'], 'f_config.yaml_retry_max_attempts');
    });

    test('trusted row: the symbol+executable prompt resolves to the '
        'consented apply_executable move', () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'The function `area` in lib/geometry.dart is bugged: it returns 0 '
            'instead of w*h. The trusted-author project pack carries the '
            'CONSENTED executable `dart/author_area` — the human already '
            'allowed the pack write, so you need ONLY the ids.',
      );
      expect(r, isA<ReadyStep>(), reason: '${(r as dynamic).runtimeType}');
      final ready = r as ReadyStep;
      expect(ready.args['action'], 'apply_executable');
      expect(ready.args['executableId'], 'dart/author_area');
      expect(ready.args['symbolId'], 'sym_lib_geometry.dart_area');
    });
  });

  group('resolveTaskPrompt — TOTAL or bounce (never a guess)', () {
    test('a missing anchor bounces with the REAL sibling candidates', () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'Replace the Changelog section of docs/README.md with the new '
            'text. Never read files.',
      );
      expect(r, isA<AmbiguousStep>());
      final ambiguous = r as AmbiguousStep;
      expect(ambiguous.reason, 'anchor_not_in_tree');
      expect(ambiguous.candidates, contains('f_docs_README.md_2'));
      expect(ambiguous.candidates, contains('f_docs_README.md_3'));
      final directive = ambiguousStepDirective(ambiguous);
      expect(directive, contains('Do NOT invent an id'));
    });

    test('an unknown executable bounces with the pack inventory', () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'The function `area` in lib/geometry.dart is bugged. The pack '
            'carries the executable `dart/does_not_exist`.',
      );
      expect(r, isA<AmbiguousStep>());
      expect((r as AmbiguousStep).reason, 'no_executable_for_class');
      expect((r as AmbiguousStep).candidates, contains('dart/author_area'));
    });

    test('a sentence with no mechanical pattern projects TIER-ROUTED '
        '(named data — repair (b) stays named-not-built)', () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'Please improve the overall developer experience of this package.',
      );
      expect(r, isA<TierRoutedStep>());
      expect((r as TierRoutedStep).reason, isNotEmpty);
    });
  });

  group('spawnResolvedStep — the frontier carries the resolved action', () {
    test('the step lands with the resolved StepAction + classification',
        () {
      final world = _treeWorld();
      final r = resolveTaskPrompt(
        world,
        'Set retry.max_attempts to 5 in config.yaml. One call.',
      );
      final stepEntity = spawnResolvedStep(
        world,
        r as ReadyStep,
        claim: 'config key set to 5',
      );
      final we = world.getEntity(stepEntity).$1;
      final step = we.get<Step>();
      expect(step, isNotNull);
      expect(step!.status, StepLifecycle.open);
      final action = we.get<StepAction>();
      expect(action, isNotNull);
      expect(action!.toolName, 'edit_symbol');
      expect(action.arguments['symbolId'], 'f_config.yaml_retry_max_attempts');
      expect(action.outcome?['source'], 'prompt_named_anchor');
      expect(we.get<StepStatus>()?.value, 'open');
    });
  });

  group('executeReadyStep — the zero-token mechanical actor', () {
    test('a CONSENTED ready step executes through the injected executor '
        'and the outcome flips the step', () async {
      final world = _treeWorld();
      final executed = <Map<String, dynamic>>[];
      final stepEntity = spawnResolvedStep(
        world,
        ReadyStep(
          {
            'action': 'replace_value',
            'symbolId': 'f_config.yaml_retry_max_attempts',
          },
          toolName: 'edit_symbol',
          source: 'prompt_named_anchor',
        ),
        claim: 'config key set to 5',
      );
      final outcome = await executeReadyStep(
        editExecutor: (args) async {
          executed.add(args);
          return '{"ok": true, "applied": true}';
        },
        args: const {
          'action': 'replace_value',
          'symbolId': 'f_config.yaml_retry_max_attempts',
        },
        consent: (args) => true,
      );
      expect(outcome['ok'], isTrue);
      expect(executed.single['symbolId'], 'f_config.yaml_retry_max_attempts');
      recordStepOutcome(world, stepEntity, outcome);
      final we = world.getEntity(stepEntity).$1;
      expect(we.get<Step>()!.status, StepLifecycle.verified);
      expect(we.get<StepStatus>()?.value, 'verified');
      expect(we.get<StepAction>()!.outcome?['ok'], isTrue);
    });

    test('DENY-BY-DEFAULT: without consent the step never executes and '
        'stays open (the model actor owns it)', () async {
      final world = _treeWorld();
      var executorCalls = 0;
      final stepEntity = spawnResolvedStep(
        world,
        ReadyStep(
          const {'action': 'replace_section', 'symbolId': 'f_docs_README.md_2'},
          toolName: 'edit_symbol',
          source: 'prompt_named_anchor',
        ),
        claim: 'section replacement',
      );
      final outcome = await executeReadyStep(
        editExecutor: (args) async {
          executorCalls++;
          return '{"ok": true}';
        },
        args: const {
          'action': 'replace_section',
          'symbolId': 'f_docs_README.md_2',
        },
        consent: (args) => false,
      );
      expect(executorCalls, 0, reason: 'no consent → no execution');
      expect(outcome['ok'], isFalse);
      expect(outcome['code'], 'mechanical_actor_unconsented');
      expect(world.getEntity(stepEntity).$1.get<Step>()!.status,
          StepLifecycle.open);
    });

    test('a failed execution records the named failure class as data',
        () async {
      final world = _treeWorld();
      final stepEntity = spawnResolvedStep(
        world,
        ReadyStep(
          const {'action': 'replace_value', 'symbolId': 'f_config.yaml_retry_backoff_ms'},
          toolName: 'edit_symbol',
          source: 'prompt_named_anchor',
        ),
        claim: 'backoff change',
      );
      final outcome = await executeReadyStep(
        editExecutor: (args) async =>
            '{"ok": false, "error": "byte fence drifted", "failureClass": '
            '"span_stale"}',
        args: const {
          'action': 'replace_value',
          'symbolId': 'f_config.yaml_retry_backoff_ms',
        },
        consent: (args) => true,
      );
      recordStepOutcome(world, stepEntity, outcome);
      final we = world.getEntity(stepEntity).$1;
      expect(we.get<Step>()!.status, StepLifecycle.failed);
      expect(we.get<StepAction>()!.outcome?['failureClass'], 'span_stale');
    });
  });
}

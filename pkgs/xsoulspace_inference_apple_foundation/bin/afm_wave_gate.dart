// ignore_for_file: avoid_print, lines_longer_as_80_chars

/// AFM WAVE GATE — the P1 REAL-model gate driver for the 2026-09-06
/// surface wave tiers (PLAN §NOW P1; the R7e pattern, one driver, FOUR
/// rows — one per new tier):
///
/// 1. `task_grammar` — a covered member with a seeded off-by-one + a
///    project pack whose op-chain repairs it; the task sentence is in the
///    MECHANICAL grammar (`fix <Symbol> in <file>.`), so the host
///    pre-pass (`taskGrammarPrepass` in the host runner) emits the ready
///    `apply_executable` decision at ZERO model tokens. Asserts pass@1
///    and that the fix landed (`dart test` green).
/// 2. `trusted_author` — the jail pack carries an `authored_body` entry +
///    a consent plan (`pack_write` verb); the model supplies ONLY
///    {executableId, symbolId}; the CONSENTED body lands at zero authored
///    tokens. The driver answers BOTH permission surfaces in-process:
///    the sync `packConsent` plan (the pack load loop is synchronous —
///    the async ACP round-trip cannot reach it) and the per-move
///    `editApprover` (the daemon routes this to session/
///    request_permission with a 45 s deny-on-timeout; in-process the
///    driver IS the permission client and answers immediately).
/// 3. `md` — a README fixture; the sentence drives ONE unified
///    `edit_symbol` move ({action: replace_section, symbolId: <the
///    section node id from the zoom cut>, body}); the host splices
///    byte-precisely and the `zero_broken_links` oracle auto-reverts any
///    broken link.
/// 4. `yaml` — a commented config.yaml fixture; ONE unified `edit_symbol`
///    move ({action: replace_value, symbolId: <the key node id>, body:
///    "5"}); the byte fence keeps comments/siblings byte-identical and
///    the `parse_semantic_diff` oracle demands the diff be EXACTLY the
///    intended change.
///
/// In-process (not stdio — the R7e app path): the REAL on-device Apple
/// Foundation Model drives `runCodingAgentOnce` (package:
/// xsoulspace_agentic_host) over the meaning profile. Fresh jail per
/// run, pass@1 per row (`maxGoalAttempts: 1`), and the row PUBLISHES
/// even on FAIL with its failure class (the standing published-row
/// discipline; results_r7.md §"R7 production #6").
///
/// ```sh
/// dart run bin/afm_wave_gate.dart                 # all 4 rows, pass@1
/// dart run bin/afm_wave_gate.dart --runs 3        # n=3 per row
/// dart run bin/afm_wave_gate.dart --row md        # a single row
/// dart run bin/afm_wave_gate.dart --dry           # fixture-plumbing
///                                                 # validation, NO model
/// ```
///
/// JSON summary lines go to stdout (row, verdict, decisions,
/// tool_rounds, tokens via Situation.tokensUsed, wall_ms). Exit codes:
/// 0 = all rows passed, 1 = any row failed, 2 = AFM unavailable. `--dry`
/// exits 0 only when every jail's plumbing validates against the REAL
/// materializers (no model, no dylib — sandbox-safe).
///
/// SURFACE NOTE (ADR 0034/0035 — the one-verb surface): ALL rows drive
/// `edit_symbol` — the unified edit verb ({action, symbolId, body?,
/// anchor?}); per-class actions (replace_section / replace_value / …)
/// are registry data taught by bounces, never separate verbs. A row that
/// hardcodes a dead verb or a format literal in its prompt is a drift
/// bug — the dry validators grep for this (the §5 format-literal gate).
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire;
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerSpec;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot;
import 'package:xsoulspace_agentic_harness/src/decisions/step_resolver.dart'
    show AmbiguousStep, ReadyStep, resolveTaskPrompt;
import 'package:xsoulspace_agentic_harness/src/tools/task_grammar.dart'
    show TaskGrammarMatch, executableDecisionForTask, parseTaskSentence;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show
        AgentPlugin,
        DefaultGenerationHandler,
        ModelRouter,
        World,
        WorldPluginX,
        classifyWaveLog;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart'
    show
        CodingAgentTask,
        formatRunLog,
        meaningProfileSystemPrompt,
        resolveRunsDirectory,
        runCodingAgentOnce,
        wireSigintDump,
        writeRunLog;
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart'
    show
        EditPackCapture,
        KeypathMaterializer,
        MdMaterializer,
        keypathParse,
        repoEtlTool,
        semanticDiff;
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart'
    show AppleFoundationNativeClient, appleFoundationBinding;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show DefaultModelNames, Model, ModelId;

// ---------------------------------------------------------------------------
// Row 1 — task-grammar: the R7e-proven off-by-one fixture, now fed through
// the mechanical SENTENCE (the host pre-pass, not a hand-taught call).
// ---------------------------------------------------------------------------

const _grammarExecutableId = 'dart/fix_inclusive_bound';

const _grammarPackJson = {
  'packId': 'edit_capture',
  'executables': [
    {
      'id': _grammarExecutableId,
      'kind': 'replace_member_body',
      'params': ['symbolId'],
      'verification': ['analyze', 'test'],
      'scope': 'lexical',
      'description':
          'Fix an off-by-one inclusive bound: the member body becomes the '
          'inclusive form (i <= n, i.e. !(i > n)) over its declared '
          'params (i, n).',
      'opChain': [
        {'label': 'load_arg', 'a': 'i'},
        {'label': 'load_arg', 'a': 'n'},
        {'label': 'gt'},
        {'label': 'not'},
        {'label': 'return'},
      ],
    },
  ],
};

/// The FIRST line is the mechanical sentence — `parseTaskSentence` reads
/// the prompt's start; everything after is teaching boilerplate.
const _grammarPrompt =
    'Fix inBounds in lib/loop.dart. The sentence above is in the mechanical '
    'task grammar: the HOST pre-pass (zero tokens, zero decisions) already '
    'resolved the ready apply_executable decision and appended it below. '
    'Carry it VERBATIM as ONE edit_symbol call (symbolId is a TOP-LEVEL '
    'arg; executableParams is {} for this executable), then run '
    'dart analyze. Never read or write files; do not re-scan and do not '
    'rename.';

Future<Directory> _seedGrammarJail(int run, bool pubGet) async {
  final jail = await Directory.systemTemp.createTemp('afm_wave_grammar$run\_');
  File('${jail.path}/pubspec.yaml').writeAsStringSync(
    'name: wave_grammar\n'
    'environment:\n  sdk: ^3.0.0\n'
    'dev_dependencies:\n  test: any\n',
  );
  File('${jail.path}/lib/loop.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
bool inBounds(int i, int n) {
  return i < n;
}
''');
  File('${jail.path}/test/loop_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:wave_grammar/loop.dart';

void main() {
  test('inBounds is inclusive', () {
    expect(inBounds(3, 3), isTrue);
  });
  test('inBounds rejects beyond', () {
    expect(inBounds(5, 4), isFalse);
  });
}
''');
  _writePack(jail, _grammarPackJson);
  if (pubGet) await _pubGet(jail);
  return jail;
}

CodingAgentTask _grammarTask() => CodingAgentTask(
  id: 'wave_task_grammar',
  prompt: _grammarPrompt,
  meaningProfile: true,
  systemPrompt: meaningProfileSystemPrompt,
  runCommand: const ['dart', 'test'],
  checkers: [
    CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
  ],
  repairHint:
      'The exact move that fixes this task: edit_symbol with the READY '
      'decision the host pre-pass appended to your goal (action '
      'apply_executable, executableId "$_grammarExecutableId", symbolId '
      'the TOP-LEVEL id of inBounds, executableParams {}). If a move '
      'bounced, the bounce text names the exact repair. Do not rename '
      'and do not re-scan.',
);

// ---------------------------------------------------------------------------
// Row 2 — trusted-author: the consented authored_body pack entry. The
// model supplies ONLY the ids; the CONSENT is host-side (the plan below).
// ---------------------------------------------------------------------------

const _trustedExecutableId = 'dart/author_area';
const _trustedAuthoredBody = 'return w * h; // trusted-authored';
// code_etl stableId: sym_<file with / → _>_<name> — the row's zoom must
// resolve `area` to sym_lib_geometry.dart_area.
const _trustedPackJson = {
  'packId': 'edit_capture',
  'executables': [
    {
      'id': _trustedExecutableId,
      'kind': 'authored_body',
      'params': ['symbolId'],
      'verification': ['analyze', 'test'],
      'scope': 'lexical',
      'description': 'trusted-author area body (consented at pack-write)',
      'authoredBody': _trustedAuthoredBody,
    },
  ],
};

/// Prose start (deliberately NOT the mechanical grammar — `The` is no
/// verb): this row exercises the CONSENT + permission path, not the
/// pre-pass.
const _trustedPrompt =
    'The function `area` in lib/geometry.dart is bugged: it returns 0 '
    'instead of w*h (area(2, 3) must be 6). The trusted-author project '
    'pack carries the CONSENTED executable `$_trustedExecutableId` — the '
    'human already allowed the pack write, so you need ONLY the ids. '
    'Flow: repo_etl scan (once) → meaning_program with read ops to find '
    'the id — [{"op": "locate", "query": "area"}] then '
    '[{"op": "zoom", "focusId": <the id from the locate ROWS>}] — the '
    'locate result\'s rows CARRY the exact ids (never invent one) → ONE '
    'edit_symbol call of EXACTLY this shape: {"action": '
    '"apply_executable", "executableId": "$_trustedExecutableId", '
    '"symbolId": <the TOP-LEVEL symbol id of area from the zoom cut>, '
    '"executableParams": {}} → dart analyze. Never read or write files; '
    'do not re-scan and do not rename.';

Future<Directory> _seedTrustedJail(int run, bool pubGet) async {
  final jail = await Directory.systemTemp.createTemp('afm_wave_trust$run\_');
  File('${jail.path}/pubspec.yaml').writeAsStringSync(
    'name: wave_trusted\n'
    'environment:\n  sdk: ^3.0.0\n'
    'dev_dependencies:\n  test: any\n',
  );
  File('${jail.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
int area(int w, int h) {
  return 0;
}
''');
  File('${jail.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:wave_trusted/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
}
''');
  _writePack(jail, _trustedPackJson);
  if (pubGet) await _pubGet(jail);
  return jail;
}

CodingAgentTask _trustedTask() => CodingAgentTask(
  id: 'wave_trusted_author',
  prompt: _trustedPrompt,
  meaningProfile: true,
  systemPrompt: meaningProfileSystemPrompt,
  runCommand: const ['dart', 'test'],
  checkers: [
    CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
  ],
  repairHint:
      'The exact move that fixes this task: edit_symbol with '
      '{"action": "apply_executable", "executableId": '
      '"$_trustedExecutableId", "symbolId": <TOP-LEVEL id of area from '
      'the locate ROWS / zoom cut>, "executableParams": {}} — the body '
      'is CONSENTED pack data; you never author it. If a move bounced, '
      'the bounce text names the exact repair. Do not rename and do not '
      're-scan.',
);

/// The in-process consent plan (the ACP `ConsentPlan` shape, driver-side):
/// a session grant over the project pack path (`pack_write` verb,
/// bounded uses) with the same audited answers the daemon logs.
class _ConsentPlan {
  _ConsentPlan({this.verbs = const {'pack_write'}, this.maxUses = 2});

  /// The in-process grant covers exactly the project pack —
  /// `EditPackCapture.file` is `.dart_tool/harnessd/edit_pack.json` by
  /// construction; the sync `packConsent` callback carries no path, so
  /// the grant is scoped by construction (the driver only ever consents
  /// over this pack).

  final Set<String> verbs;
  final int maxUses;
  int uses = 0;
  final List<String> audit = [];

  /// The `packConsent` answer (SYNC — the pack load loop cannot await an
  /// ACP round-trip). Every answer lands in the audit log.
  bool allow(EditExecutableWire wire, String authoredBodyDiff) {
    if (!verbs.contains('pack_write') || uses >= maxUses) {
      audit.add(
        'pack_write REFUSED for ${wire.id} '
        '(uses $uses/$maxUses, verbs ${verbs.join(", ")})',
      );
      return false;
    }
    uses++;
    audit.add(
      'plan-allowed pack_write: ${wire.id} ($uses/$maxUses) — '
      'diff: ${authoredBodyDiff.split('\n').length} lines',
    );
    return true;
  }
}

// ---------------------------------------------------------------------------
// Row 3 — md: the README fixture + the exact replace_section body. The
// body is DATA in the prompt (evidence tier); the host splices and the
// zero_broken_links oracle grades. config.yaml/api.md exist so every
// link in the new body resolves.
// ---------------------------------------------------------------------------

const _mdRel = 'docs/README.md';

const _mdOriginal = '''
# Wave Doc

Package overview with a [Usage](#usage) and an [Install](#install)
section; the endpoint details live in [api.md](api.md).

## Usage

Run `dart run bin/app.dart` to start the gateway. Read the
[Install](#install) notes first.

## Install

Fetch the Dart SDK from https://dart.dev, then return to [Usage](#usage).
''';

const _mdBody =
    'Call `dart run bin/app.dart --serve` to start the gateway. '
    'Configuration keys are documented in [config.yaml](config.yaml); '
    'endpoint details are in [api.md](api.md).\n';

const _mdPrompt =
    'Replace the Usage section of docs/README.md with EXACTLY this body '
    '(the host preserves the `## Usage` heading line itself): '
    '$_mdBody'
    'Drive it as ONE edit_symbol call: {"action": "replace_section", '
    '"symbolId": <the Usage section\'s node id from the zoom cut>, '
    '"body": <the prose above>}. Flow: repo_etl scan (once) → '
    'meaning_program read ops ([{"op": "locate", "query": "README"}]) — '
    'the rows CARRY the section node ids (never invent one) — then the '
    'edit_symbol call. The host splices '
    'byte-precisely and runs the zero-broken-links oracle (a broken link '
    'auto-reverts). Never read or write files.';

Future<Directory> _seedMdJail(int run, bool pubGet) async {
  final jail = await Directory.systemTemp.createTemp('afm_wave_md$run\_');
  File('${jail.path}/pubspec.yaml').writeAsStringSync(
    'name: wave_md\n'
    'environment:\n  sdk: ^3.0.0\n'
    'dev_dependencies:\n  test: any\n',
  );
  File('${jail.path}/$_mdRel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_mdOriginal);
  File('${jail.path}/docs/api.md')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('# API\n\nGET /health returns ok.\n');
  // Link target of the NEW Usage body — relative to docs/, like api.md.
  File('${jail.path}/docs/config.yaml').writeAsStringSync('# placeholder\n');
  // Host-authored oracle (the model never writes test code): the
  // workspace convention (`dart test`) grades the splice.
  File('${jail.path}/test/docs_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the Usage section was replaced, links intact', () {
    final readme = File('docs/README.md').readAsStringSync();
    expect(readme, contains('## Usage'));
    expect(readme, contains('--serve'));
    expect(readme, contains('config.yaml'));
    expect(readme, contains('api.md'));
    expect(readme.contains('to start the gateway. Read the'), isFalse);
  });
}
''');
  if (pubGet) await _pubGet(jail);
  return jail;
}

CodingAgentTask _mdTask() => CodingAgentTask(
  id: 'wave_md_section',
  prompt: _mdPrompt,
  meaningProfile: true,
  systemPrompt: meaningProfileSystemPrompt,
  runCommand: const ['dart', 'test'],
  checkers: [
    CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
    CheckerSpec(type: 'contains', path: _mdRel, value: '--serve'),
    CheckerSpec(
      type: 'not_contains',
      path: _mdRel,
      value: 'to start the gateway. Read the',
    ),
    CheckerSpec(type: 'contains', path: _mdRel, value: 'config.yaml'),
  ],
  repairHint:
      'The exact move that fixes this task: edit_symbol with '
      '{"action": "replace_section", "symbolId": <the Usage section\'s '
      'node id from the zoom cut>, "body": <the body from the task '
      'prompt>}. If the action bounced, the bounce names the legal '
      'actions for THAT node — pick from them. Do not re-scan and do '
      'not write files.',
);

// ---------------------------------------------------------------------------
// Row 4 — yaml: the commented config fixture + the exact replace_value
// move. The byte fence keeps comments/siblings identical; the
// parse_semantic_diff oracle demands the diff be EXACTLY the change.
// ---------------------------------------------------------------------------

const _yamlRel = 'config.yaml';

const _yamlOriginal = '''
# service settings — do not rename keys
service:
  name: gateway
  port: 8080

# retry policy (tuned 2026-09)
retry:
  max_attempts: 3   # keep small on-device
  backoff_ms: 50

features:
  - dark_mode
  - telemetry
''';

const _yamlPrompt =
    'Set retry.max_attempts to 5 in config.yaml (its inline comment must '
    'survive). Drive it as ONE edit_symbol call: {"action": '
    '"replace_value", "symbolId": <the retry.max_attempts key node id '
    'from the zoom cut>, "body": "5"}. Flow: repo_etl scan (once) → '
    'meaning_program read ops ([{"op": "locate", "query": '
    '"max_attempts"}]) — the rows CARRY the key node ids and their '
    'keypaths (never invent one) — then the edit_symbol call. The host '
    'splices byte-precisely (comments and siblings stay untouched) and '
    'runs the parse-semantic-diff oracle (any other change '
    'auto-reverts). Never read or write files.';

Future<Directory> _seedYamlJail(int run, bool pubGet) async {
  final jail = await Directory.systemTemp.createTemp('afm_wave_yaml$run\_');
  File('${jail.path}/pubspec.yaml').writeAsStringSync(
    'name: wave_yaml\n'
    'environment:\n  sdk: ^3.0.0\n'
    'dev_dependencies:\n  test: any\n',
  );
  File('${jail.path}/$_yamlRel').writeAsStringSync(_yamlOriginal);
  // Host-authored oracle: the convention grades content, comments and
  // siblings (the materializer's own byte fence + parse-semantic-diff
  // oracle already enforced precision AT APPLY time).
  File('${jail.path}/test/config_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('retry.max_attempts is 5; comments and siblings survived', () {
    final cfg = File('config.yaml').readAsStringSync();
    expect(cfg, contains('max_attempts: 5'));
    expect(cfg, contains('# service settings — do not rename keys'));
    expect(cfg, contains('# retry policy (tuned 2026-09)'));
    expect(cfg, contains('backoff_ms: 50'));
    expect(cfg, contains('- telemetry'));
    expect(cfg.contains('max_attempts: 3'), isFalse);
  });
}
''');
  if (pubGet) await _pubGet(jail);
  return jail;
}

CodingAgentTask _yamlTask() => CodingAgentTask(
  id: 'wave_yaml_keypath',
  prompt: _yamlPrompt,
  meaningProfile: true,
  systemPrompt: meaningProfileSystemPrompt,
  runCommand: const ['dart', 'test'],
  checkers: [
    CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
    CheckerSpec(type: 'contains', path: _yamlRel, value: 'max_attempts: 5'),
    CheckerSpec(
      type: 'contains',
      path: _yamlRel,
      value: '# retry policy (tuned 2026-09)',
    ),
    CheckerSpec(
      type: 'not_contains',
      path: _yamlRel,
      value: 'max_attempts: 3',
    ),
  ],
  repairHint:
      'The exact move that fixes this task: edit_symbol with '
      '{"action": "replace_value", "symbolId": <the retry.max_attempts '
      'key node id from the zoom cut>, "body": "5"}. If the action '
      'bounced, the bounce names the legal actions for THAT node — pick '
      'from them. Do not re-scan and do not write files.',
);

// ---------------------------------------------------------------------------
// Driver plumbing
// ---------------------------------------------------------------------------

void _writePack(Directory jail, Map<String, Object?> pack) {
  File('${jail.path}/.dart_tool/harnessd/edit_pack.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(pack));
}

Future<void> _pubGet(Directory jail) async {
  final p = await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);
  if (p.exitCode != 0) {
    stderr.writeln('[afm_wave] pub get FAILED in ${jail.path}\n'
        '${p.stdout}${p.stderr}');
  }
}

/// One wave row as data: seeder + task builder + an optional consent-plan
/// factory (row 2 only) + the dry validator.
typedef _JailSeeder = Future<Directory> Function(int run, bool pubGet);

class _WaveRow {
  const _WaveRow({
    required this.name,
    required this.seed,
    required this.task,
    this.consentPlan,
    this.dry,
  });

  final String name;
  final _JailSeeder seed;
  final CodingAgentTask Function() task;

  /// Non-null → the run wires packConsent (the sync consent plan) AND
  /// editApprover (the per-move permission answer) — the trusted-author
  /// row's permission wiring.
  final _ConsentPlan Function()? consentPlan;

  /// Non-null → `--dry` validates this row's fixture plumbing against the
  /// REAL materializers/grammar (no model, no dylib).
  final Future<bool> Function(Directory jail, List<String> problems)? dry;
}

final List<_WaveRow> _rows = [
  _WaveRow(
    name: 'task_grammar',
    seed: _seedGrammarJail,
    task: _grammarTask,
    dry: _dryGrammar,
  ),
  _WaveRow(
    name: 'trusted_author',
    seed: _seedTrustedJail,
    task: _trustedTask,
    consentPlan: _ConsentPlan.new,
    dry: _dryTrusted,
  ),
  _WaveRow(name: 'md', seed: _seedMdJail, task: _mdTask, dry: _dryMd),
  _WaveRow(name: 'yaml', seed: _seedYamlJail, task: _yamlTask, dry: _dryYaml),
];

_WaveRow? _rowByName(String name) {
  for (final r in _rows) {
    if (r.name == name) return r;
  }
  return switch (name) {
    'grammar' || 'task' => _rows[0],
    'trust' || 'trusted' || 'author' => _rows[1],
    'markdown' || 'docs' => _rows[2],
    'config' => _rows[3],
    _ => null,
  };
}

String _summaryLine(Map<String, Object?> row) => jsonEncode(row);

Future<void> main(List<String> args) async {
  var runs = 1;
  var attempts = 1;
  String? rowName;
  var dry = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--runs':
        runs = int.tryParse(args[++i]) ?? 1;
      case '--attempts':
        attempts = int.tryParse(args[++i]) ?? 1;
      case '--row':
        rowName = args[++i];
      case '--dry':
        dry = true;
    }
  }
  final selected = rowName == null
      ? _rows
      : [
          _rowByName(rowName) ??
              (throw StateError(
                'unknown row "$rowName" — known: '
                '${_rows.map((r) => r.name).join(", ")}',
              )),
        ];

  if (dry) {
    exit(await _dryAll(selected) ? 0 : 1);
  }

  // The REAL path: AFM availability FIRST — unavailable is exit 2, never
  // a PASS-less row (engine_unavailable is a classified driver state).
  final binding = appleFoundationBinding();
  final router = binding.binding.buildRouter(model: '', apiKey: null);
  final client = binding.client() ?? AppleFoundationNativeClient();
  await client.load();
  if (router == null || !await client.refreshAvailability()) {
    stderr.writeln(
      'Apple Foundation Model unavailable — the wave rows stay UNTESTED, '
      'never PASS. (Classified failure: engine_unavailable.)',
    );
    exit(2);
  }
  stderr.writeln(
    '[afm_wave] AFM available — pass@$runs per row against the real '
    'on-device model through the meaning-profile surface '
    '(in-run attempts budget: $attempts).',
  );
  // The binding registers the router model under this id.
  final modelId = const ModelId('harnessd');
  if (!router.models.containsKey(modelId)) {
    router.models[modelId] = Model(
      id: modelId,
      name: DefaultModelNames.appleFoundation,
    );
  }

  final runsDir = resolveRunsDirectory();
  final rowLines = <String>[];
  var allPassed = true;
  for (final row in selected) {
    final verdict = await _runRow(row, runs, attempts, router, modelId, runsDir);
    rowLines.add(_summaryLine(verdict));
    if (verdict['verdict'] != 'PASS') allPassed = false;
  }
  writeRunLog(runsDir, 'afm_wave_summary.log', '${rowLines.join('\n')}\n');
  stdout.writeln(rowLines.join('\n'));
  exit(allPassed ? 0 : 1);
}

Future<Map<String, Object?>> _runRow(
  _WaveRow row,
  int runs,
  int attempts,
  ModelRouter router,
  ModelId modelId,
  Directory runsDir,
) async {
  final runDetails = <String>[];
  var passed = 0;
  final rowSw = Stopwatch()..start();
  final failureClasses = <String>[];
  // P2 gate — wave-log classifier accumulators: the class split is
  // parsed from every published log text, never guessed
  // (xsoulspace_agentic_harness wave_log_classifier.dart).
  var burned = 0;
  var resolvable = 0;
  var composition = 0;
  final classCounts = <String, int>{};
  for (var i = 1; i <= runs; i++) {
    final jail = await row.seed(i, true);
    try {
      final plan = row.consentPlan?.call();
      stderr.writeln('[afm_wave] ${row.name} run $i/$runs — ${jail.path}');
      final sw = Stopwatch()..start();
      final result = await runCodingAgentOnce(
        task: row.task(),
        jail: jail,
        handler: DefaultGenerationHandler(router: router),
        backend: 'apple_foundation_afm',
        onRecorder: wireSigintDump,
        router: router,
        actorModelId: modelId,
        leanContextProfile: true,
        maxGoalAttempts: attempts,
        // Rows 1/3/4: no approver (R7e apply-mode — the proven shape).
        // Row 2: the driver answers BOTH permission surfaces in-process.
        packConsent: plan?.allow,
        editApprover: plan == null ? null : (_) async => true,
      );
      sw.stop();
      final logFile = writeRunLog(
        runsDir,
        'afm_wave_${row.name}_run$i.log',
        '${formatRunLog(result)}\n--- tool results (truncated per beat) ---\n'
        '${result.toolResults.join('\n')}\n',
      );
      // P2 gate — the wave-log classifier runs on EVERY wave re-run;
      // the split row comes from parsing the published log text.
      final logReport = classifyWaveLog(
        File(logFile.path).readAsStringSync(),
      );
      burned += logReport.burnedSteps;
      resolvable += logReport.mechanicallyResolvable;
      composition += logReport.compositionRequired;
      logReport.classes.forEach((name, n) {
        classCounts[name] = (classCounts[name] ?? 0) + n;
      });
      if (result.passed) passed++;
      final failureClass = result.failureClass.isEmpty
          ? ''
          : result.failureClass.split('\n').first;
      if (failureClass.isNotEmpty) failureClasses.add(failureClass);
      final detail = _summaryLine({
        'row': row.name,
        'run': i,
        'verdict': result.passed ? 'PASS' : 'FAIL',
        'decisions': result.decisions,
        'tool_rounds': result.toolRounds,
        'tokens': result.projectionTokens,
        'wall_ms': sw.elapsed.inMilliseconds,
        'moves': result.moves,
        if (plan != null) 'permission_answers': plan.uses,
        if (plan != null) 'consent_audit': plan.audit,
        'failure_class': failureClass,
        'log': logFile.path,
        'log_class_split': <String, Object?>{
          'burned_steps': logReport.burnedSteps,
          'mechanically_resolvable': logReport.mechanicallyResolvable,
          'composition_required': logReport.compositionRequired,
          // writeRunLog APPENDS — the file accumulates runs across
          // invocations, so the split classifies the LAST run block (the
          // one this invocation wrote); never .single (measured crash).
          'failure_class': logReport.runs.isEmpty
              ? 'unparseable'
              : logReport.runs.last.failureClass,
          'classes': Map<String, int>.of(logReport.classes),
        },
      });
      stdout.writeln(detail);
      runDetails.add(detail);
    } finally {
      try {
        jail.deleteSync(recursive: true);
      } on Object {
        // best effort — the jail is in the system temp dir
      }
    }
  }
  rowSw.stop();
  return {
    'row': row.name,
    'verdict': passed == runs ? 'PASS' : 'FAIL',
    'runs': runs,
    'passed': passed,
    'pass': '$passed/$runs',
    'tokens_source': 'Situation.tokensUsed (projection)',
    'attempts_budget': attempts,
    'wall_ms': rowSw.elapsed.inMilliseconds,
    'failure_classes': failureClasses.toSet().toList(),
    'class_split': <String, Object?>{
      'burned_steps': burned,
      'mechanically_resolvable': resolvable,
      'composition_required': composition,
      'classes': classCounts,
    },
    'runs_detail': runDetails,
  };
}

// ---------------------------------------------------------------------------
// --dry: fixture-plumbing validation — build each jail and assert its
// shape against the REAL machinery (the grammar classifier + the pack
// capture + the md/yaml materializers), with NO model and NO dylib.
// ---------------------------------------------------------------------------

Future<bool> _dryAll(List<_WaveRow> rows) async {
  var allOk = true;
  for (final row in rows) {
    final problems = <String>[];
    final jail = await row.seed(0, false);
    try {
      if (row.dry == null) {
        problems.add('no dry validator for this row');
      } else {
        await row.dry!(jail, problems);
      }
      // ADR 0009 Amendment pre-flight (repair (a)): the ONE frontier
      // resolver must resolve the row's REAL prompt over the REAL jail
      // tree — the ready decision the actor carries. A miss here means
      // the on-device row would burn decisions on id composition (the
      // measured 100%-mechanically-resolvable class).
      await _dryResolver(row, jail, problems);
    } on Object catch (e) {
      problems.add('dry validator threw: $e');
    } finally {
      try {
        jail.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    }
    final ok = problems.isEmpty;
    if (!ok) allOk = false;
    stdout.writeln(
      _summaryLine({
        'row': row.name,
        'mode': 'dry',
        'verdict': ok ? 'PASS' : 'FAIL',
        if (!ok) 'problems': problems,
      }),
    );
  }
  stderr.writeln(
    allOk
        ? '[afm_wave] DRY: every jail\'s plumbing validates against the '
              'real materializers — the rows are ready for the on-device '
              'runs.'
        : '[afm_wave] DRY: fixture plumbing FAILED — fix before the '
              'on-device runs.',
  );
  return allOk;
}

/// The resolver pre-flight: scan the jail, run [resolveTaskPrompt] on the
/// row's REAL prompt, and demand a Ready resolution with the exact ids
/// (the wave rows are the measured 100%-mechanically-resolvable class).
Future<void> _dryResolver(
  _WaveRow row,
  Directory jail,
  List<String> problems,
) async {
  final world = World()..addPlugin(AgentPlugin());
  final etl = repoEtlTool(world, jail);
  final scan = await etl.execute({'action': 'scan'});
  if ('$scan'.contains('"ok":false')) {
    problems.add('resolver pre-flight: scan failed: $scan');
    return;
  }
  final resolution = resolveTaskPrompt(world, row.task().prompt);
  final expected = _resolverExpectations[row.name];
  if (expected == null) {
    problems.add('no resolver expectation registered for ${row.name}');
    return;
  }
  if (resolution is! ReadyStep) {
    problems.add(
      'resolver pre-flight: the row prompt did NOT resolve Ready — '
      '${resolution.runtimeType}'
      '${resolution is AmbiguousStep ? " (${resolution.reason})" : ""} '
      '— the on-device row would compose ids (the measured failure class)',
    );
    return;
  }
  for (final e in expected.entries) {
    if (resolution.args[e.key] != e.value) {
      problems.add('resolver pre-flight: args[${e.key}] = '
          '${resolution.args[e.key]} — wanted ${e.value}');
    }
  }
}

/// Per-row ready-args expectations (the exact ids the materializers
/// resolve — the same law the dry validators pin for the manual path).
const _resolverExpectations = <String, Map<String, Object>>{
  'task_grammar': {
    'action': 'apply_executable',
    'executableId': _grammarExecutableId,
    'symbolId': 'sym_lib_loop.dart_inBounds',
  },
  'trusted_author': {
    'action': 'apply_executable',
    'executableId': _trustedExecutableId,
    'symbolId': 'sym_lib_geometry.dart_area',
  },
  'md': {
    'action': 'replace_section',
    'symbolId': 'sec_f_docs_README.md_2',
  },
  'yaml': {
    'action': 'replace_value',
    'symbolId': 'key_f_config.yaml_retry_max_attempts',
  },
};

/// Row 1 dry: the sentence parses; the scanned jail tree carries the pack
/// executable AND the symbol; the lookup emits the READY decision with the
/// mechanically resolved symbolId; the pack capture round-trips the chain.
Future<bool> _dryGrammar(Directory jail, List<String> problems) async {
  final reading = parseTaskSentence(_grammarPrompt);
  if (reading is! TaskGrammarMatch) {
    problems.add('sentence did not parse: $reading');
    return false;
  }
  if (reading.verbClass != 'fix' || reading.target != 'inBounds') {
    problems.add('parsed {${reading.verbClass}, ${reading.target}} — '
        'wanted {fix, inBounds}');
  }
  if (reading.params['file'] != 'lib/loop.dart') {
    problems.add('file param: ${reading.params['file']}');
  }
  final world = World()..addPlugin(AgentPlugin());
  final etl = repoEtlTool(world, jail);
  final scan = await etl.execute({'action': 'scan'});
  if ('$scan'.contains('"ok":false')) {
    problems.add('repo_etl scan failed: $scan');
  }
  final lookup = executableDecisionForTask(world, reading);
  if (!lookup.matched) {
    problems.add('decision lookup MISSED (${lookup.reason}) — the host '
        'pre-pass would fall through to the prose path');
  } else {
    final d = lookup.decision!;
    if (d['executableId'] != _grammarExecutableId) {
      problems.add('decision executableId ${d['executableId']}');
    }
    if (d['symbolId'] != 'sym_lib_loop.dart_inBounds') {
      problems.add('decision symbolId ${d['symbolId']} — wanted '
          'sym_lib_loop.dart_inBounds');
    }
    if (d['source'] != 'task_grammar') {
      problems.add('decision source ${d['source']}');
    }
  }
  final entries = EditPackCapture(jail).load();
  if (entries.length != 1) {
    problems.add('pack entries ${entries.length} — wanted 1');
  } else {
    final e = entries.single;
    if (e.wire.kind != EditExecutableKind.replaceMemberBody) {
      problems.add('pack kind ${e.wire.kind.wire}');
    }
    if (e.opChain.length != 5) {
      problems.add('opChain rows ${e.opChain.length} — wanted 5');
    }
  }
  return problems.isEmpty;
}

/// Row 2 dry: the authored_body entry round-trips; the consent plan
/// ALLOWS it (audited) and a pack_write-less plan REFUSES it (named
/// data, deny-by-default).
Future<bool> _dryTrusted(Directory jail, List<String> problems) async {
  final entries = EditPackCapture(jail).load();
  if (entries.length != 1) {
    problems.add('pack entries ${entries.length} — wanted 1');
    return false;
  }
  final e = entries.single;
  if (e.wire.kind != EditExecutableKind.authoredBody) {
    problems.add('pack kind ${e.wire.kind.wire} — wanted authored_body');
  }
  if (e.authoredBody != _trustedAuthoredBody) {
    problems.add('authoredBody "${e.authoredBody}" does not round-trip');
  }
  if (e.wire.id != _trustedExecutableId) problems.add('wire id ${e.wire.id}');

  final allowed = _ConsentPlan();
  if (!allowed.allow(e.wire, _consentDiff(e.authoredBody ?? ''))) {
    problems.add('consent plan refused the entry — the row could not run');
  }
  if (allowed.uses != 1 || allowed.audit.isEmpty) {
    problems.add('consent plan did not audit the allowance');
  }
  final refusing = _ConsentPlan(verbs: {'write'}, maxUses: 2);
  if (refusing.allow(e.wire, _consentDiff(e.authoredBody ?? ''))) {
    problems.add('a plan WITHOUT pack_write allowed the entry — '
        'deny-by-default broken');
  }
  if (!refusing.audit.any((l) => l.contains('pack_write REFUSED'))) {
    problems.add('the refusal was not audited');
  }
  return problems.isEmpty;
}

String _consentDiff(String body) =>
    '--- a/pack:$_trustedExecutableId (authored body)\n'
    '+++ b/pack:$_trustedExecutableId (authored body)\n'
    '${[for (final l in body.split('\n')) '+$l'].join('\n')}';

/// Row 3 dry: the REAL md materializer performs the row's exact move on
/// the fixture — byte-precise splice (heading preserved, nothing else
/// reflows), zero_broken_links green, no auto-revert.
Future<bool> _dryMd(Directory jail, List<String> problems) async {
  // Surface-drift gate (ADR 0034/0035 §5): the prompt teaches the ONE
  // unified verb, never a dead per-format verb or an fs-shaped path arg.
  for (final dead in ['edit_section', 'edit_key', '"path":']) {
    if (_mdPrompt.contains(dead)) {
      problems.add('md prompt teaches the DEAD surface ("$dead") — the '
          'unified verb is edit_symbol {action, symbolId, body?}');
    }
  }
  if (!_mdPrompt.contains('"action": "replace_section"')) {
    problems.add('md prompt does not carry the unified replace_section '
        'move shape');
  }
  final mat = MdMaterializer(root: FsToolsRoot(jail.path));
  final outcome = mat.perform(
    path: _mdRel,
    op: 'replace_section',
    anchor: 'Usage',
    body: _mdBody,
  );
  if (!outcome.appliedClean) {
    problems.add(
      'edit_section did not land clean: ok=${outcome.ok} '
      'reverted=${outcome.reverted} failureClass=${outcome.failureClass} '
      'detail=${outcome.detail}',
    );
    return false;
  }
  final after = File('${jail.path}/$_mdRel').readAsStringSync();
  // BYTE-PRECISE: prefix through the preserved heading + the body + the
  // untouched tail (the exact emitter contract, md_materializer_test).
  final headingIdx = _mdOriginal.indexOf('## Usage');
  final prefix = _mdOriginal.substring(0, headingIdx + '## Usage\n'.length);
  final nextIdx = _mdOriginal.indexOf('## Install');
  final suffix = _mdOriginal.substring(nextIdx);
  if (after != prefix + _mdBody + suffix) {
    problems.add('splice is not byte-precise (prefix+body+suffix mismatch)');
  }
  if (!after.contains('## Usage')) problems.add('heading lost');
  if (after.contains('to start the gateway. Read the')) {
    problems.add('old Usage content survived');
  }
  return problems.isEmpty;
}

/// Row 4 dry: the REAL keypath materializer performs the row's exact move
/// on the fixture — comments/siblings byte-identical, parse_semantic_diff
/// exactly the intended change, no auto-revert.
Future<bool> _dryYaml(Directory jail, List<String> problems) async {
  // Surface-drift gate (ADR 0034/0035 §5) — same law as the md row.
  for (final dead in ['edit_section', 'edit_key', '"path":']) {
    if (_yamlPrompt.contains(dead)) {
      problems.add('yaml prompt teaches the DEAD surface ("$dead") — the '
          'unified verb is edit_symbol {action, symbolId, body?}');
    }
  }
  if (!_yamlPrompt.contains('"action": "replace_value"')) {
    problems.add('yaml prompt does not carry the unified replace_value '
        'move shape');
  }
  final mat = KeypathMaterializer(root: FsToolsRoot(jail.path));
  final outcome = mat.perform(
    path: _yamlRel,
    op: 'replace_value',
    anchor: 'retry.max_attempts',
    body: '5',
  );
  if (!outcome.appliedClean) {
    problems.add(
      'edit_key did not land clean: ok=${outcome.ok} '
      'reverted=${outcome.reverted} failureClass=${outcome.failureClass} '
      'detail=${outcome.detail}',
    );
    return false;
  }
  final after = File('${jail.path}/$_yamlRel').readAsStringSync();
  for (final comment in [
    '# service settings — do not rename keys',
    '# retry policy (tuned 2026-09)',
    'backoff_ms: 50',
    '- telemetry',
    '- dark_mode',
    'name: gateway',
    'port: 8080',
  ]) {
    if (!after.contains(comment)) problems.add('sibling lost: $comment');
  }
  // The inline comment survives the value swap (yaml emitter rule).
  if (!after.contains('max_attempts: 5')) problems.add('value not set');
  if (after.contains('max_attempts: 3')) problems.add('old value survived');
  if (!after.contains('# keep small on-device')) {
    problems.add('the inline comment after the value was dropped');
  }
  // Semantic diff: EXACTLY the intended change.
  final before = keypathParse(_yamlOriginal, isJson: false);
  final parsed = keypathParse(after, isJson: false);
  final diff = semanticDiff(before, parsed);
  if (diff.length != 1) {
    problems.add('semantic diff has ${diff.length} changes — wanted 1: '
        '$diff');
  } else {
    final c = diff.single;
    if (c.kind != 'changed' ||
        c.path != 'retry.max_attempts' ||
        '${c.before}' != '3' ||
        '${c.after}' != '5') {
      problems.add('semantic diff is not exactly the intended change: $c');
    }
  }
  return problems.isEmpty;
}

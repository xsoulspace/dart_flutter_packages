// ignore_for_file: lines_longer_than_80_chars

/// VCS-as-meaning projection (PLAN §NOW P3 first slice).
///
/// The ADR-0023 fs-is-a-projection law applied to version control: the
/// model never does VCS addressing (no shelling out, no sha/branch
/// bookkeeping) — VCS state is PROJECTED as meaning nodes over a
/// [VcsAdapter] ABSTRACTION, read-only, LLM-free, git-replaceable. Git is
/// one implementation ([GitVcsAdapter]) via jailed, read-only commands;
/// a future VCS (jj, Sapling, p4) swaps the impl without touching node
/// shape or the projection.
///
/// Node kinds (all MeaningNode/MeaningProps/MeaningEdge DATA, locatable
/// through the existing discovery ray):
/// - `vcs`        — the repo root (dotted external id `vcs.repo`); props:
///   root, backend, current_branch, recent_commits (bounded list).
/// - `vcs_branch` — one per branch; props: name, is_current.
/// - `vcs_head`   — the HEAD commit; props: sha (short), subject, author_date.
/// - `vcs_change` — one per changed file; props: path, status (porcelain).
///
/// STATUS PROJECTION ONLY: no mutation verbs this round — writes stay with
/// the edit tier. `gitReadOnlyCommands` is the jail: any command outside
/// {status, branch, log, rev-parse} is a named [VcsCommandRefusal], so a
/// future adapter edit that adds a write command fails the gate, not the
/// repo. The projection degrades honestly: a not-a-repo dir projects as a
/// NAMED EMPTY result (`not_a_repo`), never a crash; a missing backend is
/// `vcs_unavailable`.
///
/// Re-projection is idempotent: node ids are deterministic dotted
/// external ids (outside the `kind_N` auto-id space, per the
/// `addMeaningNode` id contract), props are updated in place, and stale
/// branch/change children are dropped — same repo state → same projection.
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:ecsly/ecsly.dart';

import '../narrative/facet_index.dart' show FacetIndex;
import 'meaning_tree.dart';

// ---------------------------------------------------------------------------
// The VCS abstraction — an interface, not a git shim
// ---------------------------------------------------------------------------

/// One branch in a VCS snapshot.
class VcsBranch {
  const VcsBranch({required this.name, required this.isCurrent});
  final String name;
  final bool isCurrent;
}

/// The HEAD commit summary (short form — the projection is budgeted).
class VcsHeadSummary {
  const VcsHeadSummary({
    required this.shortSha,
    required this.subject,
    required this.authorDate,
  });
  final String shortSha;
  final String subject;
  final String authorDate;
}

/// One changed file. [status] is the backend's raw short status code
/// (e.g. porcelain `M`, `??`) — projected as data, never interpreted.
class VcsChange {
  const VcsChange({required this.path, required this.status});
  final String path;
  final String status;
}

/// One recent commit (bounded list projected as a root prop).
class VcsCommitSummary {
  const VcsCommitSummary({required this.shortSha, required this.subject});
  final String shortSha;
  final String subject;
}

/// A read-only VCS state snapshot — the WHOLE adapter contract. No write
/// verbs exist at this tier by design (writes stay with the edit tier).
class VcsSnapshot {
  const VcsSnapshot({
    required this.currentBranch,
    required this.branches,
    required this.headSummary,
    required this.changedFiles,
    required this.recentCommits,
  });
  final String currentBranch;
  final List<VcsBranch> branches;
  final VcsHeadSummary? headSummary;
  final List<VcsChange> changedFiles;
  final List<VcsCommitSummary> recentCommits;
}

/// The VCS abstraction (git-replaceable): ONE method, read-only, returning
/// `null` when [rootPath] is not a repository — the projection degrades
/// honestly from that single named null.
abstract interface class VcsAdapter {
  /// Backend name projected as a root prop (e.g. 'git').
  String get backend;

  /// Read-only snapshot, or `null` when [rootPath] is not a repo.
  /// Implementations must be bounded (caps on every list) and must throw
  /// [VcsUnavailable] only when the backend binary itself is missing.
  Future<VcsSnapshot?> snapshot(String rootPath);
}

/// The backend binary is missing — a NAMED degradation, never a crash.
class VcsUnavailable implements Exception {
  const VcsUnavailable(this.backend);
  final String backend;
  @override
  String toString() => 'VcsUnavailable: backend `$backend` is not available';
}

// ---------------------------------------------------------------------------
// The git jail — read-only command set, asserted, named refusals
// ---------------------------------------------------------------------------

/// The ONLY git subcommands the adapter may run (the read-only law):
/// status / branch / log / rev-parse. Anything else — commit, push,
/// reset, checkout — is a named refusal. The gate asserts this set.
const gitReadOnlyCommands = <String>{'status', 'branch', 'log', 'rev-parse'};

/// A named refusal to run a VCS command outside the read-only jail.
class VcsCommandRefusal implements Exception {
  const VcsCommandRefusal(this.command);
  final String command;
  @override
  String toString() =>
      'VcsCommandRefusal: git `$command` is outside the read-only VCS '
      'command set $gitReadOnlyCommands — writes stay with the edit tier';
}

/// Asserts [command] is inside the read-only jail; throws a named
/// [VcsCommandRefusal] otherwise. Every adapter invocation routes through
/// this — the law is structural, not convention.
void ensureReadOnlyGitCommand(String command) {
  if (!gitReadOnlyCommands.contains(command)) {
    throw VcsCommandRefusal(command);
  }
}

// ---------------------------------------------------------------------------
// Git implementation — jailed, read-only, bounded
// ---------------------------------------------------------------------------

/// Output budgets (the projection is budgeted like every other cut).
const _maxBranches = 50;
const _maxChanges = 200;
const _maxRecentCommits = 5;
const _maxSubject = 200;

class GitVcsAdapter implements VcsAdapter {
  const GitVcsAdapter();

  @override
  String get backend => 'git';

  Future<ProcessResult> _runGit(
    String rootPath,
    String command,
    List<String> args,
  ) {
    ensureReadOnlyGitCommand(command); // the jail: structurally read-only
    return Process.run(
      'git',
      [command, ...args],
      workingDirectory: rootPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  String _clip(String s, int cap) {
    final t = s.trim();
    return t.length > cap ? t.substring(0, cap) : t;
  }

  @override
  Future<VcsSnapshot?> snapshot(String rootPath) async {
    // Repo detection first: anything that fails here is the honest named
    // null (not a repo, bare repo, permissive-transport error).
    try {
      final inside = await _runGit(rootPath, 'rev-parse', const [
        '--is-inside-work-tree',
      ]);
      if (inside.exitCode != 0 || inside.stdout.toString().trim() != 'true') {
        return null;
      }
    } on ProcessException {
      throw VcsUnavailable(backend);
    }

    // Current branch: --show-current exits 0 with '' on a detached HEAD.
    var currentBranch = '';
    final current = await _runGit(rootPath, 'branch', const ['--show-current']);
    if (current.exitCode == 0) currentBranch = _clip(current.stdout, 120);

    // Branches (bounded, sorted for determinism).
    final branchOut = await _runGit(rootPath, 'branch', const [
      '--format=%(refname:short)',
    ]);
    final branchNames = branchOut.exitCode == 0
        ? (branchOut.stdout
              .toString()
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .take(_maxBranches)
              .toList()
              ..sort())
        : const <String>[];

    // HEAD summary (null on an unborn branch — honest, not an error).
    VcsHeadSummary? head;
    final headOut = await _runGit(rootPath, 'log', const [
      '-1',
      '--pretty=format:%h%x00%s%x00%aI',
    ]);
    if (headOut.exitCode == 0) {
      final parts = headOut.stdout.toString().split('\x00');
      if (parts.length >= 3 && parts[0].trim().isNotEmpty) {
        head = VcsHeadSummary(
          shortSha: _clip(parts[0], 40),
          subject: _clip(parts[1], _maxSubject),
          authorDate: _clip(parts[2], 40),
        );
      }
    }

    // Changed files: porcelain v1, line-bounded (paths with spaces parse;
    // newlines inside filenames degrade to the bounded truncation — named).
    final changes = <VcsChange>[];
    final statusOut = await _runGit(rootPath, 'status', const [
      '--porcelain=v1',
    ]);
    if (statusOut.exitCode == 0) {
      for (final line in statusOut.stdout.toString().split('\n')) {
        if (line.length < 4) continue;
        if (changes.length >= _maxChanges) break;
        changes.add(
          VcsChange(path: line.substring(3), status: line.substring(0, 2)),
        );
      }
    }

    // Recent commits (bounded list, projected as a root prop).
    final recent = <VcsCommitSummary>[];
    final logOut = await _runGit(rootPath, 'log', const [
      '-$_maxRecentCommits',
      '--pretty=format:%h%x00%s',
    ]);
    if (logOut.exitCode == 0) {
      for (final line in logOut.stdout.toString().split('\n')) {
        final parts = line.split('\x00');
        if (parts.length < 2 || parts[0].trim().isEmpty) continue;
        if (recent.length >= _maxRecentCommits) break;
        recent.add(
          VcsCommitSummary(
            shortSha: _clip(parts[0], 40),
            subject: _clip(parts[1], _maxSubject),
          ),
        );
      }
    }

    return VcsSnapshot(
      currentBranch: currentBranch,
      branches: [
        for (final name in branchNames)
          VcsBranch(name: name, isCurrent: name == currentBranch),
      ],
      headSummary: head,
      changedFiles: changes,
      recentCommits: recent,
    );
  }
}

// ---------------------------------------------------------------------------
// The projection — VCS state as meaning nodes over the existing tree
// ---------------------------------------------------------------------------

/// The named result of one projection pass.
class VcsProjectionResult {
  const VcsProjectionResult({required this.status, required this.nodeIds});
  final String status; // 'projected' | 'not_a_repo' | 'vcs_unavailable'
  final List<String> nodeIds;
  bool get projected => status == 'projected';
}

/// Stable-id scheme for branch/change children: dotted external ids
/// (outside the `kind_N` auto-id space, per the addMeaningNode id
/// contract). Non-id chars are slugged — the name/path prop carries the
/// truth; the id only needs determinism.
String _slug(String s) => s.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');

/// Projects the VCS state at [rootPath] into [world] as meaning nodes
/// (see the library docs for the node kinds). Idempotent: existing nodes
/// are updated in place (props replaced, facet re-indexed), stale
/// branch/change children are dropped — no duplicates, ever.
///
/// Degradation is named, never a crash: not a repo → `not_a_repo` with
/// zero nodes; missing backend → `vcs_unavailable` with zero nodes.
Future<VcsProjectionResult> projectVcsMeaning(
  World world,
  VcsAdapter adapter,
  String rootPath, {
  String rootId = 'vcs.repo',
}) async {
  VcsSnapshot? snapshot;
  try {
    snapshot = await adapter.snapshot(rootPath);
  } on VcsUnavailable {
    return const VcsProjectionResult(
      status: 'vcs_unavailable',
      nodeIds: [],
    );
  }
  if (snapshot == null) {
    return const VcsProjectionResult(status: 'not_a_repo', nodeIds: []);
  }

  final repoName = rootPath
      .split(RegExp(r'[/\\]'))
      .where((s) => s.isNotEmpty)
      .last;

  // Existing children of the root, by relation — the stale-drop set.
  final index = world.maybeGetResource<MeaningIndex>();
  final existingChildren = <String, Set<String>>{
    'branch': {},
    'head': {},
    'change': {},
  };
  if (index != null) {
    for (final (from, relation, to) in index.triples) {
      if (from != rootId) continue;
      existingChildren[relation]?.add(to);
    }
  }

  final projected = <String>{};

  void upsert(
    String id, {
    required String kind,
    required String label,
    required Map<String, dynamic> props,
  }) {
    if (hasMeaningNode(world, id)) {
      // Update in place — idempotent re-projection, never a duplicate:
      // label lives on the node component, props on the props component
      // (stale keys die with the old map), and the facet keywords are
      // re-indexed (union-only index, so the old keywords are de-indexed
      // first — locate stays honest).
      final entity = world.maybeGetResource<MeaningIndex>()?.entityOf(id);
      if (entity != null) {
        world.upsertComponent(entity, MeaningNode(id: id, kind: kind, label: label));
        world.upsertComponent(entity, MeaningProps(Map.of(props)));
        final facet = world.getResource<FacetIndex>();
        facet.deindexBeat(entity);
        facet.indexBeat(entity, meaningKeywords(kind, label, props));
        world.flush(); // ecsly buffers commands — flush or the view lies
      }
    } else {
      addMeaningNode(world, kind: kind, label: label, props: props, id: id);
    }
    projected.add(id);
  }

  void link(String from, String relation, String to) {
    if (!projected.contains(from) || !projected.contains(to)) return;
    // linkMeaning does not dedupe — an idempotent re-projection must not
    // append a second copy of an already-projected edge.
    final index = world.maybeGetResource<MeaningIndex>();
    final exists = index?.triples.any(
          (t) => t.$1 == from && t.$2 == relation && t.$3 == to,
        ) ??
        false;
    if (exists) return;
    linkMeaning(world, from: from, relation: relation, to: to);
  }

  upsert(
    rootId,
    kind: 'vcs',
    label: repoName,
    props: {
      'root': rootPath,
      'backend': adapter.backend,
      'current_branch': snapshot.currentBranch,
      'recent_commits': [
        for (final c in snapshot.recentCommits)
          {'sha': c.shortSha, 'subject': c.subject},
      ],
    },
  );

  for (final branch in snapshot.branches) {
    final id = 'vcs.branch.${_slug(branch.name)}';
    upsert(
      id,
      kind: 'vcs_branch',
      label: branch.name,
      props: {'name': branch.name, 'is_current': branch.isCurrent},
    );
    link(rootId, 'branch', id);
  }

  final head = snapshot.headSummary;
  if (head != null) {
    const headId = 'vcs.head';
    upsert(
      headId,
      kind: 'vcs_head',
      label: head.subject,
      props: {
        'sha': head.shortSha,
        'subject': head.subject,
        'author_date': head.authorDate,
      },
    );
    link(rootId, 'head', headId);
  }

  for (final change in snapshot.changedFiles) {
    final id = 'vcs.change.${_slug(change.path)}';
    upsert(
      id,
      kind: 'vcs_change',
      label: change.path,
      props: {'path': change.path, 'status': change.status},
    );
    link(rootId, 'change', id);
  }

  // Stale children (a branch deleted, a file committed or cleaned) drop —
  // the tree stays re-derivable from the current VCS state alone.
  for (final entry in existingChildren.entries) {
    for (final stale in entry.value.where((id) => !projected.contains(id))) {
      dropMeaningNode(world, stale);
    }
  }

  return VcsProjectionResult(
    status: 'projected',
    nodeIds: projected.toList()..sort(),
  );
}

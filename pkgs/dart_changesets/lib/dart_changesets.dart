/// Changesets-style release engine for Dart monorepos.
///
/// Intent files → graph-aware version PRs → per-package pub.dev publish
/// trains. Inspired by [changesets](https://github.com/changesets/changesets)
/// and [@changesets/action](https://github.com/changesets/action).
library;

export 'src/apply.dart';
export 'src/bump.dart';
export 'src/changeset.dart';
export 'src/config.dart';
export 'src/doctor.dart';
export 'src/publish.dart';
export 'src/workspace_graph.dart';

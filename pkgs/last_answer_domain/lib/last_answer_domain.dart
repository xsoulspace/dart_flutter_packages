/// Pure-Dart domain model for Last Answer documents.
///
/// Implements the recursive document node model from
/// docs/decisions/0001-recursive-document-node-model.md: one unified node
/// type, block-granularity anchoring, snapshot-on-creation, collapse-as-
/// archive. No Flutter dependencies — usable from app, TUI, CLI, and tests.
library;

export 'src/document_node.dart';

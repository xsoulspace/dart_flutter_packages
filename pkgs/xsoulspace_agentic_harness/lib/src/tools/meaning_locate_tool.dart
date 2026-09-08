// ignore_for_file: lines_longer_than_80_chars

/// `meaning_locate` — the structural DISCOVERY ray (ADR 0014 §2, re-based
/// on the meaning tree): "where is X?" answered from the map-graph —
/// NEVER grep, and NEVER zoom (zoom projects a bounded cut; locate finds
/// the nodes a cut should center on). Class-agnostic by construction: it
/// matches ANY meaning node label — symbols, intents, sections, keys,
/// files — because the model discovers MEANINGS, not files (the file
/// class is invisible at this tier; ADR 0023/0024).
///
/// Rows are token-bounded (hard cap); usage counts come from the tree's
/// own `refs` edges — the graph is the index, no second scanner exists.
/// Deterministic: match rank, then kind, then label.
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import '../meaning/meaning_tree.dart';

const _defaultMaxRows = 32;
const _hardMaxRows = 128;

ToolDef meaningLocateTool(World world) => ToolDef.encode(
      name: const ToolName('meaning_locate'),
      description:
          'Structural discovery ray over the meaning tree (ADR 0014 §2): '
          'answer "where is X?" — definitions, usages, related meanings — '
          'in ONE token-bounded call. Matches ANY meaning node label '
          '(symbols, intents, sections, keys, files); never a text search. '
          'Use BEFORE zoom/impact: locate yields the focus ids those verbs '
          'require. Args: query (identifier), maxRows (default 32).',
      argsSchema: SchemaBundle(
        root: FM.object('meaning_locate', properties: () => [
              FM.prop('query', FM.string()),
              FM.prop('maxRows', FM.integer()),
            ]),
      ),
      execute: (args) async {
        final map = args is Map ? args : const {};
        final query = map['query'];
        if (query is! String || query.trim().isEmpty) {
          return {
            'ok': false,
            'error': 'query_required',
            'hint': 'locate takes an identifier — a symbol, intent, '
                'section or keypath label',
          };
        }
        final maxRowsRaw = map['maxRows'];
        final maxRows = maxRowsRaw is num && maxRowsRaw >= 1
            ? (maxRowsRaw.toInt() > _hardMaxRows
                ? _hardMaxRows
                : maxRowsRaw.toInt())
            : _defaultMaxRows;
        final index = world.maybeGetResource<MeaningIndex>();
        if (index == null || index.byId.isEmpty) {
          return {
            'ok': false,
            'error': 'tree_empty',
            'hint': 'repo_etl scan first — the ray needs the map-graph',
          };
        }
        final q = query.trim().toLowerCase();
        // Rank: exact label match beats prefix beats containment — the ray
        // points at the SHARPEST meaning first, deterministically.
        int rankOf(String label) {
          final l = label.toLowerCase();
          if (l == q) return 0;
          if (l.startsWith(q)) return 1;
          if (l.contains(q)) return 2;
          return -1;
      }

        final hits = <(int, String, String, String)>[]; // (rank, kind, label, id)
        for (final entry in index.byId.entries) {
          final node = meaningComponentOf<MeaningNode>(world, entry.value);
          if (node == null) continue;
          final rank = rankOf(node.label);
          if (rank < 0) continue;
          hits.add((rank, node.kind, node.label, entry.key));
        }
        if (hits.isEmpty) {
          // Mechanical repair-teaching law (ADR 0034 disposition 1, read
          // side): a no-match query bounces with the workspace's actual
          // node ids — ALL classes (symbols, files, sections, keys), not
          // just the code tier: an md row needs the file/section node,
          // not a Dart symbol. Capped, token-budgeted.
          final hints = [
            for (final entry in index.byId.entries)
              if (const [
                'symbol',
                'file',
                'section',
                'key',
              ].contains(meaningComponentOf<MeaningNode>(world, entry.value)?.kind))
                entry.key,
          ].take(6).toList();
          return {
            'ok': true,
            'query': query,
            'total': 0,
            'rows': const [],
            'hint': 'no meaning matched — zoom ONE of these ids (a file '
                "node's cut carries its sections/keys), then edit",
            'hints': hints,
          };
        }
        hits.sort((a, b) {
          final byRank = a.$1.compareTo(b.$1);
          if (byRank != 0) return byRank;
          final byKind = a.$2.compareTo(b.$2);
          if (byKind != 0) return byKind;
          return a.$3.compareTo(b.$3);
        });
        // Usage counts from the tree's OWN refs edges (the graph is the
        // index — no second scanner, no fs walk).
        final matchedIds = {for (final h in hits) h.$4};
        final refsInto = <String, int>{};
        for (final t in index.triples) {
          if (t.$2 != 'refs') continue;
          if (matchedIds.contains(t.$3)) {
            refsInto[t.$3] = (refsInto[t.$3] ?? 0) + 1;
          }
        }
        final truncated = hits.length > maxRows;
        final rows = [
          for (final (rank, kind, label, id) in hits.take(maxRows))
            {
              'id': id,
              'kind': kind,
              'label': label,
              'rank': rank,
              if (refsInto[id] != null) 'refs': refsInto[id],
            },
        ];
        return {
          'ok': true,
          'query': query,
          'total': hits.length,
          'rows': rows,
          if (truncated) 'truncated': true,
          if (truncated)
            'hint': 'bounded to $maxRows rows — narrow the identifier or '
                'raise maxRows (hard cap $_hardMaxRows)',
        };
      },
    );

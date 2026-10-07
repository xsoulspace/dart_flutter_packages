import 'dart:convert';
import 'dart:io';

/// The status of one model-drafted summary.
enum NapDraftStatus {
  /// Awaiting review — the only status a reviewer should act on.
  pending,

  /// The model refused (uncertainty) — a faithful PASS, nothing to apply.
  refused,

  /// Over the byte budget after trim; never suggested for apply.
  tooLong,

  /// Multi-line or empty; never suggested for apply.
  invalid,

  /// The transport or server failed; the record keeps the error.
  error,
}

/// One model-drafted summary of one OptMem compression block, with its
/// full provenance.
///
/// Drafts are DERIVED material: they never enter the event store on their
/// own. The reviewer (human or agent) promotes a draft by running the
/// ordinary `nap` command — the same validated, provenance-linked write
/// path the tool itself uses. Until then a draft lives only in the
/// sidecar queue ([NapDraftStore]); no read path ever sees it.
final class NapDraftRecord {
  const NapDraftRecord({
    required this.id,
    required this.createdAt,
    required this.blockLo,
    required this.blockHi,
    required this.model,
    required this.providerId,
    required this.draft,
    required this.draftBytes,
    required this.status,
    required this.elapsedMs,
    required this.promptBytes,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
    this.error,
  });

  /// `<lo>-<hi>-<epochMs>` — unique per draft attempt.
  final String id;
  final DateTime createdAt;

  /// The compression block (raw beat id range) this draft was derived from.
  final int blockLo;
  final int blockHi;

  /// The model the server reported, and the provider composition that
  /// produced the draft (`mlx_local` for this package's client).
  final String model;
  final String providerId;

  /// The draft text exactly as the model produced it (trimmed of outer
  /// whitespace only).
  final String draft;
  final int draftBytes;
  final NapDraftStatus status;
  final int elapsedMs;

  /// Content-free wire facts for the benchmark ledger.
  final int promptBytes;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
  final String? error;

  /// The ready `nap` argument pair for this block: `<lo>-<hi> "<draft>"`.
  String get napArgument => '$blockLo-$blockHi "$draft"';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'block': '$blockLo-$blockHi',
    'model': model,
    'provider': providerId,
    'draft': draft,
    'draft_bytes': draftBytes,
    'status': status.name,
    'elapsed_ms': elapsedMs,
    'prompt_bytes': promptBytes,
    'prompt_tokens': ?promptTokens,
    'completion_tokens': ?completionTokens,
    'finish_reason': ?finishReason,
    'error': ?error,
  };

  static NapDraftRecord fromJson(final Map<String, Object?> json) {
    final block = '${json['block']}';
    final dash = block.indexOf('-');
    final statusName = '${json['status']}';
    return NapDraftRecord(
      id: '${json['id']}',
      createdAt: DateTime.parse('${json['created_at']}'),
      blockLo: int.parse(block.substring(0, dash)),
      blockHi: int.parse(block.substring(dash + 1)),
      model: '${json['model']}',
      providerId: '${json['provider']}',
      draft: '${json['draft']}',
      draftBytes: (json['draft_bytes'] as num?)?.toInt() ?? 0,
      status: NapDraftStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => NapDraftStatus.invalid,
      ),
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      promptBytes: (json['prompt_bytes'] as num?)?.toInt() ?? 0,
      promptTokens: (json['prompt_tokens'] as num?)?.toInt(),
      completionTokens: (json['completion_tokens'] as num?)?.toInt(),
      finishReason: json['finish_reason'] == null
          ? null
          : '${json['finish_reason']}',
      error: json['error'] == null ? null : '${json['error']}',
    );
  }
}

/// Append-only JSONL queue of draft records: `<memoryDir>/drafts/nap.jsonl`.
///
/// The queue is a REVIEW worklist, not a store: nothing reads it to answer
/// questions, and applying a draft always goes through the validated `nap`
/// command against the live chain.
final class NapDraftStore {
  NapDraftStore(this.file);

  final File file;

  Future<void> append(final NapDraftRecord record) async {
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: FileMode.append);
    try {
      sink.writeln(jsonEncode(record.toJson()));
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Every record ever appended, oldest first.
  List<NapDraftRecord> load() {
    if (!file.existsSync()) return const <NapDraftRecord>[];
    final records = <NapDraftRecord>[];
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      records.add(NapDraftRecord.fromJson(decoded.cast<String, Object?>()));
    }
    return records;
  }

  /// The latest record per block, in block order — the worklist a reviewer
  /// sees (earlier attempts for the same block are superseded history).
  List<NapDraftRecord> latestPerBlock() {
    final latest = <int, NapDraftRecord>{};
    for (final record in load()) {
      final existing = latest[record.blockLo];
      if (existing == null ||
          record.createdAt.isAfter(existing.createdAt)) {
        latest[record.blockLo] = record;
      }
    }
    final blocks = latest.keys.toList()..sort();
    return <NapDraftRecord>[for (final block in blocks) latest[block]!];
  }
}

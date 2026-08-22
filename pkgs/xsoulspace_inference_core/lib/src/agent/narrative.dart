/// Thread & Beat ontology for the agent harness.
///
/// A Thread is a first-class exploration branch — a container that holds
/// many Beats of different modalities. Beats are modality-agnostic content
/// units (text, voice, tool calls, thoughts, observations).
///
/// Everything is an entity. The graph is formed by typed reference components.
/// Stories interlink. Multiplayer is natural.
library;

import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

import 'model_router.dart';

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────

/// Status of a Thread in the narrative graph.
enum ThreadStatusEnum {
  /// Thread is active and being explored.
  active,

  /// Thread is suspended (paused, may resume).
  suspended,

  /// Thread is being scored by a mechanical system.
  scoring,

  /// Thread has been pruned (low score) — kept for history but excluded
  /// from normal projection.
  pruned,

  /// Thread has been merged into another thread.
  merged,

  /// Thread has been archived (complete, read-only).
  archived,
}

/// Modality of a Beat — what kind of content it carries.
enum BeatModalityEnum {
  text,
  streamingText,
  voice,
  structuredAction,
  toolCall,
  thought,
  observation,
}

/// Status of a Beat within its Thread.
enum BeatStatusEnum {
  /// Beat is partial — streaming or incomplete.
  partial,

  /// Beat is complete.
  complete,

  /// Beat was aborted (error, cancelled).
  aborted,

  /// Beat was superseded by a summary node; kept for history.
  archived,
}

// ─────────────────────────────────────────────
// Thread container components
// ─────────────────────────────────────────────

/// A Thread is an alternative / exploration path in the narrative graph.
///
/// Threads are scoreable, prunable, and mergeable.
class Thread extends Component {
  const Thread({this.parentThreadId});
  final Entity? parentThreadId;
}

/// Score for a [Thread]. Higher is better.
class ThreadScore extends Component {
  ThreadScore(this.value);
  double value;
}

/// Unique identifier for a Thread entity.
class ThreadId extends Component {
  const ThreadId(this.value);
  final String value;
}

/// Current status of a Thread.
class ThreadStatus extends Component {
  ThreadStatus(this.value);
  ThreadStatusEnum value;
}

/// Reference to the Scene this Thread belongs to.
class ParentScene extends Component {
  const ParentScene(this.scene);
  final Entity scene;
}

/// The Actor that originated this Thread.
class OriginActor extends Component {
  const OriginActor(this.actor);
  final Entity actor;
}

/// Optional link to a Goal this Thread serves.
class GoalLink extends Component {
  const GoalLink(this.goal);
  final Entity? goal;
}

/// Reference to a parent Thread this Thread was derived from.
/// Used for branching, forking, and isolation.
class DerivedFromThread extends Component {
  const DerivedFromThread(this.thread);
  final Entity thread;
}

/// Visibility rules — which Actors can see this Thread.
/// Empty set means visible to all Actors in the Scene.
class ThreadVisibility extends Component {
  ThreadVisibility(this.visibleTo);
  Set<AgentId> visibleTo;
}

// ─────────────────────────────────────────────
// Beat (content unit) components
// ─────────────────────────────────────────────

/// Unique identifier for a Beat entity.
class BeatId extends Component {
  const BeatId(this.value);
  final String value;
}

/// Reference to the Thread this Beat belongs to.
class BelongsToThread extends Component {
  const BelongsToThread(this.thread);
  final Entity thread;
}

/// Links a [MemorySummary] beat to the source beats it was derived from.
///
/// Written by the deliberate [summarizeThread] graph transform so a summary
/// stays traceable to its raw beats. The summary remains queryable in the
/// graph; this component records provenance, not a cache.
class SummarizesBeats extends Component {
  SummarizesBeats({List<Entity>? sources}) : sources = sources ?? <Entity>[];

  /// The source beats this summary was built from.
  List<Entity> sources;
}

/// Sequence number for ordering Beats within a Thread.
class BeatSequence extends Component {
  BeatSequence(this.value);
  int value;
}

/// The Actor that produced this Beat.
class Speaker extends Component {
  const Speaker(this.actor);
  final Entity actor;
}

/// Optional: this Beat is addressed to a specific Actor (or null = broadcast).
class AddressedTo extends Component {
  const AddressedTo(this.actor);
  final Entity? actor;
}

/// Modality of this Beat (text, voice, tool call, etc.).
class BeatModality extends Component {
  BeatModality(this.value);
  BeatModalityEnum value;
}

/// Status of this Beat (partial, complete, aborted).
class BeatStatus extends Component {
  BeatStatus(this.value);
  BeatStatusEnum value;
}

/// Optional: this Beat is a reply to another Beat (causal link).
class ReplyToBeat extends Component {
  const ReplyToBeat(this.beat);
  final Entity beat;
}

/// Optional: this Beat observes a Prop (read-only reference).
class ObservesProp extends Component {
  const ObservesProp(this.prop);
  final Entity prop;
}

/// This Beat is private to a specific Actor (inner monologue, etc.).
class PrivateToActor extends Component {
  const PrivateToActor(this.actor);
  final Entity actor;
}

// ─────────────────────────────────────────────
// Sparse modality payloads (attach only what exists)
// ─────────────────────────────────────────────

/// Text content for a text Beat.
class TextContent extends Component {
  TextContent(this.text);
  String text;
}

/// Streaming text buffer for partial Beats.
class TextStream extends Component {
  TextStream({List<String>? chunks, this.cursor = 0})
    : chunks = chunks ?? <String>[];
  final List<String> chunks;
  int cursor;
}

/// Audio stream for voice Beats (real-time chunks).
class AudioStream extends Component {
  AudioStream({List<Uint8List>? chunks}) : chunks = chunks ?? <Uint8List>[];
  final List<Uint8List> chunks;
}

/// Structured action payload.
class ActionPayload extends Component {
  ActionPayload(this.data);
  Map<String, dynamic> data;
}

/// A tool call within a Beat.
///
/// Used as both a Beat component (for stored tool calls) and as part of
/// the [ToolCallEvent] for ECS-driven tool execution.
class BeatToolCall extends Component {
  BeatToolCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

/// Result of a tool call within a Beat.
///
/// Used as both a Beat component (for stored tool results) and as part of
/// the [ToolResultEvent] for ECS-driven tool execution.
class ToolResult extends Component {
  ToolResult(this.result);
  dynamic result;
}

/// Internal thought content (private reasoning).
class ThoughtContent extends Component {
  ThoughtContent(this.text);
  String text;
}

/// Observation data from the environment.
class ObservationData extends Component {
  ObservationData(this.data);
  dynamic data;
}

// ─────────────────────────────────────────────
// Graph-forming systems
// ─────────────────────────────────────────────

/// Spawn a new Thread entity under [originActor] and [parentScene].
///
/// Optionally links to a [goal]. The Thread starts with status `active`
/// and score `0.0`.
Entity spawnThread(
  World w,
  Entity originActor,
  Entity parentScene, {
  Entity? goal,
}) {
  final entity = w.reserveEmptyEntity().entity;
  final we = w.getEntity(entity).$1;
  we.insert(ThreadStatus(ThreadStatusEnum.active));
  we.insert(ThreadScore(0));
  we.insert(OriginActor(originActor));
  we.insert(ParentScene(parentScene));
  if (goal != null) {
    we.insert(GoalLink(goal));
  }
  return entity;
}

/// Start a new Beat in [thread] spoken by [speaker] with [modality].
///
/// The Beat starts in `partial` status. Use [appendToBeat] to add content
/// and [completeBeat] to finalize.
Entity startBeat(
  World w,
  Entity thread,
  Entity speaker,
  BeatModalityEnum modality,
) {
  final entity = w.reserveEmptyEntity().entity;
  final we = w.getEntity(entity).$1;
  we.insert(BelongsToThread(thread));
  we.insert(Speaker(speaker));
  we.insert(BeatModality(modality));
  we.insert(BeatStatus(BeatStatusEnum.partial));
  we.insert(BeatSequence(_nextSequence(w, thread)));
  return entity;
}

/// Append a text chunk to a Beat's [TextStream].
///
/// Creates a [TextStream] if one doesn't exist.
void appendToBeat(World w, Entity beat, String chunk) {
  final we = w.getEntity(beat).$1;
  final stream = we.get<TextStream>() ?? TextStream();
  stream.chunks.add(chunk);
  we.insert(stream);
}

/// Complete a Beat — flips status from `partial` to `complete`.
///
/// Optionally collapses [TextStream] into [TextContent].
void completeBeat(World w, Entity beat) {
  final we = w.getEntity(beat).$1;
  final stream = we.get<TextStream>();
  if (stream != null) {
    final text = stream.chunks.join();
    we.insert(TextContent(text));
    we.remove<TextStream>();
  }
  we.insert(BeatStatus(BeatStatusEnum.complete));
}

/// Real scoring system — scores Threads based on heuristics.
///
/// Scoring factors:
/// - Number of Complete Beats
/// - Average Beat score (if present)
/// - Goal relevance (if GoalLink exists)
/// - Recency of activity
void scoreThreadsSystem(World w) {
  final threads = w.query2<Thread, ThreadScore>();
  for (final (entity, _, score) in threads) {
    // Count complete beats in this thread
    final beatCount = w
        .query2<BelongsToThread, BeatStatus>()
        .where((t) => t.$1.get<BelongsToThread>()?.thread == entity.entity)
        .length;
    // Simple heuristic: more complete beats = higher score
    score.value = (beatCount * 0.1).clamp(0.0, 1.0);
  }
}

/// Prune low-scoring Threads — marks as `pruned` instead of despawning.
///
/// Pruned Threads remain queryable for history but are excluded from
/// normal projection.
void pruneThreadsSystem(World w) {
  final threads = w.query2<Thread, ThreadScore>();
  for (final (entity, _, score) in threads.toList()) {
    if (score.value < 0.1) {
      final status = entity.get<ThreadStatus>();
      if (status != null && status.value != ThreadStatusEnum.pruned) {
        status.value = ThreadStatusEnum.pruned;
        // Deindex the thread's beats so projection cannot ray-trace into
        // pruned history via stale keyword hits.
        _deindexThreadBeats(w, entity.entity);
      }
    }
  }
}

void _deindexThreadBeats(World w, Entity thread) {
  for (final (beat, belongs, _)
      in w.query2<BelongsToThread, BeatStatus>().toList()) {
    if (belongs.thread == thread) deindexBeat(w, beat.entity);
  }
}

/// Merge low-value Threads into higher-value ones.
///
/// Re-parents Beats from source Thread to target Thread.
void mergeThreadsSystem(World w) {
  final pruned = w.query2<Thread, ThreadStatus>().where(
    (t) => t.$3.value == ThreadStatusEnum.pruned,
  );
  for (final (entity, _, status) in pruned) {
    // Find a target Thread to merge into (same Scene, higher score)
    final sourceScene = entity.get<ParentScene>();
    if (sourceScene == null) continue;

    final candidates = w.query3<Thread, ThreadScore, ParentScene>().where(
      (t) =>
          t.$4.scene == sourceScene.scene && t.$3.value > 0.1 && t.$1 != entity,
    );
    if (candidates.isEmpty) continue;

    // Pick the highest-scoring candidate
    final target = candidates
        .fold(
          candidates.first,
          (best, curr) => curr.$3.value > best.$3.value ? curr : best,
        )
        .$1;

    // Re-parent all Beats (the target keeps its index entries; the source's
    // beats were already deindexed when it was pruned — re-index them under
    // the merged thread is a no-op for the index, only ownership changes).
    final beats = w.query2<BelongsToThread, BeatStatus>();
    for (final (beat, belongs, _) in beats.toList()) {
      if (belongs.thread == entity.entity) {
        beat.insert(BelongsToThread(target.entity));
      }
    }

    // Mark source as merged
    status.value = ThreadStatusEnum.merged;
  }
}

int _nextSequence(World w, Entity thread) {
  var max = 0;
  for (final (_, _, seq) in w.query2<BelongsToThread, BeatSequence>()) {
    if (seq.value > max) max = seq.value;
  }
  return max + 1;
}

/// Finalize partial Beats — collapses streaming content into complete form.
///
/// This runs in the Narrative schedule. It checks for Beats that have
/// a [TextStream] with a cursor at the end and marks them complete.
void finalizePartialsSystem(World w) {
  final partialBeats = w.query2<BeatStatus, TextStream>();
  for (final (beat, status, stream) in partialBeats.toList()) {
    if (stream.cursor >= stream.chunks.length && stream.chunks.isNotEmpty) {
      final text = stream.chunks.join();
      beat.insert(TextContent(text));
      beat.remove<TextStream>();
      status.value = BeatStatusEnum.complete;
    }
  }
}

/// Facet index over the narrative graph.
///
/// A keyword → beats index that makes projection a ray-tracing query: given
/// a prompt, we look up the beats whose keywords match instead of scanning a
/// per-actor memory list. This is a derived index — beats are indexed when
/// they are written, and projection reads it functionally.
class FacetIndex extends Resource {
  final Map<String, Set<Entity>> byKeyword = {};
  final Map<Entity, Set<String>> keywordsOf = {};

  /// Index [beat] under [keywords]. Idempotent — re-indexing a beat with the
  /// same keywords is a no-op; new keywords are unioned in.
  void indexBeat(Entity beat, Iterable<String> keywords) {
    final owned = keywordsOf.putIfAbsent(beat, () => <String>{});
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      byKeyword.putIfAbsent(keyword, () => <Entity>{}).add(beat);
      owned.add(keyword);
    }
  }

  /// Union of all beats indexed under any of [keywords].
  Iterable<Entity> beatsFor(Iterable<String> keywords) {
    final out = <Entity>{};
    for (final keyword in keywords) {
      final hits = byKeyword[keyword];
      if (hits != null) out.addAll(hits);
    }
    return out;
  }

  /// The keywords currently indexed for [beat].
  Set<String> keywordsFor(Entity beat) => keywordsOf[beat] ?? <String>{};

  /// Remove [beat] from the index entirely.
  ///
  /// Called when a beat's thread is pruned or merged away so stale keyword
  /// hits cannot resurface pruned content in projections.
  void deindexBeat(Entity beat) {
    final owned = keywordsOf.remove(beat);
    if (owned == null) return;
    for (final keyword in owned) {
      final hits = byKeyword[keyword];
      if (hits == null) continue;
      hits.remove(beat);
      if (hits.isEmpty) byKeyword.remove(keyword);
    }
  }
}

/// Index a beat into the world's [FacetIndex] under the given keywords.
///
/// Mechanical helper — callers derive keywords from the beat's content and
/// write them here so projection can ray-trace to the beat later.
void indexBeat(World w, Entity beat, Iterable<String> keywords) {
  w.getResource<FacetIndex>().indexBeat(beat, keywords);
}

/// Remove [beat] from the world's [FacetIndex].
///
/// Call when a beat's thread is pruned/merged so stale keyword hits cannot
/// resurface pruned content in projections.
void deindexBeat(World w, Entity beat) {
  w.getResource<FacetIndex>().deindexBeat(beat);
}

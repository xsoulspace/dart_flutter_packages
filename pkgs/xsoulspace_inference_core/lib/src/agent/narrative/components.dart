import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

import '../model_router.dart';

/// Thread & Beat ontology components.
///
/// A Thread is a first-class exploration branch — a container that holds
/// many Beats of different modalities. Beats are modality-agnostic content
/// units (text, voice, tool calls, thoughts, observations).
///
/// Everything is an entity. The graph is formed by typed reference components.
library;

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
///
/// [cursor] is the render position — how much of [chunks] has been consumed
/// by incremental consumers (e.g. progressive projection of a partial beat).
/// It is NOT used for completion gating; beats complete when their owning
/// turn completes ([completeBeat]).
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
/// Graph provenance for tool calls: stamped onto the tool-result beat so the
/// call's arguments stay queryable in the graph ("what did I try last time"),
/// not just its result. Events are transient; this is the durable record.
class BeatToolCall extends Component {
  BeatToolCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

/// Result of a tool call within a Beat.
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

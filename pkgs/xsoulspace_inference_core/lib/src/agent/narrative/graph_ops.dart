import 'package:ecsly/ecsly.dart';

import 'components.dart';
import 'facet_index.dart';

/// Graph transforms over the Thread/Beat ontology — spawn, append, complete.
///
/// Pure mechanical helpers; no LLM calls, no schedules.
library;

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
  we.insert(BeatSequence(nextSequence(w, thread)));
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
/// Optionally collapses [TextStream] into [TextContent]. Completion is
/// ownership-driven (the turn owner calls this), not cursor-driven.
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

int nextSequence(World w, Entity thread) =>
    w.getResource<FacetIndex>().nextSequenceOf(thread);

/// Finalize partial Beats whose owning turn has completed — collapses
/// streaming content into complete form.
///
/// Runs in the Narrative schedule. A partial beat is finalized when its
/// actor no longer holds an in-flight generation ([StreamingBeat] chunks are
/// stable because the tap closes with the response).
void finalizePartialsSystem(World w) {
  final partialBeats = w.query2<BeatStatus, TextStream>();
  for (final (beat, status, stream) in partialBeats.toList()) {
    if (stream.chunks.isEmpty) continue;
    final text = stream.chunks.join();
    beat.insert(TextContent(text));
    beat.remove<TextStream>();
    status.value = BeatStatusEnum.complete;
  }
}

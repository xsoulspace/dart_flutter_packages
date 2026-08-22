import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../narrative/narrative.dart';

/// System 0: Seed an actor's identity into the graph as beats.
///
/// An actor's [ActorSystemPrompt] and [Goal] are its identity — "who am I / what
/// am I doing". Writing them as indexable beats in the actor's thread means
/// projection can ray-trace them on the FIRST decision, before any real beats
/// exist. This fixes the cold-start gap where projection returned nothing.
///
/// Idempotent: an actor gets identity beats exactly once (guarded by the
/// [IdentitySeeded] marker component — O(1) check instead of a full-world
/// scan). Mechanical — never touches an LLM.
void seedIdentitySystem(World world) {
  final actors = world.query2<Actor, ActorThreads>();
  for (final (entity, _, threads) in actors.toList()) {
    if (entity.has<IdentitySeeded>()) continue;
    if (threads.threads.isEmpty) continue;

    final thread = threads.threads.first;
    final (_, valid) = world.getEntity(thread);
    if (!valid) continue;

    final systemPrompt = entity.get<ActorSystemPrompt>();
    final goal = entity.get<Goal>();
    final parts = <String>[];
    if (systemPrompt != null && systemPrompt.text.isNotEmpty) {
      parts.add(systemPrompt.text);
    }
    if (goal != null && goal.text.isNotEmpty) {
      parts.add('Goal: ${goal.text}');
    }
    entity.insert(const IdentitySeeded());
    if (parts.isEmpty) continue;

    final identityBeat = world.reserveEmptyEntity().entity;
    final be = world.getEntity(identityBeat).$1;
    be.insert(TextContent(parts.join('\n')));
    be.insert(BeatStatus(BeatStatusEnum.complete));
    be.insert(BeatModality(BeatModalityEnum.observation));
    be.insert(const IdentityBeat());
    be.insert(BelongsToThread(thread));
    indexBeat(world, identityBeat, keywordsOf(parts.join(' ')), thread: thread);
  }
}

/// Marker: this actor's identity beats have been seeded. Replaces the old
/// full-world scan of [IdentityBeat]s with an O(1) component check.
class IdentitySeeded implements Component {
  const IdentitySeeded();
}

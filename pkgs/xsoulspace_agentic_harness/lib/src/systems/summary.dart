import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../narrative/narrative.dart';
import 'projection/relevance.dart' show keywordsOf;

/// Deliberate graph transform: summarize a set of beats into a
/// [MemorySummary] beat that stays in [thread].
///
/// This is OPTIONAL/requested — it is NOT run automatically in any schedule.
Entity summarizeThread(World world, Entity thread, List<Entity> sources) {
  final parts = <String>[];
  final keywords = <String>{};
  for (final source in sources) {
    final (entity, valid) = world.getEntity(source);
    if (!valid) continue;
    final text = entity.get<TextContent>();
    if (text != null && text.text.isNotEmpty) {
      parts.add(text.text);
    }
    keywords.addAll(keywordsOf(entity.get<TextContent>()?.text ?? ''));
  }

  final summaryText = parts.join(' | ');
  final summaryBeat = world.reserveEmptyEntity().entity;
  final se = world.getEntity(summaryBeat).$1;
  se.insert(TextContent(summaryText));
  se.insert(BeatStatus(BeatStatusEnum.complete));
  se.insert(BeatModality(BeatModalityEnum.observation));
  se.insert(MemorySummary(summaryText));
  se.insert(BelongsToThread(thread));
  se.insert(SummarizesBeats(sources: sources));

  indexBeat(world, summaryBeat, keywords);
  return summaryBeat;
}

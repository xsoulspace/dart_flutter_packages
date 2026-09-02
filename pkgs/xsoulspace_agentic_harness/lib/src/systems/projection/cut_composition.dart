// ignore_for_file: lines_longer_than_80_chars

/// ADR 0020 — the cut is a composed document.
///
/// A model call is ONE stateless chat: there is no conversation to preserve,
/// only this decision's view. A view is wrong when its RANKING is wrong — and
/// ranking is a per-decision-kind policy that can be declared and verified,
/// not a global sort order. So the cut is not a flat ranked soup; it is a
/// composition of TYPED SLOTS, each with its own selection/render policies:
///
/// - `goal`        — the task + criteria. Non-evictable. Hard-required: an
///   empty goal slot is a named INPUT-GATE failure before the model is called
///   (the input-side mirror of the write gate).
/// - `map`         — the workspace graph cut (fs file graph, N5b). Rendered
///   as an explicit absence when no provider is wired.
/// - `observations`— tool-result/narration beats. Selection by relevance,
///   render order oldest→newest (recency is THIS slot's render policy);
///   deduped; empty beats never admitted.
/// - `lastVerdict` — the most recent mechanical verdict detail.
/// - `plan`        — plan-frontier steps (ADR 0009), unchanged.
///
/// The codec renders slots in DECLARED order, verbatim — it never re-ranks.
/// Every emitted cut conforms to its composition or nothing is sent.
/// Conformance is LLM-free testable per composition (ADR 0020 §4).
///
/// The flat ranked cut remains the default for flows that do not declare a
/// composition — no breaking change; hosts opt in per decision kind.
library;

import 'package:ecsly/ecsly.dart';

import '../../resources/resources.dart' show Resource;

/// What source fills a slot.
enum CutSlotFill { goal, map, observations, lastVerdict }

/// One typed slot of a cut composition.
class CutSlot {
  const CutSlot({
    required this.name,
    required this.fill,
    this.capacity = 8,
    this.required = false,
    this.dedup = true,
    this.dropEmpty = true,
  });

  final String name;
  final CutSlotFill fill;

  /// Maximum fragments this slot may contribute (observations).
  final int capacity;

  /// INPUT GATE (ADR 0020 §3): a required slot that cannot fill is a named
  /// violation BEFORE the model is called. Only slots whose source must
  /// always exist (goal) are hard-required.
  final bool required;

  /// Drop fragments whose normalized text duplicates an earlier one
  /// (within the slot and across earlier slots).
  final bool dedup;

  /// Never admit empty/whitespace fragments.
  final bool dropEmpty;
}

/// An ordered composition of slots — host data, conformance-tested.
class CutComposition {
  const CutComposition({required this.name, required this.slots});

  final String name;
  final List<CutSlot> slots;

  /// The coder decision composition (run-graded native fs surface).
  static CutComposition coder() => const CutComposition(name: 'coder', slots: [
    CutSlot(name: 'goal', fill: CutSlotFill.goal, capacity: 1, required: true),
    CutSlot(name: 'map', fill: CutSlotFill.map, capacity: 1),
    CutSlot(
      name: 'observations',
      fill: CutSlotFill.observations,
      capacity: 8,
    ),
    CutSlot(name: 'lastVerdict', fill: CutSlotFill.lastVerdict, capacity: 1),
  ]);
}

/// Host-wired composition for the projection to honor. Absent → legacy flat
/// ranked cut (no breaking change for existing flows).
///
/// ADR 0020 §5 — model ≠ actor: a ROLE is (composition + tool surface +
/// model binding). [compositionByRegistry] lets each actor's registry bind
/// its own composition (same pattern as `RunGoalSpec.commandByRegistry`),
/// so one model can field coder/writer/overseer actors — each seeing the
/// world through its own tested cut.
class CutCompositionResource extends Resource {
  CutCompositionResource(this.composition, {this.mapProvider, this.compositionByRegistry});
  final CutComposition composition;

  /// Optional workspace-map source (fs file graph). Null → the map slot
  /// renders as an explicit absence.
  final String? Function()? mapProvider;

  /// Per-actor compositions keyed by the actor's `ActorTools.registryName`.
  final Map<String, CutComposition>? compositionByRegistry;

  CutComposition forRegistry(String? registryName) {
    if (registryName != null) {
      final per = compositionByRegistry?[registryName];
      if (per != null) return per;
    }
    return composition;
  }
}

/// A named input-gate failure: a required slot could not fill.
class CutViolation {
  const CutViolation({required this.slot, required this.reason});
  final String slot;
  final String reason;

  @override
  String toString() => 'cut violation [$slot]: $reason';
}

/// The composed cut: working-set strings (non-evictable, in slot order) plus
/// the selected beat entities in render order.
class ComposedCut {
  const ComposedCut({
    required this.workingSet,
    required this.orderedBeats,
    required this.absences,
    required this.violations,
    required this.duplicatesDropped,
    required this.emptyDropped,
  });

  /// Non-evictable fragments rendered BEFORE observations, in slot order.
  final List<String> workingSet;

  /// Observation beat entities in render order (chronological within slot).
  final List<Entity> orderedBeats;

  /// Green-screen notes (off-screen count, map absence, ...).
  final List<String> absences;

  /// Input-gate failures (required slots that could not fill).
  final List<CutViolation> violations;

  /// Measurement: admission policy activity (K2 columns).
  final int duplicatesDropped;
  final int emptyDropped;
}

/// Composes a cut from [candidates] (relevance-ranked beat entities, newest
/// last as produced by `rankFragments`) plus the slot sources.
///
/// Pure and deterministic: [textOf] extracts a beat's text, [originalIndex]
/// restores thread order for the observations slot's render policy.
/// LLM-free testable per ADR 0020 §4.
ComposedCut composeCut({
  required CutComposition composition,
  required List<Entity> candidates,
  required String Function(Entity beat) textOf,
  required int Function(Entity beat) originalIndex,
  required String goalText,
  String? mapText,
  String? verdictText,
  required int totalCandidates,
}) {
  final workingSet = <String>[];
  final absences = <String>[];
  final violations = <CutViolation>[];
  final seen = <String>{};
  var duplicatesDropped = 0;
  var emptyDropped = 0;
  final orderedBeats = <Entity>[];

  // Normalization key for dedup: collapse whitespace once.
  String key(String text) => text.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );

  void admit(String label, String? content, CutSlot slot) {
    if (content == null || content.trim().isEmpty) {
      if (slot.required) {
        violations.add(
          CutViolation(
            slot: slot.name,
            reason: 'required slot has no content — input gate',
          ),
        );
      }
      return;
    }
    final fragment = '$label$content';
    if (slot.dedup && !seen.add(key(fragment))) {
      duplicatesDropped++;
      return;
    }
    workingSet.add(fragment);
  }

  Entity? mapMarker;
  for (final slot in composition.slots) {
    switch (slot.fill) {
      case CutSlotFill.goal:
        admit('task: ', goalText, slot);
      case CutSlotFill.map:
        if (mapText == null || mapText.trim().isEmpty) {
          absences.add('workspace map unavailable.');
        } else {
          admit('workspace map:\n', mapText, slot);
        }
      case CutSlotFill.lastVerdict:
        admit('last check: ', verdictText, slot);
      case CutSlotFill.observations:
        // Selection: candidates arrive relevance-ranked; admission policies
        // (dropEmpty, dedup, capacity) prune; render order is ORIGINAL
        // thread order (chronological within the slot — a slot policy,
        // not a global law).
        final selected = <(Entity, int)>[];
        for (final beat in candidates) {
          final text = textOf(beat);
          if (slot.dropEmpty && text.trim().isEmpty) {
            emptyDropped++;
            continue;
          }
          if (slot.dedup && !seen.add(key(text))) {
            duplicatesDropped++;
            continue;
          }
          selected.add((beat, originalIndex(beat)));
          if (selected.length >= slot.capacity) break;
        }
        selected.sort((a, b) => a.$2.compareTo(b.$2));
        orderedBeats.addAll(selected.map((s) => s.$1));
    }
  }
  // Off-screen accounting: candidates not admitted to any beat slot.
  final offScreen = totalCandidates - orderedBeats.length;
  if (offScreen > 0) {
    absences.add('$offScreen beat(s) are off-screen.');
  }
  return ComposedCut(
    workingSet: workingSet,
    orderedBeats: orderedBeats,
    absences: absences,
    violations: violations,
    duplicatesDropped: duplicatesDropped,
    emptyDropped: emptyDropped,
  );
}

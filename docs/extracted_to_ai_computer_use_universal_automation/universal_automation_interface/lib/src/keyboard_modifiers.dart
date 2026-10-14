/// The family's keyboard-modifier vocabulary (ADR 0053): platform-
/// agnostic names, lowercase in the wire form.
///
/// Chords — `shift`+click, `meta`+drag, `control`+T — compose modifier
/// keys around pointer presses and key presses. `meta` is Command on
/// macOS, the Windows key on Windows; `alt` is Option on macOS. Every
/// tier maps the vocabulary onto its native modifier representation;
/// unknown names fail closed at parse time, never silently drop.
library;

/// The four modifiers actions can carry.
const keyboardModifiers = <String>{'shift', 'control', 'alt', 'meta'};

/// The step-level key name for a modifier (the family's named-key
/// convention, same shape as `Enter`).
String modifierKeyName(final String modifier) => switch (modifier) {
  'shift' => 'Shift',
  'control' => 'Control',
  'alt' => 'Alt',
  'meta' => 'Meta',
  _ => modifier,
};

/// Normalizes one modifier alias (`ctrl`, `option`, `cmd`, `command`,
/// `windows`); `null` outside the vocabulary.
String? normalizeModifier(final String raw) => switch (raw.toLowerCase()) {
  'shift' => 'shift',
  'control' || 'ctrl' => 'control',
  'alt' || 'option' => 'alt',
  'meta' || 'command' || 'cmd' || 'windows' => 'meta',
  _ => null,
};

/// Parses a wire modifier list: aliases normalize, unknown names throw
/// (fail-closed — a dropped modifier is a misfired chord).
List<String> parseModifiers(final Iterable<Object?> raw) => [
  for (final item in raw)
    if (normalizeModifier('$item') case final normalized?) normalized
    else throw FormatException(
      'unknown keyboard modifier "$item"; the family vocabulary is '
      'shift/control/alt/meta',
    ),
];

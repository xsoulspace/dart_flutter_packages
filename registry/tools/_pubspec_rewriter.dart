class DependencyRewriteResult {
  const DependencyRewriteResult({
    required this.content,
    required this.changed,
    required this.rewrites,
    required this.details,
  });

  final String content;
  final bool changed;
  final int rewrites;
  final List<String> details;
}

class DependencyValidationIssue {
  const DependencyValidationIssue({
    required this.section,
    required this.packageName,
    required this.reason,
  });

  final String section;
  final String packageName;
  final String reason;
}

DependencyRewriteResult rewriteHostedDependencies({
  required final String content,
  required final Set<String> internalPackageNames,
  required final Map<String, String> internalPackageVersions,
  required final String hostedUrl,
}) {
  final endsWithNewline = content.endsWith('\n');
  final lines = content.split('\n');
  final output = <String>[];
  final details = <String>[];
  var rewrites = 0;
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (_targetSections.contains(trimmed) && _indentOf(line) == 0) {
      output.add(line);
      index += 1;
      while (index < lines.length) {
        final currentLine = lines[index];
        if (_isTopLevelSectionBoundary(currentLine)) {
          break;
        }

        if (_isIgnorable(currentLine)) {
          output.add(currentLine);
          index += 1;
          continue;
        }

        if (_indentOf(currentLine) != 2 ||
            !_looksLikeMappingEntry(currentLine)) {
          output.add(currentLine);
          index += 1;
          continue;
        }

        final entryStart = index;
        final entryKey = _entryKey(currentLine);
        final entryEnd = _findDependencyEntryEnd(lines, entryStart);
        final entryLines = lines.sublist(entryStart, entryEnd);

        final replacement = _rewriteEntry(
          entryKey: entryKey,
          entryLines: entryLines,
          internalPackageNames: internalPackageNames,
          internalPackageVersions: internalPackageVersions,
          hostedUrl: hostedUrl,
        );

        if (replacement != null) {
          output.addAll(replacement.lines);
          rewrites += 1;
          details.add(
            '${trimmed.substring(0, trimmed.length - 1)}:$entryKey '
            '(${replacement.reason})',
          );
        } else {
          output.addAll(entryLines);
        }

        index = entryEnd;
      }
      continue;
    }

    output.add(line);
    index += 1;
  }

  var updated = output.join('\n');
  if (endsWithNewline && !updated.endsWith('\n')) {
    updated = '$updated\n';
  }
  if (!endsWithNewline && updated.endsWith('\n')) {
    updated = updated.substring(0, updated.length - 1);
  }

  return DependencyRewriteResult(
    content: updated,
    changed: updated != content,
    rewrites: rewrites,
    details: details,
  );
}

List<DependencyValidationIssue> validateHostedDependencies({
  required final String content,
  required final Set<String> internalPackageNames,
  required final String hostedUrl,
}) {
  final issues = <DependencyValidationIssue>[];
  final lines = content.split('\n');
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (_targetSections.contains(trimmed) && _indentOf(line) == 0) {
      final section = trimmed.substring(0, trimmed.length - 1);
      index += 1;
      while (index < lines.length) {
        final currentLine = lines[index];
        if (_isTopLevelSectionBoundary(currentLine)) {
          break;
        }

        if (_isIgnorable(currentLine) ||
            _indentOf(currentLine) != 2 ||
            !_looksLikeMappingEntry(currentLine)) {
          index += 1;
          continue;
        }

        final entryStart = index;
        final entryKey = _entryKey(currentLine);
        final entryEnd = _findDependencyEntryEnd(lines, entryStart);
        final entryLines = lines.sublist(entryStart, entryEnd);
        final analysis = _analyseEntry(entryKey, entryLines);

        if (internalPackageNames.contains(entryKey)) {
          if (!analysis.isHosted) {
            issues.add(
              DependencyValidationIssue(
                section: section,
                packageName: entryKey,
                reason: analysis.reason ?? 'internal dependency is not hosted',
              ),
            );
          } else if (analysis.hostedUrl != hostedUrl) {
            issues.add(
              DependencyValidationIssue(
                section: section,
                packageName: entryKey,
                reason:
                    'hosted url is ${analysis.hostedUrl ?? 'missing'}, '
                    'expected $hostedUrl',
              ),
            );
          } else if (!analysis.explicitNameUrlMap) {
            issues.add(
              DependencyValidationIssue(
                section: section,
                packageName: entryKey,
                reason: 'hosted dependency is not using explicit name/url form',
              ),
            );
          } else if (analysis.versionSpec == null ||
              analysis.versionSpec!.isEmpty) {
            issues.add(
              DependencyValidationIssue(
                section: section,
                packageName: entryKey,
                reason: 'hosted dependency is missing a version field',
              ),
            );
          }
        }

        index = entryEnd;
      }
      continue;
    }
    index += 1;
  }

  return issues;
}

const _targetSections = <String>{
  'dependencies:',
  'dev_dependencies:',
  'dependency_overrides:',
};

_ReplacementEntry? _rewriteEntry({
  required final String entryKey,
  required final List<String> entryLines,
  required final Set<String> internalPackageNames,
  required final Map<String, String> internalPackageVersions,
  required final String hostedUrl,
}) {
  if (!internalPackageNames.contains(entryKey)) {
    return null;
  }

  final analysis = _analyseEntry(entryKey, entryLines);
  final desiredVersion =
      analysis.versionSpec ??
      (analysis.pathValue != null ? internalPackageVersions[entryKey] : null);
  if (desiredVersion == null || desiredVersion.isEmpty) {
    return null;
  }

  final normalizedHostedUrl = hostedUrl;
  if (analysis.isHosted &&
      analysis.explicitNameUrlMap &&
      analysis.hostedUrl == normalizedHostedUrl &&
      analysis.versionSpec == desiredVersion) {
    return null;
  }

  final reason = analysis.pathValue != null
      ? 'path -> hosted ${desiredVersion}'
      : analysis.isHosted
      ? 'normalize hosted'
      : 'version -> hosted';

  return _ReplacementEntry(
    lines: <String>[
      '  $entryKey:',
      '    hosted:',
      '      name: $entryKey',
      '      url: $normalizedHostedUrl',
      '    version: $desiredVersion',
    ],
    reason: reason,
  );
}

_EntryAnalysis _analyseEntry(
  final String entryKey,
  final List<String> entryLines,
) {
  final firstLine = entryLines.first.trimLeft();
  final firstSeparator = firstLine.indexOf(':');
  final firstRemainder = firstLine.substring(firstSeparator + 1).trim();

  if (firstRemainder.isNotEmpty) {
    return _EntryAnalysis(
      versionSpec: firstRemainder,
      isHosted: false,
      explicitNameUrlMap: false,
      hostedUrl: null,
      pathValue: null,
      reason: 'dependency uses shorthand version syntax',
    );
  }

  final childBlocks = _collectChildBlocks(entryLines);
  String? versionSpec;
  String? pathValue;
  String? hostedValue;
  var explicitNameUrlMap = false;

  for (final block in childBlocks) {
    switch (block.key) {
      case 'version':
        versionSpec = block.inlineValue;
      case 'path':
        pathValue = block.inlineValue;
      case 'hosted':
        if (block.inlineValue != null && block.inlineValue!.isNotEmpty) {
          hostedValue = block.inlineValue;
        } else {
          final hostedChildren = _collectNestedChildren(block.lines, indent: 6);
          final hostedName = hostedChildren['name'];
          final hostedUrl = hostedChildren['url'];
          if (hostedName != null || hostedUrl != null) {
            hostedValue = hostedUrl;
            explicitNameUrlMap = hostedName == entryKey && hostedUrl != null;
          }
        }
    }
  }

  return _EntryAnalysis(
    versionSpec: versionSpec,
    isHosted: hostedValue != null,
    explicitNameUrlMap: explicitNameUrlMap,
    hostedUrl: hostedValue,
    pathValue: pathValue,
    reason: pathValue != null
        ? 'dependency uses path syntax'
        : hostedValue != null
        ? 'dependency already uses hosted syntax'
        : 'dependency uses unsupported mapping form',
  );
}

List<_ChildBlock> _collectChildBlocks(final List<String> entryLines) {
  final blocks = <_ChildBlock>[];
  var index = 1;
  while (index < entryLines.length) {
    final line = entryLines[index];
    if (_isIgnorable(line)) {
      index += 1;
      continue;
    }
    if (_indentOf(line) != 4 || !_looksLikeMappingEntry(line)) {
      index += 1;
      continue;
    }

    final key = _entryKey(line);
    final separator = line.trimLeft().indexOf(':');
    final inlineValue = line.trimLeft().substring(separator + 1).trim();
    final start = index;
    index += 1;
    while (index < entryLines.length) {
      final next = entryLines[index];
      if (_isIgnorable(next)) {
        index += 1;
        continue;
      }
      if (_indentOf(next) <= 4) {
        break;
      }
      index += 1;
    }
    blocks.add(
      _ChildBlock(
        key: key,
        inlineValue: inlineValue.isEmpty ? null : inlineValue,
        lines: entryLines.sublist(start, index),
      ),
    );
  }
  return blocks;
}

Map<String, String> _collectNestedChildren(
  final List<String> lines, {
  required final int indent,
}) {
  final result = <String, String>{};
  for (final line in lines.skip(1)) {
    if (_isIgnorable(line)) {
      continue;
    }
    if (_indentOf(line) != indent || !_looksLikeMappingEntry(line)) {
      continue;
    }
    final trimmed = line.trimLeft();
    final separator = trimmed.indexOf(':');
    final key = trimmed.substring(0, separator).trim();
    final value = trimmed.substring(separator + 1).trim();
    if (value.isNotEmpty) {
      result[key] = value;
    }
  }
  return result;
}

int _findDependencyEntryEnd(final List<String> lines, final int startIndex) {
  var index = startIndex + 1;
  while (index < lines.length) {
    final line = lines[index];
    if (_isTopLevelSectionBoundary(line)) {
      break;
    }
    if (_isIgnorable(line)) {
      index += 1;
      continue;
    }
    if (_indentOf(line) == 2 && _looksLikeMappingEntry(line)) {
      break;
    }
    index += 1;
  }
  return index;
}

bool _isTopLevelSectionBoundary(final String line) {
  return !_isIgnorable(line) &&
      _indentOf(line) == 0 &&
      _looksLikeMappingEntry(line);
}

bool _isIgnorable(final String line) {
  final trimmed = line.trimLeft();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

bool _looksLikeMappingEntry(final String line) {
  final trimmed = line.trimLeft();
  final separator = trimmed.indexOf(':');
  if (separator <= 0) {
    return false;
  }
  return !trimmed.startsWith('- ');
}

String _entryKey(final String line) {
  final trimmed = line.trimLeft();
  return trimmed.substring(0, trimmed.indexOf(':')).trim();
}

int _indentOf(final String line) => line.length - line.trimLeft().length;

class _ChildBlock {
  const _ChildBlock({
    required this.key,
    required this.inlineValue,
    required this.lines,
  });

  final String key;
  final String? inlineValue;
  final List<String> lines;
}

class _EntryAnalysis {
  const _EntryAnalysis({
    required this.versionSpec,
    required this.isHosted,
    required this.explicitNameUrlMap,
    required this.hostedUrl,
    required this.pathValue,
    required this.reason,
  });

  final String? versionSpec;
  final bool isHosted;
  final bool explicitNameUrlMap;
  final String? hostedUrl;
  final String? pathValue;
  final String? reason;
}

class _ReplacementEntry {
  const _ReplacementEntry({required this.lines, required this.reason});

  final List<String> lines;
  final String reason;
}

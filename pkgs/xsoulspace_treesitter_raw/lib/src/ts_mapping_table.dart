// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 4 — the TypeScript mapping table (DATA) for the
/// generic [GrammarMapper] walker. Member symbols are included from day
/// one (decision 2026-09-07): methods/functions/arrows/consts map to
/// `member` nodes under their declaring parent, so `replace_member_body`
/// and `insert_member` have nodes to address.
///
/// Per language = THIS table + fixtures — the walker never changes.
library;

import 'grammar_mapper.dart';

/// The tree-sitter-typescript (v0.23.2, pinned) node kinds mapped for the
/// spike. `memberOf: 'file'` = top-level (nearest mapped ancestor, else
/// the file node); `'parent'` = nearest mapped ancestor (e.g. a class,
/// interface or outer function).
const tsMappingTable = <String, GrammarNodeSpec>{
  'program': GrammarNodeSpec(kind: SymbolKind.file),
  // Top-level declarations.
  'class_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'abstract_class_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'function_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'generator_function_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'interface_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'enum_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'type_alias_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  // Members: methods / fields / signatures under their declaring parent.
  'method_definition': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  'method_signature': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  'property_signature': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  'public_field_definition': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  'field_definition': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  // Arrow consts / consts / vars — the NAME is on the child
  // `variable_declarator`; the walker's descendant name resolution covers
  // it (arrow_function itself needs no separate entry: it is the VALUE of
  // the declarator — the member node addresses `replace_member_body`).
  'lexical_declaration': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'file',
  ),
  'variable_declaration': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'file',
  ),
};

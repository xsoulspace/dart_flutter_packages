#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

const [, , inputPath] = process.argv;
if (!inputPath) {
  console.error('Usage: node parse_ysdk.mjs <index.d.ts>');
  process.exit(1);
}

const sourceText = fs.readFileSync(inputPath, 'utf8');
const sourceFile = ts.createSourceFile(
  path.basename(inputPath),
  sourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);

const printer = ts.createPrinter({ removeComments: true });

function nodeText(node) {
  return node ? printer.printNode(ts.EmitHint.Unspecified, node, sourceFile).trim() : '';
}

function entityNameText(name) {
  if (!name) return 'Unknown';
  if (ts.isIdentifier(name)) return name.text;
  if (ts.isQualifiedName(name)) {
    return `${entityNameText(name.left)}.${entityNameText(name.right)}`;
  }
  return nodeText(name);
}

function nameText(name) {
  if (!name) return null;
  if (ts.isIdentifier(name) || ts.isPrivateIdentifier(name)) return name.text;
  if (ts.isStringLiteral(name) || ts.isNumericLiteral(name)) return name.text;
  if (ts.isComputedPropertyName(name)) return nodeText(name.expression);
  return nodeText(name);
}

function typeParamToIr(typeParam) {
  return {
    name: typeParam.name.text,
    constraint: typeToIr(typeParam.constraint),
    defaultType: typeToIr(typeParam.default),
  };
}

function paramToIr(param, index) {
  return {
    name: param.name ? nameText(param.name) ?? `arg${index}` : `arg${index}`,
    optional: Boolean(param.questionToken || param.initializer),
    rest: Boolean(param.dotDotDotToken),
    type: typeToIr(param.type),
  };
}

function typeElementToIr(member) {
  if (ts.isPropertySignature(member)) {
    return {
      kind: 'property',
      name: nameText(member.name),
      optional: Boolean(member.questionToken),
      readonly: Boolean(member.modifiers?.some((m) => m.kind === ts.SyntaxKind.ReadonlyKeyword)),
      type: typeToIr(member.type),
    };
  }

  if (ts.isMethodSignature(member)) {
    return {
      kind: 'method',
      name: nameText(member.name),
      optional: Boolean(member.questionToken),
      typeParams: member.typeParameters?.map(typeParamToIr) ?? [],
      params: member.parameters.map(paramToIr),
      returnType: typeToIr(member.type),
    };
  }

  if (ts.isGetAccessorDeclaration(member)) {
    return {
      kind: 'getter',
      name: nameText(member.name),
      type: typeToIr(member.type),
    };
  }

  if (ts.isIndexSignatureDeclaration(member)) {
    return {
      kind: 'index',
      params: member.parameters.map(paramToIr),
      returnType: typeToIr(member.type),
    };
  }

  if (ts.isCallSignatureDeclaration(member)) {
    return {
      kind: 'call',
      typeParams: member.typeParameters?.map(typeParamToIr) ?? [],
      params: member.parameters.map(paramToIr),
      returnType: typeToIr(member.type),
    };
  }

  if (ts.isConstructSignatureDeclaration(member)) {
    return {
      kind: 'construct',
      typeParams: member.typeParameters?.map(typeParamToIr) ?? [],
      params: member.parameters.map(paramToIr),
      returnType: typeToIr(member.type),
    };
  }

  return {
    kind: 'unknown',
    text: nodeText(member),
  };
}

function typeToIr(typeNode) {
  if (!typeNode) return null;

  switch (typeNode.kind) {
    case ts.SyntaxKind.StringKeyword:
      return { kind: 'keyword', name: 'string' };
    case ts.SyntaxKind.NumberKeyword:
      return { kind: 'keyword', name: 'number' };
    case ts.SyntaxKind.BooleanKeyword:
      return { kind: 'keyword', name: 'boolean' };
    case ts.SyntaxKind.VoidKeyword:
      return { kind: 'keyword', name: 'void' };
    case ts.SyntaxKind.AnyKeyword:
      return { kind: 'keyword', name: 'any' };
    case ts.SyntaxKind.UnknownKeyword:
      return { kind: 'keyword', name: 'unknown' };
    case ts.SyntaxKind.NullKeyword:
      return { kind: 'keyword', name: 'null' };
    case ts.SyntaxKind.NeverKeyword:
      return { kind: 'keyword', name: 'never' };
    case ts.SyntaxKind.ObjectKeyword:
      return { kind: 'keyword', name: 'object' };
    case ts.SyntaxKind.UndefinedKeyword:
      return { kind: 'keyword', name: 'undefined' };
    default:
      break;
  }

  if (ts.isTypeReferenceNode(typeNode)) {
    return {
      kind: 'reference',
      name: entityNameText(typeNode.typeName),
      typeArgs: typeNode.typeArguments?.map(typeToIr) ?? [],
    };
  }

  if (ts.isArrayTypeNode(typeNode)) {
    return {
      kind: 'array',
      elementType: typeToIr(typeNode.elementType),
    };
  }

  if (ts.isTupleTypeNode(typeNode)) {
    return {
      kind: 'tuple',
      elements: typeNode.elements.map(typeToIr),
    };
  }

  if (ts.isUnionTypeNode(typeNode)) {
    return {
      kind: 'union',
      types: typeNode.types.map(typeToIr),
    };
  }

  if (ts.isIntersectionTypeNode(typeNode)) {
    return {
      kind: 'intersection',
      types: typeNode.types.map(typeToIr),
    };
  }

  if (ts.isLiteralTypeNode(typeNode)) {
    if (ts.isStringLiteral(typeNode.literal)) {
      return { kind: 'literal', valueType: 'string', value: typeNode.literal.text };
    }
    if (ts.isNumericLiteral(typeNode.literal)) {
      return { kind: 'literal', valueType: 'number', value: Number(typeNode.literal.text) };
    }
    if (typeNode.literal.kind === ts.SyntaxKind.TrueKeyword) {
      return { kind: 'literal', valueType: 'boolean', value: true };
    }
    if (typeNode.literal.kind === ts.SyntaxKind.FalseKeyword) {
      return { kind: 'literal', valueType: 'boolean', value: false };
    }
    return { kind: 'literal', valueType: 'unknown', text: nodeText(typeNode) };
  }

  if (ts.isTypeLiteralNode(typeNode)) {
    return {
      kind: 'typeLiteral',
      members: typeNode.members.map(typeElementToIr),
    };
  }

  if (ts.isFunctionTypeNode(typeNode)) {
    return {
      kind: 'function',
      typeParams: typeNode.typeParameters?.map(typeParamToIr) ?? [],
      params: typeNode.parameters.map(paramToIr),
      returnType: typeToIr(typeNode.type),
    };
  }

  if (ts.isTypeOperatorNode(typeNode)) {
    return {
      kind: 'typeOperator',
      operator: ts.tokenToString(typeNode.operator) ?? 'unknown',
      type: typeToIr(typeNode.type),
    };
  }

  if (ts.isParenthesizedTypeNode(typeNode)) {
    return {
      kind: 'parenthesized',
      type: typeToIr(typeNode.type),
    };
  }

  if (ts.isConditionalTypeNode(typeNode)) {
    return {
      kind: 'conditional',
      checkType: typeToIr(typeNode.checkType),
      extendsType: typeToIr(typeNode.extendsType),
      trueType: typeToIr(typeNode.trueType),
      falseType: typeToIr(typeNode.falseType),
    };
  }

  if (ts.isIndexedAccessTypeNode(typeNode)) {
    return {
      kind: 'indexedAccess',
      objectType: typeToIr(typeNode.objectType),
      indexType: typeToIr(typeNode.indexType),
    };
  }

  if (ts.isTypeQueryNode(typeNode)) {
    return {
      kind: 'typeQuery',
      exprName: entityNameText(typeNode.exprName),
    };
  }

  if (ts.isMappedTypeNode(typeNode)) {
    return {
      kind: 'mappedType',
      text: nodeText(typeNode),
    };
  }

  return {
    kind: 'raw',
    text: nodeText(typeNode),
  };
}

function interfaceToIr(node) {
  return {
    kind: 'interface',
    name: node.name.text,
    exported: true,
    typeParams: node.typeParameters?.map(typeParamToIr) ?? [],
    heritage: node.heritageClauses?.map((hc) => ({
      token: ts.tokenToString(hc.token) ?? 'unknown',
      types: hc.types.map((t) => ({
        name: nodeText(t.expression),
        typeArgs: t.typeArguments?.map(typeToIr) ?? [],
      })),
    })) ?? [],
    members: node.members.map(typeElementToIr),
  };
}

function typeAliasToIr(node) {
  const ir = {
    kind: 'typeAlias',
    name: node.name.text,
    exported: true,
    typeParams: node.typeParameters?.map(typeParamToIr) ?? [],
    type: typeToIr(node.type),
  };

  if (ir.type?.kind === 'union') {
    const literals = ir.type.types
      .filter((t) => t.kind === 'literal' && t.valueType === 'string')
      .map((t) => t.value);
    if (literals.length > 0 && literals.length === ir.type.types.length) {
      ir.literalUnion = literals;
    }
  }

  return ir;
}

function enumToIr(node) {
  return {
    kind: 'enum',
    name: node.name.text,
    exported: true,
    members: node.members.map((m) => ({
      name: m.name && ts.isIdentifier(m.name) ? m.name.text : nodeText(m.name),
      value: m.initializer
        ? ts.isStringLiteral(m.initializer)
          ? m.initializer.text
          : ts.isNumericLiteral(m.initializer)
            ? Number(m.initializer.text)
            : nodeText(m.initializer)
        : null,
    })),
  };
}

function variableStatementToIr(node) {
  return node.declarationList.declarations.map((d) => ({
    kind: 'variable',
    name: nameText(d.name),
    type: typeToIr(d.type),
  }));
}

const declarations = [];
const globalDeclarations = [];

for (const statement of sourceFile.statements) {
  if (ts.isInterfaceDeclaration(statement) && statement.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) {
    declarations.push(interfaceToIr(statement));
    continue;
  }

  if (ts.isTypeAliasDeclaration(statement) && statement.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) {
    declarations.push(typeAliasToIr(statement));
    continue;
  }

  if (ts.isEnumDeclaration(statement) && statement.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) {
    declarations.push(enumToIr(statement));
    continue;
  }

  if (ts.isModuleDeclaration(statement) && statement.name.kind === ts.SyntaxKind.Identifier && statement.name.text === 'global') {
    const block = statement.body;
    if (block && ts.isModuleBlock(block)) {
      for (const globalStatement of block.statements) {
        if (ts.isVariableStatement(globalStatement)) {
          globalDeclarations.push(...variableStatementToIr(globalStatement));
        }
      }
    }
  }
}

const output = {
  source: path.basename(inputPath),
  declarationCount: declarations.length,
  declarations,
  globalDeclarations,
  symbols: declarations.map((d) => d.name),
  literalUnions: declarations
    .filter((d) => d.kind === 'typeAlias' && Array.isArray(d.literalUnion))
    .map((d) => ({ name: d.name, values: d.literalUnion })),
};

process.stdout.write(JSON.stringify(output, null, 2));

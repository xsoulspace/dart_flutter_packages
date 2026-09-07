// @map file program functions.ts
// Fixture: top-level functions, arrow consts, a generator — member
// symbols included from day one (decision 2026-09-07).
export function add(a: number, b: number): number {
  return a + b;
}

export const multiply = (a: number, b: number): number => a * b;

const LIMIT = 99;

function* countdown(from: number): Generator<number> {
  yield from;
}
// @map sym function_declaration add
// @map member lexical_declaration multiply
// @map member lexical_declaration LIMIT
// @map sym generator_function_declaration countdown

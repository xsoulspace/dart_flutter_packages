// @map file program multibyte.ts
// Fixture: emoji + CJK identifiers — byte offsets ≠ code-unit offsets is
// the classic silent corruption; the span bridge must survive it.
export function 縮める(テキスト: string): string {
  // 🚀 multibyte lives in comments, strings and identifiers alike.
  const ラベル = `🚀 ${テキスト}`;
  return ラベル;
}

export const 単語 = ['日本語', '🚀🎉'];
// @map sym function_declaration 縮める
// @map member lexical_declaration 縮める.ラベル
// @map member lexical_declaration 単語

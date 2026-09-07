// @map file program calculator.ts
// Fixture: class with a field, a member arrow const, a decorated method
// (decorators must parse without producing phantom symbols).
export class Calculator {
  private base = 10;

  private scale = (x: number): number => x * 2;

  @logged()
  greet(name: string): string {
    return `hello ${name}`;
  }

  add(a: number, b: number): number {
    return this.base + a + b;
  }
}
// @map sym class_declaration Calculator
// @map member public_field_definition Calculator.base
// @map member public_field_definition Calculator.scale
// @map member method_definition Calculator.greet
// @map member method_definition Calculator.add

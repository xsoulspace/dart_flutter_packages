// @map file program generics.ts
// Fixture: generics + an interface with signatures (members without
// bodies — the v1 boundary where body-composing actions are omitted).
export interface Repository<T> {
  size: number;
  findById(id: string): T;
}

export class MemoryRepo<T> implements Repository<T> {
  size = 0;

  findById(id: string): T {
    throw new Error(`not found: ${id}`);
  }
}
// @map sym interface_declaration Repository
// @map member property_signature Repository.size
// @map member method_signature Repository.findById
// @map sym class_declaration MemoryRepo
// @map member public_field_definition MemoryRepo.size
// @map member method_definition MemoryRepo.findById

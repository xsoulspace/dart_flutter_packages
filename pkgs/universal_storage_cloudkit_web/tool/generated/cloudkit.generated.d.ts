// CloudKit JS declaration snapshot used by tool/generate.dart.
// Source intentionally pinned in-repo for deterministic generated raw bindings.

declare const CloudKit: {
  initialize(config: unknown): Promise<void> | void;
  fetchRecordByPath(input: unknown): Promise<unknown> | unknown;
  saveRecord(input: unknown): Promise<void> | void;
  deleteRecord(input: unknown): Promise<void> | void;
  queryByPathPrefix(input: unknown): Promise<unknown[]> | unknown[];
  fetchChanges(input: unknown): Promise<unknown> | unknown;
  dispose(input?: unknown): Promise<void> | void;
};

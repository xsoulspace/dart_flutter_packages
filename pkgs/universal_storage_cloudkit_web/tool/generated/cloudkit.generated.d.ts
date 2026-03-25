// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: pinned CloudKit JS declaration snapshot for deterministic web interop generation.

export type CloudKitEnvironment = 'development' | 'production';
export type CloudKitDatabaseScope = 'private' | 'public' | 'shared';

export interface CloudKitApiTokenAuth {
  apiToken: string;
  persist?: boolean;
}

export interface CloudKitContainerConfig {
  containerIdentifier: string;
  environment: CloudKitEnvironment;
  apiTokenAuth?: CloudKitApiTokenAuth;
}

export interface CloudKitConfigureOptions {
  containerIdentifier: string;
  environment: CloudKitEnvironment;
  containers?: CloudKitContainerConfig[];
}

export interface CloudKitZoneID {
  zoneName: string;
  ownerRecordName?: string;
}

export interface CloudKitRecordID {
  recordName: string;
  zoneID?: CloudKitZoneID;
}

export interface CloudKitFieldValue {
  value: unknown;
}

export interface CloudKitRecord {
  recordName: string;
  recordType?: string;
  recordID?: CloudKitRecordID;
  recordChangeTag?: string;
  zoneID?: CloudKitZoneID;
  fields?: Record<string, CloudKitFieldValue>;
  modifiedTimestamp?: number;
}

export interface CloudKitQueryFilter {
  fieldName: string;
  comparator: string;
  fieldValue: CloudKitFieldValue;
}

export interface CloudKitQuery {
  recordType: string;
  filterBy?: CloudKitQueryFilter[];
  sortBy?: unknown[];
}

export interface CloudKitPerformQueryRequest {
  zoneID?: CloudKitZoneID;
  query: CloudKitQuery;
  resultsLimit?: number;
  continuationMarker?: string;
}

export interface CloudKitQueryResponse {
  records?: CloudKitRecord[];
  continuationMarker?: string;
}

export interface CloudKitSaveRecordsRequest {
  zoneID?: CloudKitZoneID;
  records: CloudKitRecord[];
}

export interface CloudKitDeleteRecordsRequest {
  zoneID?: CloudKitZoneID;
  recordNames?: string[];
  records?: CloudKitRecord[];
}

export interface CloudKitFetchChangedRecordsRequest {
  zoneID?: CloudKitZoneID;
  syncToken?: string;
}

export interface CloudKitChangesResponse {
  records?: CloudKitRecord[];
  updatedRecords?: CloudKitRecord[];
  deletedRecordNames?: (string | CloudKitRecordID)[];
  syncToken?: string;
  serverChangeToken?: string;
}

export interface CloudKitAuthResult {
  isAuthenticated?: boolean;
  redirectURL?: string;
  [key: string]: unknown;
}

export interface CloudKitDatabase {
  performQuery(request: CloudKitPerformQueryRequest): Promise<CloudKitQueryResponse>;
  saveRecords(request: CloudKitSaveRecordsRequest): Promise<CloudKitQueryResponse>;
  deleteRecords(request: CloudKitDeleteRecordsRequest): Promise<void>;
  fetchChangedRecords(request: CloudKitFetchChangedRecordsRequest): Promise<CloudKitChangesResponse>;
  fetchChanges(request: { serverChangeToken?: string }): Promise<CloudKitChangesResponse>;
}

export interface CloudKitContainer {
  privateCloudDatabase?: CloudKitDatabase;
  setUpAuth(): Promise<CloudKitAuthResult>;
  getDatabaseWithDatabaseScope(scope: CloudKitDatabaseScope): Promise<CloudKitDatabase>;
}

export interface CloudKitGlobal {
  configure(config: CloudKitConfigureOptions): Promise<void>;
  getDefaultContainer(): Promise<CloudKitContainer>;
  getContainer(containerIdentifier: string): Promise<CloudKitContainer>;

  // Compatibility adapter mode (optional).
  initialize?(config: unknown): Promise<void>;
  fetchRecordByPath?(input: unknown): Promise<unknown>;
  saveRecord?(input: unknown): Promise<void>;
  deleteRecord?(input: unknown): Promise<void>;
  queryByPathPrefix?(input: unknown): Promise<unknown[]>;
  fetchChanges?(input: unknown): Promise<unknown>;
  dispose?(input?: unknown): Promise<void>;
}

declare global {
  interface Window {
    CloudKit: CloudKitGlobal | undefined;
  }

  const CloudKit: CloudKitGlobal | undefined;
}

export {};

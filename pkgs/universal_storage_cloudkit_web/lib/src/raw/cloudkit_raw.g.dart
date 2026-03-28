// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: CloudKit JS declaration snapshot
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('CloudKit')
external CloudKitGlobalRaw? get cloudKitGlobal;
bool get hasCloudKitGlobal => cloudKitGlobal != null;

typedef CloudKitEnvironmentRaw = JSString;

abstract final class CloudKitEnvironmentRawValues {
  static JSString get development => 'development'.toJS;
  static JSString get production => 'production'.toJS;
}

typedef CloudKitDatabaseScopeRaw = JSString;

abstract final class CloudKitDatabaseScopeRawValues {
  static JSString get private => 'private'.toJS;
  static JSString get public => 'public'.toJS;
  static JSString get shared => 'shared'.toJS;
}

extension type CloudKitApiTokenAuthRaw(JSObject _) implements JSObject {
  external JSString get apiToken;
  external JSBoolean? get persist;
}

extension type CloudKitContainerConfigRaw(JSObject _) implements JSObject {
  external JSString get containerIdentifier;
  external CloudKitEnvironmentRaw get environment;
  external CloudKitApiTokenAuthRaw? get apiTokenAuth;
}

extension type CloudKitConfigureOptionsRaw(JSObject _) implements JSObject {
  external JSString get containerIdentifier;
  external CloudKitEnvironmentRaw get environment;
  external JSArray<CloudKitContainerConfigRaw>? get containers;
}

extension type CloudKitZoneIDRaw(JSObject _) implements JSObject {
  external JSString get zoneName;
  external JSString? get ownerRecordName;
}

extension type CloudKitRecordIDRaw(JSObject _) implements JSObject {
  external JSString get recordName;
  external CloudKitZoneIDRaw? get zoneID;
}

extension type CloudKitFieldValueRaw(JSObject _) implements JSObject {
  external JSAny? get value;
}

extension type CloudKitRecordRaw(JSObject _) implements JSObject {
  external JSString get recordName;
  external JSString? get recordType;
  external CloudKitRecordIDRaw? get recordID;
  external JSString? get recordChangeTag;
  external CloudKitZoneIDRaw? get zoneID;
  external JSObject? get fields;
  external JSNumber? get modifiedTimestamp;
}

extension type CloudKitQueryFilterRaw(JSObject _) implements JSObject {
  external JSString get fieldName;
  external JSString get comparator;
  external CloudKitFieldValueRaw get fieldValue;
}

extension type CloudKitQueryRaw(JSObject _) implements JSObject {
  external JSString get recordType;
  external JSArray<CloudKitQueryFilterRaw>? get filterBy;
  external JSArray<JSAny?>? get sortBy;
}

extension type CloudKitPerformQueryRequestRaw(JSObject _) implements JSObject {
  external CloudKitZoneIDRaw? get zoneID;
  external CloudKitQueryRaw get query;
  external JSNumber? get resultsLimit;
  external JSString? get continuationMarker;
}

extension type CloudKitQueryResponseRaw(JSObject _) implements JSObject {
  external JSArray<CloudKitRecordRaw>? get records;
  external JSString? get continuationMarker;
}

extension type CloudKitSaveRecordsRequestRaw(JSObject _) implements JSObject {
  external CloudKitZoneIDRaw? get zoneID;
  external JSArray<CloudKitRecordRaw> get records;
}

extension type CloudKitDeleteRecordsRequestRaw(JSObject _) implements JSObject {
  external CloudKitZoneIDRaw? get zoneID;
  external JSArray<JSString>? get recordNames;
  external JSArray<CloudKitRecordRaw>? get records;
}

extension type CloudKitFetchChangedRecordsRequestRaw(JSObject _)
    implements JSObject {
  external CloudKitZoneIDRaw? get zoneID;
  external JSString? get syncToken;
}

extension type CloudKitChangesResponseRaw(JSObject _) implements JSObject {
  external JSArray<CloudKitRecordRaw>? get records;
  external JSArray<CloudKitRecordRaw>? get updatedRecords;
  external JSArray<JSAny?>? get deletedRecordNames;
  external JSString? get syncToken;
  external JSString? get serverChangeToken;
}

extension type CloudKitAuthResultRaw(JSObject _) implements JSObject {
  external JSBoolean? get isAuthenticated;
  external JSString? get redirectURL;
  external JSAny? operator [](JSAny? key);
}

extension type CloudKitDatabaseRaw(JSObject _) implements JSObject {
  external JSPromise<CloudKitQueryResponseRaw> performQuery(
    CloudKitPerformQueryRequestRaw request,
  );
  external JSPromise<CloudKitQueryResponseRaw> saveRecords(
    CloudKitSaveRecordsRequestRaw request,
  );
  external JSPromise<JSAny?> deleteRecords(
    CloudKitDeleteRecordsRequestRaw request,
  );
  external JSPromise<CloudKitChangesResponseRaw> fetchChangedRecords(
    CloudKitFetchChangedRecordsRequestRaw request,
  );
  external JSPromise<CloudKitChangesResponseRaw> fetchChanges(JSAny? request);
}

extension type CloudKitContainerRaw(JSObject _) implements JSObject {
  external CloudKitDatabaseRaw? get privateCloudDatabase;
  external JSPromise<CloudKitAuthResultRaw> setUpAuth();
  external JSPromise<CloudKitDatabaseRaw> getDatabaseWithDatabaseScope(
    CloudKitDatabaseScopeRaw scope,
  );
}

extension type CloudKitGlobalRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> configure(CloudKitConfigureOptionsRaw config);
  external JSPromise<CloudKitContainerRaw> getDefaultContainer();
  external JSPromise<CloudKitContainerRaw> getContainer(
    JSString containerIdentifier,
  );
  external JSPromise<JSAny?> initialize(JSAny? config);
  external JSPromise<JSAny?> fetchRecordByPath(JSAny? input);
  external JSPromise<JSAny?> saveRecord(JSAny? input);
  external JSPromise<JSAny?> deleteRecord(JSAny? input);
  external JSPromise<JSArray<JSAny?>> queryByPathPrefix(JSAny? input);
  external JSPromise<JSAny?> fetchChanges(JSAny? input);
  external JSPromise<JSAny?> dispose([JSAny? input]);
}

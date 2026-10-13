import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

LiveApplyJournal _journal({String? profile = storagePosixRwxProfile}) =>
    LiveApplyJournal(
      runId: 'mode-vector',
      createdUtc: '2026-10-13T00:00:00Z',
      fileStateProfile: profile,
      entries: [
        LiveApplyEntry(
          path: 'a',
          prior: LiveApplyPrior(
            content: 'old',
            sha256: liveApplySha256('old'),
            mode: 0x180,
          ),
          postSha256: liveApplySha256('new'),
          postMode: 0x1ed,
          pending: true,
          pendingPreSha256: liveApplySha256('old'),
          pendingPreMode: 0x180,
        ),
      ],
    );

Map<String, dynamic> _map() =>
    (jsonDecode(jsonEncode(_journal().toMap())) as Map).cast<String, dynamic>();
Map<String, dynamic> _row(Map<String, dynamic> map) =>
    (map['entries'] as List).single as Map<String, dynamic>;

void main() {
  test('qualified prior post and pending-pre modes round-trip as v3', () {
    final map = _map();
    expect(map['schema_version'], 3);
    final read = LiveApplyJournal.fromMap(map);
    expect(read.fileStateProfile, storagePosixRwxProfile);
    final row = read.entries.single;
    expect(row.prior!.mode, 0x180);
    expect(row.postMode, 0x1ed);
    expect(row.pendingPreMode, 0x180);
    expect(read.toMap(), map);
  });

  test('creation deletion and absence retain explicit nullable modes', () {
    for (final absent in [false, true]) {
      final map = _map();
      final row = _row(map);
      row['prior'] = null;
      row['pending_pre_sha256'] = null;
      row['pending_pre_mode'] = null;
      row['post_absent'] = absent;
      row['post_mode'] = absent ? null : 0x1a4;
      expect(() => LiveApplyJournal.fromMap(map), returnsNormally);
    }
  });

  test('v3 requires declared supported profile and entries', () {
    for (final profile in [null, '', 'posix-rwx-v2', 1]) {
      final map = _map()..['file_state_profile'] = profile;
      expect(() => LiveApplyJournal.fromMap(map), throwsFormatException);
    }
    final missing = _map()..remove('entries');
    expect(() => LiveApplyJournal.fromMap(missing), throwsFormatException);
    final floatVersion = _map()..['schema_version'] = 3.0;
    expect(() => LiveApplyJournal.fromMap(floatVersion), throwsFormatException);
  });

  for (final key in ['post_mode', 'pending_pre_mode']) {
    test('v3 requires explicit $key and refuses malformed wire values', () {
      final missing = _map();
      _row(missing).remove(key);
      expect(() => LiveApplyJournal.fromMap(missing), throwsFormatException);
      for (final value in [null, -1, 512, 420.0, '0644', true]) {
        final map = _map();
        _row(map)[key] = value;
        expect(() => LiveApplyJournal.fromMap(map), throwsFormatException);
      }
    });
  }

  test('v3 refuses missing prior permission and contradictory absence', () {
    final missing = _map();
    (_row(missing)['prior'] as Map).remove('mode');
    expect(() => LiveApplyJournal.fromMap(missing), throwsFormatException);
    final absentPost = _map();
    _row(absentPost)['post_absent'] = true;
    expect(() => LiveApplyJournal.fromMap(absentPost), throwsFormatException);
    final absentPre = _map();
    _row(absentPre)['pending_pre_sha256'] = null;
    expect(() => LiveApplyJournal.fromMap(absentPre), throwsFormatException);
  });

  test('malformed in-memory v3 cannot be persisted', () {
    final journal = _journal();
    journal.entries.single.postMode = null;
    expect(journal.toMap, throwsFormatException);
    expect(_journal(profile: 'unknown').toMap, throwsFormatException);
  });

  test('legacy v2 remains content-only without guessed or extra modes', () {
    final legacy = _journal(profile: null).toMap();
    expect(legacy['schema_version'], 2);
    expect(legacy.containsKey('file_state_profile'), false);
    expect(_row(legacy).containsKey('post_mode'), false);
    expect((_row(legacy)['prior'] as Map).containsKey('mode'), false);
    // Even unqualified extra metadata cannot promote a legacy journal.
    _row(legacy)['post_mode'] = 'not a mode';
    _row(legacy)['pending_pre_mode'] = true;
    (_row(legacy)['prior'] as Map)['mode'] = 0x180;
    legacy['file_state_profile'] = storagePosixRwxProfile;
    final read = LiveApplyJournal.fromMap(legacy);
    expect(read.fileStateProfile, isNull);
    expect(read.entries.single.prior!.mode, isNull);
    expect(read.entries.single.postMode, isNull);
    expect(read.entries.single.pendingPreMode, isNull);
    expect(read.toMap()['schema_version'], 2);
  });

  test('legacy v1 ambiguity refusal and unambiguous reading are unchanged', () {
    final safe = _journal(profile: null).toMap()..remove('schema_version');
    expect(LiveApplyJournal.fromMap(safe).fileStateProfile, isNull);
    final ambiguous = _journal(profile: null).toMap()..remove('schema_version');
    _row(ambiguous)['post_sha256'] = liveApplyDeletedSha256;
    expect(() => LiveApplyJournal.fromMap(ambiguous), throwsFormatException);
  });
}

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

void main() {
  test('all origins share lifecycle but remain distinguishable', () {
    for (final origin in InteractionOrigin.values) {
      final session = InteractionSession(id: origin.name, target: 'edge', revision: 'r1', origin: origin)..begin();
      session.update({'destination': 'restore'}, currentRevision: 'r1');
      expect(session.end(currentRevision: 'r1'), {'destination': 'restore'});
      expect(session.toJson()['origin'], origin.name);
      expect(() => session.update({}, currentRevision: 'r1'), throwsStateError);
    }
  });
  test('revision drift cancels candidate rather than applying it', () {
    final session = InteractionSession(id: '1', target: 'edge', revision: 'r1', origin: InteractionOrigin.physicalHuman)..begin();
    session.update({'width': 700}, currentRevision: 'r1');
    expect(() => session.end(currentRevision: 'r2'), throwsStateError);
    expect(session.phase, InteractionPhase.cancelled); expect(session.candidate, isEmpty);
  });
}

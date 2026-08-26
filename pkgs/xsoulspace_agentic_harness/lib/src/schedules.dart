import 'package:ecsly/ecsly.dart';

/// The agent schedules, in tick order: AgencyGrant → Project → ActorAct →
/// ProcessResponses, plus Mechanical and Narrative. See
/// `docs/agent/architecture.mdx` for the full map and invariants.
abstract class Schedules {
  static const agencyGrant = ScheduleId('AgencyGrant');
  static const project = ScheduleId('Project');
  static const actorAct = ScheduleId('ActorAct');
  static const processResponses = ScheduleId('ProcessResponses');
  static const mechanical = ScheduleId('Mechanical');
  static const narrative = ScheduleId('Narrative');
}

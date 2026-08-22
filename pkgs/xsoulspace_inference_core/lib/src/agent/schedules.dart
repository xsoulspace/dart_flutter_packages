import 'package:ecsly/ecsly.dart';

abstract class Schedules {
  static const agencyGrant = ScheduleId('AgencyGrant');
  static const project = ScheduleId('Project');
  static const actorAct = ScheduleId('ActorAct');
  static const processResponses = ScheduleId('ProcessResponses');
  static const mechanical = ScheduleId('Mechanical');
  static const narrative = ScheduleId('Narrative');
}

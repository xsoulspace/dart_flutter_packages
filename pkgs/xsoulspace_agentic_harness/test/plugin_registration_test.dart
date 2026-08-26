// ignore_for_file: lines_longer_than_80_chars

/// AgentPlugin registration — what the plugin installs into a [World].
library;

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

void main() {
  group('AgentPlugin', () {
    test('registers all core schedules', () {
      final world = World()..addPlugin(AgentPlugin());
      for (final name in [
        'AgencyGrant',
        'Project',
        'ActorAct',
        'ProcessResponses',
        'Mechanical',
        'Narrative',
      ]) {
        expect(
          world.hasSchedule(ScheduleId(name)),
          isTrue,
          reason: 'missing $name',
        );
      }
    });

    test('registers event channels for the request/response loop', () {
      final world = World()..addPlugin(AgentPlugin());
      expect(world.events.hasRegistered<ActorGenerateRequest>(), isTrue);
      expect(world.events.hasRegistered<ActorGenerateResponse>(), isTrue);
      expect(world.events.hasRegistered<ActorGenerateStreamEvent>(), isTrue);
      expect(world.events.hasRegistered<ToolCallEvent>(), isTrue);
      expect(world.events.hasRegistered<ToolResultEvent>(), isTrue);
    });

    test('installs the facet index and projection resources', () {
      final world = World()..addPlugin(AgentPlugin());
      expect(world.getResource<FacetIndex>(), isNotNull);
      expect(world.getResource<ProjectionBudget>(), isNotNull);
      expect(world.getResource<ProjectionPolicy>(), isNotNull);
      expect(world.getResource<AgencyPolicy>(), isNotNull);
    });
  });
}

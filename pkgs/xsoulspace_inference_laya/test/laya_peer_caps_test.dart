import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

/// ADR 0051 Phase 4: the loopback facts stay local/none, and a mesh peer's
/// endpoint carries local-execution + network-required — the distinction the
/// model-routing ladder (local host → mesh peer → hosted) reads.
void main() {
  test('loopback default keeps local/none capability facts', () {
    final provider = LayaLocalDecisionProvider(
      runtime: LayaServeRuntime(),
    );
    expect(
      provider.capabilities.executionLocation,
      DecisionExecutionLocation.local,
    );
    expect(
      provider.capabilities.networkRequirement,
      DecisionNetworkRequirement.none,
    );
  });

  test('a mesh peer endpoint reports local execution, network required', () {
    final provider = LayaLocalDecisionProvider(
      runtime: LayaServeRuntime(),
      endpoint: Uri.parse('http://192.168.1.20:8000/v1/systemone'),
      executionLocation: DecisionExecutionLocation.local,
      networkRequirement: DecisionNetworkRequirement.required,
    );
    expect(
      provider.capabilities.executionLocation,
      DecisionExecutionLocation.local,
    );
    expect(
      provider.capabilities.networkRequirement,
      DecisionNetworkRequirement.required,
    );
  });
}

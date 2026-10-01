import '../ai/v3/ai_v3_context.dart';
import '../ai/v3/ai_v3_contract.dart';
import '../ai/v3/ai_v3_planner_service.dart';
import '../ai/v3/ai_v3_resources.dart';

/// Adapts the voice relay plan into local prepare/verify/rollback execution.
class VoiceRelayPlanner implements AiV3Planner {
  VoiceRelayPlanner({required this.request, required this.onResponse});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) request;
  final void Function(Map<String, dynamic>) onResponse;
  AiV3Plan? nextLocalPlan;
  int lastPlanningMs = 0;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    final local = nextLocalPlan;
    if (local != null) {
      nextLocalPlan = null;
      // Local microphone transcription still passes through prepare/readback.
      return AiV3PlannerResult(
        plan: local,
        meta: {'voice_local_capture': true},
      );
    }
    final planningWatch = Stopwatch()..start();
    late final Map<String, dynamic> response;
    try {
      response = await request(
        buildAiV3ContextRequestBody(
          contextData: context.data,
          originalRequest: originalRequest,
          promptTraceId: promptTraceId,
          resourceRefsEnabled: true,
        ),
      );
    } finally {
      planningWatch.stop();
      lastPlanningMs = planningWatch.elapsedMilliseconds;
    }
    final kind = response['kind'];
    if (kind == 'daw_plan') {
      final server = response['response'];
      if (server is! Map ||
          server['schema_version'] != aiV3ServerResponseVersion ||
          server['plan'] is! Map) {
        throw const AiV3PlannerException('v3_server_response_contract_invalid');
      }
      final plan = AiV3Plan.fromJson(
        Map<String, dynamic>.from(server['plan'] as Map),
        allowResourceRefs: true,
        resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
      );
      onResponse(response);
      return AiV3PlannerResult(plan: plan, meta: {'voice_relay': true});
    }
    if (kind == 'session_action') {
      final action = response['action'];
      if (action is! Map ||
          action['type'] is! String ||
          action['arguments'] is! Map) {
        throw const AiV3PlannerException('voice_session_action_invalid');
      }
      onResponse(response);
      // No success text: the controller executes this typed action afterwards.
      return const AiV3PlannerResult(
        plan: AiV3Plan(outcome: 'respond', userMessage: '', commands: []),
        meta: {'voice_session_action_pending': true},
      );
    }
    if (const {'clarify', 'respond', 'unsupported'}.contains(kind) &&
        response['message'] is String) {
      onResponse(response);
      return AiV3PlannerResult(
        plan: AiV3Plan(
          outcome: kind as String,
          userMessage: response['message'] as String,
          commands: [],
        ),
        meta: {'voice_relay': true},
      );
    }
    throw const AiV3PlannerException('voice_router_response_invalid');
  }
}

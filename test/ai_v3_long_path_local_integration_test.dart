import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_service.dart';
import 'package:mixroom/config/llm_config.dart';

void main() {
  test(
    'opt-in client completes through local REST adapter after 40 seconds',
    () async {
      final process = await Process.start(
        'python3',
        <String>[
          'tool/ai_v3_eval/local_v3_bridge.py',
          '--port',
          '0',
          '--transport',
          'long',
          '--scenario',
          'success',
          '--delay-ms',
          '40000',
        ],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          ...Platform.environment,
          'PYTHONDONTWRITEBYTECODE': '1',
        },
      );
      final ready = Completer<Map<String, dynamic>>();
      final stderr = StringBuffer();
      final stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map &&
                  decoded['message'] == 'Local V3 bridge ready' &&
                  !ready.isCompleted) {
                ready.complete(Map<String, dynamic>.from(decoded));
              }
            } on FormatException {
              // The bridge contract emits JSON lines. Ignore unrelated local
              // process output and let the startup deadline report failure.
            }
          });
      final stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(stderr.write);

      try {
        final readyPayload = await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'Local bridge did not start: ${stderr.toString()}',
          ),
        );
        final route = LlmConfig.resolveAiV3RequestRoute(
          standardApiBaseUrl: 'https://standard.example/prod',
          standardTimeoutSeconds: 35,
          longPathEnabled: true,
          longApiBaseUrl: readyPayload['url'] as String,
        );
        expect(route.usesLongPath, isTrue);
        expect(route.requestTimeoutSeconds, 130);

        final service = AiV3PlannerService(
          proxyApiBaseUrl: route.proxyApiBaseUrl,
          requestTimeout: Duration(seconds: route.requestTimeoutSeconds),
          authTokenProvider: () async => 'local-test-token',
        );
        final stopwatch = Stopwatch()..start();
        final result = await service.plan(
          context: AiV3CoreContext(
            profile: AiV3ContextProfile.essential,
            stateDigest: 'local-long-path-digest',
            data: <String, dynamic>{
              'schema_version': 'core_context_v3_prototype_1',
              'project': <String, dynamic>{
                'project_id': 'local-long-path-project',
                'bpm': 120,
              },
              'rows': const <Object>[],
              'clips': const <Object>[],
            },
          ),
          originalRequest: 'Return the deterministic local response.',
        );
        stopwatch.stop();

        expect(result.plan.outcome, 'respond');
        expect(
          stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(seconds: 35)),
        );
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 130)));

        final healthResponse = await http.get(
          Uri.parse('${route.proxyApiBaseUrl}/_local/health'),
        );
        final health = Map<String, dynamic>.from(
          jsonDecode(healthResponse.body) as Map,
        );
        expect(healthResponse.statusCode, 200);
        expect(health['transport_mode'], 'long');
        expect(health['provider_timeout_seconds'], 105);
        expect(health['lambda_timeout_seconds'], 115);
        expect(health['request_count'], 1);
        expect(health['provider_attempt_count'], 1);
        expect(health['usage_reserve_count'], 1);
        expect(health['usage_finalize_count'], 1);
        expect(health['usage_release_count'], 0);
      } finally {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      }
    },
    skip: Platform.environment['PRO4_RUN_SLOW_LOCAL_LONG_PATH'] == '1'
        ? false
        : 'set PRO4_RUN_SLOW_LOCAL_LONG_PATH=1 for the 40-second local check',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

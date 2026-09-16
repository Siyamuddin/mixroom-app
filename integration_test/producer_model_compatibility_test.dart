import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/ai/onnx_magnitude_predictor.dart';
import 'package:mixroom/ai/remote_magnitude_model_manager.dart';
import 'package:mixroom/models/goal_vector.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/project_state.dart';

// Inject local test artifacts without touching the installed model selection,
// preferences, network or producer projects.
class _TestModels extends RemoteMagnitudeModelManager {
  _TestModels(this.directory);
  final Directory directory;
  @override
  Future<MagnitudeModelSelection?> installedSelection() async =>
      MagnitudeModelSelection(
        source: 'remote',
        bundleVersion: 'pro20-native-test',
        applyModelReference: '${directory.path}/apply.onnx',
        magnitudeModelReference: '${directory.path}/magnitude.onnx',
        applyModelVersion: 'pro20-test-apply',
        magnitudeModelVersion: 'pro20-test-magnitude',
      );
  @override
  Future<void> markActivationFailed(
    MagnitudeModelSelection selection,
    Object error,
  ) async {
    throw StateError('Trained model failed native activation: $error');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'trained 77-feature artifacts run through the real local predictor',
    (tester) async {
      const apply = String.fromEnvironment('PRO20_TEST_APPLY_MODEL');
      const magnitude = String.fromEnvironment('PRO20_TEST_MAGNITUDE_MODEL');
      expect(
        apply,
        isNotEmpty,
        reason:
            'Run prepare_native_model_test.py and use --dart-define-from-file',
      );
      expect(magnitude, isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'pro20-native-models-',
      );
      await File(
        '${directory.path}/apply.onnx',
      ).writeAsBytes(base64Decode(apply));
      await File(
        '${directory.path}/magnitude.onnx',
      ).writeAsBytes(base64Decode(magnitude));
      final predictor = OnnxMixingMagnitudePredictor(
        enabled: true,
        applyModelAsset: '',
        magnitudeModelAsset: '',
        remoteModelManager: _TestModels(directory),
      );
      addTearDown(() async {
        await predictor.dispose();
        await directory.delete(recursive: true);
      });
      await predictor.load();
      expect(predictor.isReady, isTrue);
      expect(
        predictor.observabilityContext['mix_magnitude_model_bundle_version'],
        'pro20-native-test',
      );
      final project = ProjectState(
        bpm: 120,
        masterGain0to3: 1,
        maxRows: 0,
        rows: [],
        overlapMatrix: [],
        masterEffects: [
          EffectState(
            effectIndex: 0,
            name: 'Compressor',
            effectId: 'compressor',
            instanceId: '1',
            isBypassed: false,
            parameters: [
              EffectParameterState.fromMap({
                'id': 'threshold',
                'name': 'Threshold',
                'type': 'float',
                'value': -12.0,
                'min': -60.0,
                'max': 0.0,
              }),
            ],
          ),
        ],
      );
      final result = await predictor.refine(
        project: project,
        goal: GoalVector.fromJson({
          'intensity': 0.5,
          'intents': [
            {'kind': 'compressor'},
          ],
        }),
        actions: [
          MixAction('set_master_gain', {'mode': 'set', 'value': 1.5}),
          MixAction('adjust_master_effect_param_by_name', {
            'effect_name_contains': 'Compressor',
            'param_name': 'Threshold',
            'mode': 'set',
            'value': -24.0,
          }),
        ],
        strict: true,
      );
      expect(result.fallbackUsed, isFalse, reason: result.fallbackReason);
      expect(result.debugEntries, hasLength(2));
      for (final entry in result.debugEntries) {
        expect(entry.applyScore?.isFinite, isTrue);
        expect(entry.rawMagnitude?.isFinite, isTrue);
      }
      expect(result.actions, hasLength(2));
      expect(result.actions.last.data['value'], inInclusiveRange(-60, 0));
    },
  );
}

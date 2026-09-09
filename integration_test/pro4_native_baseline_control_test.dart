import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';

import 'ai_v3_midi_creation_identity_test.dart' as baseline;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = await Directory.systemTemp.createTemp('pro4_baseline_control_');
    ProjectManager.setRootDirectoryForTesting(root);
  });
  tearDownAll(() => ProjectManager.setRootDirectoryForTesting(null));
  // Run the existing test unchanged; isolate only its project storage.
  baseline.main();
}

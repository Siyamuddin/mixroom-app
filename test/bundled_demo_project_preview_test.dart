import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled demo preview is derived from the project document', () async {
    const assetPath =
        'assets/demo_projects/Demo Project (Standard Jazz).mixroom';

    final preview = await ProjectManager.readBundledDemoProjectPreview(
      assetPath,
    );

    expect(preview, isNotNull);
    expect(preview!.name, 'Demo Project (Standard Jazz)');
    expect(preview.tempoBpm, 73);
    expect(
      preview.rows.map((row) => row.name),
      containsAll(<String>['Bass', 'Piano', 'Drums']),
    );
    expect(preview.clips, hasLength(3));
    expect(preview.clips.every((clip) => clip.durationSeconds > 86), isTrue);
    expect(
      preview.clips.every((clip) => clip.waveformPeaks.length == 96),
      isTrue,
    );
    expect(
      preview.clips.every((clip) => clip.waveformPeaks.toSet().length > 8),
      isTrue,
    );
  });
}

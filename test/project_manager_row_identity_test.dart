import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';

void main() {
  group('ProjectManager row identity restore', () {
    test('resolves saved clip row using persisted row ids when available', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{'rowId': 42, 'name': 'Drums', 'iconId': 0},
        <String, dynamic>{'rowId': 91, 'name': 'Bass', 'iconId': 0},
        <String, dynamic>{'rowId': 7, 'name': 'Vocals', 'iconId': 0},
      ];

      final persisted = ProjectManager.persistedRowOrderIndexById(rows);
      final track = <String, dynamic>{
        'rowId': 91,
        'rowIndex': 0,
      };

      expect(
        ProjectManager.resolveSavedTrackRowIndex(
          track: track,
          persistedRowIndexById: persisted,
        ),
        1,
      );
    });

    test('falls back to row index for legacy projects without persisted rows',
        () {
      final track = <String, dynamic>{
        'rowId': 91,
        'rowIndex': 2,
      };

      expect(
        ProjectManager.resolveSavedTrackRowIndex(
          track: track,
          persistedRowIndexById: const <int, int>{},
        ),
        2,
      );
    });
  });

  group('ProjectManager unique audio file names', () {
    test('increments duplicate basenames while preserving extension', () {
      final used = <String>{};

      final first = ProjectManager.uniqueAudioFileName(
        preferredName: 'kick.wav',
        usedNamesLower: used,
      );
      final second = ProjectManager.uniqueAudioFileName(
        preferredName: 'kick.wav',
        usedNamesLower: used,
      );
      final third = ProjectManager.uniqueAudioFileName(
        preferredName: 'kick.wav',
        usedNamesLower: used,
      );

      expect(first, 'kick.wav');
      expect(second, 'kick #1.wav');
      expect(third, 'kick #2.wav');
    });
  });
}

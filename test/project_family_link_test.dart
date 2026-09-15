import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_compatibility_service.dart';
import 'package:mixroom/helpers/project_manager.dart';

void main() {
  test('frozen mix fork writes family fields without grouping by name', () {
    final original = <String, dynamic>{
      'name': 'Night Song',
      'projectId': 'orig-123',
    };
    final fork = <String, dynamic>{
      'name': 'Night Song Frozen mix',
      'projectId': 'fork-999',
    };

    ProjectManager.applyFrozenMixFamily(originalJson: original, forkJson: fork);

    expect(original['familyId'], 'orig-123');
    expect(original['mixKind'], ProjectManager.mixKindOriginal);
    expect(original['projectId'], 'orig-123');
    expect(fork['familyId'], 'orig-123');
    expect(fork['mixKind'], ProjectManager.mixKindFrozen);
    expect(fork['forkedFromProjectId'], 'orig-123');
    expect(fork['projectId'], 'fork-999');
  });

  test('assignFreshProjectId replaces both projectId keys', () {
    final json = <String, dynamic>{
      'projectId': 'old-id',
      'project_id': 'legacy-id',
      'name': 'Song',
    };

    final next = ProjectManager.assignFreshProjectId(json);

    expect(next, isNotEmpty);
    expect(next, isNot(equals('old-id')));
    expect(json['projectId'], next);
    expect(json.containsKey('project_id'), isFalse);
    expect(json['name'], 'Song');
  });

  test('manual duplicate strips family fields', () {
    final json = <String, dynamic>{
      'name': 'Night Song Copy',
      'projectId': 'copy-1',
      'familyId': 'orig-123',
      'mixKind': ProjectManager.mixKindFrozen,
      'forkedFromProjectId': 'orig-123',
    };

    ProjectManager.stripFamilyMetadata(json);

    expect(json.containsKey('familyId'), isFalse);
    expect(json.containsKey('mixKind'), isFalse);
    expect(json.containsKey('forkedFromProjectId'), isFalse);
    expect(json['projectId'], 'copy-1');
  });

  test('frozen mix display name stays collision-friendly', () {
    expect(ProjectManager.frozenMixDisplayName('Song'), 'Song Frozen mix');
    expect(
      ProjectManager.frozenMixDisplayName('Song Frozen mix'),
      'Song Frozen mix',
    );
    expect(ProjectManager.frozenMixDisplayName('  '), 'Frozen mix');
  });

  test('later frozen mixes are numbered from 2', () {
    expect(
      ProjectManager.frozenMixDisplayName('Song', index: 1),
      'Song Frozen mix',
    );
    expect(
      ProjectManager.frozenMixDisplayName('Song', index: 2),
      'Song Frozen mix 2',
    );
    expect(
      ProjectManager.frozenMixDisplayName('Song', index: 10),
      'Song Frozen mix 10',
    );
    expect(ProjectManager.frozenMixDisplayName('  ', index: 3), 'Frozen mix 3');
  });

  test('frozen mix index is read back from default names only', () {
    int? indexOf(String frozenName) => ProjectManager.frozenMixIndexFromName(
      originalName: 'Song',
      frozenName: frozenName,
    );

    expect(indexOf('Song Frozen mix'), 1);
    expect(indexOf('song frozen mix'), 1);
    expect(indexOf('Song Frozen mix 2'), 2);
    expect(indexOf('Song Frozen mix 12'), 12);
    expect(indexOf('Song Frozen mix #1'), isNull);
    expect(indexOf('Song Frozen mix 1'), isNull);
    expect(indexOf('Song Frozen mix 0'), isNull);
    expect(indexOf('Custom frozen label'), isNull);
    expect(indexOf('Other Song Frozen mix 2'), isNull);
  });

  test('next frozen mix number is the smallest unused one', () {
    int next(List<String> existing) => ProjectManager.nextFrozenMixIndex(
      originalName: 'Song',
      existingFrozenNames: existing,
      allProjectNames: <String>['Song', ...existing],
    );

    expect(next(const <String>[]), 1);
    expect(next(const <String>['Song Frozen mix']), 2);
    expect(next(const <String>['Song Frozen mix', 'Song Frozen mix 2']), 3);
    // Deleting "2" and making another copy gives "2" back, not "4".
    expect(next(const <String>['Song Frozen mix', 'Song Frozen mix 3']), 2);
    // Custom names and legacy "#1" copies do not reserve a number.
    expect(next(const <String>['My custom copy', 'Song Frozen mix #1']), 1);
  });

  test('next frozen mix number skips names used by any project', () {
    // An unrelated project already called "Song Frozen mix 2" (no family
    // link) must not be overwritten or turned into a "#1" folder name.
    expect(
      ProjectManager.nextFrozenMixIndex(
        originalName: 'Song',
        existingFrozenNames: const <String>['Song Frozen mix'],
        allProjectNames: const <String>[
          'Song',
          'Song Frozen mix',
          'song frozen mix 2',
        ],
      ),
      3,
    );
    // An Original that itself ends in "Frozen mix" collides with index 1,
    // so its first copy is "Chill Frozen mix 2".
    expect(
      ProjectManager.nextFrozenMixIndex(
        originalName: 'Chill Frozen mix',
        existingFrozenNames: const <String>[],
        allProjectNames: const <String>['Chill Frozen mix'],
      ),
      2,
    );
    expect(
      ProjectManager.frozenMixDisplayName('Chill Frozen mix', index: 2),
      'Chill Frozen mix 2',
    );
  });

  test('frozen mix label keeps the number and drops the song name', () {
    expect(ProjectManager.frozenMixLabel('Song Frozen mix'), 'Frozen mix');
    expect(ProjectManager.frozenMixLabel('Song Frozen mix 2'), 'Frozen mix 2');
    expect(
      ProjectManager.frozenMixLabel('Renamed thing Frozen mix 7'),
      'Frozen mix 7',
    );
    expect(ProjectManager.frozenMixLabel('Custom frozen label'), 'Frozen mix');
    expect(ProjectManager.frozenMixLabel('Song Frozen mix #1'), 'Frozen mix');
  });

  test(
    'family link metadata does not invalidate the playable mix fingerprint',
    () {
      final original = <String, dynamic>{
        'name': 'Night Song',
        'projectId': 'orig-123',
        'tempoBpm': 120,
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{
            'fileName': 'placeholder.wav',
            'clipType': 'midi',
            'rowIndex': 0,
            'instrumentId': 'vst3:com.acme.synth',
            'instrumentOrigin': 'third_party',
          },
        ],
      };
      final linked = Map<String, dynamic>.from(original);
      final fork = <String, dynamic>{'projectId': 'fork-999'};
      ProjectManager.applyFrozenMixFamily(originalJson: linked, forkJson: fork);

      expect(
        ProjectCompatibilityService.sourceFingerprint(linked),
        ProjectCompatibilityService.sourceFingerprint(original),
      );
      expect(
        ProjectCompatibilityService.cloudChangeFingerprint(linked),
        ProjectCompatibilityService.cloudChangeFingerprint(original),
      );
    },
  );
}

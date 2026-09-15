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

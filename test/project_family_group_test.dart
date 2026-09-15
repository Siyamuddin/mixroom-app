import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_family.dart';
import 'package:mixroom/helpers/project_manager.dart';

ProjectMeta _meta({
  required String name,
  required String projectId,
  String? familyId,
  String? mixKind,
  DateTime? lastOpenedAt,
}) {
  return ProjectMeta(
    dir: Directory('/tmp/$projectId'),
    name: name,
    projectId: projectId,
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: lastOpenedAt ?? DateTime(2026, 1, 2),
    familyId: familyId,
    mixKind: mixKind,
  );
}

void main() {
  test('groups by familyId and never by display name', () {
    final original = _meta(
      name: 'Night Song',
      projectId: 'orig-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindOriginal,
    );
    final frozen = _meta(
      name: 'Night Song Frozen mix',
      projectId: 'fork-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindFrozen,
    );
    final otherSameName = _meta(name: 'Night Song', projectId: 'other-1');
    final otherUntitled = _meta(name: 'Untitled', projectId: 'untitled-1');
    final anotherUntitled = _meta(name: 'Untitled', projectId: 'untitled-2');

    final groups = groupProjectsByFamily(<ProjectMeta>[
      frozen,
      otherUntitled,
      original,
      otherSameName,
      anotherUntitled,
    ]);

    expect(groups, hasLength(4));
    final family = groups.singleWhere((group) => group.familyId == 'orig-1');
    expect(family.members, hasLength(2));
    expect(family.displayProject.projectId, 'orig-1');
    expect(family.frozenMix?.projectId, 'fork-1');
    expect(family.canExpand, isTrue);
    expect(
      groups.where((group) => group.displayProject.name == 'Untitled'),
      hasLength(2),
    );
    expect(
      groups.where((group) => group.displayProject.name == 'Night Song'),
      hasLength(2),
    );
  });

  test('projects without family fields stay ungrouped', () {
    final first = _meta(name: 'Legacy Copy', projectId: 'legacy-1');
    final second = _meta(name: 'Legacy Copy Frozen mix', projectId: 'legacy-2');

    final groups = groupProjectsByFamily(<ProjectMeta>[first, second]);

    expect(groups, hasLength(2));
    expect(groups.every((group) => group.isLinkedFamily), isFalse);
    expect(groups.every((group) => group.canExpand), isFalse);
  });

  test('search matches a collapsed frozen mix member', () {
    final group = ProjectFamilyGroup(
      members: <ProjectMeta>[
        _meta(
          name: 'Night Song',
          projectId: 'orig-1',
          familyId: 'orig-1',
          mixKind: ProjectManager.mixKindOriginal,
        ),
        _meta(
          name: 'Night Song Frozen mix',
          projectId: 'fork-1',
          familyId: 'orig-1',
          mixKind: ProjectManager.mixKindFrozen,
        ),
      ],
    );

    expect(group.matchesQuery('frozen'), isTrue);
    expect(group.matchesQuery('Night'), isTrue);
    expect(group.matchesQuery('zzz'), isFalse);
  });

  test('family groups still count each folder toward the project limit', () {
    final projects = <ProjectMeta>[
      _meta(
        name: 'Song',
        projectId: 'orig-1',
        familyId: 'orig-1',
        mixKind: ProjectManager.mixKindOriginal,
      ),
      _meta(
        name: 'Song Frozen mix',
        projectId: 'fork-1',
        familyId: 'orig-1',
        mixKind: ProjectManager.mixKindFrozen,
      ),
      _meta(name: 'Other', projectId: 'other-1'),
    ];

    final groups = groupProjectsByFamily(projects);
    expect(groups, hasLength(2));
    expect(projects.length, 3);
    expect(
      groups.fold<int>(0, (count, group) => count + group.members.length),
      projects.length,
    );
  });

  test('local frozen sibling is found by familyId, not by name', () {
    final original = _meta(
      name: 'Song',
      projectId: 'orig-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindOriginal,
    );
    final frozen = _meta(
      name: 'Custom frozen label',
      projectId: 'fork-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindFrozen,
    );
    final sameName = _meta(name: 'Song Frozen mix', projectId: 'unrelated');

    expect(
      localFrozenMixSibling(
        projects: <ProjectMeta>[frozen, sameName],
        localProject: original,
      )?.projectId,
      'fork-1',
    );
    expect(
      frozenMixNameFollowsOriginal(
        originalName: 'Song',
        frozenName: 'Song Frozen mix',
      ),
      isTrue,
    );
    expect(
      frozenMixNameFollowsOriginal(
        originalName: 'Song',
        frozenName: 'Custom frozen label',
      ),
      isFalse,
    );
  });
}

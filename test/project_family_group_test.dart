import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_family.dart';
import 'package:mixroom/helpers/project_manager.dart';

ProjectMeta _meta({
  required String name,
  required String projectId,
  String? familyId,
  String? mixKind,
  DateTime? createdAt,
  DateTime? lastOpenedAt,
}) {
  return ProjectMeta(
    dir: Directory('/tmp/$projectId'),
    name: name,
    projectId: projectId,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
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

  test('frozen mixes without their original are shown as plain projects', () {
    final frozenA = _meta(
      name: 'Night Song Frozen mix',
      projectId: 'fork-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindFrozen,
    );
    final frozenB = _meta(
      name: 'Night Song Frozen mix 2',
      projectId: 'fork-2',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindFrozen,
    );
    final unrelated = _meta(name: 'Other', projectId: 'other-1');

    final groups = groupProjectsByFamily(<ProjectMeta>[
      frozenA,
      unrelated,
      frozenB,
    ]);

    // No Original on this device -> no group; each copy is its own row.
    expect(groups, hasLength(3));
    expect(groups.every((group) => group.canExpand), isFalse);
    expect(
      groups.map((group) => group.displayProject.name),
      containsAll(<String>[
        'Night Song Frozen mix',
        'Night Song Frozen mix 2',
        'Other',
      ]),
    );
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

  test('numbered frozen mixes still follow the original name', () {
    expect(
      frozenMixNameFollowsOriginal(
        originalName: 'Song',
        frozenName: 'Song Frozen mix 2',
      ),
      isTrue,
    );
    expect(
      frozenMixNameFollowsOriginal(
        originalName: 'Song',
        frozenName: 'Song Frozen mix #1',
      ),
      isFalse,
    );
  });

  test('frozen mixes are listed in creation order, original first', () {
    final original = _meta(
      name: 'Song',
      projectId: 'orig-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindOriginal,
      createdAt: DateTime(2026, 1, 1),
    );
    ProjectMeta frozen(String name, String id, int day) => _meta(
      name: name,
      projectId: id,
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindFrozen,
      createdAt: DateTime(2026, 1, day),
    );
    final group = ProjectFamilyGroup(
      members: <ProjectMeta>[
        frozen('Song Frozen mix 10', 'fork-10', 12),
        frozen('Song Frozen mix 2', 'fork-2', 3),
        original,
        frozen('Song Frozen mix', 'fork-1', 2),
      ],
    );

    expect(group.members.map((member) => member.projectId).toList(), <String>[
      'orig-1',
      'fork-1',
      'fork-2',
      'fork-10',
    ]);
    expect(group.displayProject.projectId, 'orig-1');
  });

  test('all frozen mixes of a family are found by familyId', () {
    final original = _meta(
      name: 'Song',
      projectId: 'orig-1',
      familyId: 'orig-1',
      mixKind: ProjectManager.mixKindOriginal,
    );
    final projects = <ProjectMeta>[
      _meta(
        name: 'Song Frozen mix',
        projectId: 'fork-1',
        familyId: 'orig-1',
        mixKind: ProjectManager.mixKindFrozen,
      ),
      _meta(name: 'Song Frozen mix 2', projectId: 'unrelated'),
      _meta(
        name: 'Custom label',
        projectId: 'fork-2',
        familyId: 'orig-1',
        mixKind: ProjectManager.mixKindFrozen,
      ),
      original,
    ];

    expect(
      localFrozenMixesOf(
        projects: projects,
        original: original,
      ).map((member) => member.projectId).toList(),
      <String>['fork-1', 'fork-2'],
    );
    expect(
      localFrozenMixesOf(
        projects: projects,
        original: _meta(name: 'Loose', projectId: 'loose'),
      ),
      isEmpty,
    );
  });
}

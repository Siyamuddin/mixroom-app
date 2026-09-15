import 'package:mixroom/helpers/project_manager.dart';

bool projectIsFrozenMix(ProjectMeta meta) {
  return (meta.mixKind ?? '').trim() == ProjectManager.mixKindFrozen;
}

String? projectFamilyId(ProjectMeta meta) {
  final id = (meta.familyId ?? '').trim();
  return id.isEmpty ? null : id;
}

class ProjectFamilyGroup {
  ProjectFamilyGroup({required List<ProjectMeta> members})
    : members = List<ProjectMeta>.unmodifiable(_sortedMembers(members));

  final List<ProjectMeta> members;

  String? get familyId => projectFamilyId(members.first);

  bool get isLinkedFamily => familyId != null;

  bool get canExpand => members.length > 1;

  ProjectMeta get displayProject {
    for (final member in members) {
      if (!projectIsFrozenMix(member)) return member;
    }
    return members.first;
  }

  ProjectMeta? get original {
    for (final member in members) {
      if (!projectIsFrozenMix(member)) return member;
    }
    return null;
  }

  ProjectMeta? get frozenMix {
    for (final member in members) {
      if (projectIsFrozenMix(member)) return member;
    }
    return null;
  }

  DateTime get sortOpenedAt {
    var latest = members.first.lastOpenedAt;
    for (final member in members.skip(1)) {
      if (member.lastOpenedAt.isAfter(latest)) {
        latest = member.lastOpenedAt;
      }
    }
    return latest;
  }

  bool matchesQuery(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    return members.any((member) => member.name.toLowerCase().contains(trimmed));
  }
}

List<ProjectFamilyGroup> groupProjectsByFamily(Iterable<ProjectMeta> projects) {
  final grouped = <String, List<ProjectMeta>>{};
  final ungrouped = <ProjectFamilyGroup>[];
  for (final project in projects) {
    final familyId = projectFamilyId(project);
    if (familyId == null) {
      ungrouped.add(ProjectFamilyGroup(members: <ProjectMeta>[project]));
      continue;
    }
    grouped.putIfAbsent(familyId, () => <ProjectMeta>[]).add(project);
  }
  return <ProjectFamilyGroup>[
    for (final members in grouped.values) ProjectFamilyGroup(members: members),
    ...ungrouped,
  ];
}

/// True when [frozenName] is still a default name for [originalName]
/// (`Song Frozen mix`, `Song Frozen mix 2`, ...), so it should follow the
/// original when the original is renamed.
bool frozenMixNameFollowsOriginal({
  required String originalName,
  required String frozenName,
}) {
  return ProjectManager.frozenMixIndexFromName(
        originalName: originalName,
        frozenName: frozenName,
      ) !=
      null;
}

/// Every Frozen mix that belongs to the same family as [original].
List<ProjectMeta> localFrozenMixesOf({
  required Iterable<ProjectMeta> projects,
  required ProjectMeta original,
}) {
  final familyId = projectFamilyId(original);
  if (familyId == null) return const <ProjectMeta>[];
  return <ProjectMeta>[
    for (final project in projects)
      if (projectFamilyId(project) == familyId && projectIsFrozenMix(project))
        project,
  ];
}

ProjectMeta? localFrozenMixSibling({
  required Iterable<ProjectMeta> projects,
  required ProjectMeta? localProject,
}) {
  if (localProject == null) return null;
  final familyId = projectFamilyId(localProject);
  if (familyId == null) return null;
  for (final project in projects) {
    if (projectFamilyId(project) != familyId) continue;
    if (projectIsFrozenMix(project)) return project;
  }
  return null;
}

List<ProjectMeta> _sortedMembers(List<ProjectMeta> members) {
  final sorted = List<ProjectMeta>.from(members);
  sorted.sort((a, b) {
    final aFrozen = projectIsFrozenMix(a);
    final bFrozen = projectIsFrozenMix(b);
    if (aFrozen != bFrozen) return aFrozen ? 1 : -1;
    // Frozen mixes are snapshots, so list them in the order they were made.
    // A name sort would put "Frozen mix 10" before "Frozen mix 2".
    if (aFrozen && bFrozen) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      if (byCreated != 0) return byCreated;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

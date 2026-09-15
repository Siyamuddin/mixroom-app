import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final openBrace = source.indexOf('{', start + signature.length);
  expect(openBrace, greaterThan(start), reason: signature);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace, i + 1);
      }
    }
  }
  fail('Unclosed method: $signature');
}

void main() {
  late String projects;
  late String familyHelper;

  setUpAll(() {
    projects = File('lib/screens/projects.dart').readAsStringSync();
    familyHelper = File('lib/helpers/project_family.dart').readAsStringSync();
  });

  test('On Device lists family groups instead of one row per folder', () {
    expect(
      familyHelper,
      contains('List<ProjectFamilyGroup> groupProjectsByFamily('),
    );
    expect(familyHelper, contains('projectFamilyId(project)'));
    expect(familyHelper, isNot(contains('project.name ==')));

    final visible = _methodBody(
      projects,
      'List<ProjectFamilyGroup> _visibleProjectGroups()',
    );
    expect(visible, contains('groupProjectsByFamily('));
    expect(visible, contains('_projects'));
    expect(visible, contains('group.matchesQuery(query)'));

    final entries = _methodBody(
      projects,
      'List<_ProjectListEntry> _visibleEntriesForTab(_ProjectLibraryTab tab)',
    );
    expect(entries, contains('_visibleProjectGroups()'));
    expect(entries, contains('_ProjectListEntry.family'));
    expect(
      entries,
      isNot(contains('_visibleProjects().map(_ProjectListEntry.project)')),
    );
  });

  test('deleting an original with a frozen sibling asks mix vs song', () {
    final delete = _methodBody(
      projects,
      'Future<void> _deleteProject(ProjectMeta meta) async',
    );
    expect(delete, contains('_showDeleteMixOrSongDialog('));
    expect(delete, contains('_FamilyDeleteScope.song'));
    expect(delete, contains('projectIsFrozenMix(meta)'));
    expect(projects, contains('_FamilyDeleteScope.mix'));

    expect(projects, contains("ValueKey('projects_delete_this_mix')"));
    expect(projects, contains("ValueKey('projects_delete_whole_song')"));
    expect(
      projects,
      contains('Delete only this mix, or the original and Frozen mix?'),
    );
  });

  test('cloud tiles stay one song and surface a local Frozen mix action', () {
    final cloudVisible = _methodBody(
      projects,
      'List<CloudProjectAccessItem> _visibleCloudProjects()',
    );
    expect(cloudVisible, contains('_cloudProjects.where((project)'));
    expect(cloudVisible, contains('localFrozenMixSibling('));
    expect(cloudVisible, isNot(contains('_ProjectListEntry.project')));

    expect(projects, contains('_buildOnDeviceFamilyTile('));
    expect(projects, contains('frozenMix'));
    expect(projects, contains("'Frozen mix'"));
  });
}

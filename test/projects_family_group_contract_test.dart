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

  test('deleting any member of a song group asks mix vs song', () {
    final delete = _methodBody(
      projects,
      'Future<void> _deleteProject(ProjectMeta meta) async',
    );
    expect(delete, contains('_showDeleteMixOrSongDialog('));
    expect(delete, contains('_FamilyDeleteScope.song'));
    expect(projects, contains('_FamilyDeleteScope.mix'));
    // The choice is offered for the Original and for a Frozen mix alike:
    // the only condition is that the project sits in a group.
    expect(delete, contains('if (group.canExpand) {'));
    expect(delete, isNot(contains('!projectIsFrozenMix(meta)')));
    expect(delete, contains('songName: meta.name'));

    expect(projects, contains("ValueKey('projects_delete_this_mix')"));
    expect(projects, contains("ValueKey('projects_delete_whole_song')"));
    expect(
      projects,
      contains('Delete only this mix, or the original and Frozen mix?'),
    );

    // The dialog knows how many Frozen mixes go with the song and says so
    // when there is more than one, on both the question and the red button.
    expect(
      delete,
      contains(
        'frozenMixCount: group.members.where(projectIsFrozenMix).length',
      ),
    );
    final dialog = _methodBody(
      projects,
      'Future<_FamilyDeleteScope?> _showDeleteMixOrSongDialog({',
    );
    expect(
      projects,
      contains(
        'Future<_FamilyDeleteScope?> _showDeleteMixOrSongDialog({\n'
        '    required String songName,\n'
        '    required int frozenMixCount,\n',
      ),
    );
    expect(
      dialog,
      contains(
        'Delete only this mix, or the original and {count} Frozen mixes?',
      ),
    );
    expect(dialog, contains('Whole song ({count} projects)'));
    expect(dialog, contains("replaceAll('{count}', '\${frozenMixCount + 1}')"));
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

  test('frozen mixes cannot be synced to Cloud as a separate project', () {
    final menu = _methodBody(projects, 'Future<void> _showProjectItemMenu({');
    expect(menu, contains('!projectIsFrozenMix(project)'));

    final sync = _methodBody(
      projects,
      'Future<void> _syncProjectToCloud(ProjectMeta meta) async',
    );
    expect(sync, contains('projectIsFrozenMix(meta)'));
    expect(
      sync,
      contains(
        'Frozen mixes stay on this device. Sync the original project instead.',
      ),
    );
  });
}

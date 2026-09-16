import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final asyncBrace = source.indexOf('async {', start);
  expect(asyncBrace, greaterThan(start), reason: signature);
  final openBrace = source.indexOf('{', asyncBrace);
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
  late String projectManager;

  setUpAll(() {
    projects = File('lib/screens/projects.dart').readAsStringSync();
    projectManager = File(
      'lib/helpers/project_manager.dart',
    ).readAsStringSync();
  });

  test(
    'opening a local project checks the cloud before pushing the editor',
    () {
      final openProject = _methodBody(projects, 'Future<void> _openProject(');
      expect(openProject, contains('checkCloud'));
      expect(openProject, contains('_openLinkedLocalProject('));
      // An interrupted Cloud update is repaired before anything is read,
      // on every open path (cloud check or not).
      expect(
        openProject.indexOf('recoverInterruptedUpdate(dir)'),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(openProject.indexOf('_pushEditor(')),
        ),
      );

      final linkedOpen = _methodBody(
        projects,
        'Future<void> _openLinkedLocalProject(ProjectMeta meta) async',
      );
      expect(linkedOpen, contains('_applyLocalOpenAction('));
      expect(linkedOpen, contains('kCloudOpenCheckTimeout'));
      expect(linkedOpen, contains('isNetworkUnavailableError('));
      expect(
        linkedOpen,
        contains(
          "Couldn't check for cloud updates. Opened the copy on this device.",
        ),
      );

      final apply = _methodBody(
        projects,
        'Future<void> _applyLocalOpenAction({',
      );
      expect(
        apply,
        contains('resolveLocalOpenAction(project: meta, cloud: cloud)'),
      );
      expect(apply, contains('_updateLocalProjectFromCloud('));
      expect(apply, contains('_showLocalCloudConflictDialog('));
    },
  );

  test('in-place cloud updates skip the local project limit', () {
    final update = _methodBody(
      projects,
      'Future<void> _updateLocalProjectFromCloud({',
    );
    expect(update, contains('updateProjectFromMixroomBundle('));
    expect(update, contains('ProjectVersionReason.cloudUpdate'));
    expect(update, isNot(contains('canCreateNew')));
    expect(update, contains('_cloudProjectsInFlight'));
  });

  test('keep both needs a free slot and unlinks the local copy', () {
    final keepBoth = _methodBody(
      projects,
      'Future<void> _keepBothLocalAndCloud({',
    );
    expect(keepBoth, contains('canCreateNew'));
    expect(keepBoth, contains('stripCloudSyncMetadata'));
    expect(keepBoth, contains('stripFamilyMetadata'));
    expect(keepBoth, contains('assignFreshProjectId'));
    expect(keepBoth, contains('_downloadAndOpenNewCloudCopy('));
    // A local Original keeps its Frozen mixes: the family moves to the fresh
    // id instead of being stripped, and the copies are pointed at it.
    expect(keepBoth, contains("json['familyId'] = newProjectId"));
    expect(
      keepBoth,
      contains("json['mixKind'] = ProjectManager.mixKindOriginal"),
    );
    expect(keepBoth, contains('relinkFrozenMixFamily('));
    expect(keepBoth, contains('oldFamilyId: oldFamilyId'));
    expect(keepBoth, contains('newProjectId: newProjectId'));
    expect(
      keepBoth.indexOf('relinkFrozenMixFamily('),
      allOf(
        greaterThan(keepBoth.indexOf('writeProjectJson(renamedDir, json)')),
        lessThan(keepBoth.indexOf('_downloadAndOpenNewCloudCopy(')),
      ),
    );

    final export = _methodBody(projects, 'Future<void> _startProjectExport(');
    expect(export, contains('checkCloud: false'));
  });

  test(
    'cloud matching prefers an exact cloudProjectId over localProjectId',
    () {
      final localStart = projects.indexOf(
        'ProjectMeta? _localProjectForCloud(CloudProjectAccessItem cloud)',
      );
      final cloudStart = projects.indexOf(
        'CloudProjectAccessItem? _cloudProjectForLocal(ProjectMeta meta)',
      );
      expect(localStart, greaterThanOrEqualTo(0));
      expect(cloudStart, greaterThan(localStart));
      final localForCloud = projects.substring(localStart, cloudStart);
      expect(
        localForCloud.indexOf('project.cloudProjectId'),
        lessThan(localForCloud.indexOf('cloud.localProjectId')),
      );

      final nextMethod = projects.indexOf(
        'List<_CloudProjectDestination> _availableCloudDestinations',
        cloudStart,
      );
      expect(nextMethod, greaterThan(cloudStart));
      final cloudForLocal = projects.substring(cloudStart, nextMethod);
      expect(
        cloudForLocal.indexOf('cloudProjectId.isNotEmpty'),
        lessThan(
          cloudForLocal.indexOf('project.localProjectId == meta.projectId'),
        ),
      );
    },
  );

  test('cloud list refresh does not stamp a local fingerprint as synced', () {
    final persist = _methodBody(
      projects,
      'Future<void> _persistCloudLinksForLocalMatches() async',
    );
    expect(persist, isNot(contains('cloudSourceFingerprint')));
    expect(persist, isNot(contains('sourceFingerprint(')));
    expect(persist, contains("json['cloudProjectId'] = cloud.projectId"));
    expect(projects, contains("'Sync status unknown'"));
  });

  test(
    'cloud tab reuses the local open dispatcher instead of detaching a stale copy',
    () {
      final openCloud = _methodBody(
        projects,
        'Future<void> _openCloudProject(CloudProjectAccessItem cloud) async',
      );
      expect(openCloud, contains('_applyLocalOpenAction('));
      expect(openCloud, contains('_downloadAndOpenNewCloudCopy('));
      expect(openCloud, isNot(contains("staleJson.remove('cloudProjectId')")));
      expect(openCloud, isNot(contains('importMixroomBundle')));
    },
  );

  test('bundle import can update an existing project folder in place', () {
    expect(
      projectManager,
      contains('static Future<void> updateProjectFromMixroomBundle({'),
    );
    expect(projectManager, contains('incomingUpdateDirectoryName'));
    final update = _methodBody(
      projectManager,
      'static Future<void> updateProjectFromMixroomBundle({',
    );
    expect(update, contains("jsonMap['projectId'] = localProjectId"));
    expect(update, contains("jsonMap['name'] = p.basename(projectDir.path)"));
    // The new JSON is staged next to project.json and only replaces it by a
    // rename after both folder swaps: that rename is the commit point.
    expect(update, contains('incomingProjectJsonName'));
    expect(update, contains('_renameOver(incomingJsonFile, existingJsonFile)'));
    expect(update, isNot(contains('writeProjectJson(projectDir, jsonMap)')));
    expect(update, contains('_swapDirectory'));
    expect(update, contains('_restoreOutgoingDirectory'));
    expect(
      update.indexOf('_renameOver(incomingJsonFile, existingJsonFile)'),
      greaterThan(update.lastIndexOf('_swapDirectory(')),
    );
    expect(
      update.indexOf('committed = true;'),
      greaterThan(update.indexOf('_renameOver(')),
    );
    expect(update, contains('if (!committed)'));
    expect(projectManager, contains('_runFfmpegOrThrow'));
    expect(projectManager, contains('getReturnCode()'));
  });
}

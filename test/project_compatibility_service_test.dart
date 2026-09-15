import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_compatibility_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('detects third-party dependencies across plugin scopes', () {
    final manifest = ProjectCompatibilityService.inspect(_sourceProject());

    expect(
      manifest.dependencies.map((item) => item.scope),
      containsAll(<Object>[
        ProjectCompatibilityScope.instrument,
        ProjectCompatibilityScope.row,
        ProjectCompatibilityScope.group,
        ProjectCompatibilityScope.master,
      ]),
    );
    expect(manifest.dependencies, hasLength(4));
  });

  test('invalidates a frozen instrument when its MIDI clip moves', () {
    final source = _sourceProject();
    final dependency = ProjectCompatibilityService.inspect(source).dependencies
        .firstWhere(
          (item) => item.scope == ProjectCompatibilityScope.instrument,
        );
    final moved = Map<String, dynamic>.from(jsonDecode(_json(source)) as Map);
    final tracks = (moved['tracks'] as List).cast<Map>();
    tracks.single['offset'] = 12.5;

    expect(
      ProjectCompatibilityService.artifactFingerprint(source, dependency),
      isNot(ProjectCompatibilityService.artifactFingerprint(moved, dependency)),
    );
  });

  test('keeps a frozen MIDI row at its absolute project position', () {
    final source = _sourceProject()
      ..['rowEffects'] = <Map<String, dynamic>>[]
      ..['trackGroups'] = <Map<String, dynamic>>[]
      ..['master'] = <String, dynamic>{
        'effects': <String, dynamic>{'effects': <Map<String, dynamic>>[]},
      };
    final inspected = ProjectCompatibilityService.inspect(source);
    final dependency = inspected.dependencies.single;
    const frozenOffsetSeconds = 12.5;
    final projection = ProjectCompatibilityService.buildCompatibleProjection(
      sourceProject: source,
      manifest: ProjectCompatibilityManifest(
        sourceFingerprint: inspected.sourceFingerprint,
        dependencies: inspected.dependencies,
        artifacts: <ProjectCompatibilityArtifact>[
          ProjectCompatibilityArtifact(
            dependencyKey: dependency.key,
            fileName: 'compatibility/audio/frozen_row_0.wav',
            fingerprint: ProjectCompatibilityService.artifactFingerprint(
              source,
              dependency,
            ),
            trackJson: <String, dynamic>{
              'fileName': 'compatibility/audio/frozen_row_0.wav',
              'clipType': 'audio',
              'clipId': 'compatibility-frozen-row-0',
              'rowIndex': 0,
              'offset': frozenOffsetSeconds,
              'trimStartMs': 0,
            },
            replacementRows: const <int>[0],
          ),
        ],
      ),
    );

    final frozenTrack = (projection['tracks'] as List).single as Map;
    expect(frozenTrack['offset'], frozenOffsetSeconds);
    expect(frozenTrack['clipType'], 'audio');
  });

  test(
    'promotes compatibility audio when its portable view is edited',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mixroom_compat_edit_',
      );
      try {
        final sourceProject = Directory(p.join(root.path, 'source'));
        final editedProject = Directory(p.join(root.path, 'edited'));
        final compatibilityAudio =
            ProjectCompatibilityService.audioDirectoryFor(sourceProject);
        await compatibilityAudio.create(recursive: true);
        await Directory(
          p.join(editedProject.path, 'audio'),
        ).create(recursive: true);
        final referenceMix = File(
          p.join(compatibilityAudio.path, 'original_mix_reference.wav'),
        );
        await referenceMix.writeAsBytes(<int>[1, 2, 3], flush: true);

        final promoted =
            await ProjectCompatibilityService.promoteAudioForEditedCopy(
              sourceProjectDir: sourceProject,
              editedProjectDir: editedProject,
              audioFiles: <File>[referenceMix, referenceMix],
            );

        final promotedFile = promoted[p.normalize(referenceMix.path)];
        expect(promotedFile, isNotNull);
        expect(
          p.isWithin(p.join(editedProject.path, 'audio'), promotedFile!.path),
          isTrue,
        );
        expect(
          ProjectCompatibilityService.persistedAudioFileName(
            projectDir: editedProject,
            audioFile: promotedFile,
          ),
          'original_mix_reference.wav',
        );
        expect(await promotedFile.readAsBytes(), <int>[1, 2, 3]);
        expect(promoted, hasLength(1));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('uses the rendered mix when the master has an unavailable plugin', () {
    final source = _sourceProject()
      ..['rows'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'rowId': 10,
          'name': 'Synth',
          'kind': 'instrument',
          'groupId': 'band',
        },
        <String, dynamic>{
          'rowId': 11,
          'name': 'Bass',
          'kind': 'audio',
          'groupId': 'band',
        },
      ]
      ..['tracks'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'fileName': 'synth.wav',
          'clipType': 'audio',
          'rowIndex': 0,
          'clipId': 'synth',
        },
        <String, dynamic>{
          'fileName': 'bass.wav',
          'clipType': 'audio',
          'rowIndex': 1,
          'clipId': 'bass',
        },
      ]
      ..['rowStates'] = <Map<String, dynamic>>[
        <String, dynamic>{'row': 0, 'gain': 1.3, 'pan': 0.2},
        <String, dynamic>{'row': 1, 'gain': 2.4, 'pan': 0.8},
      ]
      ..['trackGroups'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'band',
          'rowIds': <int>[10, 11],
          'gain': 1.5,
          'pan': 0.25,
          'effects': <Map<String, dynamic>>[
            <String, dynamic>{
              'effectId': 'mixroom:compressor',
              'pluginOrigin': 'mixroom',
            },
          ],
        },
      ];
    final inspected = ProjectCompatibilityService.inspect(source);
    final masterDependencies = inspected.dependencies
        .where(
          (dependency) => dependency.scope == ProjectCompatibilityScope.master,
        )
        .toList(growable: false);
    const referenceMix = 'compatibility/audio/original_mix_reference.wav';

    final projection = ProjectCompatibilityService.buildCompatibleProjection(
      sourceProject: source,
      manifest: ProjectCompatibilityManifest(
        sourceFingerprint: inspected.sourceFingerprint,
        dependencies: masterDependencies,
        artifacts: <ProjectCompatibilityArtifact>[
          for (final dependency in masterDependencies)
            ProjectCompatibilityArtifact(
              dependencyKey: dependency.key,
              fileName: referenceMix,
              fingerprint: ProjectCompatibilityService.artifactFingerprint(
                source,
                dependency,
              ),
            ),
        ],
        referenceMixFileName: referenceMix,
      ),
    );

    final tracks = (projection['tracks'] as List).cast<Map>();
    expect(tracks, hasLength(1));
    expect(tracks.single['fileName'], referenceMix);
    expect(tracks.single['clipId'], 'compatibility-original-mix');
    final rows = (projection['rows'] as List).cast<Map>();
    expect(rows.map((row) => row['name']), <Object?>[
      'Master',
      'Synth',
      'Bass',
    ]);
    expect(rows.first['kind'], 'audio');
    expect(tracks.single['rowIndex'], 0);
    expect(tracks.single['rowId'], rows.first['rowId']);
    final rowStates = (projection['rowStates'] as List).cast<Map>();
    expect(rowStates.map((state) => state['row']), <Object?>[0, 1, 2]);
    expect(rowStates.first['rowId'], rows.first['rowId']);
    expect(rowStates.map((state) => state['gain']), everyElement(2.0));
    expect(rowStates.map((state) => state['pan']), everyElement(0.5));
    final group = (projection['trackGroups'] as List).single as Map;
    expect(group['gain'], 2.0);
    expect(group['pan'], 0.5);
    expect(group['effects'], isEmpty);
    final master = projection['master'] as Map;
    expect(master['gain'], 2.0);
    expect(master['pan'], 0.5);
    expect((master['effects'] as Map)['effects'], isEmpty);
  });

  test('invalidates plugin audio when the project sample rate changes', () {
    final source = _sourceProject()
      ..['ui'] = <String, dynamic>{
        'sampleRate': 44100,
        'crossfadeMode': 'equal_power',
        'showProducerCaptureUi': true,
      };
    final dependency = ProjectCompatibilityService.inspect(source).dependencies
        .firstWhere(
          (item) => item.scope == ProjectCompatibilityScope.instrument,
        );
    final changed = Map<String, dynamic>.from(jsonDecode(_json(source)) as Map);
    (changed['ui'] as Map)['sampleRate'] = 48000;

    expect(
      ProjectCompatibilityService.sourceFingerprint(source),
      isNot(ProjectCompatibilityService.sourceFingerprint(changed)),
    );
    expect(
      ProjectCompatibilityService.artifactFingerprint(source, dependency),
      isNot(
        ProjectCompatibilityService.artifactFingerprint(changed, dependency),
      ),
    );
  });

  test('maps frozen rows to their unavailable plugin names', () {
    final source = _sourceProject();
    final manifest = ProjectCompatibilityService.inspect(source);
    final instrument = manifest.dependencies.firstWhere(
      (item) => item.scope == ProjectCompatibilityScope.instrument,
    );
    final rowEffect = manifest.dependencies.firstWhere(
      (item) => item.scope == ProjectCompatibilityScope.row,
    );
    final names = ProjectCompatibilityService.frozenPluginNamesByRow(
      manifest: ProjectCompatibilityManifest(
        sourceFingerprint: manifest.sourceFingerprint,
        dependencies: manifest.dependencies,
        artifacts: <ProjectCompatibilityArtifact>[
          ProjectCompatibilityArtifact(
            dependencyKey: instrument.key,
            fileName: 'compatibility/audio/synth.wav',
            fingerprint: 'synth',
            trackJson: <String, dynamic>{
              'fileName': 'compatibility/audio/synth.wav',
              'rowIndex': 0,
            },
            replacementRows: const <int>[0],
          ),
          ProjectCompatibilityArtifact(
            dependencyKey: rowEffect.key,
            fileName: 'compatibility/audio/fx.wav',
            fingerprint: 'fx',
            replacementRows: const <int>[0],
          ),
        ],
      ),
      projection: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{
            'fileName': 'compatibility/audio/synth.wav',
            'rowIndex': 0,
          },
        ],
      },
    );

    expect(names[0], containsAll(<String>['Acme Synth', 'Acme Delay']));
  });

  test(
    'writes a current plugin-free projection and resolves it for a host without plugins',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_compat_',
      );
      try {
        final source = _sourceProject();
        await File(
          p.join(projectDir.path, 'project.json'),
        ).writeAsString(_json(source));
        final dependencies = ProjectCompatibilityService.inspect(
          source,
        ).dependencies;
        final audioDir = ProjectCompatibilityService.audioDirectoryFor(
          projectDir,
        );
        await audioDir.create(recursive: true);
        final artifacts = <ProjectCompatibilityArtifact>[];
        var referenceMixFileName = '';
        for (var index = 0; index < dependencies.length; index++) {
          final fileName = 'compatibility/audio/frozen_$index.wav';
          await File(p.join(projectDir.path, fileName)).writeAsBytes(<int>[1]);
          if (dependencies[index].scope == ProjectCompatibilityScope.master) {
            referenceMixFileName = fileName;
          }
          artifacts.add(
            ProjectCompatibilityArtifact(
              dependencyKey: dependencies[index].key,
              fileName: fileName,
              fingerprint: ProjectCompatibilityService.artifactFingerprint(
                source,
                dependencies[index],
              ),
              trackJson:
                  dependencies[index].scope ==
                      ProjectCompatibilityScope.instrument
                  ? <String, dynamic>{
                      'fileName': fileName,
                      'label': 'Frozen synth',
                      'clipType': 'audio',
                      'rowIndex': 0,
                      'clipId': 'clip-1',
                    }
                  : null,
              replacementRows:
                  dependencies[index].scope ==
                      ProjectCompatibilityScope.instrument
                  ? const <int>[0]
                  : const <int>[],
            ),
          );
        }

        await ProjectCompatibilityService.writeCompatibleCopy(
          projectDir: projectDir,
          sourceProject: source,
          artifacts: artifacts,
          referenceMixFileName: referenceMixFileName,
        );

        expect(await ProjectCompatibilityService.isCurrent(projectDir), isTrue);
        // Cloud import can assign a local display name. That metadata must
        // not make a valid frozen sidecar fall back to the plugin source.
        source['name'] = 'Renamed cloud copy';
        source['familyId'] = 'orig-123';
        source['mixKind'] = 'original';
        await File(
          p.join(projectDir.path, 'project.json'),
        ).writeAsString(_json(source));
        expect(await ProjectCompatibilityService.isCurrent(projectDir), isTrue);
        final opened = await ProjectCompatibilityService.resolveForOpen(
          projectDir: projectDir,
          sourceProject: source,
          canHostExternalPlugins: false,
          hasPlugin: (_) => false,
        );
        expect(opened.usingCompatibleAudio, isTrue);
        expect(opened.playableOnThisDevice, isTrue);
        final tracks = (opened.projectState['tracks'] as List).cast<Map>();
        expect(tracks.single['clipType'], 'audio');
        expect(tracks.single['fileName'], referenceMixFileName);
        expect(tracks.single['instrumentId'], isEmpty);
        final rows = (opened.projectState['rows'] as List).cast<Map>();
        expect(rows, hasLength(1));
        expect(rows.single['name'], 'Master');
        expect(tracks.single['rowId'], rows.single['rowId']);
        final rowEffects = (opened.projectState['rowEffects'] as List)
            .cast<Map>();
        expect((rowEffects.single['effects'] as List), isEmpty);
        final master = opened.projectState['master'] as Map;
        final masterEffects = (master['effects'] as Map)['effects'] as List;
        expect(masterEffects, isEmpty);
      } finally {
        await projectDir.delete(recursive: true);
      }
    },
  );

  test(
    'missing sidecar on a plugin-less host is not a playable open',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_compat_nomix_',
      );
      try {
        final source = _sourceProject();
        await File(
          p.join(projectDir.path, 'project.json'),
        ).writeAsString(_json(source));
        final opened = await ProjectCompatibilityService.resolveForOpen(
          projectDir: projectDir,
          sourceProject: source,
          canHostExternalPlugins: false,
          hasPlugin: (_) => false,
        );
        expect(opened.usingCompatibleAudio, isFalse);
        expect(opened.playableOnThisDevice, isFalse);
        expect(
          identical(opened.projectState, source) ||
              opened.projectState['tracks'] == source['tracks'],
          isTrue,
        );
      } finally {
        await projectDir.delete(recursive: true);
      }
    },
  );

  test(
    'unready plugin catalog is not treated as every plugin being available',
    () {
      expect(
        ProjectCompatibilityService.isPlayableOnThisDevice(
          sourceProject: _sourceProject(),
          usingCompatibleAudio: false,
          canHostExternalPlugins: true,
          hasPlugin: (_) => true,
          pluginCatalogReady: false,
        ),
        isFalse,
      );
      expect(
        ProjectCompatibilityService.isPlayableOnThisDevice(
          sourceProject: _sourceProject(),
          usingCompatibleAudio: true,
          canHostExternalPlugins: true,
          hasPlugin: (_) => true,
          pluginCatalogReady: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'unready catalog still prefers a current sidecar and blocks raw plugin source',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_compat_unready_',
      );
      try {
        final source = _sourceProject();
        await File(
          p.join(projectDir.path, 'project.json'),
        ).writeAsString(_json(source));
        final openedSource = await ProjectCompatibilityService.resolveForOpen(
          projectDir: projectDir,
          sourceProject: source,
          canHostExternalPlugins: true,
          hasPlugin: (_) => true,
          pluginCatalogReady: false,
        );
        expect(openedSource.usingCompatibleAudio, isFalse);
        expect(openedSource.playableOnThisDevice, isFalse);

        final dependencies = ProjectCompatibilityService.inspect(
          source,
        ).dependencies;
        final audioDir = ProjectCompatibilityService.audioDirectoryFor(
          projectDir,
        );
        await audioDir.create(recursive: true);
        final artifacts = <ProjectCompatibilityArtifact>[];
        var referenceMixFileName = '';
        for (var index = 0; index < dependencies.length; index++) {
          final fileName = 'compatibility/audio/frozen_$index.wav';
          await File(p.join(projectDir.path, fileName)).writeAsBytes(<int>[1]);
          if (dependencies[index].scope == ProjectCompatibilityScope.master) {
            referenceMixFileName = fileName;
          }
          artifacts.add(
            ProjectCompatibilityArtifact(
              dependencyKey: dependencies[index].key,
              fileName: fileName,
              fingerprint: ProjectCompatibilityService.artifactFingerprint(
                source,
                dependencies[index],
              ),
              trackJson:
                  dependencies[index].scope ==
                      ProjectCompatibilityScope.instrument
                  ? <String, dynamic>{
                      'fileName': fileName,
                      'label': 'Frozen synth',
                      'clipType': 'audio',
                      'rowIndex': 0,
                      'clipId': 'clip-1',
                    }
                  : null,
              replacementRows:
                  dependencies[index].scope ==
                      ProjectCompatibilityScope.instrument
                  ? const <int>[0]
                  : const <int>[],
            ),
          );
        }
        await ProjectCompatibilityService.writeCompatibleCopy(
          projectDir: projectDir,
          sourceProject: source,
          artifacts: artifacts,
          referenceMixFileName: referenceMixFileName,
        );

        final openedSidecar = await ProjectCompatibilityService.resolveForOpen(
          projectDir: projectDir,
          sourceProject: source,
          canHostExternalPlugins: true,
          hasPlugin: (_) => true,
          pluginCatalogReady: false,
        );
        expect(openedSidecar.usingCompatibleAudio, isTrue);
        expect(openedSidecar.playableOnThisDevice, isTrue);
      } finally {
        await projectDir.delete(recursive: true);
      }
    },
  );

  test('stale sidecar on a plugin-less host is not a playable open', () async {
    final projectDir = await Directory.systemTemp.createTemp(
      'mixroom_compat_stale_',
    );
    try {
      final source = _sourceProject();
      await File(
        p.join(projectDir.path, 'project.json'),
      ).writeAsString(_json(source));
      await Directory(
        p.join(projectDir.path, 'compatibility'),
      ).create(recursive: true);
      await File(
        p.join(projectDir.path, 'compatibility', 'manifest.json'),
      ).writeAsString(
        _json(<String, dynamic>{
          'version': ProjectCompatibilityManifest.version,
          'sourceFingerprint': 'stale-fingerprint',
          'dependencies': const <Map<String, dynamic>>[],
          'artifacts': const <Map<String, dynamic>>[],
        }),
      );
      await File(
        p.join(projectDir.path, 'compatibility', 'project.json'),
      ).writeAsString(_json(source));
      final opened = await ProjectCompatibilityService.resolveForOpen(
        projectDir: projectDir,
        sourceProject: source,
        canHostExternalPlugins: false,
        hasPlugin: (_) => false,
      );
      expect(opened.usingCompatibleAudio, isFalse);
      expect(opened.playableOnThisDevice, isFalse);
    } finally {
      await projectDir.delete(recursive: true);
    }
  });

  test(
    'keeps compatibility audio paths when a fallback project is saved',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_compat_path_',
      );
      try {
        final frozenFile = File(
          p.join(projectDir.path, 'compatibility', 'audio', 'frozen.wav'),
        );
        await frozenFile.parent.create(recursive: true);
        await frozenFile.writeAsBytes(<int>[1]);

        expect(
          ProjectCompatibilityService.persistedAudioFileName(
            projectDir: projectDir,
            audioFile: frozenFile,
          ),
          'compatibility/audio/frozen.wav',
        );
        expect(
          ProjectCompatibilityService.resolveAudioFile(
            projectDir,
            'compatibility/audio/frozen.wav',
          ).path,
          frozenFile.path,
        );
      } finally {
        await projectDir.delete(recursive: true);
      }
    },
  );

  test(
    'does not treat a projection with stripped frozen paths as current',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_compat_validation_',
      );
      try {
        final source = _sourceProject()
          ..['rowEffects'] = <Map<String, dynamic>>[]
          ..['trackGroups'] = <Map<String, dynamic>>[]
          ..['master'] = <String, dynamic>{
            'effects': <String, dynamic>{'effects': <Map<String, dynamic>>[]},
          };
        await File(
          p.join(projectDir.path, 'project.json'),
        ).writeAsString(_json(source));
        final dependency = ProjectCompatibilityService.inspect(source)
            .dependencies
            .firstWhere(
              (item) => item.scope == ProjectCompatibilityScope.instrument,
            );
        const fileName = 'compatibility/audio/frozen.wav';
        final frozenFile = File(p.join(projectDir.path, fileName));
        await frozenFile.parent.create(recursive: true);
        await frozenFile.writeAsBytes(<int>[1]);
        await ProjectCompatibilityService.writeCompatibleCopy(
          projectDir: projectDir,
          sourceProject: source,
          artifacts: <ProjectCompatibilityArtifact>[
            ProjectCompatibilityArtifact(
              dependencyKey: dependency.key,
              fileName: fileName,
              fingerprint: ProjectCompatibilityService.artifactFingerprint(
                source,
                dependency,
              ),
              trackJson: <String, dynamic>{
                'fileName': fileName,
                'clipType': 'audio',
                'rowIndex': 0,
                'clipId': 'frozen',
              },
              replacementRows: const <int>[0],
            ),
          ],
        );
        final projectionFile = ProjectCompatibilityService.projectionFileFor(
          projectDir,
        );
        final projection = Map<String, dynamic>.from(
          jsonDecode(await projectionFile.readAsString()) as Map,
        );
        final track = (projection['tracks'] as List).single as Map;
        track['fileName'] = 'frozen.wav';
        await projectionFile.writeAsString(_json(projection));

        expect(
          await ProjectCompatibilityService.isCurrent(projectDir),
          isFalse,
        );
      } finally {
        await projectDir.delete(recursive: true);
      }
    },
  );
}

Map<String, dynamic> _sourceProject() => <String, dynamic>{
  'name': 'Third-party session',
  'tracks': <Map<String, dynamic>>[
    <String, dynamic>{
      'fileName': 'placeholder.wav',
      'clipType': 'midi',
      'rowIndex': 0,
      'clipId': 'clip-1',
      'instrumentId': 'vst3:com.acme.synth',
      'instrumentOrigin': 'third_party',
      'instrumentName': 'Acme Synth',
    },
  ],
  'rowEffects': <Map<String, dynamic>>[
    <String, dynamic>{
      'row': 0,
      'effects': <Map<String, dynamic>>[
        <String, dynamic>{
          'effectId': 'au:com.acme.delay',
          'pluginOrigin': 'third_party',
          'displayName': 'Acme Delay',
        },
      ],
    },
  ],
  'trackGroups': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'drums',
      'effects': <Map<String, dynamic>>[
        <String, dynamic>{
          'effectId': '/Library/Audio/Plug-Ins/VST3/Glue.vst3',
          'displayName': 'Glue',
        },
      ],
    },
  ],
  'master': <String, dynamic>{
    'effects': <String, dynamic>{
      'effects': <Map<String, dynamic>>[
        <String, dynamic>{
          'effectId': 'AudioUnit:Effects:com.acme.limiter',
          'displayName': 'Acme Limiter',
        },
      ],
    },
  },
};

String _json(Map<String, dynamic> value) => const JsonEncoder().convert(value);

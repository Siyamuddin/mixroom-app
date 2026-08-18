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
        for (var index = 0; index < dependencies.length; index++) {
          final fileName = 'compatibility/audio/frozen_$index.wav';
          await File(p.join(projectDir.path, fileName)).writeAsBytes(<int>[1]);
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
        );

        expect(await ProjectCompatibilityService.isCurrent(projectDir), isTrue);
        // Cloud import can assign a local display name. That metadata must
        // not make a valid frozen sidecar fall back to the plugin source.
        source['name'] = 'Renamed cloud copy';
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
        final tracks = (opened.projectState['tracks'] as List).cast<Map>();
        expect(tracks.single['clipType'], 'audio');
        expect(tracks.single['instrumentId'], isEmpty);
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

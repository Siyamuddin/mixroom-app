/*
class ProjectManager = logic for a creating/saving a project
class ProjectBundle = export; define format for sharing projects
class ProjectBundleImport = import; opening the zipped project

Export usage:
final path = await ProjectBundle.exportMixroomBundle(
  projectDir: _projectDir,
  audioMode: BundleAudioMode.flacLossless, // or preserveAsIs
);

Import usage:
final newDir = await ProjectBundleImport.importMixroomBundle(
  bundleFile: File(pickedPath),
  audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
);

*/

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';

class ProjectMeta {
  final Directory dir;
  final String name;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  ProjectMeta({
    required this.dir,
    required this.name,
    required this.createdAt,
    required this.lastOpenedAt,
  });
}

class ProjectManager {
  static const int maxProjects = 5;

  static Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, "mixroom_projects"));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static File _projectJsonFile(Directory dir) => File(p.join(dir.path, "project.json"));
  static Directory _audioDir(Directory dir) => Directory(p.join(dir.path, "audio"));

  static String _sanitizeFolderName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') // safe cross-platform
        .replaceAll(RegExp(r'\s+'), ' ');
    final safe = cleaned.isEmpty ? "Untitled Project" : cleaned;
    return safe.length > 60 ? safe.substring(0, 60).trim() : safe;
  }

  static Future<Directory> _nextAvailableProjectDirName(String preferredName) async {
    final root = await _rootDir();
    final base = _sanitizeFolderName(preferredName);

    Directory candidate = Directory(p.join(root.path, base));
    if (!await candidate.exists()) return candidate;

    int i = 1;
    while (true) {
      candidate = Directory(p.join(root.path, "$base #$i"));
      if (!await candidate.exists()) return candidate;
      i++;
    }
  }

  static Future<List<ProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final dirs = root.listSync().whereType<Directory>().toList();

    final metas = <ProjectMeta>[];
    for (final d in dirs) {
      final f = _projectJsonFile(d);
      if (!f.existsSync()) continue;
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        metas.add(
          ProjectMeta(
            dir: d,
            name: (json["name"] ?? "Untitled") as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch((json["createdAt"] ?? 0) as int),
            lastOpenedAt: DateTime.fromMillisecondsSinceEpoch((json["lastOpenedAt"] ?? 0) as int),
          ),
        );
      } catch (_) {}
    }

    metas.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return metas;
  }

  static Future<bool> canCreateNew() async {
    final list = await listProjects();
    return list.length < maxProjects;
  }

  static Future<Directory> createNewProjectDir({String name = "Untitled Project"}) async {
    final dir = await _nextAvailableProjectDirName(name);
    await dir.create(recursive: true);

    final audio = _audioDir(dir);
    if (!await audio.exists()) await audio.create(recursive: true);

    final now = DateTime.now().millisecondsSinceEpoch;

    // IMPORTANT: the real project name must match the final folder name
    final folderName = p.basename(dir.path);

    final json = <String, dynamic>{
      "version": 1,
      "name": folderName,
      "createdAt": now,
      "lastOpenedAt": now,
      "tracks": [],
      "rowEffects": [],
      "masterEffects": {"effects": []},
      "projectId": now.toString(),
    };

    await _projectJsonFile(dir).writeAsString(jsonEncode(json));
    return dir;
  }

  static Future<void> deleteProject(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<Directory> renameProject(Directory dir, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const FormatException("Project name can’t be empty.");
    }

    final jsonFileOld = _projectJsonFile(dir);
    if (!await jsonFileOld.exists()) {
      throw FileSystemException("project.json missing", jsonFileOld.path);
    }

    // Find collision-safe folder name inside SAME parent
    final parent = dir.parent;
    final base = _sanitizeFolderName(trimmed);

    Directory desired = Directory(p.join(parent.path, base));
    if (await desired.exists()) {
      int i = 1;
      while (true) {
        desired = Directory(p.join(parent.path, "$base #$i"));
        if (!await desired.exists()) break;
        i++;
      }
    }

    // 1) Rename folder FIRST (so folder+json will match)
    Directory finalDir = dir;
    if (p.normalize(dir.path) != p.normalize(desired.path)) {
      finalDir = await dir.rename(desired.path); // IMPORTANT: capture returned Directory
    }

    // 2) Update JSON name INSIDE the NEW folder.
    // If you want json name to match folder name exactly (including #1), use folderName:
    final folderName = p.basename(finalDir.path);

    final jsonFileNew = _projectJsonFile(finalDir);
    final json = jsonDecode(await jsonFileNew.readAsString()) as Map<String, dynamic>;
    json["name"] = folderName; // guarantees match
    await jsonFileNew.writeAsString(jsonEncode(json));

    return finalDir;
  }

  static Future<Map<String, dynamic>> readProjectJson(Directory dir) async {
    final f = _projectJsonFile(dir);
    if (!await f.exists()) {
      throw Exception("project.json missing in ${dir.path}");
    }
    return (jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  static Future<void> writeProjectJson(Directory dir, Map<String, dynamic> json) async {
    final f = _projectJsonFile(dir);
    await f.writeAsString(jsonEncode(json));
  }

  static Directory audioDir(Directory dir) => _audioDir(dir);
}

enum BundleAudioMode {
  preserveAsIs, // copy whatever files are in project/audio/ in their respective formats
  flacLossless, // convert everything to .flac (lossless)
}

class ProjectBundle {
  static Future<String> exportMixroomBundle({
    required Directory projectDir,
    required BundleAudioMode audioMode,
  }) async {
    final projectJson = File(p.join(projectDir.path, "project.json"));
    if (!projectJson.existsSync()) {
      throw Exception("Missing project.json in ${projectDir.path}");
    }

    final jsonMap = jsonDecode(projectJson.readAsStringSync()) as Map<String, dynamic>;
    final projectName = (jsonMap["name"] as String?) ?? "Mixroom Project";

    final tmpDir = await getTemporaryDirectory();
    final base = _sanitizeFileName(projectName);
    String bundlePath = p.join(tmpDir.path, "$base.mixroom");

    // staging folders
    final staging = Directory(p.join(tmpDir.path, "mixroom_bundle_staging_${DateTime.now().millisecondsSinceEpoch}"));
    await staging.create(recursive: true);

    // ensure project.json
    await projectJson.copy(p.join(staging.path, "project.json"));

    // copy/convert audio
    final srcAudioDir = Directory(p.join(projectDir.path, "audio"));
    final dstAudioDir = Directory(p.join(staging.path, "audio"));
    await dstAudioDir.create(recursive: true);

    if (await srcAudioDir.exists()) {
      final audioFiles = srcAudioDir.listSync().whereType<File>().toList();

      for (final f in audioFiles) {
        final ext = p.extension(f.path).toLowerCase();

        if (audioMode == BundleAudioMode.preserveAsIs) {
          await f.copy(p.join(dstAudioDir.path, p.basename(f.path)));
        } else {
          final outName = "${p.basenameWithoutExtension(f.path)}.flac";
          final outPath = p.join(dstAudioDir.path, outName);

          if (ext == ".flac") {
            await f.copy(outPath);
          } else {
            await _convertToFlacLossless(inPath: f.path, outPath: outPath);
          }
        }
      }
    }

    // meta.json
    final meta = {
      "bundleVersion": 1,
      "audioMode": audioMode.name,
      "exportedAt": DateTime.now().toIso8601String(),
    };
    await File(p.join(staging.path, "meta.json")).writeAsString(jsonEncode(meta));

    // --------------------------------------------
    // BUILD THE ZIP USING archive (no ZipFileEncoder)
    // --------------------------------------------

    final archive = Archive();

    // Add project.json
    final stagedProjJson = File(p.join(staging.path, "project.json"));
    final projBytes = stagedProjJson.readAsBytesSync();
    archive.addFile(ArchiveFile("project.json", projBytes.length, projBytes));

    // Add meta.json
    final stagedMetaJson = File(p.join(staging.path, "meta.json"));
    final metaBytes = stagedMetaJson.readAsBytesSync();
    archive.addFile(ArchiveFile("meta.json", metaBytes.length, metaBytes));

    // Add audio files
    final audioDirInStaging = Directory(p.join(staging.path, "audio"));
    if (audioDirInStaging.existsSync()) {
      for (final file in audioDirInStaging.listSync().whereType<File>()) {
        final bytes = file.readAsBytesSync();
        archive.addFile(
          ArchiveFile(
            "audio/${p.basename(file.path)}",
            bytes.length,
            bytes,
          ),
        );
      }
    }

    // Encode ZIP in memory
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null || zipData.isEmpty) {
      throw Exception("ZipEncoder produced empty archive");
    }

    // Write to disk
    final outFile = File(bundlePath);
    await outFile.writeAsBytes(zipData, flush: true);

    // Optional sanity check
    final len = await outFile.length();
    if (len < 1024) {
      throw Exception("Export resulted in tiny file ($len bytes)");
    }

    // Cleanup staging
    try {
      await staging.delete(recursive: true);
    } catch (_) {}

    return bundlePath;
  }

  static Future<void> _convertToFlacLossless({required String inPath, required String outPath}) async {
    // FLAC is lossless. This preserves audio quality; it just compresses storage.
    // You can add -ar 48000 if you WANT to standardize, but it’s not required.
    final cmd = '-y -i "${inPath}" -c:a flac "${outPath}"';
    await FFmpegKit.execute(cmd);
  }

  static String _sanitizeFileName(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? "MixroomProject" : cleaned;
  }
}

enum ImportAudioStrategy {
  keepAsBundled, // if bundle has flac, keep flac; if wav keep wav
  convertFlacToWav48k // if bundle has flac, convert to wav 48k (useful if your engine expects wav)
}

class ProjectBundleImport {
  static Future<Directory> importMixroomBundle({
    required File bundleFile,
    required ImportAudioStrategy audioStrategy,
  }) async {
    if (!bundleFile.existsSync()) throw Exception("Bundle file missing");

    final tmpDir = await getTemporaryDirectory();
    final unpackDir = Directory(p.join(tmpDir.path, "mixroom_unpacked_${DateTime.now().millisecondsSinceEpoch}"));
    await unpackDir.create(recursive: true);

    // unzip into unpackDir
    final bytes = bundleFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final item in archive) {
      final outPath = p.join(unpackDir.path, item.name);
      if (item.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(item.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    // read incoming project.json
    final incomingJsonFile = File(p.join(unpackDir.path, "project.json"));
    if (!incomingJsonFile.existsSync()) throw Exception("Bundle missing project.json");

    final jsonMap = jsonDecode(incomingJsonFile.readAsStringSync()) as Map<String, dynamic>;
    final incomingName = (jsonMap["name"] as String?) ?? "Imported Project";

    // create a new local project dir (handles name collision via #1)
    final destProjectDir = await ProjectManager.createNewProjectDir(name: incomingName);

    // final project name MUST match the resolved folder name
    final resolvedName = p.basename(destProjectDir.path);

    // update json BEFORE writing
    jsonMap["name"] = resolvedName;
    jsonMap["lastOpenedAt"] = DateTime.now().millisecondsSinceEpoch;

    // write once
    await File(p.join(destProjectDir.path, "project.json")).writeAsString(jsonEncode(jsonMap));

    // import audio
    final srcAudioDir = Directory(p.join(unpackDir.path, "audio"));
    final dstAudioDir = Directory(p.join(destProjectDir.path, "audio"));
    await dstAudioDir.create(recursive: true);

    if (await srcAudioDir.exists()) {
      final files = srcAudioDir.listSync().whereType<File>().toList();
      for (final f in files) {
        final ext = p.extension(f.path).toLowerCase();
        final base = p.basenameWithoutExtension(f.path);

        if (audioStrategy == ImportAudioStrategy.convertFlacToWav48k && ext == ".flac") {
          final outWav = File(p.join(dstAudioDir.path, "$base.wav"));
          final cmd = '-y -i "${f.path}" -c:a pcm_s16le -ar 48000 "${outWav.path}"';
          await FFmpegKit.execute(cmd);
        } else {
          await f.copy(p.join(dstAudioDir.path, p.basename(f.path)));
        }
      }
    }

    // cleanup unpack dir
    try {
      await unpackDir.delete(recursive: true);
    } catch (_) {}

    return destProjectDir;
  }
}

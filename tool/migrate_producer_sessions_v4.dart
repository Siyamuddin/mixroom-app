import 'dart:convert';
import 'dart:io';

import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/migrate_producer_sessions_v4.dart <file-or-directory> [...]',
    );
    exitCode = 64;
    return;
  }
  var migrated = 0;
  var skipped = 0;
  for (final argument in arguments) {
    final type = FileSystemEntity.typeSync(argument);
    final files = type == FileSystemEntityType.directory
        ? await Directory(argument)
              .list(followLinks: false)
              .where(
                (entity) => entity is File && entity.path.endsWith('.json'),
              )
              .cast<File>()
              .toList()
        : type == FileSystemEntityType.file
        ? <File>[File(argument)]
        : const <File>[];
    for (final file in files) {
      try {
        final source = (jsonDecode(await file.readAsString()) as Map)
            .cast<String, dynamic>();
        if (source['schema_version'] != 3) {
          skipped++;
          continue;
        }
        final output = File(
          p.join(
            file.parent.path,
            '${p.basenameWithoutExtension(file.path)}.v4.json',
          ),
        );
        if (await output.exists()) {
          skipped++;
          continue;
        }
        await output.writeAsString(
          const JsonEncoder.withIndent(
            ' ',
          ).convert(migrateProducerSessionV3(source)),
          flush: true,
        );
        migrated++;
      } catch (error) {
        stderr.writeln('${file.path}: $error');
        skipped++;
      }
    }
  }
  stdout.writeln('Migrated $migrated session(s); skipped $skipped.');
}

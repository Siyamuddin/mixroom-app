import 'dart:convert';
import 'dart:io';

const manifestPath = 'docs/engineering/docs_manifest.json';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final changedFiles = await _changedFiles(args);
  final manifest = _loadManifest();
  final docs = (manifest['docs'] as List<dynamic>).cast<Map<String, dynamic>>();

  final manifestErrors = _validateManifest(docs);
  if (manifestErrors.isNotEmpty) {
    stderr.writeln('Docs manifest is invalid:');
    for (final error in manifestErrors) {
      stderr.writeln('- $error');
    }
    exitCode = 1;
    return;
  }

  if (changedFiles.isEmpty) {
    stdout.writeln('Docs freshness check passed. No changed files found.');
    return;
  }

  final changedSet = changedFiles.toSet();
  final failures = <_DocFailure>[];

  for (final entry in docs) {
    final docPath = entry['doc'] as String;
    final watchPaths = (entry['watch_paths'] as List<dynamic>).cast<String>();
    final matched = changedFiles
        .where((path) => _matchesAnyWatchPath(path, watchPaths))
        .toList();

    if (matched.isEmpty || changedSet.contains(docPath)) {
      continue;
    }

    failures.add(
      _DocFailure(
        docPath: docPath,
        owner: entry['owner'] as String,
        updateTrigger: entry['update_trigger'] as String,
        matchedFiles: matched,
      ),
    );
  }

  if (failures.isEmpty) {
    stdout.writeln('Docs freshness check passed.');
    return;
  }

  stderr.writeln('Docs freshness check failed.');
  stderr.writeln(
    'Update the flagged docs in this change, or record why the current docs still apply.',
  );
  stderr.writeln('');

  for (final failure in failures) {
    stderr.writeln(failure.docPath);
    stderr.writeln('  owner: ${failure.owner}');
    stderr.writeln('  update trigger: ${failure.updateTrigger}');
    stderr.writeln('  changed files:');
    for (final file in failure.matchedFiles.take(8)) {
      stderr.writeln('  - $file');
    }
    final hiddenCount = failure.matchedFiles.length - 8;
    if (hiddenCount > 0) {
      stderr.writeln('  - ... $hiddenCount more');
    }
    stderr.writeln('');
  }

  exitCode = 1;
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tool/check_docs_freshness.dart --staged
  dart run tool/check_docs_freshness.dart --base origin/main
  dart run tool/check_docs_freshness.dart --changed-file-list /tmp/files.txt

Options:
  --staged                 Check staged files, suitable for pre-commit.
  --base <ref>             Check files changed from <ref>...HEAD, suitable for PR/release.
  --changed-file-list <p>  Check newline-delimited paths from a file.
  --help                   Show this message.
''');
}

Map<String, dynamic> _loadManifest() {
  final file = File(manifestPath);
  if (!file.existsSync()) {
    stderr.writeln('Missing $manifestPath');
    exit(1);
  }

  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<String> _validateManifest(List<Map<String, dynamic>> docs) {
  final errors = <String>[];

  for (final entry in docs) {
    final doc = entry['doc'];
    final owner = entry['owner'];
    final updateTrigger = entry['update_trigger'];
    final watchPaths = entry['watch_paths'];

    if (doc is! String || doc.isEmpty) {
      errors.add('Each entry needs a non-empty doc path.');
      continue;
    }
    if (!File(doc).existsSync()) {
      errors.add('$doc does not exist.');
    }
    if (owner is! String || owner.isEmpty) {
      errors.add('$doc needs an owner.');
    }
    if (updateTrigger is! String || updateTrigger.isEmpty) {
      errors.add('$doc needs an update_trigger.');
    }
    if (watchPaths is! List || watchPaths.isEmpty) {
      errors.add('$doc needs at least one watch path.');
    }
  }

  return errors;
}

Future<List<String>> _changedFiles(List<String> args) async {
  final changedFileListIndex = args.indexOf('--changed-file-list');
  if (changedFileListIndex >= 0) {
    final path = _valueAfter(args, changedFileListIndex, '--changed-file-list');
    return File(path)
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  if (args.contains('--staged')) {
    return _gitChangedFiles(
        ['diff', '--cached', '--name-only', '--diff-filter=ACMRTD']);
  }

  final baseIndex = args.indexOf('--base');
  if (baseIndex >= 0) {
    final base = _valueAfter(args, baseIndex, '--base');
    return _gitChangedFiles(
        ['diff', '--name-only', '--diff-filter=ACMRTD', '$base...HEAD']);
  }

  return _gitChangedFiles(
      ['diff', '--name-only', '--diff-filter=ACMRTD', 'HEAD']);
}

String _valueAfter(List<String> args, int index, String option) {
  if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
    stderr.writeln('Missing value for $option');
    exit(2);
  }
  return args[index + 1];
}

Future<List<String>> _gitChangedFiles(List<String> gitArgs) async {
  final result = await Process.run('git', gitArgs);
  if (result.exitCode != 0) {
    stderr.writeln('git ${gitArgs.join(' ')} failed:');
    stderr.write(result.stderr);
    exit(2);
  }

  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

bool _matchesAnyWatchPath(String changedPath, List<String> watchPaths) {
  return watchPaths
      .any((watchPath) => _matchesWatchPath(changedPath, watchPath));
}

bool _matchesWatchPath(String changedPath, String watchPath) {
  if (watchPath.endsWith('/**')) {
    final prefix = watchPath.substring(0, watchPath.length - 2);
    return changedPath.startsWith(prefix);
  }

  if (watchPath.endsWith('/')) {
    return changedPath.startsWith(watchPath);
  }

  return changedPath == watchPath;
}

class _DocFailure {
  const _DocFailure({
    required this.docPath,
    required this.owner,
    required this.updateTrigger,
    required this.matchedFiles,
  });

  final String docPath;
  final String owner;
  final String updateTrigger;
  final List<String> matchedFiles;
}

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
      if (depth == 0) return source.substring(openBrace, i + 1);
    }
  }
  fail('Unclosed method: $signature');
}

void main() {
  late String createProject;

  setUpAll(() {
    final source = File('lib/screens/signed_in_shell.dart').readAsStringSync();
    createProject = _methodBody(
      source,
      'Future<void> _createMusicProject() async',
    );
  });

  test('project creation becomes single-flight before its first await', () {
    final acquire = createProject.indexOf('_creatingProject = true');
    final firstAwait = createProject.indexOf('await ');

    expect(acquire, greaterThanOrEqualTo(0));
    expect(firstAwait, greaterThan(acquire));
    expect(createProject, contains('if (_creatingProject) return;'));
    expect(createProject, contains('finally'));
    expect(createProject, contains('_creatingProject = false'));
  });

  test('both Add Project surfaces receive the busy state', () {
    final source = File('lib/screens/signed_in_shell.dart').readAsStringSync();
    expect(
      RegExp(r'creatingProject: _creatingProject').allMatches(source).length,
      2,
    );
  });
}

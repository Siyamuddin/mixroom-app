import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

class VoiceProjectNotes {
  VoiceProjectNotes(this.file);
  final File file;

  Future<List<Map<String, dynamic>>> list() async {
    if (!await file.exists()) return [];
    final value = jsonDecode(await file.readAsString());
    if (value is! List) throw const FormatException('Invalid project notes.');
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> add(
    String text, {
    required int playheadMs,
    required String projectId,
    int? trackId,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 2000) {
      throw const FormatException('A note must contain 1 to 2000 characters.');
    }
    final notes = await list();
    final note = <String, dynamic>{
      'id': const Uuid().v4(),
      'text': normalized,
      'playheadMs': playheadMs,
      'projectId': projectId,
      if (trackId != null) 'trackId': trackId,
      'completed': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    notes.add(note);
    await _save(notes);
    return note;
  }

  Future<bool> complete(String id) async {
    final notes = await list();
    final index = notes.indexWhere((note) => note['id'] == id);
    if (index < 0) return false;
    notes[index]['completed'] = true;
    await _save(notes);
    return true;
  }

  Future<void> _save(List<Map<String, dynamic>> notes) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(notes), flush: true);
    await pending.rename(file.path);
  }
}

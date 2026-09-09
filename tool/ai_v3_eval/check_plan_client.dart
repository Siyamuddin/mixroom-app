// Offline, in-memory contract check. No project execution or model calls.
import 'dart:convert';
import 'dart:io';
import '../../lib/ai/v3/ai_v3_contract.dart';
import '../../lib/ai/v3/ai_v3_resources.dart';

Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      final plan = AiV3Plan.fromJson(
        Map<String, dynamic>.from(jsonDecode(line) as Map),
        allowResourceRefs: true,
        resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
      );
      stdout.writeln(jsonEncode({'valid': true, 'commands': plan.commands.length}));
    } on AiV3ContractException catch (error) {
      stdout.writeln(jsonEncode({'valid': false, 'error': error.code}));
    } catch (_) {
      stdout.writeln(jsonEncode({'valid': false, 'error': 'checker_input_invalid'}));
    }
  }
}

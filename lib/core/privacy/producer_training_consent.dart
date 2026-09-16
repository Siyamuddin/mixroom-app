import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProducerTrainingConsent {
  const ProducerTrainingConsent._();

  static const String _key = 'mixroom.producer_training.consent_version';

  static Future<bool> isAccepted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key) == ProducerDataCollector.consentVersion;
  }

  static Future<void> accept() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, ProducerDataCollector.consentVersion);
  }

  static Future<void> revoke() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}

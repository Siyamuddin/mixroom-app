import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensitiveStorage {
  SensitiveStorage._();

  static final SensitiveStorage instance = SensitiveStorage._();

  static const AndroidOptions _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);

  final FlutterSecureStorage _secureStorage =
      const FlutterSecureStorage(aOptions: _androidOptions);

  Future<String?> read(String key) async {
    final secureValue = await _readSecure(key);
    if (secureValue != null) {
      return secureValue;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<String?> readWithMigration(String key) async {
    final secureValue = await _readSecure(key);
    if (secureValue != null && secureValue.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return secureValue;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    final wroteSecure = await _writeSecure(key, legacyValue);
    if (wroteSecure) {
      await prefs.remove(key);
    }
    return legacyValue;
  }

  Future<void> write(String key, String value) async {
    final wroteSecure = await _writeSecure(key, value);
    final prefs = await SharedPreferences.getInstance();
    if (wroteSecure) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(key, value);
  }

  Future<void> delete(String key) async {
    await _deleteSecure(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secureStorage.read(
        key: key,
        aOptions: _androidOptions,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writeSecure(String key, String value) async {
    try {
      await _secureStorage.write(
        key: key,
        value: value,
        aOptions: _androidOptions,
      );
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      await _secureStorage.delete(
        key: key,
        aOptions: _androidOptions,
      );
    } on MissingPluginException {
      // SharedPreferences cleanup still runs below.
    } on PlatformException {
      // SharedPreferences cleanup still runs below.
    } catch (_) {
      // SharedPreferences cleanup still runs below.
    }
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class VoiceRelayTransport {
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  });
  void close();
}

class HttpVoiceRelayTransport implements VoiceRelayTransport {
  HttpVoiceRelayTransport(String baseUrl, {http.Client? client})
    : baseUrl = validateVoiceRelayUrl(baseUrl),
      _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    // A relay redirect must never forward a paired device token to another host.
    request.followRedirects = false;
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 90)),
    ).timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceRelayException(response.statusCode);
    }
    if (response.body.isEmpty) return {};
    final value = jsonDecode(response.body);
    if (value is! Map) throw const FormatException('Invalid relay response.');
    return Map<String, dynamic>.from(value);
  }

  @override
  void close() => _client.close();
}

String validateVoiceRelayUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' &&
              const {
                'localhost',
                '127.0.0.1',
                '[::1]',
                '::1',
              }.contains(uri.host.toLowerCase())))) {
    throw const FormatException(
      'Use HTTPS, or HTTP on localhost, 127.0.0.1 or [::1], '
      'without credentials, a query or a fragment.',
    );
  }
  return uri.toString().replaceFirst(RegExp(r'/+$'), '');
}

class VoiceRelayException implements Exception {
  const VoiceRelayException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Voice relay request failed ($statusCode).';
}

import 'package:flutter/material.dart';

Future<({String baseUrl, String code})?> showVoicePairDialog(
  BuildContext context, {
  required String initialBaseUrl,
}) async {
  final url = TextEditingController(text: initialBaseUrl);
  final code = TextEditingController();
  try {
    return await showDialog<({String baseUrl, String code})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect your voice session'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start the local voice backend, open the MixRoom companion in your browser, and enter its pairing code here.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: code,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Pairing code'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'Voice relay URL',
                  hintText: 'http://127.0.0.1:8765/api/voice',
                  helperText: 'Local backend: port 8765, path /api/voice',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use headphones. Your browser microphone controls the session; MixRoom records the selected audio input.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              baseUrl: url.text.trim(),
              code: code.text.trim(),
            )),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  } finally {
    // Route exit animations can still reference the text fields briefly.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      url.dispose();
      code.dispose();
    });
  }
}

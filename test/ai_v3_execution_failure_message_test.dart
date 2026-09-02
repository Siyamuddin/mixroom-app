import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_execution_failure_message.dart';

class _ThrowingDescription {
  @override
  String toString() => throw StateError('description unavailable');
}

void main() {
  group('V3 execution failure messages', () {
    test('maps known failure families to actionable project-safe wording', () {
      final cases = <Object, String>{
        StateError(
          'v3_transport_recording_active',
        ): 'Playback controls cannot be changed while recording. Stop recording first, then try again. Nothing was changed.',
        StateError(
          'v3_audio_to_midi_source_silent',
        ): 'I could not detect usable notes in that audio. The project was unchanged. Try a clearer pitched clip or convert a different clip.',
        StateError(
          'v3_audio_to_midi_source_unreadable',
        ): 'I could not read that audio clip for transcription. The project was unchanged. Try another readable audio clip.',
        StateError(
          'v3_resource_binding_unavailable',
        ): 'I couldn’t finish a requested track or clip change, so I restored the project. Check that the target is still available and try again.',
        StateError(
          'v3_generated_resource_stale',
        ): 'I couldn’t finish a requested track or clip change, so I restored the project. Check that the target is still available and try again.',
        StateError(
          'v3_audio_to_midi_row_create_failed',
        ): 'I couldn’t finish a requested track or clip change, so I restored the project. Check that the target is still available and try again.',
        StateError(
          'v3_mix_action_target_invalid',
        ): 'I couldn’t apply the mix to all requested tracks, so I restored the project. Check the target tracks and try again.',
        StateError(
          'v3_effect_parameter_apply_failed',
        ): 'I couldn’t apply one of the requested sound changes, so I restored the project. Try again or choose another available effect or instrument.',
        StateError(
          'v3_row_instrument_unavailable',
        ): 'I couldn’t apply one of the requested sound changes, so I restored the project. Try again or choose another available effect or instrument.',
        StateError(
          'v3_midi_instrument_pitch_unavailable',
        ): 'I couldn’t apply one of the requested sound changes, so I restored the project. Try again or choose another available effect or instrument.',
        StateError(
          'v3_phone_cleanup_unavailable',
        ): 'I couldn’t apply one of the requested sound changes, so I restored the project. Try again or choose another available effect or instrument.',
        StateError(
          'v3_group_membership_mismatch',
        ): 'I couldn’t apply the requested track grouping, so I restored the project. Check that those tracks still exist and try again.',
        StateError(
          'v3_transport_playback_state_mismatch',
        ): 'I couldn’t apply the requested playback change, so I restored the project. Check the transport state and try again.',
      };

      for (final entry in cases.entries) {
        expect(
          aiV3RolledBackFailureMessage(entry.key),
          entry.value,
          reason: entry.key.toString(),
        );
      }
    });

    test('uses a neutral restored-project fallback for unknown failures', () {
      expect(
        aiV3RolledBackFailureMessage(StateError('unexpected failure')),
        'Something went wrong while applying the changes, so I restored the project to its previous state. Please try again.',
      );
      expect(
        aiV3RolledBackFailureMessage(StateError('v3_readback_mismatch')),
        'Something went wrong while applying the changes, so I restored the project to its previous state. Please try again.',
      );
    });

    test('never exposes exception details or legacy technical wording', () {
      const secretPrompt = 'secret prompt text';
      const internalId = 'clip-tenant-private-4815';
      final message = aiV3RolledBackFailureMessage(
        StateError(
          'v3_resource_binding_unavailable $internalId $secretPrompt '
          'schema contract stack trace provider-response-99',
        ),
      );

      expect(message, isNot(contains(secretPrompt)));
      expect(message, isNot(contains(internalId)));
      expect(message.toLowerCase(), isNot(contains('schema')));
      expect(message.toLowerCase(), isNot(contains('contract')));
      expect(message.toLowerCase(), isNot(contains('stack trace')));
      expect(message.toLowerCase(), isNot(contains('provider')));
      expect(message, isNot(contains('transaction was rolled back')));
      expect(
        message,
        isNot(contains('could not safely prepare every requested change')),
      );
    });

    test('falls back safely when the exception description cannot be read', () {
      expect(
        aiV3RolledBackFailureMessage(_ThrowingDescription()),
        'Something went wrong while applying the changes, so I restored the project to its previous state. Please try again.',
      );
    });
  });
}

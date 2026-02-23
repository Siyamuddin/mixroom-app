// goal_vector_builder.dart

import '../models/goal_vector.dart';

class GoalVectorBuilder {
  GoalVector fromUserText(String text) {
    final t = text.toLowerCase();

    final intents = <MixIntent>[];

    if (t.contains('louder') || t.contains('up')) {
      intents.add(MixIntent(kind: 'gain', direction: 'up', confidence: 0.6));
    } else if (t.contains('quieter') || t.contains('down')) {
      intents.add(MixIntent(kind: 'gain', direction: 'down', confidence: 0.6));
    }

    if (t.contains('muddy') || t.contains('boomy')) {
      intents.add(MixIntent(kind: 'eq', descriptor: 'muddy', confidence: 0.7));
    }
    if (t.contains('harsh') || t.contains('piercing')) {
      intents.add(MixIntent(kind: 'eq', descriptor: 'harsh', confidence: 0.7));
    }
    if (t.contains('reverb')) {
      intents.add(MixIntent(kind: 'reverb', direction: 'up', confidence: 0.6));
    }
    if (t.contains('delay')) {
      intents.add(MixIntent(kind: 'delay', direction: 'up', confidence: 0.6));
    }
    if (t.contains('de-ess') || t.contains('sibil')) {
      intents.add(MixIntent(kind: 'deesser', direction: 'up', confidence: 0.7));
    }

    String? role;
    if (t.contains('vocal'))
      role = 'vocals';
    else if (t.contains('drum'))
      role = 'drums';
    else if (t.contains('bass'))
      role = 'bass';
    else if (t.contains('guitar'))
      role = 'guitar';
    else if (t.contains('synth') || t.contains('keys')) role = 'synth';

    return GoalVector(
      type: 'mix_request',
      userText: text,
      intents: intents.isEmpty
          ? [MixIntent(kind: 'balance', confidence: 0.5)]
          : intents,
      target: MixTarget(
          role: role,
          scope: role == null ? 'auto' : 'row',
          confidence: role == null ? 0.3 : 0.7),
      intensity: t.contains('slightly') ? 0.3 : 0.6,
    );
  }
}

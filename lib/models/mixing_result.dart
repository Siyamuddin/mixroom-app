// mixing_result.dart

class MixAction {
  /// Supported action types:
  /// - set_row_gain                 {row, delta}
  /// - set_row_pan                  {row, delta}
  /// - ensure_effect                {row, effect_name_contains}
  /// - delete_effect                {row, effect_name_contains}
  /// - adjust_effect_param_by_name  {row, effect_name_contains, param_name OR param_name_contains_any,
  ///                                 mode:set|delta, value|value_norm?, delta|delta_norm?,
  ///                                 clamp_0_1?, skip_if_missing_effect?}
  /// - set_master_gain              {mode:set|delta, value|delta}
  /// - set_master_pan               {mode:set|delta, value|delta}
  /// - ensure_master_effect         {effect_name_contains}
  /// - delete_master_effect         {effect_name_contains}
  /// - adjust_master_effect_param_by_name
  ///                                {effect_name_contains, param_name OR param_name_contains_any,
  ///                                 mode:set|delta, value|value_norm?, delta|delta_norm?,
  ///                                 clamp_0_1?, skip_if_missing_effect?}
  /// - hard_reset_master_fx         {}
  /// - noop
  final String type;
  final Map<String, dynamic> data;

  MixAction(this.type, this.data);

  Map<String, dynamic> toJson() => {'type': type, 'data': data};
}

class MixingResult {
  final List<MixAction> actions;

  /// Short human-facing summary (“Adjusted gain on 2 tracks…")
  final String summary;

  /// Optional: extra helpful notes/warnings/suggestions
  final List<String> notes;

  /// If true, executor should do nothing
  final bool isNoOp;

  const MixingResult({
    required this.actions,
    required this.summary,
    required this.isNoOp,
    this.notes = const [],
  });

  MixingResult copyWith({
    List<MixAction>? actions,
    String? summary,
    bool? isNoOp,
    List<String>? notes,
  }) {
    return MixingResult(
      actions: actions ?? this.actions,
      summary: summary ?? this.summary,
      isNoOp: isNoOp ?? this.isNoOp,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_no_op': isNoOp,
      'summary': summary,
      'notes': notes,
      'actions': actions.map((a) => a.toJson()).toList(),
    };
  }
}

class ChatPipelineResult {
  final String message;
  final MixingResult? mixing;
  final Map<String, dynamic>? meta;

  const ChatPipelineResult.message(this.message, {this.meta}) : mixing = null;
  const ChatPipelineResult.mix(this.mixing, this.message, {this.meta});

  bool get hasMix =>
      mixing != null && !(mixing!.isNoOp || mixing!.actions.isEmpty);

  @override
  String toString() {
    if (mixing == null) {
      return 'ChatPipelineResult(message: "$message")';
    }

    final mix = mixing!;
    final buf = StringBuffer();

    buf.writeln('ChatPipelineResult {');
    buf.writeln('  hasMix: $hasMix');
    buf.writeln('  summary: "${mix.summary}"');

    if (mix.notes.isNotEmpty) {
      buf.writeln('  notes:');
      for (final n in mix.notes) {
        buf.writeln('    - $n');
      }
    }

    buf.writeln('  actions (${mix.actions.length}):');

    if (mix.actions.isEmpty) {
      buf.writeln('    (none)');
    } else {
      for (int i = 0; i < mix.actions.length; i++) {
        final a = mix.actions[i];
        buf.writeln('    [$i] ${a.type}');
        if (a.data.isEmpty) {
          buf.writeln('         data: {}');
        } else {
          a.data.forEach((key, value) {
            buf.writeln('         $key: $value');
          });
        }
      }
    }

    buf.writeln('}');
    return buf.toString();
  }
}

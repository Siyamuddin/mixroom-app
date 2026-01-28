// import 'package:flutter/material.dart';
// import 'package:flutter_chat_ui/flutter_chat_ui.dart';
// import 'package:flutter_chat_core/flutter_chat_core.dart';
// import 'package:uuid/uuid.dart';
// import 'package:mixroom/models/models.dart';
// import '../ai/action_executor_service.dart';
// import '../ai/goal_vector_builder.dart';
// import '../ai/instrument_classifier.dart';
// import '../ai/_old_local_llm_service.dart';
// import '../ai/local_mixing_model.dart';
// import '../ai/project_state_builder.dart';
// import '../models/goal_vector.dart';
// import '../models/mixing_result.dart';
// import '../models/project_state.dart';

// class ChatScreen extends StatefulWidget {
//   final List<AudioTrack> audioTracks;
//   final double bpmFallback;

//   const ChatScreen({
//     super.key,
//     required this.audioTracks,
//     required this.bpmFallback,
//   });

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> {
//   final _uuid = const Uuid();

//   late final InstrumentClassifier _classifier;
//   late final ProjectStateBuilder _projectBuilder;
//   late final LocalLlmService _llm;
//   late final GoalVectorBuilder _goalFallback;
//   late final LocalMixingModel _mixModel;
//   late final ActionExecutorService _executor;

//   late final ChatController _chatController;

//   bool _busy = false;

//   @override
//   void initState() {
//     super.initState();
//     _chatController = InMemoryChatController();

//     _classifier = InstrumentClassifier();
//     _projectBuilder = ProjectStateBuilder(classifier: _classifier);
//     _llm = LocalLlmService();
//     _goalFallback = GoalVectorBuilder();
//     _mixModel = LocalMixingModel();
//     _executor = ActionExecutorService();
//     _boot();
//   }

//   Future<void> _boot() async {
//     // Load ONNX classifier (optional; won’t crash if not ready)
//     try {
//       await _classifier.loadFromAsset('assets/models/instrument_classifier.onnx');
//     } catch (_) {
//       // Safe: role probs will fallback
//     }

//     _pushAssistant(
//       "I'm MixAssistant.\n\nAsk things like:\n"
//       "• “increase vocal reverb”\n"
//       "• “mix feels muddy”\n"
//       "• “what does reverb do?”\n\n"
//       "I'll only propose changes via tool calls and apply them safely.",
//     );
//   }

//   void _pushAssistant(String text) {
//     _chatController.insertMessage(
//       TextMessage(
//         id: _uuid.v4(),
//         authorId: 'assistant',
//         createdAt: DateTime.now().toUtc(),
//         text: text,
//       ),
//     );
//   }

//   void _pushUser(String text) {
//     _chatController.insertMessage(
//       TextMessage(
//         id: _uuid.v4(),
//         authorId: 'user',
//         createdAt: DateTime.now().toUtc(),
//         text: text,
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('MixAssistant'),
//       ),
//       body: Stack(
//         children: [
//           Chat(
//             chatController: _chatController,
//             currentUserId: 'user',
//             onMessageSend: (text) async {
//               await _onSend(text);
//             },
//             resolveUser: (UserID id) async {
//               if (id == 'user') {
//                 return User(id: 'user', name: 'You');
//               }
//               return User(id: 'assistant', name: 'MixAssistant');
//             },
//           ),
//           if (_busy)
//             Positioned.fill(
//               child: IgnorePointer(
//                 ignoring: true,
//                 child: Container(
//                   color: Colors.black.withOpacity(0.12),
//                   alignment: Alignment.topCenter,
//                   padding: const EdgeInsets.only(top: 16),
//                   child: const CircularProgressIndicator(),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

// // 3. Fix _onSend logic
//   Future<void> _onSend(String text) async {
//     if (_busy) return;
//     _pushUser(text);
//     setState(() => _busy = true);

//     debugPrint('_onSend -> USER: $text');

//     try {
//       final project = await _projectBuilder.build(
//         audioTracks: widget.audioTracks,
//         bpmFallback: widget.bpmFallback,
//       );

//       debugPrint('_onSend -> ProjectState:\n${project.toPrettyJson()}');

//       // FIX: method name is 'send', and returns LlmResult
//       final LlmResult result = await _llm.send(
//         userText: text,
//         projectState: project,
//       );

//       debugPrint('_onSend -> LLM result: '
//           'tool=${result.toolName}, '
//           'text=${result.text}, '
//           'args=${result.toolArgs}');

//       if (!result.isToolCall) {
//         _pushAssistant(result.text ?? "I'm not sure how to help with that.");
//         return;
//       }

//       // FIX: Access args via toolArgs property
//       final args = result.toolArgs!;
//       final goalJson = Map<String, dynamic>.from(args['goal'] as Map);
//       final goal = _goalFromJson(goalJson, fallbackUserText: text);

//       final mix = _mixModel.run(project: project, goal: goal);

//       await _executor.executeAll(mix.actions);

//       debugPrint('_onSend -> MixingResult: ${mix.toJson()}');

//       if (mix.isNoOp) {
//         _pushAssistant("No changes needed.\n\n(${mix.summary})");
//       } else {
//         _pushAssistant("Done.\n\n${mix.summary}");
//       }
//     } catch (e) {
//       _pushAssistant("I hit an error:\n$e");
//     } finally {
//       setState(() => _busy = false);
//     }
//   }

//   GoalVector _goalFromJson(Map<String, dynamic> j, {required String fallbackUserText}) {
//     try {
//       final type = (j['type'] ?? 'mix_request') as String;
//       final userText = (j['user_text'] ?? fallbackUserText) as String;
//       final issues = (j['issues'] as List?)?.map((e) => e.toString()).toList() ?? const ['generic'];
//       final target = Map<String, dynamic>.from((j['target'] as Map?) ?? const {});
//       final intensity = ((j['intensity'] as num?) ?? 0.5).toDouble().clamp(0.0, 1.0);

//       return GoalVector(
//         type: type,
//         userText: userText,
//         issues: issues,
//         target: target,
//         intensity: intensity,
//       );
//     } catch (_) {
//       return _goalFallback.fromUserText(fallbackUserText);
//     }
//   }
// }

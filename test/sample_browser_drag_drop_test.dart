import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';

void _setTestTargetPlatform(TargetPlatform? platform) {
  debugDefaultTargetPlatformOverride = platform;
  PlatformCapabilities.debugResetForCurrentPlatform();
}

Future<void> _runOnPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  _setTestTargetPlatform(platform);
  try {
    await body();
  } finally {
    _setTestTargetPlatform(null);
  }
}

void main() {
  test('sampleDragPointerFromFeedbackOffset adds the shared anchor', () {
    const Offset origin = Offset(10, 20);
    expect(
      sampleDragPointerFromFeedbackOffset(origin),
      origin + kSampleDragFeedbackAnchor,
    );
    expect(kSampleDragFeedbackAnchor, const Offset(42, 48));
  });

  test('desktop drag does not retract or close the File Browser', () {
    expect(
      shouldRetractSampleBrowserForDrag(
        isDesktop: true,
        isDragActive: true,
      ),
      isFalse,
    );
    expect(
      shouldRetractSampleBrowserForDrag(
        isDesktop: true,
        isDragActive: false,
      ),
      isFalse,
    );
    expect(shouldCloseSampleBrowserAfterSuccessfulDrop(), isFalse);
  });

  test('mobile drag retracts the File Browser and restores it after', () {
    expect(
      shouldRetractSampleBrowserForDrag(
        isDesktop: false,
        isDragActive: true,
      ),
      isTrue,
    );
    expect(
      shouldRetractSampleBrowserForDrag(
        isDesktop: false,
        isDragActive: false,
      ),
      isFalse,
    );
    expect(shouldCloseSampleBrowserAfterSuccessfulDrop(), isFalse);
    expect(
      kSampleBrowserDragRetractDuration,
      const Duration(milliseconds: 190),
    );
  });

  testWidgets(
    'desktop sample tiles use Draggable rather than LongPressDraggable',
    (tester) async {
      await _runOnPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(_buildDragKindProbe());
        expect(find.byType(LongPressDraggable<SampleDragData>), findsNothing);
        expect(
          find.byWidgetPredicate(_isDesktopSampleDraggable),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets('iOS sample tiles keep LongPressDraggable', (tester) async {
    await _runOnPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_buildDragKindProbe());
      expect(find.byType(LongPressDraggable<SampleDragData>), findsOneWidget);
      expect(find.byWidgetPredicate(_isDesktopSampleDraggable), findsNothing);
    });
  });

  testWidgets('covering panel pass-through accepts a drop after drag starts', (
    tester,
  ) async {
    await _runOnPlatform(TargetPlatform.macOS, () async {
      final List<SampleDragData> accepted = <SampleDragData>[];
      await tester.pumpWidget(_SampleDropOverlayApp(onAccepted: accepted.add));
      await tester.pump();
      final Offset source = tester.getCenter(find.text('kick.wav'));
      const Offset coveredTarget = Offset(300, 270);
      final TestGesture gesture = await tester.startGesture(source);
      await gesture.moveBy(const Offset(24, 16));
      await tester.pump();
      await gesture.moveTo(coveredTarget);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(accepted, isNotEmpty);
      expect(accepted.single.filePath, '/tmp/kick.wav');
    });
  });

  testWidgets(
    'drop uses pointer position when ghost origin is outside the target',
    (tester) async {
      await _runOnPlatform(TargetPlatform.macOS, () async {
        Offset? acceptedPointer;
        await tester.pumpWidget(
          _SampleDropOverlayApp(
            onAccepted: (_) {},
            onAcceptedPointer: (Offset pointer) {
              acceptedPointer = pointer;
            },
          ),
        );
        await tester.pump();
        const Offset dropPointer = Offset(220, 170);
        final Offset source = tester.getCenter(find.text('kick.wav'));
        final TestGesture gesture = await tester.startGesture(source);
        await gesture.moveBy(const Offset(24, 16));
        await tester.pump();
        await gesture.moveTo(dropPointer);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(acceptedPointer, isNotNull);
        expect((acceptedPointer! - dropPointer).distance, lessThan(1.0));
      });
    },
  );

  testWidgets(
    'hovering a miss first still accepts after moving onto the target',
    (tester) async {
      await _runOnPlatform(TargetPlatform.macOS, () async {
        final List<SampleDragData> accepted = <SampleDragData>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DragTarget<SampleDragData>(
                        onWillAcceptWithDetails:
                            (DragTargetDetails<SampleDragData> details) {
                              return true;
                            },
                        onAcceptWithDetails:
                            (DragTargetDetails<SampleDragData> details) {
                              final Offset pointer =
                                  sampleDragPointerFromFeedbackOffset(
                                    details.offset,
                                  );
                              if (pointer.dy < 300) return;
                              accepted.add(details.data);
                            },
                        builder: (_, __, ___) {
                          return const ColoredBox(color: Color(0xFF224466));
                        },
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: buildSampleFileDraggable(
                        data: const SampleDragData(
                          filePath: '/tmp/kick.wav',
                          label: 'kick',
                        ),
                        feedback: const SizedBox(width: 84, height: 56),
                        childWhenDragging: const SizedBox.shrink(),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('kick.wav'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final Offset source = tester.getCenter(find.text('kick.wav'));
        const Offset missInsideTarget = Offset(400, 180);
        const Offset validDrop = Offset(400, 420);
        final TestGesture gesture = await tester.startGesture(source);
        await gesture.moveBy(const Offset(24, 16));
        await tester.pump();
        await gesture.moveTo(missInsideTarget);
        await tester.pump();
        await gesture.moveTo(validDrop);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(accepted, isNotEmpty);
      });
    },
  );
}

bool _isDesktopSampleDraggable(Widget widget) {
  return widget is Draggable<SampleDragData> &&
      widget is! LongPressDraggable<SampleDragData>;
}

Widget _buildDragKindProbe() {
  const SampleDragData data = SampleDragData(
    filePath: '/tmp/kick.wav',
    label: 'kick',
  );
  return MaterialApp(
    home: Scaffold(
      body: buildSampleFileDraggable(
        data: data,
        child: const Text('kick.wav'),
        feedback: const SizedBox(width: 84, height: 56),
        childWhenDragging: const SizedBox.shrink(),
      ),
    ),
  );
}

class _SampleDropOverlayApp extends StatefulWidget {
  const _SampleDropOverlayApp({
    required this.onAccepted,
    this.onAcceptedPointer,
  });

  final ValueChanged<SampleDragData> onAccepted;
  final ValueChanged<Offset>? onAcceptedPointer;

  @override
  State<_SampleDropOverlayApp> createState() => _SampleDropOverlayAppState();
}

class _SampleDropOverlayAppState extends State<_SampleDropOverlayApp> {
  bool _dragActive = false;
  final GlobalKey _targetKey = GlobalKey();

  bool _pointerIsInsideTarget(Offset pointer) {
    final BuildContext? targetContext = _targetKey.currentContext;
    if (targetContext == null) return false;
    final RenderObject? renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final Offset local = renderObject.globalToLocal(pointer);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= renderObject.size.width &&
        local.dy <= renderObject.size.height;
  }

  @override
  Widget build(BuildContext context) {
    const SampleDragData dragData = SampleDragData(
      filePath: '/tmp/kick.wav',
      label: 'kick',
    );
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: Stack(
            children: <Widget>[
              Positioned(
                key: _targetKey,
                left: 200,
                top: 150,
                width: 400,
                height: 250,
                child: DragTarget<SampleDragData>(
                  onWillAcceptWithDetails:
                      (DragTargetDetails<SampleDragData> details) {
                        // Claim the target even when the first hover is a
                        // miss. Flutter will not re-run willAccept while the
                        // pointer stays inside.
                        return true;
                      },
                  onAcceptWithDetails:
                      (DragTargetDetails<SampleDragData> details) {
                        final Offset pointer =
                            sampleDragPointerFromFeedbackOffset(details.offset);
                        if (!_pointerIsInsideTarget(pointer)) {
                          return;
                        }
                        widget.onAcceptedPointer?.call(pointer);
                        widget.onAccepted(details.data);
                      },
                  builder: (_, __, ___) {
                    return const ColoredBox(color: Color(0xFF224466));
                  },
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: 360,
                height: 600,
                child: IgnorePointer(
                  ignoring: _dragActive,
                  child: ColoredBox(
                    color: const Color(0x88FF0000),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: buildSampleFileDraggable(
                        data: dragData,
                        onDragStarted: () {
                          setState(() {
                            _dragActive = true;
                          });
                        },
                        onDragEnd: (_) {
                          setState(() {
                            _dragActive = false;
                          });
                        },
                        feedback: const SizedBox(width: 84, height: 56),
                        childWhenDragging: const SizedBox.shrink(),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('kick.wav'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

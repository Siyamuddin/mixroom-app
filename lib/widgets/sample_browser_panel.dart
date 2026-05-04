import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SampleDragData {
  final String filePath;
  final String label;
  final Duration? duration;

  const SampleDragData({
    required this.filePath,
    required this.label,
    this.duration,
  });
}

class SampleBrowserPanel extends StatefulWidget {
  final List<String> rootFolders;
  final String? auditioningPath;
  final Future<void> Function(String filePath) onAuditionTap;
  final Future<void> Function(String filePath) onInsertSample;
  final Future<void> Function() onAddFolder;
  final void Function(String rootPath) onRemoveFolder;
  final Future<Duration?> Function(String filePath) resolveDuration;
  final void Function(bool active)? onDragActivityChanged;
  final VoidCallback onClose;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Stream<Duration> previewPositionStream;
  final Stream<Duration?> previewDurationStream;
  final bool previewPlaying;
  final Future<void> Function(Duration position) onPreviewSeek;
  final Future<void> Function()? onOpenSystemSettings;
  final VoidCallback? onDragOutsidePanel;

  const SampleBrowserPanel({
    super.key,
    required this.rootFolders,
    required this.auditioningPath,
    required this.onAuditionTap,
    required this.onInsertSample,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.resolveDuration,
    required this.onClose,
    required this.expanded,
    required this.onExpandedChanged,
    required this.previewPositionStream,
    required this.previewDurationStream,
    required this.previewPlaying,
    required this.onPreviewSeek,
    this.onOpenSystemSettings,
    this.onDragActivityChanged,
    this.onDragOutsidePanel,
  });

  @override
  State<SampleBrowserPanel> createState() => _SampleBrowserPanelState();
}

class _SampleBrowserPanelState extends State<SampleBrowserPanel> {
  static const Duration _kFolderHoldDelay = Duration(milliseconds: 180);
  static const double _kFolderHoldMoveTolerance = 14.0;
  static const int _kPreviewWaveformBars = 128;
  static const int _kPreviewWaveformPcmRate = 8000;
  static const Set<String> _kAudioExtensions = <String>{
    '.wav',
    '.wave',
    '.mp3',
    '.flac',
    '.aif',
    '.aiff',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.caf',
  };

  final Set<String> _expandedDirs = <String>{};
  final Set<String> _loadingDirs = <String>{};
  final Map<String, List<FileSystemEntity>> _childrenByDir =
      <String, List<FileSystemEntity>>{};
  final Map<String, String> _dirErrors = <String, String>{};
  final Map<String, Duration?> _durationByFile = <String, Duration?>{};
  final Set<String> _durationLoading = <String>{};
  final Map<String, List<double>> _waveformByFile = <String, List<double>>{};
  final Set<String> _waveformLoading = <String>{};

  String? _selectedRoot;
  String? _previewFocusPath;
  List<String> _rootFoldersSnapshot = const <String>[];
  bool _dragOutsideNotified = false;
  Timer? _folderHoldTimer;
  Offset? _folderHoldDownPos;
  bool _folderHoldMenuShown = false;

  @override
  void initState() {
    super.initState();
    _rootFoldersSnapshot = List<String>.from(widget.rootFolders);
    _syncSelectedRoot();
  }

  @override
  void didUpdateWidget(covariant SampleBrowserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(_rootFoldersSnapshot, widget.rootFolders)) {
      _rootFoldersSnapshot = List<String>.from(widget.rootFolders);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncSelectedRoot();
      });
    }
    if (widget.auditioningPath != null &&
        widget.auditioningPath != _previewFocusPath) {
      _previewFocusPath = widget.auditioningPath;
      _ensureWaveformForFile(widget.auditioningPath!);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _folderHoldTimer?.cancel();
    super.dispose();
  }

  void _startFolderHold(String rootPath, String label, Offset globalPos) {
    _folderHoldTimer?.cancel();
    _folderHoldDownPos = globalPos;
    _folderHoldMenuShown = false;
    _folderHoldTimer = Timer(_kFolderHoldDelay, () {
      _folderHoldTimer = null;
      _folderHoldMenuShown = true;
      HapticFeedback.lightImpact();
      _showFolderActions(rootPath, label, globalPos);
    });
  }

  void _updateFolderHoldMove(Offset globalPos) {
    final down = _folderHoldDownPos;
    if (down == null || _folderHoldMenuShown) return;
    if ((globalPos - down).distance > _kFolderHoldMoveTolerance) {
      _folderHoldTimer?.cancel();
      _folderHoldTimer = null;
      _folderHoldDownPos = null;
    }
  }

  void _endFolderHold() {
    _folderHoldTimer?.cancel();
    _folderHoldTimer = null;
    _folderHoldDownPos = null;
    _folderHoldMenuShown = false;
  }

  void _syncSelectedRoot() {
    if (widget.rootFolders.isEmpty) {
      setState(() {
        _selectedRoot = null;
      });
      return;
    }
    if (_selectedRoot != null && widget.rootFolders.contains(_selectedRoot)) {
      return;
    }
    final nextRoot = widget.rootFolders.first;
    setState(() {
      _selectedRoot = nextRoot;
      _expandedDirs.add(nextRoot);
    });
    _ensureDirectoryLoaded(nextRoot);
  }

  bool _isAudioFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _kAudioExtensions.contains(ext);
  }

  String _decodeDisplayLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !trimmed.contains('%')) return trimmed;
    try {
      return Uri.decodeFull(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  String _displayNameForPath(String path) {
    final base = p.basename(path).trim();
    final fallback = path.trim();
    final rawLabel = base.isEmpty ? fallback : base;
    final decodedLabel = _decodeDisplayLabel(rawLabel);
    return decodedLabel.isEmpty ? rawLabel : decodedLabel;
  }

  String _friendlyDirError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('permission denied') ||
        lower.contains('operation not permitted')) {
      return 'Mixroom needs permission to read this folder.';
    }
    if (lower.contains('folder is unavailable') ||
        lower.contains('no such file')) {
      return 'This folder is no longer available.';
    }
    return 'Unable to open this folder.';
  }

  bool _isPermissionErrorMessage(String? message) {
    if (message == null) return false;
    final lower = message.toLowerCase();
    return lower.contains('media access') ||
        lower.contains('permission denied') ||
        lower.contains('operation not permitted');
  }

  Future<void> _ensureDirectoryLoaded(String dirPath,
      {bool force = false}) async {
    if (!force && _childrenByDir.containsKey(dirPath)) return;
    if (_loadingDirs.contains(dirPath)) return;
    setState(() {
      _loadingDirs.add(dirPath);
    });

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        throw FileSystemException('Folder is unavailable', dirPath);
      }
      final entities = await dir.list(followLinks: false).toList();
      final visible = <FileSystemEntity>[];
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory || _isAudioFile(entity.path)) {
          visible.add(entity);
        }
      }
      visible.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return _displayNameForPath(a.path)
            .toLowerCase()
            .compareTo(_displayNameForPath(b.path).toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _childrenByDir[dirPath] = visible;
        _dirErrors.remove(dirPath);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _childrenByDir[dirPath] = const <FileSystemEntity>[];
        _dirErrors[dirPath] = _friendlyDirError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDirs.remove(dirPath);
        });
      }
    }
  }

  void _toggleDir(String dirPath) {
    final shouldExpand = !_expandedDirs.contains(dirPath);
    setState(() {
      if (shouldExpand) {
        _expandedDirs.add(dirPath);
      } else {
        _expandedDirs.remove(dirPath);
      }
    });
    if (shouldExpand) {
      _ensureDirectoryLoaded(dirPath);
    }
  }

  void _selectRoot(String rootPath) {
    setState(() {
      _selectedRoot = rootPath;
      _expandedDirs.add(rootPath);
    });
    _ensureDirectoryLoaded(rootPath);
  }

  void _setPreviewFocusPath(String filePath) {
    if (_previewFocusPath == filePath) return;
    setState(() {
      _previewFocusPath = filePath;
    });
    _ensureWaveformForFile(filePath);
  }

  Future<void> _ensureWaveformForFile(String filePath) async {
    if (_waveformByFile.containsKey(filePath)) return;
    if (_waveformLoading.contains(filePath)) return;
    _waveformLoading.add(filePath);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
    try {
      final raw = await _extractWaveformWithFfmpeg(filePath);
      if (!mounted) return;
      if (raw.isEmpty) {
        setState(() {
          _waveformLoading.remove(filePath);
        });
        return;
      }
      final abs = raw.map((e) => e.abs()).toList();
      final maxVal = abs.reduce(math.max);
      if (maxVal <= 0) {
        setState(() {
          _waveformLoading.remove(filePath);
        });
        return;
      }
      final normalized = abs.map((v) => (v / maxVal).clamp(0.0, 1.0)).toList();
      setState(() {
        _waveformByFile[filePath] = normalized;
        _waveformLoading.remove(filePath);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _waveformLoading.remove(filePath);
      });
    }
  }

  Future<List<double>> _extractWaveformWithFfmpeg(String filePath) async {
    final tmpDir = await getTemporaryDirectory();
    final rawPath = p.join(
      tmpDir.path,
      'sample_preview_${filePath.hashCode}_${DateTime.now().microsecondsSinceEpoch}.raw',
    );
    try {
      await FFmpegKit.execute(
        '-v error -i "$filePath" -ac 1 -ar $_kPreviewWaveformPcmRate -f s16le -y "$rawPath"',
      );

      final rawFile = File(rawPath);
      if (!await rawFile.exists()) {
        return const <double>[];
      }
      final bytes = await rawFile.readAsBytes();
      if (bytes.length < 2) {
        return const <double>[];
      }

      final totalSamples = bytes.length ~/ 2;
      if (totalSamples <= 0) {
        return const <double>[];
      }

      final out =
          List<double>.filled(_kPreviewWaveformBars, 0.0, growable: false);
      for (int i = 0; i < _kPreviewWaveformBars; i++) {
        int start = (i * totalSamples / _kPreviewWaveformBars).floor();
        int end = ((i + 1) * totalSamples / _kPreviewWaveformBars).floor();
        start = start.clamp(0, totalSamples);
        end = end.clamp(0, totalSamples);
        if (end <= start) {
          continue;
        }

        double sumSq = 0.0;
        int count = 0;
        for (int s = start; s < end; s++) {
          final bi = s * 2;
          int v = bytes[bi] | (bytes[bi + 1] << 8);
          if ((v & 0x8000) != 0) {
            v -= 0x10000;
          }
          final sample = v / 32768.0;
          sumSq += sample * sample;
          count++;
        }
        if (count > 0) {
          out[i] = math.sqrt(sumSq / count).clamp(0.0, 1.0);
        }
      }
      return _amplifyAndCapWaveform(out);
    } finally {
      try {
        final rawFile = File(rawPath);
        if (await rawFile.exists()) {
          await rawFile.delete();
        }
      } catch (_) {}
    }
  }

  List<double> _amplifyAndCapWaveform(List<double> data) {
    if (data.isEmpty) return const <double>[];
    return data.map((v) {
      if (v > 1.0) return 1.0;
      if (v < 0.0) return 0.0;
      return v;
    }).toList(growable: false);
  }

  void _ensureDuration(String filePath) {
    if (_durationByFile.containsKey(filePath)) return;
    if (_durationLoading.contains(filePath)) return;
    _durationLoading.add(filePath);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
    widget.resolveDuration(filePath).then((duration) {
      if (!mounted) return;
      setState(() {
        _durationByFile[filePath] = duration;
        _durationLoading.remove(filePath);
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _durationLoading.remove(filePath);
      });
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _durationLabel(String filePath) {
    _ensureDuration(filePath);
    if (_durationLoading.contains(filePath)) return '...';
    final duration = _durationByFile[filePath];
    if (duration == null) return '--:--';
    return _formatDuration(duration);
  }

  List<_TreeLine> _buildTreeLines() {
    final root = _selectedRoot;
    if (root == null) return const <_TreeLine>[];
    final lines = <_TreeLine>[];
    _appendChildren(root, 0, lines);
    return lines;
  }

  void _appendChildren(String dirPath, int depth, List<_TreeLine> lines) {
    if (!_expandedDirs.contains(dirPath)) return;
    final children = _childrenByDir[dirPath];
    if (children == null) return;
    for (final entity in children) {
      final isDir = entity is Directory;
      lines.add(
        _TreeLine(
          path: entity.path,
          depth: depth,
          isDirectory: isDir,
          isRoot: false,
        ),
      );
      if (isDir) {
        _appendChildren(entity.path, depth + 1, lines);
      }
    }
  }

  Widget _buildRootSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: widget.rootFolders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final root = widget.rootFolders[index];
          final selected = root == _selectedRoot;
          final label = _displayNameForPath(root);
          return Listener(
            onPointerDown: (event) =>
                _startFolderHold(root, label, event.position),
            onPointerMove: (event) => _updateFolderHoldMove(event.position),
            onPointerUp: (_) => _endFolderHold(),
            onPointerCancel: (_) => _endFolderHold(),
            child: InputChip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                Icons.folder_outlined,
                size: 14,
                color: Colors.white.withOpacity(selected ? 0.95 : 0.75),
              ),
              label: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(selected ? 1.0 : 0.85),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11.2,
                ),
              ),
              selectedColor: const Color(0xFFA48E76).withOpacity(0.5),
              backgroundColor: Colors.white.withOpacity(0.08),
              side: BorderSide(color: Colors.white.withOpacity(0.16)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              onSelected: (_) => _selectRoot(root),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFolderActions(
      String rootPath, String label, Offset globalPosition) async {
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF7D7973),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        math.max(0, globalPosition.dy - 36),
        math.max(0, overlay.size.width - globalPosition.dx),
        math.max(0, overlay.size.height - globalPosition.dy + 36),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              const Icon(Icons.folder_delete_outlined,
                  color: Color(0xFFFFA4A4), size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${L10n.translate(context, 'Remove')} "$label"',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFFD1D1)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (selected == 'remove') {
      widget.onRemoveFolder(rootPath);
    }
  }

  Future<void> _showUsageInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF7B7772),
          title: Text(L10n.translate(ctx, 'File Browser Help'),
              style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HelpRow(
                icon: Icons.create_new_folder_outlined,
                text: L10n.translate(ctx, 'Load a folder into the browser.'),
              ),
              const SizedBox(height: 8),
              _HelpRow(
                icon: Icons.folder_open_outlined,
                text: L10n.translate(
                    ctx, 'Tap a folder button to switch the current folder.'),
              ),
              const SizedBox(height: 8),
              _HelpRow(
                icon: Icons.play_circle_outline,
                text: L10n.translate(ctx, 'Preview an audio file.'),
              ),
              const SizedBox(height: 8),
              _HelpRow(
                icon: Icons.pan_tool_alt_outlined,
                text: L10n.translate(
                    ctx, 'Hold and drag a file into the timeline.'),
              ),
              const SizedBox(height: 8),
              _HelpRow(
                icon: Icons.delete_outline,
                text: L10n.translate(ctx, 'Hold a folder button to remove it.'),
              ),
              const SizedBox(height: 8),
              _HelpRow(
                icon: Icons.multitrack_audio_outlined,
                text: L10n.translate(
                    ctx, 'Use the bottom waveform to seek preview playback.'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L10n.translate(ctx, 'OK')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDirectoryRow(_TreeLine line) {
    final indent = math.min(12 + line.depth * 12.0, 92.0);
    final isExpanded = _expandedDirs.contains(line.path);
    final isLoading = _loadingDirs.contains(line.path);
    final hasError = _dirErrors.containsKey(line.path);
    final title = _displayNameForPath(line.path);
    return InkWell(
      onTap: () => _toggleDir(line.path),
      splashColor: Colors.white.withOpacity(0.085),
      highlightColor: Colors.white.withOpacity(0.03),
      hoverColor: Colors.white.withOpacity(0.02),
      focusColor: Colors.white.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Row(
          children: [
            SizedBox(width: indent),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                isExpanded ? Icons.folder_open : Icons.folder_outlined,
                color: hasError ? Colors.orangeAccent : const Color(0xFFF7F0E8),
                size: 15,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.96),
                  fontSize: 12.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.orangeAccent.withOpacity(0.9),
                  size: 14,
                ),
              ),
            if (isLoading)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.3,
                  color: Colors.white.withOpacity(0.75),
                ),
              )
            else
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                color: Colors.white54,
                size: 17,
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(_TreeLine line) {
    final indent = math.min(12 + line.depth * 12.0, 92.0);
    final filePath = line.path;
    final fileName = _displayNameForPath(filePath);
    final isAuditioning = widget.auditioningPath == filePath;

    final tile = LayoutBuilder(
      builder: (context, constraints) {
        final showDuration = constraints.maxWidth > 340;
        final showInsertButton = constraints.maxWidth > 280;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _setPreviewFocusPath(filePath);
            widget.onAuditionTap(filePath);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              decoration: BoxDecoration(
                color: isAuditioning
                    ? const Color(0x33C89C67)
                    : Colors.white.withOpacity(0.035),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAuditioning
                      ? const Color(0x99EFB67D)
                      : Colors.white.withOpacity(0.04),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: indent),
                  Icon(
                    isAuditioning
                        ? Icons.stop_circle
                        : Icons.play_circle_outline,
                    size: 16,
                    color: isAuditioning
                        ? const Color(0xFFFFD1A6)
                        : Colors.white70,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.94),
                        fontSize: 11.8,
                      ),
                    ),
                  ),
                  if (showDuration)
                    SizedBox(
                      width: 48,
                      child: Text(
                        _durationLabel(filePath),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10.5,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                  if (showInsertButton)
                    IconButton(
                      tooltip: L10n.translate(context, 'Insert at playhead'),
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: EdgeInsets.zero,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                      icon: const Icon(Icons.add_circle_outline,
                          size: 14, color: Colors.white70),
                      color: Colors.white70,
                      onPressed: () => widget.onInsertSample(filePath),
                    ),
                  if (!showInsertButton) const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        );
      },
    );

    return LongPressDraggable<SampleDragData>(
      data: SampleDragData(
        filePath: filePath,
        label: p.basenameWithoutExtension(fileName),
        duration: _durationByFile[filePath],
      ),
      dragAnchorStrategy: (draggable, context, position) =>
          const Offset(42, 48),
      delay: const Duration(milliseconds: 135),
      onDragStarted: () {
        _dragOutsideNotified = false;
        widget.onDragActivityChanged?.call(true);
      },
      onDragUpdate: (details) {
        if (_dragOutsideNotified || widget.onDragOutsidePanel == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(details.globalPosition);
        final bounds = Rect.fromLTWH(0, 0, box.size.width, box.size.height);
        if (!bounds.contains(local)) {
          _dragOutsideNotified = true;
          widget.onDragOutsidePanel?.call();
        }
      },
      onDragEnd: (_) {
        _dragOutsideNotified = false;
        widget.onDragActivityChanged?.call(false);
      },
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF7C7872).withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.38,
        child: tile,
      ),
      child: tile,
    );
  }

  Widget _buildTree() {
    final root = _selectedRoot;
    if (root == null) {
      return Center(
        child: TextButton.icon(
          onPressed: widget.onAddFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(L10n.translate(context, 'Add a sample folder')),
        ),
      );
    }

    final rootError = _dirErrors[root];
    final rootExists = Directory(root).existsSync();
    final showSettingsCta = _isPermissionErrorMessage(rootError) &&
        widget.onOpenSystemSettings != null;
    if (!rootExists || rootError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, color: Colors.white54),
              const SizedBox(height: 8),
              Text(
                rootError == null
                    ? L10n.translate(
                        context, 'This folder is currently unavailable.')
                    : rootError,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                L10n.translate(context,
                    'Tip: choose local folders (not cloud-only placeholders).'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (showSettingsCta)
                    OutlinedButton(
                      onPressed: widget.onOpenSystemSettings,
                      child: Text(L10n.translate(context, 'Open settings')),
                    ),
                  OutlinedButton(
                    onPressed: widget.onAddFolder,
                    child: Text(L10n.translate(context, 'Pick folder')),
                  ),
                  OutlinedButton(
                    onPressed: () => _ensureDirectoryLoaded(root, force: true),
                    child: Text(L10n.translate(context, 'Retry')),
                  ),
                  TextButton(
                    onPressed: () => widget.onRemoveFolder(root),
                    child: Text(L10n.translate(context, 'Remove folder')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final lines = _buildTreeLines();
    if (_loadingDirs.contains(root) && !_childrenByDir.containsKey(root)) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (lines.isEmpty) {
      return Center(
        child: Text(
          L10n.translate(context, 'No files found.'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        if (line.isDirectory) {
          return _buildDirectoryRow(line);
        }
        return _buildFileRow(line);
      },
    );
  }

  String _formatPreviewClock(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Widget _buildPreviewStrip() {
    final filePath = _previewFocusPath ?? widget.auditioningPath;
    if (filePath == null || filePath.isEmpty) {
      return const SizedBox.shrink();
    }
    _ensureWaveformForFile(filePath);
    final waveform = _waveformByFile[filePath] ?? const <double>[];
    final loading = _waveformLoading.contains(filePath);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xB39A948A),
            Color(0xA06B747D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: StreamBuilder<Duration?>(
        stream: widget.previewDurationStream,
        builder: (context, durationSnap) {
          final total = durationSnap.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: widget.previewPositionStream,
            builder: (context, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final totalMs = total.inMilliseconds;
              final progress = totalMs <= 0
                  ? 0.0
                  : (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);

              Future<void> seekFromDx(double localX, double width) async {
                if (totalMs <= 0 || width <= 1) return;
                final ratio = (localX / width).clamp(0.0, 1.0);
                final target =
                    Duration(milliseconds: (totalMs * ratio).round());
                await widget.onPreviewSeek(target);
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => seekFromDx(
                            d.localPosition.dx, constraints.maxWidth),
                        child: SizedBox(
                          height: 28,
                          child: loading
                              ? const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.8),
                                  ),
                                )
                              : CustomPaint(
                                  painter: _WaveformPreviewPainter(
                                    waveform: waveform,
                                    progress: progress,
                                    active: widget.previewPlaying,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayNameForPath(filePath),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatPreviewClock(pos)} / ${_formatPreviewClock(total)}',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoot = _selectedRoot;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xBC9B8E7E),
                Color(0xB088837E),
                Color(0xB86B7780),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 28,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: const SizedBox.expand(),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              L10n.translate(context, 'File Browser'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: L10n.translate(context, 'How to use'),
                            onPressed: _showUsageInfo,
                            padding: EdgeInsets.zero,
                            visualDensity: const VisualDensity(
                                horizontal: -2, vertical: -2),
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 34),
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white70, size: 19),
                          ),
                          IconButton(
                            tooltip: L10n.translate(context, 'Add folder'),
                            onPressed: widget.onAddFolder,
                            padding: EdgeInsets.zero,
                            visualDensity: const VisualDensity(
                                horizontal: -2, vertical: -2),
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 34),
                            icon: const Icon(Icons.create_new_folder_outlined,
                                color: Colors.white70, size: 19),
                          ),
                          if (selectedRoot != null)
                            IconButton(
                              tooltip:
                                  L10n.translate(context, 'Refresh folder'),
                              onPressed: () => _ensureDirectoryLoaded(
                                  selectedRoot,
                                  force: true),
                              padding: EdgeInsets.zero,
                              visualDensity: const VisualDensity(
                                  horizontal: -2, vertical: -2),
                              constraints: const BoxConstraints.tightFor(
                                  width: 36, height: 34),
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white70, size: 19),
                            ),
                          if (selectedRoot != null)
                            IconButton(
                              tooltip: widget.expanded
                                  ? L10n.translate(context, 'Collapse panel')
                                  : L10n.translate(context, 'Expand panel'),
                              onPressed: () =>
                                  widget.onExpandedChanged(!widget.expanded),
                              padding: EdgeInsets.zero,
                              visualDensity: const VisualDensity(
                                  horizontal: -2, vertical: -2),
                              constraints: const BoxConstraints.tightFor(
                                  width: 36, height: 34),
                              icon: Icon(
                                widget.expanded
                                    ? Icons.fullscreen_exit_outlined
                                    : Icons.fullscreen_outlined,
                                color: Colors.white70,
                                size: 19,
                              ),
                            ),
                          IconButton(
                            tooltip: L10n.translate(context, 'Close'),
                            onPressed: widget.onClose,
                            padding: EdgeInsets.zero,
                            visualDensity: const VisualDensity(
                                horizontal: -2, vertical: -2),
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 34),
                            icon: const Icon(Icons.close,
                                color: Colors.white70, size: 19),
                          ),
                        ],
                      ),
                    ),
                    if (widget.rootFolders.isNotEmpty) _buildRootSelector(),
                    Expanded(child: _buildTree()),
                    _buildPreviewStrip(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveformPreviewPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final bool active;

  const _WaveformPreviewPainter({
    required this.waveform,
    required this.progress,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = waveform.isEmpty ? List<double>.filled(64, 0.18) : waveform;
    final barPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7;
    final playedPaint = Paint()
      ..color = active ? const Color(0xFF7EECC2) : const Color(0xFF7DB4FF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7;
    final dxStep = size.width / bars.length;
    final centerY = size.height / 2;
    final playedX = size.width * progress.clamp(0.0, 1.0);

    for (int i = 0; i < bars.length; i++) {
      final x = (i + 0.5) * dxStep;
      final amp = bars[i].clamp(0.04, 1.0);
      final h = amp * (size.height * 0.78);
      final paint = x <= playedX ? playedPaint : barPaint;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }

    final headPaint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawCircle(Offset(playedX, centerY), 2.0, headPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPreviewPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.progress != progress ||
        oldDelegate.active != active;
  }
}

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HelpRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFA9C3FF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _TreeLine {
  final String path;
  final int depth;
  final bool isDirectory;
  final bool isRoot;

  const _TreeLine({
    required this.path,
    required this.depth,
    required this.isDirectory,
    required this.isRoot,
  });
}

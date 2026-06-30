import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
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

class SampleBrowserPanelViewState {
  final String? selectedRoot;
  final String? selectedTreePath;
  final String? previewFocusPath;
  final String sampleFilter;
  final Set<String> expandedDirs;
  final double treeScrollOffset;

  const SampleBrowserPanelViewState({
    this.selectedRoot,
    this.selectedTreePath,
    this.previewFocusPath,
    this.sampleFilter = 'all',
    this.expandedDirs = const <String>{},
    this.treeScrollOffset = 0.0,
  });
}

class SampleBrowserPanel extends StatefulWidget {
  final List<String> rootFolders;
  final Set<String> fixedRootFolders;
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
  final SampleBrowserPanelViewState? initialViewState;
  final ValueChanged<SampleBrowserPanelViewState>? onViewStateChanged;

  const SampleBrowserPanel({
    super.key,
    required this.rootFolders,
    this.fixedRootFolders = const <String>{},
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
    this.initialViewState,
    this.onViewStateChanged,
  });

  @override
  State<SampleBrowserPanel> createState() => _SampleBrowserPanelState();
}

class _SampleBrowserPanelState extends State<SampleBrowserPanel> {
  static const Color _kPanelText = Color(0xFFF4F4F4);
  static const Color _kPanelMutedText = Color(0xB8F4F4F4);
  static const Color _kPanelBorder = Color.fromRGBO(255, 255, 255, 0.12);
  static const Color _kPanelFill = Color.fromRGBO(244, 244, 244, 0.08);
  static const Color _kPanelFillStrong = Color.fromRGBO(244, 244, 244, 0.14);
  static const Color _kPanelAccent = Color(0xFF78D9FF);
  static const Color _kHelpWarmBorder = Color(0xFFE0B27F);
  static const Duration _kFolderHoldDelay = Duration(milliseconds: 180);
  static const double _kFolderHoldMoveTolerance = 14.0;
  static const int _kPreviewWaveformMobileBars = 128;
  static const int _kPreviewWaveformMaxBars = 640;
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
  final FocusNode _treeFocusNode = FocusNode(debugLabel: 'sample_browser_tree');
  late final ScrollController _treeScrollController;
  final Map<String, GlobalKey> _treeRowKeys = <String, GlobalKey>{};

  String? _selectedRoot;
  String? _selectedTreePath;
  String? _previewFocusPath;
  String _sampleFilter = 'all';
  List<String> _rootFoldersSnapshot = const <String>[];
  double? _pendingTreeScrollOffset;
  bool _dragOutsideNotified = false;
  Timer? _folderHoldTimer;
  Offset? _folderHoldDownPos;
  bool _folderHoldMenuShown = false;

  @override
  void initState() {
    super.initState();
    final initialViewState = widget.initialViewState;
    if (initialViewState != null) {
      _selectedRoot = initialViewState.selectedRoot;
      _selectedTreePath = initialViewState.selectedTreePath;
      _previewFocusPath = initialViewState.previewFocusPath;
      _sampleFilter = initialViewState.sampleFilter;
      _expandedDirs.addAll(initialViewState.expandedDirs);
    }
    final initialTreeScrollOffset = math.max(
      0.0,
      initialViewState?.treeScrollOffset ?? 0.0,
    );
    _pendingTreeScrollOffset =
        initialTreeScrollOffset > 0.0 ? initialTreeScrollOffset : null;
    _treeScrollController = ScrollController(
      initialScrollOffset: initialTreeScrollOffset,
    );
    _treeScrollController.addListener(_notifyViewState);
    _rootFoldersSnapshot = List<String>.from(widget.rootFolders);
    _syncSelectedRoot();
    _restoreExpandedDirectories();
    final previewPath = _previewFocusPath ?? widget.auditioningPath;
    if (previewPath != null) {
      _ensureWaveformForFile(previewPath);
    }
    _restorePendingTreeScrollOffset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_treeFocusNode.canRequestFocus) return;
      _treeFocusNode.requestFocus();
    });
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
    _notifyViewState();
    _treeScrollController.removeListener(_notifyViewState);
    _treeFocusNode.dispose();
    _treeScrollController.dispose();
    super.dispose();
  }

  void _notifyViewState() {
    final onViewStateChanged = widget.onViewStateChanged;
    if (onViewStateChanged == null) return;
    onViewStateChanged(
      SampleBrowserPanelViewState(
        selectedRoot: _selectedRoot,
        selectedTreePath: _selectedTreePath,
        previewFocusPath: _previewFocusPath,
        sampleFilter: _sampleFilter,
        expandedDirs: Set<String>.from(_expandedDirs),
        treeScrollOffset: _treeScrollController.hasClients
            ? _treeScrollController.offset
            : math.max(0.0, widget.initialViewState?.treeScrollOffset ?? 0.0),
      ),
    );
  }

  void _restoreExpandedDirectories() {
    for (final dirPath in _expandedDirs.toList(growable: false)) {
      unawaited(_ensureDirectoryLoaded(dirPath));
    }
  }

  void _restorePendingTreeScrollOffset() {
    final targetOffset = _pendingTreeScrollOffset;
    if (targetOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_treeScrollController.hasClients) return;
      final position = _treeScrollController.position;
      if (position.maxScrollExtent <= 0.0 && targetOffset > 0.0) return;
      final restoredOffset = targetOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _pendingTreeScrollOffset = null;
      _treeScrollController.jumpTo(restoredOffset);
      _notifyViewState();
    });
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
        _selectedTreePath = null;
      });
      _notifyViewState();
      return;
    }
    if (_selectedRoot != null && widget.rootFolders.contains(_selectedRoot)) {
      return;
    }
    final nextRoot = widget.rootFolders.first;
    setState(() {
      _selectedRoot = nextRoot;
      _selectedTreePath = null;
      _expandedDirs.add(nextRoot);
    });
    _notifyViewState();
    _ensureDirectoryLoaded(nextRoot);
  }

  bool _isAudioFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _kAudioExtensions.contains(ext);
  }

  bool _sampleMatchesFilter(String path) {
    if (_sampleFilter == 'all') return true;
    final label = p.basenameWithoutExtension(path).toLowerCase();
    final duration = _durationByFile[path];
    final shortOneShot = duration != null && duration.inMilliseconds <= 1800;
    final loopLike = label.contains('loop') ||
        RegExp(r'(^|[^0-9])([6-9][0-9]|1[0-9]{2}|2[0-4][0-9])\s?bpm')
            .hasMatch(label) ||
        (duration != null && duration.inMilliseconds >= 1800);
    switch (_sampleFilter) {
      case 'loops':
        return loopLike;
      case 'oneshots':
        return shortOneShot ||
            label.contains('one shot') ||
            label.contains('oneshot') ||
            label.contains('kick') ||
            label.contains('snare') ||
            label.contains('clap') ||
            label.contains('hat');
      case 'drums':
        return label.contains('drum') ||
            label.contains('kick') ||
            label.contains('snare') ||
            label.contains('clap') ||
            label.contains('hat') ||
            label.contains('perc');
      case 'bass':
        return label.contains('bass') || label.contains('808');
      case 'melodic':
        return label.contains('chord') ||
            label.contains('melody') ||
            label.contains('keys') ||
            label.contains('piano') ||
            label.contains('synth') ||
            label.contains('guitar');
      case 'fx':
        return label.contains('fx') ||
            label.contains('sweep') ||
            label.contains('riser') ||
            label.contains('impact') ||
            label.contains('texture');
      default:
        return true;
    }
  }

  bool _isFixedRoot(String rootPath) {
    final normalized = p.normalize(rootPath);
    return widget.fixedRootFolders
        .any((root) => p.normalize(root) == normalized);
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
      _restorePendingTreeScrollOffset();
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
    _notifyViewState();
    if (shouldExpand) {
      _ensureDirectoryLoaded(dirPath);
    }
  }

  void _selectRoot(String rootPath) {
    setState(() {
      _selectedRoot = rootPath;
      _selectedTreePath = null;
      _expandedDirs.add(rootPath);
    });
    _notifyViewState();
    _requestTreeFocus();
    _ensureDirectoryLoaded(rootPath);
  }

  void _setPreviewFocusPath(String filePath) {
    if (_previewFocusPath == filePath) return;
    setState(() {
      _previewFocusPath = filePath;
    });
    _notifyViewState();
    _ensureWaveformForFile(filePath);
  }

  void _requestTreeFocus() {
    if (!_treeFocusNode.canRequestFocus) return;
    _treeFocusNode.requestFocus();
  }

  GlobalKey _keyForTreePath(String path) {
    return _treeRowKeys.putIfAbsent(path, GlobalKey.new);
  }

  void _pruneTreeRowKeys(List<_TreeLine> lines) {
    final visiblePaths = lines.map((line) => line.path).toSet();
    _treeRowKeys.removeWhere((path, _) => !visiblePaths.contains(path));
  }

  void _ensureSelectedRowVisible(String path) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _treeRowKeys[path]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectTreeLine(
    _TreeLine line, {
    bool auditionFile = false,
    bool ensureVisible = false,
  }) {
    final changed = _selectedTreePath != line.path;
    if (changed) {
      setState(() {
        _selectedTreePath = line.path;
      });
      _notifyViewState();
    }
    if (ensureVisible) {
      _ensureSelectedRowVisible(line.path);
    }
    if (!line.isDirectory) {
      _setPreviewFocusPath(line.path);
      if (auditionFile && changed) {
        unawaited(widget.onAuditionTap(line.path));
      }
    }
  }

  bool _isAncestorPath(String ancestor, String child) {
    final normalizedAncestor = p.normalize(ancestor);
    final normalizedChild = p.normalize(child);
    if (normalizedAncestor == normalizedChild) return false;
    final parent = p.dirname(normalizedChild);
    if (parent == normalizedChild) return false;
    return parent == normalizedAncestor ||
        _isAncestorPath(normalizedAncestor, parent);
  }

  String? _nearestVisibleParentPath(String path, List<_TreeLine> lines) {
    var parent = p.dirname(path);
    final root = _selectedRoot;
    while (parent.isNotEmpty && parent != path && parent != root) {
      final visible = lines.any((line) => line.path == parent);
      if (visible) return parent;
      path = parent;
      parent = p.dirname(path);
    }
    return null;
  }

  _TreeLine? _lineForPath(List<_TreeLine> lines, String? path) {
    if (path == null) return null;
    for (final line in lines) {
      if (line.path == path) return line;
    }
    return null;
  }

  void _restartPreviewForFile(String filePath) {
    _setPreviewFocusPath(filePath);
    if (widget.auditioningPath == filePath && widget.previewPlaying) {
      unawaited(widget.onPreviewSeek(Duration.zero));
      return;
    }
    unawaited(widget.onAuditionTap(filePath));
  }

  KeyEventResult _handleTreeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    final lines = _buildTreeLines();
    if (lines.isEmpty) return KeyEventResult.handled;

    final selectedLine = _lineForPath(lines, _selectedTreePath) ??
        _lineForPath(lines, widget.auditioningPath) ??
        _lineForPath(lines, _previewFocusPath);
    final selectedIndex =
        selectedLine == null ? -1 : lines.indexOf(selectedLine);

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      final nextIndex = selectedIndex < 0
          ? (delta > 0 ? 0 : lines.length - 1)
          : (selectedIndex + delta).clamp(0, lines.length - 1);
      _selectTreeLine(
        lines[nextIndex],
        auditionFile: true,
        ensureVisible: true,
      );
      return KeyEventResult.handled;
    }

    if (selectedLine == null) {
      _selectTreeLine(
        lines.first,
        auditionFile: true,
        ensureVisible: true,
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (selectedLine.isDirectory &&
          !_expandedDirs.contains(selectedLine.path)) {
        setState(() {
          _expandedDirs.add(selectedLine.path);
        });
        _notifyViewState();
        unawaited(_ensureDirectoryLoaded(selectedLine.path));
      } else if (!selectedLine.isDirectory) {
        _selectTreeLine(selectedLine);
        _restartPreviewForFile(selectedLine.path);
      }
      return KeyEventResult.handled;
    }

    final collapses = <String>{};
    if (selectedLine.isDirectory && _expandedDirs.contains(selectedLine.path)) {
      collapses.add(selectedLine.path);
    } else {
      final parent = _nearestVisibleParentPath(selectedLine.path, lines);
      if (parent != null) collapses.add(parent);
    }
    if (selectedLine.isDirectory) {
      collapses.addAll(
        _expandedDirs.where((dir) => _isAncestorPath(selectedLine.path, dir)),
      );
    }

    final parentPath = _nearestVisibleParentPath(selectedLine.path, lines);
    setState(() {
      _expandedDirs.removeAll(collapses);
      if (parentPath != null) {
        _selectedTreePath = parentPath;
      }
    });
    _notifyViewState();
    if (parentPath != null) {
      _ensureSelectedRowVisible(parentPath);
    }
    return KeyEventResult.handled;
  }

  Future<void> _ensureWaveformForFile(String filePath) async {
    final cached = _waveformByFile[filePath];
    if (cached != null && cached.length >= _kPreviewWaveformMaxBars) return;
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

      final out = List<double>.filled(
        _kPreviewWaveformMaxBars,
        0.0,
        growable: false,
      );
      for (int i = 0; i < _kPreviewWaveformMaxBars; i++) {
        int start = (i * totalSamples / _kPreviewWaveformMaxBars).floor();
        int end = ((i + 1) * totalSamples / _kPreviewWaveformMaxBars).floor();
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

  int _previewWaveformBarCountForWidth(double width) {
    if (!width.isFinite || width <= 0) {
      return _kPreviewWaveformMobileBars;
    }
    if (width <= 360) {
      return _kPreviewWaveformMobileBars;
    }
    return (width / 2.25)
        .round()
        .clamp(_kPreviewWaveformMobileBars, _kPreviewWaveformMaxBars)
        .toInt();
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
      if (!isDir && !_sampleMatchesFilter(entity.path)) {
        continue;
      }
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
          final fixed = _isFixedRoot(root);
          final label = _displayNameForPath(root);
          return Listener(
            onPointerDown: fixed
                ? null
                : (event) => _startFolderHold(root, label, event.position),
            onPointerMove:
                fixed ? null : (event) => _updateFolderHoldMove(event.position),
            onPointerUp: fixed ? null : (_) => _endFolderHold(),
            onPointerCancel: fixed ? null : (_) => _endFolderHold(),
            child: InputChip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                fixed ? Icons.folder_special_outlined : Icons.folder_outlined,
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
              selectedColor: _kPanelFillStrong,
              backgroundColor: _kPanelFill,
              side: BorderSide(
                color: selected
                    ? _kPanelAccent.withOpacity(0.34)
                    : Colors.white.withOpacity(0.16),
              ),
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
    if (_isFixedRoot(rootPath)) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF2F3A45),
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
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color.fromRGBO(87, 96, 106, 0.96),
                      Color.fromRGBO(49, 58, 68, 0.96),
                    ],
                  ),
                  border: Border.all(color: _kPanelBorder),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.30),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _kHelpWarmBorder.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: _kHelpWarmBorder.withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Icon(
                              Icons.help_outline_rounded,
                              color: _kHelpWarmBorder,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              L10n.translate(ctx, 'File Browser Help'),
                              style: const TextStyle(
                                color: _kPanelText,
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.translate(
                          ctx,
                          'A few gestures that make browsing samples faster.',
                        ),
                        style: const TextStyle(
                          color: _kPanelMutedText,
                          fontFamily: 'Pretendard',
                          fontSize: 12.2,
                          fontWeight: FontWeight.w500,
                          height: 1.32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      _HelpRow(
                        icon: Icons.create_new_folder_outlined,
                        accent: const Color(0xFF7DB4FF),
                        title: L10n.translate(ctx, 'Add folders'),
                        body: L10n.translate(
                            ctx, 'Load a folder into the browser.'),
                      ),
                      _HelpRow(
                        icon: Icons.folder_open_outlined,
                        accent: const Color(0xFF83D4B9),
                        title: L10n.translate(ctx, 'Switch folder roots'),
                        body: L10n.translate(ctx,
                            'Tap a folder button to switch the current folder.'),
                      ),
                      _HelpRow(
                        icon: Icons.play_circle_outline,
                        accent: const Color(0xFFF7C56D),
                        title: L10n.translate(ctx, 'Preview samples'),
                        body: L10n.translate(ctx, 'Preview an audio file.'),
                      ),
                      _HelpRow(
                        icon: Icons.pan_tool_alt_outlined,
                        accent: const Color(0xFFE78CF3),
                        title: L10n.translate(ctx, 'Drag into timeline'),
                        body: L10n.translate(
                            ctx, 'Hold and drag a file into the timeline.'),
                      ),
                      _HelpRow(
                        icon: Icons.delete_outline,
                        accent: const Color(0xFFFF9A7D),
                        title: L10n.translate(ctx, 'Remove folder roots'),
                        body: L10n.translate(
                            ctx, 'Hold a folder button to remove it.'),
                      ),
                      _HelpRow(
                        icon: Icons.multitrack_audio_outlined,
                        accent: const Color(0xFF78D9FF),
                        title: L10n.translate(ctx, 'Scrub preview'),
                        body: L10n.translate(ctx,
                            'Use the bottom waveform to seek preview playback.'),
                        showDivider: false,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            foregroundColor: _kPanelText,
                            backgroundColor: _kPanelFillStrong,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                          child: Text(
                            L10n.translate(ctx, 'Got it'),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryRow(_TreeLine line) {
    final indent = math.min(12 + line.depth * 12.0, 92.0);
    final isExpanded = _expandedDirs.contains(line.path);
    final isLoading = _loadingDirs.contains(line.path);
    final hasError = _dirErrors.containsKey(line.path);
    final isSelected = _selectedTreePath == line.path;
    final title = _displayNameForPath(line.path);
    return KeyedSubtree(
      key: _keyForTreePath(line.path),
      child: InkWell(
        onTap: () {
          _requestTreeFocus();
          _selectTreeLine(line);
          _toggleDir(line.path);
        },
        splashColor: Colors.white.withOpacity(0.085),
        highlightColor: Colors.white.withOpacity(0.03),
        hoverColor: Colors.white.withOpacity(0.02),
        focusColor: Colors.white.withOpacity(0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.105)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Colors.white.withOpacity(0.26)
                    : Colors.transparent,
              ),
            ),
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
                    color: hasError
                        ? Colors.orangeAccent
                        : const Color(0xFFF7F0E8),
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
        ),
      ),
    );
  }

  Widget _buildFileRow(_TreeLine line) {
    final indent = math.min(12 + line.depth * 12.0, 92.0);
    final filePath = line.path;
    final fileName = _displayNameForPath(filePath);
    final isAuditioning = widget.auditioningPath == filePath;
    final isSelected = _selectedTreePath == filePath;

    final tile = LayoutBuilder(
      builder: (context, constraints) {
        final showDuration = constraints.maxWidth > 340;
        final showInsertButton = constraints.maxWidth > 280;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _requestTreeFocus();
            _selectTreeLine(line);
            widget.onAuditionTap(filePath);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              decoration: BoxDecoration(
                color: isAuditioning
                    ? _kPanelAccent.withOpacity(0.15)
                    : isSelected
                        ? Colors.white.withOpacity(0.105)
                        : Colors.white.withOpacity(0.035),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAuditioning
                      ? _kPanelAccent.withOpacity(0.50)
                      : isSelected
                          ? Colors.white.withOpacity(0.26)
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
                    color: isAuditioning ? _kPanelAccent : Colors.white70,
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

    final dragData = SampleDragData(
      filePath: filePath,
      label: p.basenameWithoutExtension(fileName),
      duration: _durationByFile[filePath],
    );
    final dragFeedback = Material(
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
    );

    void handleDragStarted() {
      _dragOutsideNotified = false;
      widget.onDragActivityChanged?.call(true);
    }

    void handleDragUpdate(DragUpdateDetails details) {
      if (_dragOutsideNotified || widget.onDragOutsidePanel == null) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final local = box.globalToLocal(details.globalPosition);
      final bounds = Rect.fromLTWH(0, 0, box.size.width, box.size.height);
      if (!bounds.contains(local)) {
        _dragOutsideNotified = true;
        widget.onDragOutsidePanel?.call();
      }
    }

    void handleDragEnd() {
      _dragOutsideNotified = false;
      widget.onDragActivityChanged?.call(false);
    }

    final draggable = PlatformCapabilities.current.isDesktop
        ? Draggable<SampleDragData>(
            data: dragData,
            dragAnchorStrategy: (draggable, context, position) =>
                const Offset(42, 48),
            onDragStarted: handleDragStarted,
            onDragUpdate: handleDragUpdate,
            onDragCompleted: handleDragEnd,
            onDragEnd: (_) => handleDragEnd(),
            onDraggableCanceled: (_, __) => handleDragEnd(),
            feedback: dragFeedback,
            childWhenDragging: Opacity(
              opacity: 0.38,
              child: tile,
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: tile,
            ),
          )
        : LongPressDraggable<SampleDragData>(
            data: dragData,
            dragAnchorStrategy: (draggable, context, position) =>
                const Offset(42, 48),
            delay: const Duration(milliseconds: 135),
            onDragStarted: handleDragStarted,
            onDragUpdate: handleDragUpdate,
            onDragCompleted: handleDragEnd,
            onDragEnd: (_) => handleDragEnd(),
            onDraggableCanceled: (_, __) => handleDragEnd(),
            feedback: dragFeedback,
            childWhenDragging: Opacity(
              opacity: 0.38,
              child: tile,
            ),
            child: tile,
          );

    return KeyedSubtree(
      key: _keyForTreePath(line.path),
      child: draggable,
    );
  }

  Widget _buildSampleFilterChips() {
    const filters = <MapEntry<String, IconData>>[
      MapEntry('all', Icons.apps_rounded),
      MapEntry('loops', Icons.repeat_rounded),
      MapEntry('oneshots', Icons.adjust_rounded),
      MapEntry('drums', Icons.graphic_eq_rounded),
      MapEntry('bass', Icons.speaker_rounded),
      MapEntry('melodic', Icons.piano_rounded),
      MapEntry('fx', Icons.auto_awesome_rounded),
    ];
    String labelFor(String id) {
      switch (id) {
        case 'loops':
          return L10n.translate(context, 'Loops');
        case 'oneshots':
          return L10n.translate(context, 'One Shots');
        case 'drums':
          return L10n.translate(context, 'Drums');
        case 'bass':
          return L10n.translate(context, 'Bass');
        case 'melodic':
          return L10n.translate(context, 'Melodic');
        case 'fx':
          return L10n.translate(context, 'FX');
        default:
          return L10n.translate(context, 'All');
      }
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final entry = filters[index];
          final selected = _sampleFilter == entry.key;
          return FilterChip(
            selected: selected,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            avatar: Icon(
              entry.value,
              size: 13,
              color: selected ? Colors.black87 : Colors.white70,
            ),
            label: Text(
              labelFor(entry.key),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black87 : Colors.white70,
              ),
            ),
            selectedColor: _kPanelAccent,
            backgroundColor: _kPanelFill,
            side: BorderSide(
              color: selected
                  ? _kPanelAccent.withOpacity(0.6)
                  : Colors.white.withOpacity(0.12),
            ),
            onSelected: (_) {
              setState(() {
                _sampleFilter = entry.key;
              });
              _notifyViewState();
            },
          );
        },
      ),
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

    _pruneTreeRowKeys(lines);
    _restorePendingTreeScrollOffset();
    return ListView.builder(
      controller: _treeScrollController,
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
            Color.fromRGBO(87, 96, 106, 0.78),
            Color.fromRGBO(49, 58, 68, 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPanelBorder),
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
                                    targetBarCount:
                                        _previewWaveformBarCountForWidth(
                                      constraints.maxWidth,
                                    ),
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
                                color: _kPanelMutedText,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatPreviewClock(pos)} / ${_formatPreviewClock(total)}',
                            style: const TextStyle(
                                color: _kPanelMutedText, fontSize: 10.5),
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
    return Focus(
      focusNode: _treeFocusNode,
      onKeyEvent: _handleTreeKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _requestTreeFocus(),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color.fromRGBO(87, 96, 106, 0.96),
                    Color.fromRGBO(49, 58, 68, 0.96),
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
                border: Border.all(color: _kPanelBorder),
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
                                    color: _kPanelText,
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
                                icon: const Icon(
                                    Icons.create_new_folder_outlined,
                                    color: Colors.white70,
                                    size: 19),
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
                                      ? L10n.translate(
                                          context, 'Collapse panel')
                                      : L10n.translate(context, 'Expand panel'),
                                  onPressed: () => widget
                                      .onExpandedChanged(!widget.expanded),
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
                                visualDensity: VisualDensity.standard,
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 19),
                              ),
                            ],
                          ),
                        ),
                        if (widget.rootFolders.isNotEmpty) _buildRootSelector(),
                        if (widget.rootFolders.isNotEmpty)
                          _buildSampleFilterChips(),
                        Expanded(child: _buildTree()),
                        _buildPreviewStrip(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
  final int targetBarCount;

  const _WaveformPreviewPainter({
    required this.waveform,
    required this.progress,
    required this.active,
    required this.targetBarCount,
  });

  List<double> _barsForPaint() {
    final count = targetBarCount.clamp(32, 640).toInt();
    if (waveform.isEmpty) {
      return List<double>.generate(
        count,
        (i) => 0.14 + (math.sin(i * 0.47).abs() * 0.08),
        growable: false,
      );
    }
    if (waveform.length == count) return waveform;

    final out = List<double>.filled(count, 0.0, growable: false);
    for (int i = 0; i < count; i++) {
      var start = (i * waveform.length / count).floor();
      var end = ((i + 1) * waveform.length / count).ceil();
      start = start.clamp(0, waveform.length - 1);
      end = end.clamp(start + 1, waveform.length);

      var sum = 0.0;
      var peak = 0.0;
      for (int j = start; j < end; j++) {
        final v = waveform[j].clamp(0.0, 1.0);
        sum += v;
        if (v > peak) peak = v;
      }
      final avg = sum / (end - start);
      out[i] = math.max(avg, peak * 0.72).clamp(0.0, 1.0);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bars = _barsForPaint();
    final dxStep = size.width / bars.length;
    final strokeWidth = dxStep < 2.15
        ? 1.15
        : dxStep < 2.7
            ? 1.35
            : 1.7;
    final barPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final playedPaint = Paint()
      ..color = active ? const Color(0xFF7EECC2) : const Color(0xFF7DB4FF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
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
        oldDelegate.active != active ||
        oldDelegate.targetBarCount != targetBarCount;
  }
}

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final bool showDivider;

  const _HelpRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _SampleBrowserPanelState._kPanelText,
                          fontFamily: 'Pretendard',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(
                          color: _SampleBrowserPanelState._kPanelMutedText,
                          fontFamily: 'Pretendard',
                          fontSize: 12.2,
                          fontWeight: FontWeight.w500,
                          height: 1.34,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
        ],
      ),
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

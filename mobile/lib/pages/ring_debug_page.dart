import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ring/ring_capability_probe.dart';
import '../ring/ring_connection.dart';

class RingDebugPage extends StatefulWidget {
  const RingDebugPage({super.key});
  @override
  State<RingDebugPage> createState() => _RingDebugPageState();
}

class _RingDebugPageState extends State<RingDebugPage> {
  final _ring = ChipletRing();
  RingState _state = const RingState(
    conn: RingConnState.disconnected,
    devices: [],
  );
  final _pcm = BytesBuilder();
  int _channels = 1;

  StreamSubscription<RingState>? _stateSub;
  StreamSubscription<RingAudioFrame>? _audioSub;
  StreamSubscription<int>? _keySub;
  StreamSubscription<RingFileEvent>? _fileSub;
  bool _recording = false;
  int? _lastKey;

  // On-device file management
  final List<RingFileRef> _files = [];
  final _dl = BytesBuilder();
  bool _downloading = false;
  String? _listOperationId;
  String? _downloadOperationId;
  var _operationSequence = 0;

  bool _probing = false;
  Duration? _activeProbeDuration;
  String _probeStatus = '尚未测量';
  final List<RingConnectedProbeResult> _probeResults = [];

  String _operationId(String kind) =>
      'debug-$kind-${DateTime.now().microsecondsSinceEpoch}-${_operationSequence++}';

  @override
  void initState() {
    super.initState();
    _stateSub = _ring.state.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    // Double-click capture is owned by the global RingCaptureController (→ 闪念 card),
    // so the debug page only shows the key code here to avoid double-handling the
    // same gesture. Use the manual buttons below to test raw WAV export.
    _keySub = _ring.keyEvents.listen((k) {
      if (!mounted) return;
      setState(() => _lastKey = k);
    });
    _fileSub = _ring.fileEvents.listen(_onFileEvent);
    _refreshConnectionState();
  }

  Future<void> _refreshConnectionState() async {
    final connected =
        RingConnection.instance.isConnected || await _ring.isConnected();
    if (!mounted) return;
    setState(
      () => _state = RingState(
        conn: connected ? RingConnState.connected : RingConnState.disconnected,
        devices: _state.devices,
      ),
    );
  }

  void _onFileEvent(RingFileEvent event) {
    switch (event) {
      case RingFileItemEvent(:final file):
        if (event.operationId != _listOperationId) return;
        if (mounted) {
          setState(() {
            _files.removeWhere(
              (existing) => existing.identityMaterial == file.identityMaterial,
            );
            _files.add(file);
          });
        }
      case RingFileEmptyEvent():
        if (event.operationId != _listOperationId) return;
        _toast('戒指上无本地文件');
      case RingFileAudioEvent(:final pcm):
        if (event.operationId == _downloadOperationId) {
          _dl.add(pcm);
        }
      case RingFileDoneEvent():
        if (_downloading && event.operationId == _downloadOperationId) {
          _downloading = false;
          _exportDownloaded();
        }
      case RingFileDeletedEvent(:final ok):
        _toast(ok ? '删除成功' : '删除失败');
        _refreshFiles();
      case RingMemoryInfoEvent(:final raw):
        _toast('存储信息: ${_hex(raw)}');
      case RingMemoryStateEvent(:final state):
        _toast('存储状态: $state');
      case RingMemoryFullEvent():
        _toast('戒指本地存储已满');
      case RingRecordingAckEvent(:final active, :final ok):
        _toast('${active ? "开始" : "停止"}本地录音${ok ? "成功" : "失败"}');
      case RingUnknownFileEvent(:final kind):
        if (kind == 'formatted') {
          _toast('已格式化（全部删除）');
          if (mounted) setState(() => _files.clear());
        }
    }
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _refreshFiles() {
    final operationId = _operationId('list');
    if (mounted) {
      setState(() {
        _files.clear();
        _listOperationId = operationId;
      });
    }
    _ring.getFileList(operationId: operationId);
  }

  // type = last `_`-segment of the filename (before extension), e.g. ..._8.txt -> 8
  int _typeOf(String name) {
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final parts = base.split('_');
    return int.tryParse(parts.last) ?? 0;
  }

  void _download(RingFileRef file) {
    final operationId = _operationId('download');
    _dl.clear();
    _downloading = true;
    _downloadOperationId = operationId;
    _ring.downloadFile(
      _typeOf(file.name),
      file.id,
      operationId: operationId,
      fileName: file.name,
      sizeBytes: file.sizeBytes,
    );
  }

  Future<void> _runProbe(Duration duration) async {
    if (_probing) return;
    final connected =
        RingConnection.instance.isConnected || await _ring.isConnected();
    if (!connected) {
      _toast('请先连接戒指');
      return;
    }
    if (mounted && _state.conn != RingConnState.connected) {
      setState(
        () => _state = RingState(
          conn: RingConnState.connected,
          devices: _state.devices,
        ),
      );
    }
    setState(() {
      _probing = true;
      _activeProbeDuration = duration;
      _probeStatus = '${duration.inSeconds} 秒测量中，请持续说话…';
    });
    try {
      final probe = RingCapabilityProbe(
        gateway: ChipletRingCapabilityGateway(_ring),
      );
      final result = await probe.runConnectedProbe(duration: duration);
      if (!mounted) return;
      setState(() {
        _probeResults.removeWhere((item) => item.duration == duration);
        _probeResults.add(result);
        _probeResults.sort((a, b) => a.duration.compareTo(b.duration));
        _probeStatus = _probeSummary(result);
      });
      _refreshFiles();
    } catch (error) {
      if (mounted) setState(() => _probeStatus = '测量失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _probing = false;
          _activeProbeDuration = null;
        });
      }
    }
  }

  String _probeSummary(RingConnectedProbeResult result) {
    final fileBytes = result.newFiles.isEmpty
        ? 0
        : result.newFiles.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    final mode = switch (result.connectedMode) {
      RingConnectedCaptureMode.dualPath => '双路径',
      RingConnectedCaptureMode.localFirst => '本地优先',
      RingConnectedCaptureMode.realtimeOnly => '仅实时',
      RingConnectedCaptureMode.unsupported => '不可用',
    };
    return '${result.duration.inSeconds}s · $mode · '
        '本地文件 ${result.newFiles.length} / $fileBytes B · '
        '下载 PCM ${result.downloadedPcmBytes} B · '
        '实时 PCM ${result.livePcmBytes} B · 丢帧 ${result.liveFrameGaps}';
  }

  Future<void> _exportDownloaded() async {
    // NOTE: stored audio may be raw ADPCM rather than PCM — if playback is noise,
    // it needs AdPcmTool decoding before WAV wrapping (calibrate on device).
    final wav = pcmToWav(_dl.toBytes(), sampleRate: 8000, channels: 1);
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ringfile_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(wav);
    await Share.shareXFiles([XFile(path)], text: 'ring local file');
  }

  void _record() {
    _pcm.clear();
    _audioSub?.cancel();
    _audioSub = _ring.audioFrames.listen((f) {
      _channels = f.channels;
      _pcm.add(f.pcm);
    });
    _ring.startRecording();
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopAndExport() async {
    if (mounted) setState(() => _recording = false);
    await _ring.stopRecording();
    final wav = pcmToWav(_pcm.toBytes(), sampleRate: 8000, channels: _channels);
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ring_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(wav);
    await Share.shareXFiles([XFile(path)], text: 'ring recording');
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _audioSub?.cancel();
    _keySub?.cancel();
    _fileSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ring Debug · ${_state.conn.name}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${_recording ? "● 录音中" : "○ 待机"}   双击=全局闪念捕捉 · 按钮=本地导出   最近按键: ${_lastKey ?? "-"}',
              style: TextStyle(
                color: _recording ? Colors.red : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: _ring.startScan,
                child: const Text('扫描'),
              ),
              ElevatedButton(onPressed: _record, child: const Text('实时录音')),
              ElevatedButton(
                onPressed: _stopAndExport,
                child: const Text('停止并导出'),
              ),
            ],
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '双路径能力探针',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seconds in const [30, 60, 120])
                  ElevatedButton(
                    onPressed: _probing
                        ? null
                        : () => _runProbe(Duration(seconds: seconds)),
                    child: Text(
                      _activeProbeDuration?.inSeconds == seconds
                          ? '$seconds 秒测量中'
                          : '测 $seconds 秒',
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _probeStatus,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_probeResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final result in _probeResults)
                    Text(
                      _probeSummary(result),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '本地文件（戒指存储）',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _ring.startLocalRecording(
                  operationId: _operationId('local-start'),
                ),
                child: const Text('本地录音'),
              ),
              ElevatedButton(
                onPressed: () => _ring.stopLocalRecording(
                  operationId: _operationId('local-stop'),
                ),
                child: const Text('停止本地'),
              ),
              ElevatedButton(
                onPressed: _refreshFiles,
                child: const Text('刷新文件列表'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('格式化'),
                      content: const Text('将删除戒指上全部本地文件,确定?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('确定删除'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) _ring.formatFiles();
                },
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('格式化(全删)'),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                if (_state.devices.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('设备:', style: TextStyle(color: Colors.grey)),
                  ),
                for (final d in _state.devices)
                  ListTile(
                    dense: true,
                    title: Text(d.name.isEmpty ? d.id : d.name),
                    subtitle: Text('${d.id}  rssi=${d.rssi}'),
                    onTap: () => _ring.connect(d.id),
                  ),
                if (_files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '文件 (${_files.length}):',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                for (final f in _files)
                  ListTile(
                    dense: true,
                    title: Text(f.name),
                    subtitle: Text(
                      'size=${f.sizeBytes}  type=${_typeOf(f.name)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: '下载并导出',
                          onPressed: _downloading ? null : () => _download(f),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: '删除',
                          onPressed: () => _ring.deleteFile(
                            f.id,
                            operationId: _operationId('delete'),
                            fileName: f.name,
                            sizeBytes: f.sizeBytes,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

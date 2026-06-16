import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RingDebugPage extends StatefulWidget {
  const RingDebugPage({super.key});
  @override
  State<RingDebugPage> createState() => _RingDebugPageState();
}

class _RingDebugPageState extends State<RingDebugPage> {
  final _ring = ChipletRing();
  RingState _state = const RingState(conn: RingConnState.disconnected, devices: []);
  final _pcm = BytesBuilder();
  int _channels = 1;

  StreamSubscription<RingState>? _stateSub;
  StreamSubscription<RingAudioFrame>? _audioSub;
  StreamSubscription<int>? _keySub;
  StreamSubscription<Map>? _fileSub;
  bool _recording = false;
  int? _lastKey;

  // On-device file management
  final List<Map> _files = [];
  final _dl = BytesBuilder();
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _stateSub = _ring.state.listen((s) { if (mounted) setState(() => _state = s); });
    // Ring gesture: double-click (key code 2) toggles recording, mirroring the
    // vendor demo's double-click-to-record. Single-tap also shown for debugging.
    _keySub = _ring.keyEvents.listen((k) {
      if (!mounted) return;
      setState(() => _lastKey = k);
      if (k == 2) {
        if (_recording) { _stopAndExport(); } else { _record(); }
      }
    });
    _fileSub = _ring.fileEvents.listen(_onFileEvent);
  }

  void _onFileEvent(Map e) {
    switch (e['kind']) {
      case 'item':
        if (mounted) setState(() => _files.add(Map.from(e)));
        break;
      case 'audio':
        _dl.add(List<int>.from(e['pcm'] as List));
        break;
      case 'text':
        _toast('文本文件: ${(e['content'] as String?)?.length ?? 0} 字');
        break;
      case 'done':
        if (_downloading) { _downloading = false; _exportDownloaded(); }
        break;
      case 'deleted':
        _toast(e['ok'] == true ? '删除成功' : '删除失败');
        _refreshFiles();
        break;
      case 'formatted':
        _toast('已格式化(全部删除)');
        if (mounted) setState(() => _files.clear());
        break;
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshFiles() {
    if (mounted) setState(() => _files.clear());
    _ring.getFileList();
  }

  // type = last `_`-segment of the filename (before extension), e.g. ..._8.txt -> 8
  int _typeOf(String name) {
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final parts = base.split('_');
    return int.tryParse(parts.last) ?? 0;
  }

  void _download(Map f) {
    _dl.clear();
    _downloading = true;
    _ring.downloadFile(_typeOf(f['name'] as String), List<int>.from(f['id'] as List));
  }

  Future<void> _exportDownloaded() async {
    // NOTE: stored audio may be raw ADPCM rather than PCM — if playback is noise,
    // it needs AdPcmTool decoding before WAV wrapping (calibrate on device).
    final wav = pcmToWav(_dl.toBytes(), sampleRate: 8000, channels: 1);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ringfile_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(wav);
    await Share.shareXFiles([XFile(path)], text: 'ring local file');
  }

  void _record() {
    _pcm.clear();
    _audioSub?.cancel();
    _audioSub = _ring.startRecording().listen((f) {
      _channels = f.channels;
      _pcm.add(f.pcm);
    });
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopAndExport() async {
    if (mounted) setState(() => _recording = false);
    await _ring.stopRecording();
    final wav = pcmToWav(_pcm.toBytes(), sampleRate: 8000, channels: _channels);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ring_${DateTime.now().millisecondsSinceEpoch}.wav';
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
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${_recording ? "● 录音中" : "○ 待机"}   双击戒指开始/停止   最近按键: ${_lastKey ?? "-"}',
            style: TextStyle(
              color: _recording ? Colors.red : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(spacing: 8, children: [
          ElevatedButton(onPressed: _ring.startScan, child: const Text('扫描')),
          ElevatedButton(onPressed: _record, child: const Text('实时录音')),
          ElevatedButton(onPressed: _stopAndExport, child: const Text('停止并导出')),
        ]),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('本地文件（戒指存储）', style: TextStyle(fontWeight: FontWeight.w700))),
        ),
        Wrap(spacing: 8, children: [
          ElevatedButton(onPressed: () => _ring.startLocalRecording(), child: const Text('本地录音')),
          ElevatedButton(onPressed: () => _ring.stopLocalRecording(), child: const Text('停止本地')),
          ElevatedButton(onPressed: _refreshFiles, child: const Text('刷新文件列表')),
          ElevatedButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('格式化'),
                  content: const Text('将删除戒指上全部本地文件,确定?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定删除')),
                  ],
                ),
              );
              if (ok == true) _ring.formatFiles();
            },
            style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('格式化(全删)'),
          ),
        ]),
        Expanded(
          child: ListView(children: [
            if (_state.devices.isNotEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('设备:', style: TextStyle(color: Colors.grey))),
            for (final d in _state.devices)
              ListTile(
                dense: true,
                title: Text(d.name.isEmpty ? d.id : d.name),
                subtitle: Text('${d.id}  rssi=${d.rssi}'),
                onTap: () => _ring.connect(d.id),
              ),
            if (_files.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text('文件 (${_files.length}):', style: const TextStyle(color: Colors.grey))),
            for (final f in _files)
              ListTile(
                dense: true,
                title: Text('${f['name']}'),
                subtitle: Text('size=${f['size']}  type=${_typeOf('${f['name']}')}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.download), tooltip: '下载并播放', onPressed: () => _download(f)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: '删除', onPressed: () => _ring.deleteFile(List<int>.from(f['id'] as List))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

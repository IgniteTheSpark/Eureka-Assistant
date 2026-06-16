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

  @override
  void initState() {
    super.initState();
    _stateSub = _ring.state.listen((s) { if (mounted) setState(() => _state = s); });
  }

  void _record() {
    _pcm.clear();
    _audioSub?.cancel();
    _audioSub = _ring.startRecording().listen((f) {
      _channels = f.channels;
      _pcm.add(f.pcm);
    });
  }

  Future<void> _stopAndExport() async {
    await _ring.stopRecording();
    final wav = pcmToWav(_pcm.toBytes(), sampleRate: 16000, channels: _channels);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ring_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(wav);
    await Share.shareXFiles([XFile(path)], text: 'ring recording');
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _audioSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ring Debug · ${_state.conn.name}')),
      body: Column(children: [
        Wrap(spacing: 8, children: [
          ElevatedButton(onPressed: _ring.startScan, child: const Text('扫描')),
          ElevatedButton(onPressed: _record, child: const Text('录音')),
          ElevatedButton(onPressed: _stopAndExport, child: const Text('停止并导出')),
        ]),
        Expanded(
          child: ListView(children: [
            for (final d in _state.devices)
              ListTile(
                title: Text(d.name.isEmpty ? d.id : d.name),
                subtitle: Text('${d.id}  rssi=${d.rssi}'),
                onTap: () => _ring.connect(d.id),
              ),
          ]),
        ),
      ]),
    );
  }
}

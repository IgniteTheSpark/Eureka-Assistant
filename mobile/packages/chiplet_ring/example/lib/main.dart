import 'package:flutter/material.dart';
import 'package:chiplet_ring/chiplet_ring.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _ring = ChipletRing();
  RingState _state = const RingState(conn: RingConnState.disconnected, devices: []);

  @override
  void initState() {
    super.initState();
    _ring.state.listen((s) => setState(() => _state = s));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('chiplet_ring · ${_state.conn.name}')),
        body: Center(
          child: ElevatedButton(
            onPressed: _ring.startScan,
            child: const Text('扫描'),
          ),
        ),
      ),
    );
  }
}

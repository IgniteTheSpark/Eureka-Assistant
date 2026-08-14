import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderer assets are local and expose the narrow API', () async {
    final template = await rootBundle.loadString(
      'assets/reka_dither/reka_dither.html',
    );
    final engine = await rootBundle.loadString(
      'assets/reka_dither/reka_dither_engine.js',
    );
    final three = await rootBundle.loadString(
      'assets/reka_dither/three.bundle.min.js',
    );
    final license = await rootBundle.loadString(
      'assets/reka_dither/THREE-LICENSE',
    );

    expect(template, contains('RekaHost.postMessage'));
    expect(template, contains('/*__THREE_SOURCE_JSON__*/'));
    expect(template, contains('/*__ENGINE_SOURCE__*/'));
    expect(template, contains('/*__OPTIONS_JSON__*/'));
    expect(engine, contains('setMotion'));
    expect(engine, contains('setReduceMotion'));
    expect(engine, contains('setPaused'));
    expect(engine, contains('pulseRefresh'));
    expect(engine, contains('setProduction'));
    expect(engine, contains('dragYawMultiplier'));
    expect(engine, contains('dragPitchMultiplier'));
    expect(engine, contains("state === 'dragging'"));
    expect(engine, contains('? 4'));
    expect(engine, contains('0x78ff74'));
    expect(engine, contains('eyeGroup'));
    expect(engine, contains('destroy'));
    expect(engine, contains('THRESHOLDS'));
    expect(engine, contains('WebGLRenderTarget'));
    expect(engine, contains('emissiveIntensity'));
    expect(engine, isNot(contains('layers.set(1)')));
    expect(engine, isNot(contains('clearDepth()')));
    expect(engine, isNot(contains('fetch(')));
    expect(engine, isNot(contains('OrbitControls')));
    expect(engine, isNot(contains('GLTFLoader')));
    expect(three, contains('REVISION'));
    expect(three, isNot(contains('./three.core.min.js')));
    expect(license, contains('MIT License'));
  });
}

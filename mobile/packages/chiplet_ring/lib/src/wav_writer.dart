import 'dart:typed_data';

Uint8List pcmToWav(Uint8List pcm, {required int sampleRate, required int channels}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataLen = pcm.length;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  str('RIFF'); u32(36 + dataLen); str('WAVE');
  str('fmt '); u32(16); u16(1); u16(channels);
  u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bitsPerSample);
  str('data'); u32(dataLen); b.add(pcm);
  return b.toBytes();
}

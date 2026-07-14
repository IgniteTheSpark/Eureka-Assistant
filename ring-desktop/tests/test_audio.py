import wave

from ring_desktop.audio import decode_adpcm, write_wav_temp


def test_decode_ratio():
    # IMA ADPCM: 每字节 2 个 4-bit 样本；16-bit => 每 ADPCM 字节出 4 字节 PCM
    pcm = decode_adpcm(b"\x00" * 20)
    assert len(pcm) == 20 * 4


def test_write_wav_header(tmp_path):
    pcm = b"\x00\x00" * 100  # 100 个 16-bit 样本
    path = write_wav_temp(pcm, path=str(tmp_path / "a.wav"))
    with wave.open(path, "rb") as w:
        assert w.getnchannels() == 1
        assert w.getsampwidth() == 2
        assert w.getframerate() == 8000
        assert w.getnframes() == 100

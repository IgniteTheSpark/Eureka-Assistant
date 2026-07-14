import audioop
import itertools
import os
import tempfile
import wave
from typing import Optional

SAMPLE_RATE = 8000  # 实测 8kHz 单声道 16-bit
_seq = itertools.count()  # 每次录音用独立文件名，避免并发覆盖


def decode_adpcm(adpcm: bytes) -> bytes:
    """戒指音频帧的 ADPCM 负载 -> 16-bit 线性 PCM（标准 IMA/DVI ADPCM，单声道）。"""
    pcm, _ = audioop.adpcm2lin(adpcm, 2, None)
    return pcm


def write_wav_temp(pcm: bytes, path: Optional[str] = None) -> str:
    """把 PCM 写成 8kHz 单声道 WAV，返回路径。"""
    if path is None:
        path = os.path.join(tempfile.gettempdir(), f"ring_capture_{next(_seq)}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)
    return path

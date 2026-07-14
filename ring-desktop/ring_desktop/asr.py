import httpx

# 复用 UReka 后端同步 ASR（AppConfig.tencentAsrBase 默认值）。无鉴权头。
ASR_BASE = "https://pre.card.biz"


def transcribe(wav_path: str, base: str = ASR_BASE) -> str:
    """POST 一个 WAV 到后端，返回识别文字。"""
    with open(wav_path, "rb") as f:
        data = f.read()  # 读成字节再传：Content-Length 精确、不受并发文件改动影响
    r = httpx.post(
        f"{base}/api/platform/speech/asr",
        files={"audio": ("ring.wav", data, "audio/wav")},
        data={"speaker_diarization": "false"},
        timeout=30.0,
    )
    r.raise_for_status()
    return r.json().get("data", {}).get("text", "")

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator


TimestampInput = int | float | str | None
Sha256 = str


class S3UploadInfo(BaseModel):
    s3_key: str = Field(min_length=1, max_length=512)
    upload_url: str = Field(min_length=1)
    audio_url: str = Field(min_length=1)
    content_type: str = Field(default="audio/mpeg", min_length=1, max_length=100)
    headers: dict[str, str] = Field(default_factory=dict)
    upload_expires_in: int | None = Field(default=None, gt=0)
    uploaded_at: TimestampInput = None

    @field_validator("s3_key", "upload_url", "audio_url", "content_type")
    @classmethod
    def strip_required(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("value must not be blank")
        return cleaned


class CaptureIdentity(BaseModel):
    client_task_id: str = Field(min_length=1, max_length=160)
    source: Literal["realtime", "offline"] = "realtime"
    card_sn: str = Field(min_length=1, max_length=160)
    device_file_name: str = Field(
        min_length=1,
        max_length=255,
        pattern=r"^F.*\.[oO][pP][uU][sS]$",
    )
    capture_started_at: TimestampInput = None
    capture_ended_at: TimestampInput = None
    device_crc: int | None = Field(default=None, ge=0)
    device_size_bytes: int | None = Field(default=None, gt=0)

    @field_validator("client_task_id", "card_sn", "device_file_name")
    @classmethod
    def strip_required(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("value must not be blank")
        return cleaned


class TencentAsrSyncResultRequest(CaptureIdentity):
    local_audio_sha256: Sha256 = Field(pattern=r"^[0-9a-fA-F]{64}$")
    local_audio_size_bytes: int = Field(gt=0)
    audio_format: Literal["opus"] = "opus"
    asr_mode: Literal["sync_client"] = "sync_client"
    asr_provider: str = Field(
        default="tencent_asr_sync_client",
        min_length=1,
        max_length=100,
    )
    asr_status: Literal["completed", "failed"] = "completed"
    asr_text: str = ""
    asr_segments: list[dict[str, Any]] = Field(default_factory=list)
    raw_response: dict[str, Any] = Field(default_factory=dict)
    asr_error: str = ""
    error_message: str = ""
    speaker_diarization: bool = False

    @field_validator("asr_provider")
    @classmethod
    def strip_provider(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("asr_provider must not be blank")
        return cleaned


class TencentAsrS3UploadRequest(CaptureIdentity):
    local_mp3_sha256: Sha256 | None = Field(
        default=None,
        pattern=r"^[0-9a-fA-F]{64}$",
    )
    local_mp3_size_bytes: int | None = Field(default=None, gt=0)
    local_audio_sha256: Sha256 | None = Field(
        default=None,
        pattern=r"^[0-9a-fA-F]{64}$",
    )
    local_audio_size_bytes: int | None = Field(default=None, gt=0)
    asr_mode: Literal["async"] = "async"
    audio_format: Literal["mp3"] = "mp3"
    s3: S3UploadInfo
    engine_type: str = Field(default="16k_zh", min_length=1, max_length=64)
    speaker_diarization: bool = False
    hotword_list: str = ""

    @field_validator("engine_type")
    @classmethod
    def strip_engine_type(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("engine_type must not be blank")
        return cleaned


class CaptureAcceptance(BaseModel):
    ok: bool = True
    accepted: bool = True
    duplicate: bool
    recording_id: str
    file_id: str
    asr_status: str
    asr_text: str
    pipeline_status: str
    message: str
    error: str = ""


class FlashRequest(BaseModel):
    text: str = Field(min_length=1)
    session_id: str = ""
    source: Literal["voice", "typed", "imported"] = "voice"
    capture_session_type: str = ""
    file_id: str = ""

    @field_validator("text")
    @classmethod
    def strip_text(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("text must not be blank")
        return cleaned


class FlashResponse(BaseModel):
    ok: bool
    session_id: str
    input_turn_id: str
    reply: str = ""
    summary: str = ""
    cards: list[dict] = Field(default_factory=list)
    derived_assets: list[dict] = Field(default_factory=list)
    has_pending: bool = False
    elapsed_ms: int = 0
    error: str = ""


class ListeningRequest(BaseModel):
    state: Literal["on", "off"]

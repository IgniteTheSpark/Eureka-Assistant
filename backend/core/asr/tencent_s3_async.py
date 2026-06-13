"""Tencent ASR S3 async task polling via the internal public service."""
from __future__ import annotations

import logging
from urllib.parse import urlsplit, urlunsplit

import httpx

from config import settings
from core.asr.base import AsrError, AsrResult

logger = logging.getLogger("flash_file")
LOG_TAG = "[FlashFile]"


class TencentS3AsyncAsrClient:
    provider_name = "tencent_asr_s3_async"

    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or settings.tencent_asr_service_base_url).rstrip("/")

    async def create_s3_task(
        self,
        *,
        audio_url: str,
        engine_type: str = "16k_zh",
        speaker_diarization: bool = False,
        hotword_list: str = "",
    ) -> dict:
        url = f"{self.base_url}/api/platform/speech/tencent_asr/s3_task"
        payload = {
            "audio_url": audio_url,
            "engine_type": engine_type,
            "speaker_diarization": speaker_diarization,
            "hotword_list": hotword_list,
        }
        logger.info(
            "%s platform speech s3_task request audio_url=%s engine=%s speaker_diarization=%s base_url=%s",
            LOG_TAG,
            _safe_url(audio_url),
            engine_type,
            speaker_diarization,
            self.base_url,
        )
        try:
            async with httpx.AsyncClient(timeout=20) as cx:
                resp = await cx.post(url, json=payload)
        except httpx.RequestError as e:
            logger.info("%s platform speech s3_task request error error=%s", LOG_TAG, str(e)[:300])
            raise AsrError(f"Tencent ASR s3_task request failed: {str(e)[:160]}")

        try:
            body = resp.json()
        except ValueError:
            logger.info("%s platform speech s3_task non-json response status=%s", LOG_TAG, resp.status_code)
            raise AsrError("Tencent ASR s3_task response is not JSON")
        if resp.status_code >= 400:
            logger.info("%s platform speech s3_task http failed status=%s body=%s", LOG_TAG, resp.status_code, resp.text[:300])
            raise AsrError(f"Tencent ASR s3_task failed: http {resp.status_code}")
        if not isinstance(body, dict) or body.get("code") != 0:
            logger.info("%s platform speech s3_task biz failed status=%s body=%s", LOG_TAG, resp.status_code, str(body)[:300])
            raise AsrError(str((body or {}).get("message") or "Tencent ASR s3_task failed")[:200])
        data = body.get("data")
        if not isinstance(data, dict) or not data.get("task_id"):
            logger.info("%s platform speech s3_task missing task_id body=%s", LOG_TAG, str(body)[:300])
            raise AsrError("Tencent ASR s3_task missing task_id")
        result = dict(data)
        result["_raw_response"] = body
        logger.info("%s platform speech s3_task response task_id=%s", LOG_TAG, result.get("task_id"))
        return result

    async def fetch_task_result(self, task_id: str | int) -> dict:
        url = f"{self.base_url}/api/platform/speech/tencent_asr/task_result"
        logger.info("%s platform speech task_result request task_id=%s base_url=%s", LOG_TAG, task_id, self.base_url)
        try:
            async with httpx.AsyncClient(timeout=20) as cx:
                resp = await cx.post(url, json={"task_id": int(task_id)})
        except (TypeError, ValueError):
            logger.info("%s platform speech invalid task_id=%s", LOG_TAG, task_id)
            raise AsrError("invalid Tencent ASR task_id")
        except httpx.RequestError as e:
            logger.info("%s platform speech request error task_id=%s error=%s", LOG_TAG, task_id, str(e)[:300])
            raise AsrError(f"Tencent ASR task_result request failed: {str(e)[:160]}")

        try:
            body = resp.json()
        except ValueError:
            logger.info("%s platform speech non-json response task_id=%s status=%s", LOG_TAG, task_id, resp.status_code)
            raise AsrError("Tencent ASR task_result response is not JSON")
        if resp.status_code >= 400:
            logger.info("%s platform speech http failed task_id=%s status=%s body=%s", LOG_TAG, task_id, resp.status_code, resp.text[:300])
            raise AsrError(f"Tencent ASR task_result failed: http {resp.status_code}")
        if not isinstance(body, dict) or body.get("code") != 0:
            logger.info("%s platform speech biz failed task_id=%s status=%s body=%s", LOG_TAG, task_id, resp.status_code, str(body)[:300])
            raise AsrError(str((body or {}).get("message") or "Tencent ASR task_result failed")[:200])
        data = body.get("data")
        if not isinstance(data, dict):
            logger.info("%s platform speech missing data task_id=%s body=%s", LOG_TAG, task_id, str(body)[:300])
            raise AsrError("Tencent ASR task_result missing data")
        logger.info(
            "%s platform speech task_result response task_id=%s status=%s text_len=%s segments=%s",
            LOG_TAG,
            task_id,
            data.get("status"),
            len(data.get("text") or ""),
            len(data.get("segments") or []),
        )
        result = dict(data)
        result["_raw_response"] = body
        return result


class TencentSyncAsrClient:
    provider_name = "tencent_asr_sync"

    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or settings.tencent_asr_service_base_url).rstrip("/")

    async def recognize_audio_url(
        self,
        *,
        audio_url: str,
        speaker_diarization: bool = False,
    ) -> dict:
        url = f"{self.base_url}/api/platform/speech/asr"
        logger.info(
            "%s platform speech sync_asr request audio_url=%s speaker_diarization=%s base_url=%s",
            LOG_TAG,
            _safe_url(audio_url),
            speaker_diarization,
            self.base_url,
        )
        try:
            async with httpx.AsyncClient(timeout=60) as cx:
                resp = await cx.post(
                    url,
                    data={
                        "audio": audio_url,
                        "speaker_diarization": "true" if speaker_diarization else "false",
                    },
                )
        except httpx.RequestError as e:
            logger.info("%s platform speech sync_asr request error error=%s", LOG_TAG, str(e)[:300])
            raise AsrError(f"Tencent ASR sync request failed: {str(e)[:160]}")

        try:
            body = resp.json()
        except ValueError:
            logger.info("%s platform speech sync_asr non-json response status=%s", LOG_TAG, resp.status_code)
            raise AsrError("Tencent ASR sync response is not JSON")
        if resp.status_code >= 400:
            logger.info("%s platform speech sync_asr http failed status=%s body=%s", LOG_TAG, resp.status_code, resp.text[:300])
            raise AsrError(f"Tencent ASR sync failed: http {resp.status_code}")
        if not isinstance(body, dict) or body.get("code") != 0:
            logger.info("%s platform speech sync_asr biz failed status=%s body=%s", LOG_TAG, resp.status_code, str(body)[:300])
            raise AsrError(str((body or {}).get("message") or "Tencent ASR sync failed")[:200])
        data = body.get("data")
        if not isinstance(data, dict):
            logger.info("%s platform speech sync_asr missing data body=%s", LOG_TAG, str(body)[:300])
            raise AsrError("Tencent ASR sync missing data")
        result = dict(data)
        result["_raw_response"] = body
        logger.info(
            "%s platform speech sync_asr response text_len=%s segments=%s",
            LOG_TAG,
            len(result.get("text") or ""),
            len(result.get("segments") or []),
        )
        return result


def _safe_url(url: str) -> str:
    try:
        parsed = urlsplit(url)
    except Exception:
        return url
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "", ""))


def parse_finished_result(data: dict) -> AsrResult:
    text = (data.get("text") or "").strip()
    if not text:
        logger.info("%s platform speech finished empty text task_id=%s", LOG_TAG, data.get("task_id"))
        raise AsrError("Tencent ASR finished with empty text")

    raw_segments = data.get("segments") or []
    segments: list[dict] = []
    end_times: list[int | float] = []
    if isinstance(raw_segments, list):
        for seg in raw_segments:
            if not isinstance(seg, dict):
                continue
            start_ms = seg.get("start_ms")
            end_ms = seg.get("end_ms")
            if isinstance(end_ms, (int, float)):
                end_times.append(end_ms)
            segments.append({
                "text": seg.get("text") or "",
                "speaker_id": seg.get("speaker_id"),
                "begin_time": start_ms,
                "end_time": end_ms,
            })

    return AsrResult(
        text=text,
        language="zh",
        duration_sec=(max(end_times) / 1000.0) if end_times else None,
        segments=segments,
        provider_request_id=str(data.get("task_id") or ""),
        raw=data.get("_raw_response") or data,
    )


def parse_sync_result(data: dict) -> AsrResult:
    result_data = dict(data)
    result_data.setdefault("task_id", "")
    return parse_finished_result(result_data)

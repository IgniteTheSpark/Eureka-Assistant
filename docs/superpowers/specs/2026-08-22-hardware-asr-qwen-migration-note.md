# Hardware ASR Alibaba Migration Note

**Status:** Pending validation. This note does not authorize a production provider switch.

## Current hardware path

Hardware recording is completed before transcription:

- `ring-desktop/ring_desktop/asr.py` uploads a completed WAV file to `https://pre.card.biz/api/platform/speech/asr` and waits for final text.
- The Theme V2 large-file capture flow stores an audio URL, creates a Tencent asynchronous task, and polls by task ID through `theme_v2_service/app/domains/capture/asr.py`.
- Existing persistence fields and operational status names still include `tencent_*`; changing the provider therefore requires a data-contract migration or a compatibility layer, not only a new environment variable.

## Why the mobile Qwen model is not a direct replacement

Alibaba Cloud documents `qwen-audio-3.0-asr-flash-streaming` as a low-latency realtime model that produces text while speech is arriving. Its model page explicitly marks batch inference as unsupported. It fits live app microphone input, where Eureka forwards PCM16 frames over a WebSocket.

The hardware flow already has a completed recording or URL. Feeding that file into the realtime WebSocket would require Eureka to download the entire object, decode/resample it, replay it as timed PCM frames, and rebuild asynchronous task durability. That adds cost and failure modes without gaining live partial text.

## Recommended Alibaba target for hardware

Use Alibaba Cloud's asynchronous non-realtime file transcription API behind the existing hardware `create task -> poll result` provider interface. The current official Paraformer HTTP API:

- accepts one HTTP, HTTPS, or supported OSS audio URL per task;
- returns a task ID from `POST /api/v1/services/audio/asr/transcription`;
- exposes task polling at `POST /api/v1/tasks/{task_id}`;
- supports Chinese and English language hints, plus Japanese, Cantonese, Korean, German, French, and Russian for `paraformer-v2`;
- does not accept base64 audio, raw binary streams, or a local file directly.

This protocol is structurally close to the current Tencent S3 asynchronous provider and is the smallest safe migration path. The provider name and model must remain configuration, while capture jobs consume the existing provider-neutral `create_task` and `get_result` contract.

## Required validation before switching

1. Confirm the hardware recording format, sample rate, channel count, maximum duration, object URL lifetime, and whether Alibaba can fetch the current signed URLs.
2. Run Mandarin, English, Mandarin-English code-switching, silence, noisy room, and interrupted-upload fixtures against both providers.
3. Compare p50/p95 completion latency, recognition quality, task failure rate, and per-minute cost.
4. Decide whether to rename `tencent_*` database fields or keep a backward-compatible storage adapter for historical rows.
5. Add a provider flag, deploy with Tencent as rollback, migrate a small account cohort, then remove the old provider only after production evidence.

## Official references

- [Qwen streaming ASR model](https://help.aliyun.com/zh/model-studio/qwen-audio-3-0-asr-flash-streaming)
- [Paraformer non-realtime speech recognition HTTP API](https://help.aliyun.com/zh/model-studio/paraformer-recorded-speech-recognition-restful-api)

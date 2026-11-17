"""Optional, authenticated English Whisper inference service. Audio is never persisted."""
from __future__ import annotations

import asyncio
import hmac
import io
import logging
import os
from pathlib import Path
import wave
from contextlib import asynccontextmanager
from typing import Protocol

import numpy as np
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

MAX_BYTES = 32000 * 15 + 4096
log = logging.getLogger("voicecraft")


class Transcriber(Protocol):
    def transcribe(self, samples: np.ndarray) -> str: ...


class WhisperTranscriber:
    def __init__(self) -> None:
        from faster_whisper import WhisperModel

        self.model = WhisperModel(
            os.getenv("WHISPER_MODEL", "tiny.en"),
            device=os.getenv("WHISPER_DEVICE", "cpu"),
            compute_type=os.getenv("WHISPER_COMPUTE_TYPE", "int8"),
            download_root=os.getenv("WHISPER_CACHE", str(Path.home() / ".cache" / "voicecraft" / "whisper")),
            cpu_threads=int(os.getenv("WHISPER_CPU_THREADS", "4")),
        )

    def transcribe(self, samples: np.ndarray) -> str:
        segments, _ = self.model.transcribe(
            samples, language="en", task="transcribe", beam_size=3,
            vad_filter=True, condition_on_previous_text=False,
        )
        return " ".join(segment.text.strip() for segment in segments).strip()


def decode_wav(data: bytes) -> np.ndarray:
    try:
        with wave.open(io.BytesIO(data), "rb") as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 16000, "NONE"):
                raise ValueError("Expected mono 16-bit PCM WAV at 16000 Hz")
            frames = audio.getnframes()
            if not 1 <= frames <= 16000 * 15:
                raise ValueError("Audio must be between 1 sample and 15 seconds")
            raw = audio.readframes(frames)
            if len(raw) != frames * 2:
                raise ValueError("Truncated WAV payload")
            return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    except (wave.Error, EOFError, ValueError) as exc:
        raise HTTPException(422, "Expected a valid mono 16-bit 16000 Hz WAV, up to 15 seconds") from exc


def create_app(transcriber: Transcriber | None = None, token: str | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        secret = token if token is not None else os.getenv("VOICECRAFT_API_TOKEN", "")
        if len(secret.encode()) < 32:
            raise RuntimeError("Set VOICECRAFT_API_TOKEN to at least 32 bytes; e.g. openssl rand -hex 32")
        app.state.token = secret.encode()
        app.state.transcriber = transcriber or await asyncio.to_thread(WhisperTranscriber)
        app.state.lock = asyncio.Lock()
        yield

    app = FastAPI(title="VoiceCraft Whisper", version="1.0.0", lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)

    @app.get("/healthz")
    async def health():
        return {"status": "ok"}

    @app.post("/v1/transcribe")
    async def transcribe(request: Request):
        supplied = request.headers.get("authorization", "").encode()
        if not hmac.compare_digest(supplied, b"Bearer " + app.state.token):
            raise HTTPException(401, "Invalid server access token", headers={"WWW-Authenticate": "Bearer"})
        if request.headers.get("content-type", "").split(";")[0].lower() != "audio/wav":
            raise HTTPException(415, "Content-Type must be audio/wav")
        # Enforce the limit on the stream itself, including requests without Content-Length.
        body = bytearray()
        async for chunk in request.stream():
            if len(body) + len(chunk) > MAX_BYTES:
                raise HTTPException(413, "Audio upload exceeds 15-second limit")
            body.extend(chunk)
        samples = decode_wav(bytes(body))
        # Bound concurrent inference and reject overload instead of building an unbounded queue.
        if app.state.lock.locked():
            raise HTTPException(429, "Whisper is busy; try again later", headers={"Retry-After": "4"})
        async with app.state.lock:
            try:
                text = await asyncio.to_thread(app.state.transcriber.transcribe, samples)
            except Exception:
                log.exception("Whisper inference failed")
                return JSONResponse(status_code=503, content={"detail": "Whisper inference failed"})
        return {"text": text, "language": "en"}

    return app


app = create_app()

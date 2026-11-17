import io
import unittest
import wave
from concurrent.futures import ThreadPoolExecutor
from threading import Event

import numpy as np
from fastapi.testclient import TestClient

from app import MAX_BYTES, create_app

TOKEN = "a" * 64
HEADERS = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "audio/wav"}


def wav(rate=16000, channels=1, frames=1600):
    out = io.BytesIO()
    with wave.open(out, "wb") as file:
        file.setnchannels(channels)
        file.setsampwidth(2)
        file.setframerate(rate)
        file.writeframes(b"\0\0" * channels * frames)
    return out.getvalue()


class FakeTranscriber:
    def transcribe(self, samples):
        assert samples.dtype == np.float32
        assert len(samples) == 1600
        return "Hello from VoiceCraft."


class APITests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(FakeTranscriber(), TOKEN))
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_health_and_transcription(self):
        self.assertEqual(self.client.get("/healthz").json(), {"status": "ok"})
        response = self.client.post("/v1/transcribe", headers=HEADERS, content=wav())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"text": "Hello from VoiceCraft.", "language": "en"})

    def test_auth_required(self):
        for header in ("", "Bearer wrong", "Bearer é"):
            headers = {**HEADERS, "Authorization": header.encode("utf-8")}
            self.assertEqual(self.client.post("/v1/transcribe", headers=headers, content=wav()).status_code, 401)

    def test_bad_audio(self):
        for data in [b"not audio", wav(rate=44100), wav(channels=2), wav(frames=0), wav()[:-20]]:
            with self.subTest(size=len(data)):
                self.assertEqual(self.client.post("/v1/transcribe", headers=HEADERS, content=data).status_code, 422)

    def test_limits_and_content_type(self):
        self.assertEqual(self.client.post("/v1/transcribe", headers=HEADERS, content=b"x" * (MAX_BYTES + 1)).status_code, 413)
        self.assertEqual(self.client.post("/v1/transcribe", headers=HEADERS, content=wav(frames=240001)).status_code, 422)
        self.assertEqual(self.client.post("/v1/transcribe", headers={**HEADERS, "Content-Type": "application/json"}, content=wav()).status_code, 415)

    def test_inference_failure_is_sanitized(self):
        class Broken:
            def transcribe(self, _):
                raise RuntimeError("private internal details")
        with TestClient(create_app(Broken(), TOKEN)) as client:
            result = client.post("/v1/transcribe", headers=HEADERS, content=wav())
            self.assertEqual(result.status_code, 503)
            self.assertNotIn("private internal", result.text)

    def test_overload_is_bounded(self):
        started, release = Event(), Event()
        class Slow:
            def transcribe(self, _):
                started.set()
                release.wait(5)
                return "done"
        with TestClient(create_app(Slow(), TOKEN)) as client, ThreadPoolExecutor() as pool:
            future = pool.submit(client.post, "/v1/transcribe", headers=HEADERS, content=wav())
            try:
                self.assertTrue(started.wait(3))
                self.assertEqual(client.post("/v1/transcribe", headers=HEADERS, content=wav()).status_code, 429)
            finally:
                release.set()
            self.assertEqual(future.result().status_code, 200)

    def test_refuses_insecure_default(self):
        with self.assertRaises(RuntimeError):
            with TestClient(create_app(FakeTranscriber(), "short")):
                pass


if __name__ == "__main__":
    unittest.main()

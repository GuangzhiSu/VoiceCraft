"""Opt in with VOICECRAFT_RUN_INFERENCE_TEST=1; downloads ~75 MB on first use."""
import os
from pathlib import Path
import unittest
from fastapi.testclient import TestClient
from app import create_app


@unittest.skipUnless(os.getenv("VOICECRAFT_RUN_INFERENCE_TEST") == "1", "Real model test is opt-in")
class RealModelTests(unittest.TestCase):
    def test_synthetic_english_speech(self):
        token = "integration-test-only-not-a-deployment-secret"
        fixture = Path(__file__).parent / "fixtures" / "english.wav"
        with TestClient(create_app(token=token)) as client:
            response = client.post("/v1/transcribe", headers={
                "Authorization": f"Bearer {token}", "Content-Type": "audio/wav",
            }, content=fixture.read_bytes())
            self.assertEqual(response.status_code, 200, response.text)
            words = response.json()["text"].lower()
            for word in ["hello", "world", "recording", "application"]:
                self.assertIn(word, words)

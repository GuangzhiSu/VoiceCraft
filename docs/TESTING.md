# Verification and device checklist

## Checks performed for this delivery

| Check | Result |
| --- | --- |
| Backend API tests in an isolated Python 3.12 environment using the pinned requirements | 7 passed |
| Actual faster-whisper tiny.en model initialization and inference through the FastAPI endpoint | Passed; HTTP 200 |
| Real-model regression test using the included synthetic English WAV | Passed; 8 total tests including the API suite |
| Backend dependency consistency (`pip check`) | Passed |
| Swift parsing with the tree-sitter Swift grammar | All 12 Swift source/test files parsed without syntax errors |
| Xcode project OpenStep parsing and referenced file existence | Passed; application and test targets present |
| Property lists, privacy manifest, asset JSON, workflow/project YAML and shared scheme XML | Parsed successfully |
| iOS compilation and XCTest execution | **Passed: 4 tests, 0 failures** on GitHub Actions macOS / Xcode 16.4 / iOS 18.5 simulator |
| Release iPhone archive and unsigned SideStore IPA | **Passed** on GitHub Actions macOS / Xcode 16.4; arm64, iPhoneOS, minimum iOS 17.0, ZIP integrity, bundle ID and permission descriptions validated in [run 45336225279](https://github.com/GuangzhiSu/VoiceCraft/actions/runs/45336225279), commit `3af4708` |
| Physical iPhone microphone, Apple Speech, WhisperKit model inference and visual/device QA | Not run; requires an iPhone |
| Docker image build | Not run; Python runtime/inference was tested directly |
| GitHub Actions | Backend and iOS jobs passed in [run 44017274184](https://github.com/GuangzhiSu/VoiceCraft/actions/runs/44017274184), commit `aeef47f` |

The initial iOS CI run exposed a mismatch between the app and Swift package simulator architectures. Debug builds now use the active architecture consistently; the subsequent build and all four XCTest cases passed. Commits were published through the authenticated `GuangzhiSu` account.

The synthetic speech said: “Hello world. This is a test of the Voice Craft recording application.” The actual model returned: “Hello world, this is a test of the voicecraft recording application.” This validates the server path and model loading, not iPhone WhisperKit performance or general transcription accuracy.

Direct and transitive dependencies were installed in a clean virtual environment. The model smoke test caught a missing `requests` dependency in faster-whisper's download path; `requests` and a compatible Hugging Face Hub release are now explicitly pinned.

Run the opt-in model test (downloads approximately 75 MB the first time):

```bash
pip install -r backend/requirements.txt -r backend/requirements-test.txt
cd backend
VOICECRAFT_RUN_INFERENCE_TEST=1 python -m unittest discover -s tests -v
```

The GitHub Actions workflow also exposes this real-model test as an optional manual input. Normal runs use the seven API tests and skip downloading model weights.

## Required checks on a Mac / iPhone

1. Open the checked-in project in Xcode 16+, resolve packages and build the VoiceCraft scheme. Run XCTest in an available iOS simulator. The checked-in project has passed the simulator build and four unit tests in CI; repeat locally when changing SDKs or dependencies.
2. Select a development team and unique bundle ID; run on an iOS 17+ iPhone. No signing credentials are included.
3. Grant microphone and speech permissions. Speak in English for 20 seconds with Apple Speech; confirm partial captions, timer and input level update.
4. Record with Apple Speech for at least two minutes. Confirm transcription continues over the 45-second request rotations without obvious gaps/repeated sentences. Check sentence boundaries, pauses and silence.
5. Select Whisper, allow the first model/tokenizer download and Core ML preparation, then speak for 30 seconds. Confirm several updates before stopping, including final trailing words.
6. Force-quit/relaunch after model preparation, turn off network access, select local Whisper and verify transcription works offline. Test battery, heat, memory and speed on the actual target phone.
7. Stop mid-sentence; confirm the saved audio includes the full utterance and the final transcription window is handled. Play it back and share both audio and text.
8. Deny permissions, disable Apple Speech availability, enter an invalid server token, disconnect the server and change microphone routes. Confirm useful errors, an incomplete transcript marker when applicable, and retained audio.
9. Move the app to the background and receive a phone call. Confirm recording stops, the checkpoint is visible after relaunch, and finalization does not block future sessions.
10. Fill storage or induce a write failure; verify Retry Save preserves the session and blocks new recordings until resolved. Corrupt a test copy of the index and confirm new recordings are blocked without replacing the damaged index.
11. Verify deleting a recording removes its audio and index entry. Verify saved files through Finder File Sharing. Use test data for destructive checks.
12. Check layout and VoiceOver with a small iPhone, large text size, long transcripts and multiple saved sessions. The waveform is decorative and excluded from accessibility.

## Known limitations

- English only; no speaker identification or diarization.
- Foreground recording only. Moving away from the app ends the recording.
- Whisper's short-window text merge can duplicate or omit words, especially repeated phrases, fast speech and chunk boundaries. It does not provide true token streaming or timestamp-aligned transcript segments.
- The local model downloads on first use; that first run requires network access to Hugging Face. tiny.en trades recognition accuracy for speed and memory.
- Apple Speech service limits and availability depend on Apple, the installed language assets and the device. Long-session request handover remains a required hardware validation.
- A sudden crash before Stop can leave a CAF file that is not yet indexed. Export it using Finder File Sharing.
- Server access is intended for a trusted personal deployment. It uses one bearer token rather than multi-user accounts. Public production deployment needs appropriate TLS and ingress configuration.
- App Store upload, TestFlight distribution, production backend hosting and developer-account signing have not been performed.

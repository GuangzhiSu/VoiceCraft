# Architecture

## Native application

SwiftUI renders a `@MainActor RecorderModel` with four states: idle, preparing, recording, finishing. Preparation requests permissions and loads the selected model before starting microphone capture. Model selection is locked for the duration of a recording. Foreground-only recording is intentional; navigating away, a phone interruption or a device change stops and saves the session.

`AudioCapture` owns one AVAudioEngine tap. The tap copies incoming buffers, then a serial queue writes them to a continuous CAF file. The same buffers feed either Apple's recognition request or an AVAudioConverter that produces 16 kHz mono Float32 PCM for Whisper. The audio file records the whole session; transcription windows do not truncate or replace it.

Whisper inference runs sequentially, outside the main actor in a service actor. Every window contains four seconds of fresh PCM plus the preceding half-second. A bounded two-minute queue protects against a device/server that cannot keep up: overflow stops the session with an error instead of silently dropping audio. Silence below a conservative RMS floor is skipped; Whisper's own decoding defaults also apply. These safeguards do not eliminate hallucinations or ambient-noise errors.

Overlap text merging compares normalized suffix/prefix words; it is intentionally lightweight and not a substitute for timestamp-aligned streaming. Repeated phrases and words cut at chunk boundaries can still be wrong. The final short window is drained on Stop after the in-flight request finishes.

Apple Speech uses en-US, partial results, punctuation and on-device recognition when supported. Requests are replaced on natural completion and every 45 seconds. A one-second audio replay into the next request reduces boundary loss; word overlap merging reduces duplication. A generation token ignores stale callbacks from cancelled tasks. Actual Apple availability, request limits and accuracy vary by device and OS.

## Persistence and recovery

Recordings use UUID filenames and an atomic JSON index, inside Documents/Recordings. Files are protected until the first device unlock after boot. Index decode failures block new recordings so corrupted metadata is not silently replaced. Finder File Sharing provides recovery/export access.

Stop first closes the tap/file and writes an incomplete snapshot, then finishes transcription. The final save replaces that session's snapshot using its UUID. Index save failures retain a retryable recording in memory and disable new recordings. Audio is retained on transcription failure and indexed with an incomplete flag. The background task gives finalization extra time; the checkpoint remains if the process is suspended or killed.

A crash before Stop may leave an unindexed CAF file; automatic crash recovery is not implemented. Deletion first updates the index, then removes the audio file; if file removal fails the app reports the error, and the orphan can be removed through file sharing.

## Optional server

Local WhisperKit is the default. An optional HTTPS HTTP backend runs faster-whisper tiny.en on CPU. No OpenAI cloud account or billing credential is needed. Client token storage uses Keychain, not UserDefaults. Each request is independent, so the server maintains no user session or transcript state.

The backend requires a non-default token of at least 32 bytes, validates streaming request size and WAV properties, serializes model access, rejects overload, and returns sanitized inference errors. Full authorization is checked before the upload body is consumed. Audio stays in memory; model weights are cached on disk. Public deployments must configure TLS, ingress limits, service supervision, and suitable user authentication before opening access beyond a trusted personal deployment.

## Build

The checked-in Xcode project and shared scheme can be opened directly. `ios/project.yml` provides equivalent XcodeGen configuration for regeneration. Dependencies are pinned at the direct-package level; Xcode resolves transitive dependencies during its first build. No signing credentials, developer team, API tokens or generated provisioning profiles are committed.

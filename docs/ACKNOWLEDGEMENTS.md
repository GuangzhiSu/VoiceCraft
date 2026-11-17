# Third-party acknowledgements

VoiceCraft uses Apple system frameworks (AVFoundation, Speech, SwiftUI, Security), the MIT-licensed WhisperKit Swift package v0.9.4, and an optional backend using FastAPI, Uvicorn, NumPy and faster-whisper. WhisperKit also resolves its own package dependencies, including Hugging Face swift-transformers and Apple swift-argument-parser.

Whisper models originate from OpenAI's Whisper project (MIT license). On-device Core ML conversions are downloaded from the argmaxinc/whisperkit-coreml Hugging Face repository; optional backend weights are downloaded by faster-whisper. Model weights are not included in this source distribution.

The app icon is an original geometric microphone drawing created for this project. No stock photos or user recordings are included. The backend test fixture is synthetic speech generated using FFmpeg/libflite, not a real speaker recording.

Keep third-party license notices with redistributed dependencies and model artifacts. The canonical license texts are included in their upstream distributions:

- https://github.com/argmaxinc/WhisperKit/blob/v0.9.4/LICENSE
- https://github.com/openai/whisper/blob/main/LICENSE
- https://github.com/SYSTRAN/faster-whisper/blob/master/LICENSE
- https://github.com/fastapi/fastapi/blob/master/LICENSE
- https://github.com/encode/uvicorn/blob/master/LICENSE.md
- https://numpy.org/doc/stable/license.html

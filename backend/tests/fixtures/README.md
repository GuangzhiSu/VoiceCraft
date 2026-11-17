# Synthetic English test speech

`english.wav` is synthetic speech generated with FFmpeg's libflite `slt` voice, resampled to mono 16-bit 16 kHz PCM. It contains no real speaker recording.

Text: “Hello world. This is a test of the Voice Craft recording application.”

Reproduce on a system with the flite filter:

```bash
ffmpeg -f lavfi -i "flite=text='Hello world. This is a test of the Voice Craft recording application.':voice=slt" -ar 16000 -ac 1 -y english.wav
```

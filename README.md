# VoiceCraft

原生 iOS 英文录音与实时转录 App。点击一次开始录音，再次点击停止并保存音频和文字。

## 功能

- **Apple Speech**：持续显示英文字幕；支持时优先使用设备端识别，否则由 Apple 在线识别。
- **OpenAI Whisper tiny.en**：通过 WhisperKit 在 iPhone 本地推理，首次使用下载模型；无需 OpenAI API Key。
- **可选 Whisper 后端**：手机性能不足时，可改用自建的 faster-whisper 服务；仍然是 Whisper 模型。
- 录音计时、麦克风音量动画、滚动字幕、历史记录、音频回放、音频与文字分享、删除。
- 权限拒绝、网络错误、音频中断、麦克风切换和保存失败都有明确提示。
- 进入后台时停止录音并保存；支持长录音的 Apple Speech 请求轮换。

**Whisper 是分块的近实时识别**：每 4 秒新音频附加 0.5 秒上下文后转录，显示延迟为采集时间加推理时间。短片段交界处使用单词重叠合并，可能出现重复或漏词，需要人工校对。它不是逐 token 流式识别。Apple Speech 通常提供更频繁的部分结果。

这里的“录制说话人”指录制麦克风音频；本版本不识别人名、声纹或区分多位说话人。

## 在 iPhone 上运行

需要 **Mac、Xcode 16+、iOS 17+ 的 iPhone**。Whisper 建议使用较新的 Apple Silicon iPhone；性能和识别准确率需要在目标手机上实测。模拟器可用于界面和单元测试，录音、Apple Speech 和 Core ML 推理请以真机为准。

1. 克隆仓库并打开工程：

   ```bash
   git clone https://github.com/GuangzhiSu/VoiceCraft.git
   cd VoiceCraft
   open ios/VoiceCraft.xcodeproj
   ```

2. 等待 Xcode 自动解析 Swift Package 依赖（WhisperKit 固定为 `0.9.4`）。
3. 在 **Signing & Capabilities → Team** 选择自己的 Apple 开发账号；必要时修改 Bundle Identifier。
4. 连接 iPhone、打开 Developer Mode，选择该设备，点击 Run。
5. App 内选择 Apple Speech 或 Whisper，点击 **Start Recording**；允许麦克风权限。Apple 模式还需要语音识别权限。
6. Whisper 第一次启动会从 Hugging Face 下载 `openai_whisper-tiny.en` Core ML 模型并编译/加载；保持网络连接和 App 前台运行。准备完成后才会开始录音，后续可离线使用已缓存模型。

默认两种引擎都不需要启动本项目的后端。Apple 模式在设备不支持离线识别时可能需要联网。

如需重新生成工程，工程配置还保存在 `ios/project.yml`：

```bash
brew install xcodegen
cd ios
xcodegen generate
```

## 可选：启动 Whisper 后端

后端使用开放权重 Whisper，**不调用 OpenAI 付费 API**。

```bash
cd backend
cp .env.example .env
openssl rand -hex 32
# 把生成的随机值填入 .env 的 VOICECRAFT_API_TOKEN

docker compose up --build -d
docker compose logs -f
curl http://localhost:8000/healthz
```

首次启动会下载 `tiny.en` 模型，启动时间取决于网络。模型缓存保存在 Docker volume。

在 App 的 Settings 中：

1. 打开 **Use my Whisper server**。
2. 填写部署后的 HTTPS 地址，及 `.env` 中的同一个 token。
3. 选择 Whisper 后录音。

局域网开发可使用 `http://你的Mac主机名.local:8000`（iPhone 和 Mac 需在同一网络，并允许本地网络权限）。iPhone 上的 `localhost` 指 iPhone 自己。普通公网 HTTP 地址会被 App 拒绝；生产部署请使用 HTTPS 反向代理并设置请求体限制（例如 512 KB）和超时。不要把 `.env` 或 token 提交到仓库。

### 接口

- `GET /healthz`：模型加载完成后返回 `{"status":"ok"}`。
- `POST /v1/transcribe`：`Authorization: Bearer <token>`、`Content-Type: audio/wav`；请求体为 16 kHz、单声道、16-bit PCM WAV，最长 15 秒。
- 返回 `{"text":"Hello world.","language":"en"}`。
- 错误码：`401` 鉴权失败、`413` 上传过大、`415` 类型不支持、`422` 音频无效、`429` 推理忙、`503` 推理失败。

服务不会保存上传的音频；同时只执行一个推理请求，繁忙时立即拒绝，避免无界排队。默认 CPU/int8。更大模型可修改 Compose 中 `WHISPER_MODEL`；GPU 需要另行配置匹配的 CUDA 运行环境。

## 代码结构

```text
ios/VoiceCraft/Views/          SwiftUI 录音、设置、录音历史和详情
ios/VoiceCraft/Models/         录音状态机、记录数据和文字合并
ios/VoiceCraft/Audio/          同步录音、16 kHz 重采样和分块队列
ios/VoiceCraft/Services/       Apple Speech、WhisperKit、可选 HTTP 客户端、存储、Keychain
backend/                      可选 FastAPI + faster-whisper 服务
```

架构与生命周期见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)；真机测试步骤和已知限制见 [docs/TESTING.md](docs/TESTING.md)。

## 数据与隐私

音频（CAF）和转录索引（JSON）保存在 App 的 Documents/Recordings 中；服务 token 单独保存在 Keychain。支持 Finder File Sharing 导出 Documents，便于备份或恢复未被索引的音频。录音不排除在设备备份之外；卸载 App 会删除本地数据。Whisper 模型缓存不加入备份。

停止时先保存带有“转录未完成”标记的快照，再等待最终识别结果；若 iOS 在等待期间终止 App，仍可从历史中找到这份快照。突然崩溃发生在主动停止之前时，音频可能仅存在于 Documents 中，需通过 Finder 导出。转录准确率不保证，不建议忽略原始音频进行重要判断。

选择远程 Whisper 时，短音频片段会发送到你设置的服务器；选择不支持本地识别的 Apple Speech 时，音频可能由 Apple 在线处理。发布到 App Store 前应根据实际部署审核隐私披露、第三方 SDK 清单、签名和产品信息。

## 测试

```bash
# 后端接口测试，无需下载模型
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements-test.txt
(cd backend && python -m unittest discover -s tests -v)

# iOS（Mac / Xcode；替换为本机可用的模拟器名称）
xcodebuild test -project ios/VoiceCraft.xcodeproj -scheme VoiceCraft \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

GitHub Actions 配置包括后端接口测试和 macOS 上的 iOS 编译/单元测试。当前交付环境为 Linux，已运行的检查与未运行的检查分开记录在 [docs/TESTING.md](docs/TESTING.md)。

## 参考与许可

- [Apple Speech 文档](https://developer.apple.com/documentation/speech)
- [WhisperKit v0.9.4](https://github.com/argmaxinc/WhisperKit/tree/v0.9.4)（MIT）
- [OpenAI Whisper](https://github.com/openai/whisper)（MIT）
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)（MIT）

本项目不附带模型权重。第三方代码及模型适用各自许可；详见 [docs/ACKNOWLEDGEMENTS.md](docs/ACKNOWLEDGEMENTS.md)。

# iOS 27 直接取屏方案可行性核查（2026-10-27）

用户最新确认当前系统是 iOS 27，优先于日志34中历史的 iOS 26.7.1。本次仅做技术评估，未改生产代码、未编译新包、未刷固件。

已读取用户指定的 ChatGPT「查找开源项目」讨论全文，核对当前本地源码和苹果官方接口。

结论：可执行，推荐先验证 ScreenCaptureKit 直接取屏，再决定性能策略；正常运行目标为 iPhone + ESP32，不需要电脑参与。用户明确实机使用 Wi-Fi、蓝牙和镜像，手机与板之间没有 USB 连接，且不能占用手机充电口。后续设计必须保留无线运行；模型服务仍需手机网络。

证据与边界：
- 苹果 iOS 示例明确要求 iOS27，使用系统 SCContentSharingPicker 选择整屏共享，以 SCStream 输出样本；screen-capture 后台模式支持整屏捕获跨前后台继续运行。授权停止或系统中断时必须停止执行并恢复取帧，不能视为无限后台保证。
- 本地 VideoFeed.swift 已定义 ScreenSource；AgentLoop/Pointer 依赖该接口，可以新增直接取屏实现。现有 AirPlay/板载时钟/解码心跳的新鲜度规则需要按原生帧重写，不能把旧判断直接搬过去。
- 本地检出的 README 和 hardware/hid_bridge/hid_bridge.ino 使用 BLE 控制指令 + USB HID 鼠标键盘；这只能证明该份源码的实现，不能据此推断用户实机连了 USB。用户实机的无线控制固件、版本和协议尚未核对。boboabw/phone-agent 使用 BLE HID 配件，不能认定可直接替换。接入取屏前需核对实际固件，并优先复用现有无线命令通道。
- Actions.swift 已支持最多6条动作，Pointer.swift 已跟踪位置、10次归位及按需精确纠偏。AgentLoop.swift 当前在 tap 之后丢弃基于旧画面的后续动作并重新观察。高速模式需明确可连续执行的动作及失效条件，不能全局解除该防护。
- ScreenCaptureKit 本身不会解决中文拼音/剪贴板路径、选错聊天对象、任务完成判定及云模型耗时。
- 0.3秒点击与0.5秒本地判断是研发目标，尚无本机实测。应分别记录帧年龄、模型耗时、HID耗时及结果确认耗时。

参考项目核查：boboabw/phone-agent，提交 a90045074afcd4de69f885fba25b0b171d690f45。CaptureService.swift 确有 SCContentSharingPicker、SCStream 和帧状态管理，昂贵图像转换本地限流到4 FPS。该仓库验证文档明确离线测试/编译不能替代真机跨App、BLE和后台验收，故只作实现参考，不宣称可直接获得演示性能。

建议最小验收：使用Xcode27 SDK编译，开启系统整屏共享；全程无线，切到微信/Claude持续获取新帧且原无线控制有效；测试键盘弹出、旋转、共享中断和恢复；重复相同任务对照旧取屏链路。成功后再增加高速/精准/自动策略。没有证据要求先购买新开发板；是否需要固件适配，须以实机固件核对结果决定。

2026-10-27 用户追问补充：
- “最多6条”是 Actions.swift:63 每次模型回复提取动作的上限，不是6张截图，不是任务总步数；后续循环仍会继续。当前 tap 后重新观察，所以实际一批常少于6条。调高上限本身不能消除模型往返；仅对前提可在本地验证的动作细化连续执行。
- 本地取屏、图像差分、设备端OCR与HID执行不产生云模型token；发送给模型的图像、提示、历史和模型输出产生用量。采集帧率与模型请求频率必须分开：本地维护最新帧，仅在需要模型决策时提交；避免把连续视频帧逐帧上传。适当分辨率、局部识别和有界历史需保证文字可读与坐标映射正确。
- 使用相同模型和近似图像/文本输入时，直接取屏不会天然增加token；若上传更多/更高清画面或扩大历史则可能增加。减少失败重试可能降低用量，但未做真实任务对照，不能承诺比例。后续需记录每任务调用数、输入/输出token、耗时和成功率。
- 官方图片用量说明：https://docs.volcengine.com/docs/ark/image-understanding?lang=zh 。具体以用户实际模型版本和接口usage为准，不套用其他厂商计算公式。

来源：
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- https://github.com/boboabw/phone-agent/blob/a90045074afcd4de69f885fba25b0b171d690f45/PhoneAgent/Services/CaptureService.swift
- https://github.com/boboabw/phone-agent/blob/a90045074afcd4de69f885fba25b0b171d690f45/docs/verification.md

路由及工具：读取共享路由与Jev工作规则；Agent Router匹配brainstorming并按可行性评估路径执行。使用computer-use浏览器读取指定对话、官方网页和本地代码检索；调用本机Headroom处理源码，保护策略保留近期源码而未产生压缩收益。未安装新skill/plugin/MCP，未向ChatGPT发送消息。

## 2026-10-27 速度估算补充
依据日志34中的20261026-220416失败过程，不是成功任务基准，也不是build73实测。通过前一份metrics的17条累计步骤与后一份30条的共同前缀一致性断言，隔离本次13条步骤，并与steps.jsonl的13次actor调用核对：
- 执行阶段记录75.743秒；actor合计32.110秒，平均2.470秒/次。
- 本次步骤frame_ms合计7.736秒（包含取帧与页面稳定等待），hid_ms合计6.985秒。
- 最后actor回复到paused记录约25.989秒；不能无证据全部归因于取屏。
- 即使将已记录frame_ms全部消除，本样本直接可省也仅7.736秒，约10.2%；真实页面动画/加载仍需等待，所以这是直接计时项的理想上限，不是方案整体提速上限。新鲜画面减少旧计划、重复模型调用的间接收益尚未实测。
- 每少一次相近模型调用，按本样本均值可少约2.47秒模型等待；不能预先断言能减少几次。不能承诺2倍、3倍，或把失败过程改造后推算成成功任务完成耗时。
本轮仅分析已有结构化计时，未改运行代码，未做新旧方案真机对照。

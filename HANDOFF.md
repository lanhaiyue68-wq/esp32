# Codex 接手 ESP32 / Lan Agent — 2026-10-24

## 目标与范围
用户要求接手 Claude「ESP32 网络配置与日志分析」。原始会话 17c84dbc-debc-4306-8308-7ef8c39bfb2f，最后需求：微信作为主人手机任务入口，可操作其他 App 并回原会话报告结果。最新工作树是本目录，原基线 build 44 / b28465de9a480983eb9e3095b53fc16aecf4725e；不要误改旧 ../esp32-iphone-agent。

## 已交付
- build 45，已测试源码 57e066330899ff5882cedf8d852045ab56dddfe0。分支 codex/wechat-phone-tasks 已推 private remote lanhaiyue-web/esp32-iphone-agent-app；未推 origin、未合并 main。后续文档提交不改变已测试 App 源码。
- E:/桌面/Lan-Agent-build45-unsigned.ipa、.ipa.sha256、Lan-Agent-build45-使用说明.txt。IPA 4,980,087 bytes；SHA256 2456fa64652a02828fabfcf34c5f1bd9f5b1c8a31f016e6485a0b80ee66a51da。
- WatchMode.swift：显式权限、精确会话/发言人匹配、主人原消息交给 watchRun → AppModel.run → AgentLoop。跨 App 沿用完整文字校验、40 步上限和无人值守失败策略。
- AppModel.swift：一个持久化待回报项；失败只重试回报，不重做任务，三次失败后停止并保存供下次续发。停止不继续导航/发送，撤权拦截回报，离开聊天前清除旧输入框坐标。
- WatchView.swift 与字符串目录：默认关闭的开关和中文说明。空白名单、部分名字匹配、未列出会话及 ChatTool 代答均没有跨 App 权限。普通回复及微信内任务保留。
- 使用说明 docs/wechat-phone-tasks.md；需求/计划/清单真源 specs/001-wechat-phone-tasks/。

## 验证证据
- RED 工作流 40050688780：203 项中仅新回归失败，原有 202 项通过；日志 ../tmp/codex-watch-red.log。
- GREEN 工作流 40051367358：真实 Xcode 设备 Release 编译成功，207 项模拟器 XCTest、包括新增 5 项全部通过；对应上述完整源码 SHA。
- 112 个 Swift 文件语法、字符串 JSON、plist/entitlements 与 git diff --check 通过。IPA 的 App/Widget build 45、ZIP 完整性、中文开关、无内置模型凭据及 SHA256 核对通过。
- 原始构建日志、Headroom 压缩及 verification.json 在 ../out/build45-wechat-phone-tasks/。基线备份 E:/Backups/esp32-before-wechat-phone-tasks-20261024.zip。
- 按 spec/plan/tasks 做收敛检查，无待实施代码差距；T009 真机验收保留，不能把模拟器当真机。

## 路由和工具
已读取共享 skill-routing-reminder 并执行 Agent Router。采用 direct-execution、systematic-debugging、spec-kit-orchestration、TDD、ponytail 和 verification-before-completion。依用户规则未派子 Agent，自行核查调用链和代码。
Spec Kit 1.0.6 在本工作树初始化，Codex/Claude 集成校验通过、事件关闭。生成的 .agents/.claude/.specify 基础设施仅本地保留并加入本地 git exclude，未上传整套生成技能。无外部扩展 hooks。
Headroom 代码压缩受 recent_code 保护，节省 0；RED 日志节省 1,200 tokens，GREEN 日志节省 7,123 tokens；未改模型代理。

## 下一步和限制
软件交付完成，尚未安装到手机、未发送真实微信消息、未操控手机、未刷固件或更改 Wi-Fi/配对/校准/签名/模型配置。真机点击、镜像、结果回报、停止及发送失败恢复待独立验收。
使用者沿用原 Bundle ID 签名安装，在微信守候开启手机任务，把自己的私聊名加入会话范围及发言人白名单，保持镜像并启动守候。一次一条，等结果后再下一个任务。微信显示名/OCR 不构成强身份认证。
继续开发请保留本分支，不用旧 build 44 覆盖；合并主分支或安装均需相应用户要求。

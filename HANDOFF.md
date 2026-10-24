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


## 2026-10-24 build 46 微信任务提速已交付
- 用户反馈慢；代码 f616a058a06abb9b6e2beec6b738303143f3974f，分支 codex/wechat-phone-tasks。去掉首次回报前 6 秒冷却；回报成功后 20 秒退避改正常 6 秒冷却（失败仍 20 秒）；守候/任务完成轮询改 0.5/0.1 秒；后台启动跳过 0.8 秒不可见动画。2 秒持续画面变化、5 秒检查限流、发送核对、文字校验、权限和停止检查均保留。
- 关键文件 WatchMode.swift、RunSession.swift、Shared.xcconfig；新增 watch timing 阶段耗时，不增加消息内容。路由 systematic-debugging / verification-before-completion，沿用现有规格作小范围调整，无子 Agent。
- 工作流 40099241832：Xcode 设备 Release 编译及 207 项模拟器 XCTest 全部通过，112 Swift 文件语法检查通过。仅固定等待调整，未增加镜像实现的测试。Headroom 压缩云端日志节省 7,137 tokens（19.3%），原文保留。
- 桌面 E:/桌面/Lan-Agent-build46-unsigned.ipa，4,985,868 bytes；SHA256 d0c46aae0589e087349e78018d81d478ab64b7113405f124ae8f02a8a7d4d47d。包/Widget build、中文开关、ZIP、无模型 key 和桌面 SHA256 核对通过。build 45 保留回退。
- 证据 ../out/build46-watch-speed/{verification.json,baseline-timing.json,optimized-timing.json,xcode-build-and-tests.log}。这些是源代码固定等待变化，不是实机加速比例。未安装/发真实消息/刷固件；下一步 T009/T013 真机验收并按 watch timing 对比模型、任务、回报耗时。

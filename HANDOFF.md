## 最新交付：build 48 / 日志22导航回归修复 — 2026-10-25

- 最新工作树 E:/AgentStorage/esp32/iphone-agent-build13，分支 codex/wechat-phone-tasks；应用测试源码 0f1315eb3634de0f70b5945e798ad28753e73f86，后续仅交付文档提交。仅 private remote，未推 origin/main。
- 已确认47回归：多会话原始目标当固定计划，打开未读后返回列表，红点消耗而没有read/decide。六轮巡查26次actor调用，五次空chat一次bounce失败。原始证据仅本机 out/logs22-diagnosis，不上传日志/截图。
- 48：状态分支计划；导航前本机完整唯一顶部标题完成（gate/帧恢复核验后），读消息独立确认完整实际会话；普通任务/发送清空回调；多会话读后继续已有未读巡查直到列表为空。47有效的启动/解码优化与文字、发出、stale、bounce保护保留。
- 关键代码 WatchMode.swift、RunSession.swift、AgentLoop.swift；新增 WatchNavigationTests.swift五项回归。路由：systematic-debugging、TDD、verification-before-completion；沿用现有spec，不新增平台技能，不使用子Agent。
- RED40104949418：原210通过，新4项失败/9条断言，另1新项通过。GREEN40105825214：最终源码设备Release编译成功，215项XCTest全部通过；本机114Swift语法检查通过。
- 桌面 E:/桌面/Lan-Agent-build48-unsigned.ipa，4,988,236 bytes，SHA256 dbde67367ad8ec7eba1eb3b3b7dc4fb9400d322d38f8912e50510561b29e6bcf；47的IPA/校验/说明已送回收筒，仅保留48。验证证据 out/build48-logs22-navigation-fix/verification.json。
- 用户长期偏好：每次新版验证交付桌面后，自动回收桌面旧IPA/校验/说明，无需再问；源码、日志和构建证据保留。
- 下一步：用户覆盖签名安装，重启守候并发一条新消息，采48日志验证read/decide/任务/回报及真实耗时。47已清红点但未处理的旧消息不自动补执行。没有操作真实手机，测试不可换算真实成功率。

## 最新用户偏好：桌面安装包仅保留最新已验证版
已于2026-10-24将 Lan Agent 桌面build44/45/46送回收筒，只留build48及对应说明和校验码。以后每次新版验证并交付桌面后自动回收桌面旧IPA/校验码/说明，无需重复确认；不扩展到源码、日志或构建证据。用户要求优先于之前「桌面保留旧版回退」记录。

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


## 2026-10-24 build 47 日志 21 提速验证中
日志在 E:/AgentStorage/esp32/out/logs21-performance/，只本地读取。14 个最新运行中，回执输入动作 14.36 秒，背景重建 GOP 达 854 单元；多会话巡查每次重做 planner；后台无离开动作仍等待新画面。修复源码 744d3e7，条件化后台重建、复用固定巡查计划、保留当前帧验证的后台快速启动。RED 40102025495 的 210 项仅健康后台解码案例失败；GREEN 40102487275 正在跑。113 Swift 语法通过。暂不交付未验证 IPA；未改 stale plan/隐私/文字/停止/身份权限，未实机操作。路由 systematic-debugging/TDD/verification-before-completion，未派 Agent。下一步核对 GREEN 及包校验，交付 build47，更新记录，真机测速另待验收。


## 2026-10-24 build 47 日志 21 提速交付完成
- 已测试源码 744d3e727a647ed00ff134b46ab50eefdae2f415，分支 codex/wechat-phone-tasks。多会话巡查复用固定计划；后台钩子仅在没有成功解码的可用新帧时重建 GOP（其余恢复路径保留）；后台无离开动作时直接核验当前帧。包含 build46 等待提速。stale plan、文字/发送/隐私/停止/权限及动作后新帧验证均保留。
- 关键文件 ios/IPhoneAgent/Video/VideoFeed.swift、App/AppModel.swift、App/RunSession.swift、App/WatchMode.swift、IPhoneAgentTests/DecoderRecoveryTests.swift、Config/Shared.xcconfig。
- RED 工作流 40102025495：210 项仅新健康解码案例失败。GREEN 40102487275：Xcode 设备 Release 编译和 210 项模拟器 XCTest（含新增3项）全部通过。113 Swift 文件语法、JSON/plist、git diff --check 通过。设备上表现和速度仍需同任务对比，不能用单元测试代替。
- 桌面 E:/桌面/Lan-Agent-build47-unsigned.ipa、.sha256、Lan-Agent-build47-使用说明.txt。IPA 4,986,172 bytes；SHA256 0a9c978d042cbdea9ba988243337978f2e983162c941f1023d5d8d8d4bca16e3。App/Widget build47、ZIP、中文开关、无模型凭据和桌面 SHA256 均核对。旧45/46保留。
- 原日志和截图只在 E:/AgentStorage/esp32/out/logs21-performance/ 本地分析，未上传仓库。诊断报告区分 trace 跨度和动作done：39.17秒会话导航/52.87秒手机任务；输入动作14.36秒与854单元GOP恢复重叠。最后CancellationError对应用户手动停止。
- 证据 ../out/build47-logs21-speed/{verification.json,xcode-build-and-tests.log,checkpoint.json}。路由 systematic-debugging/TDD/verification-before-completion，沿用现有 Spec Kit 规格；未派子 Agent。Headroom 实际压缩诊断及CI日志（GREEN省7137、RED省7237 tokens），未更改模型代理。
- 下一步 T009/T013/T018：用户原BundleID签名安装47，真机同任务比较 watch timing / decoder 日志并验收低错误率。未安装、未发送真实消息、未修改硬件/网络/模型设置。没有其他待实施代码差距；仅真机验收待办。

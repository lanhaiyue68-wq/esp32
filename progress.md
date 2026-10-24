# 当前进度

2026-10-24：Codex 接手 Claude「ESP32 网络配置与日志分析」，实际工作目录为本目录，App 基线 build 44。当前分支 codex/wechat-phone-tasks。

已重现：真实 Xcode 流水线 40050688780，203 项测试中仅新增微信外任务测试失败，原有 202 项通过；设备 Release 编译成功。

已实现并通过云端验证的 build 45：默认关闭的跨 App 任务入口、严格会话/发言人匹配、原始消息交给现有执行器、普通文本输入校验、持久化待回报与仅重试回报、停止检查、设置及中文说明。112 个 Swift 文件语法检查、字符串目录 JSON、plist/entitlements 与 git diff --check 通过。

真实验证：工作流 40051367358，源码 57e066330899ff5882cedf8d852045ab56dddfe0；Xcode 设备 Release 编译成功，207 项模拟器 XCTest 全过（含新增 5 项）。IPA 的 App/Widget build 45、ZIP 完整性、中文开关及 SHA256 核对通过。桌面交付 E:/桌面/Lan-Agent-build45-unsigned.ipa，以及 .ipa.sha256 与使用说明。SHA256：2456fa64652a02828fabfcf34c5f1bd9f5b1c8a31f016e6485a0b80ee66a51da。

软件交付已完成。下一步仅为真机安装与实测：尚未执行真实消息、手机操作或安装，不改固件与设备配置。主分支未合并；代码保存在 codex/wechat-phone-tasks。测试和包验证详情位于 ../out/build45-wechat-phone-tasks/verification.json。

真源：specs/001-wechat-phone-tasks/{spec,plan,tasks}.md。备份：E:/Backups/esp32-before-wechat-phone-tasks-20261024.zip。


## 2026-10-24 build 46 微信任务提速已交付
- 用户反馈慢；代码 f616a058a06abb9b6e2beec6b738303143f3974f，分支 codex/wechat-phone-tasks。去掉首次回报前 6 秒冷却；回报成功后 20 秒退避改正常 6 秒冷却（失败仍 20 秒）；守候/任务完成轮询改 0.5/0.1 秒；后台启动跳过 0.8 秒不可见动画。2 秒持续画面变化、5 秒检查限流、发送核对、文字校验、权限和停止检查均保留。
- 关键文件 WatchMode.swift、RunSession.swift、Shared.xcconfig；新增 watch timing 阶段耗时，不增加消息内容。路由 systematic-debugging / verification-before-completion，沿用现有规格作小范围调整，无子 Agent。
- 工作流 40099241832：Xcode 设备 Release 编译及 207 项模拟器 XCTest 全部通过，112 Swift 文件语法检查通过。仅固定等待调整，未增加镜像实现的测试。Headroom 压缩云端日志节省 7,137 tokens（19.3%），原文保留。
- 桌面 E:/桌面/Lan-Agent-build46-unsigned.ipa，4,985,868 bytes；SHA256 d0c46aae0589e087349e78018d81d478ab64b7113405f124ae8f02a8a7d4d47d。包/Widget build、中文开关、ZIP、无模型 key 和桌面 SHA256 核对通过。build 45 保留回退。
- 证据 ../out/build46-watch-speed/{verification.json,baseline-timing.json,optimized-timing.json,xcode-build-and-tests.log}。这些是源代码固定等待变化，不是实机加速比例。未安装/发真实消息/刷固件；下一步 T009/T013 真机验收并按 watch timing 对比模型、任务、回报耗时。


## 2026-10-24 build 47 日志 21 提速交付完成
- 已测试源码 744d3e727a647ed00ff134b46ab50eefdae2f415，分支 codex/wechat-phone-tasks。多会话巡查复用固定计划；后台钩子仅在没有成功解码的可用新帧时重建 GOP（其余恢复路径保留）；后台无离开动作时直接核验当前帧。包含 build46 等待提速。stale plan、文字/发送/隐私/停止/权限及动作后新帧验证均保留。
- 关键文件 ios/IPhoneAgent/Video/VideoFeed.swift、App/AppModel.swift、App/RunSession.swift、App/WatchMode.swift、IPhoneAgentTests/DecoderRecoveryTests.swift、Config/Shared.xcconfig。
- RED 工作流 40102025495：210 项仅新健康解码案例失败。GREEN 40102487275：Xcode 设备 Release 编译和 210 项模拟器 XCTest（含新增3项）全部通过。113 Swift 文件语法、JSON/plist、git diff --check 通过。设备上表现和速度仍需同任务对比，不能用单元测试代替。
- 桌面 E:/桌面/Lan-Agent-build47-unsigned.ipa、.sha256、Lan-Agent-build47-使用说明.txt。IPA 4,986,172 bytes；SHA256 0a9c978d042cbdea9ba988243337978f2e983162c941f1023d5d8d8d4bca16e3。App/Widget build47、ZIP、中文开关、无模型凭据和桌面 SHA256 均核对。旧45/46保留。
- 原日志和截图只在 E:/AgentStorage/esp32/out/logs21-performance/ 本地分析，未上传仓库。诊断报告区分 trace 跨度和动作done：39.17秒会话导航/52.87秒手机任务；输入动作14.36秒与854单元GOP恢复重叠。最后CancellationError对应用户手动停止。
- 证据 ../out/build47-logs21-speed/{verification.json,xcode-build-and-tests.log,checkpoint.json}。路由 systematic-debugging/TDD/verification-before-completion，沿用现有 Spec Kit 规格；未派子 Agent。Headroom 实际压缩诊断及CI日志（GREEN省7137、RED省7237 tokens），未更改模型代理。
- 下一步 T009/T013/T018：用户原BundleID签名安装47，真机同任务比较 watch timing / decoder 日志并验收低错误率。未安装、未发送真实消息、未修改硬件/网络/模型设置。没有其他待实施代码差距；仅真机验收待办。


## 2026-10-24 桌面旧版本清理完成
遵照用户要求，将桌面 build44/45/46 的7个旧IPA/校验码/说明文件送资源回收筒；桌面只留 build47 及其对应说明/校验码，最新版SHA256复核通过。以后新版验证交付后自动同样清理桌面旧版，用户偏好记入 memory.md。源码和原始日志不属于此次清理范围。工具拦下永久删除后，使用可恢复的回收筒方式完成，没有绕过删除限制。

## 2026-10-25 build 48 日志 22 修复进行中
已确认 build 47 多会话固定计划造成进入目标后返回列表，消耗红点却没有读取消息。六轮巡查26次 actor调用，最后一次循环保护失败原文 kept going back and forth between two screens。已加导航前本地标题完成与 readChat 独立目标核对；RED CI 40104949418 在跑。Swift 114文件语法与配置格式检查通过。原日志留本地 out/logs22-diagnosis；未控制真实手机。下一步全量云端验证、交付48再回收桌面47。

补充：多会话读取完成后继续本轮未读巡查，直到列表确认没有目标未读才进入等待；避免当前会话处理完就进入冷却，使其他已有未读等到下个定时周期。待回报仍优先，不重新执行任务。

## 2026-10-25 build 48 已交付
最终源码0f1315eb3634de0f70b5945e798ad28753e73f86，云端40105825214设备Release与215项XCTest全部通过。桌面Lan-Agent-build48-unsigned.ipa，4,988,236 bytes，SHA256 dbde67367ad8ec7eba1eb3b3b7dc4fb9400d322d38f8912e50510561b29e6bcf；桌面47的IPA/校验/说明已回收，只留48。未操作真实手机，端到端与速度仍待用户新消息和48日志验证。


## 2026-10-25 影片速度對照（只讀調查）
- 已用 video-understand、影片抽幀／本機轉錄、公開源碼核對新物種說影片。畫面 AgentMouse-S3 與 boboabw/phone-agent 高度吻合，但作者精確版本／模型未確認。
- 該專案當前以 iPhone ScreenCaptureKit 直接取畫面，BLE HID 操作；與本專案 AirPlay → ESP32 → BLE → App 解碼路徑不同。當前原生取畫面方案要求 iOS27，尚未核對使用者設備相容性。
- 微信點讚示範本身約半分鐘，不能從影片推導完整任務平均耗時或成功率。既有 logs22 導航與模型重複成本仍需分段量測。
- 完整證據：E:/AgentStorage/esp32/out/video-comparison-20261025/comparison.md；本次未改產品程式或交付 build49，build48 真機速度待驗證。


## 2026-10-25 build49 速度优化已交付
- 已测试源码 24a22f586d46506cd26340647595f158a0c9e330，分支 codex/wechat-phone-tasks，仅private远端。
- 已授权微信手机任务采用directStart：当前截图与原始Goal直接交actor，省去初始planner；错误／卡住／replan仍沿用planner。普通任务、固定导航和发送默认保留原策略，每次run清除旧模式。
- VideoFeed以既有完整usable(after:)证据进行有界等待，新帧或boundary后heartbeat确认的静止帧均及时返回；避免固定1.5～3秒等待使证据过期并进入快照失败。保留settled、latest_ms／帧时间／断链／取消／恢复／快照及全部原有输入／会话／发出检查。
- RED40108170022：223项中4个新测试失败（5条失败，含1个旧等待路径引发的BlindError）；原215项通过。GREEN40108655015：Xcode26.6设备Release编译和223项XCTest全部通过；115Swift语法、JSON、plist、entitlements及diff检查通过。
- 桌面 E:/桌面/Lan-Agent-build49-unsigned.ipa，4,987,626 bytes；SHA256 7d3a9307af79bad1c360cc77fc070c096be8b6b5a46d13ac33f36bd081d72be9。App/Widget49、ZIP、minimumOS18.0、无模型预设和新编译路径已核对；桌面48的IPA／sha／说明三件套已回收。
- 路由 systematic-debugging／TDD／verification-before-completion，沿用已有spec；未派子Agent。Headroom压缩RED省7443、GREEN省7123 tokens；合成88字节H264测试不含手机画面。
- 证据 ../out/build49-speed/{implementation-plan.md,verification.json,red-ci.log,green-ci.log,checkpoint.json}。未改固件／网络／账号／模型配置；原生ScreenCaptureKit要求iOS27且现有编译环境26.6，本轮未接入。未操作真机，整体提速和成功率待同任务新日志验证。

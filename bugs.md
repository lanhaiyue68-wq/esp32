# 问题与验证

## 2026-10-24 微信指令无法执行微信外任务

根因：WatchSettings.composePrompt 与 ownerTask 都明确限定微信内操作；主页任务执行器本身支持其他 App。

修复：显式开关 + 精确匹配的会话/发言人范围，跨 App 使用本轮授权消息原文。模型只决定是否要执行，不能替换主人指令。回报保存为单独待发项，失败只重试回报。

RED 证据：工作流 40050688780；WatchPhoneTaskTests.testAnEnabledOwnersRequestCanBecomeATaskOutsideWeChat 断言失败；其余 202 项通过。日志及 Headroom 压缩证据位于 ../tmp/codex-watch-red.log 和 .headroom.json（节省 1,200 tokens / 35.5%）。

GREEN 证据：工作流 40051367358，57e066330899ff5882cedf8d852045ab56dddfe0；设备 Release 编译成功，207 项 XCTest、包括新增 5 项回归全过。完整日志和包校验在 ../out/build45-wechat-phone-tasks；Headroom 对构建日志节省 7,123 tokens / 19.3%。

当前限制：微信显示名/OCR 不是强身份认证；一次下一个任务，等结果后再发下一条；真实手机点击、镜像与发送尚未验收。发送回报失败最多三次会停止守候，待回报保留供下次开始时续发。没有新增固件变更或设备设置改动。


## 2026-10-24 build 46 微信任务提速已交付
- 用户反馈慢；代码 f616a058a06abb9b6e2beec6b738303143f3974f，分支 codex/wechat-phone-tasks。去掉首次回报前 6 秒冷却；回报成功后 20 秒退避改正常 6 秒冷却（失败仍 20 秒）；守候/任务完成轮询改 0.5/0.1 秒；后台启动跳过 0.8 秒不可见动画。2 秒持续画面变化、5 秒检查限流、发送核对、文字校验、权限和停止检查均保留。
- 关键文件 WatchMode.swift、RunSession.swift、Shared.xcconfig；新增 watch timing 阶段耗时，不增加消息内容。路由 systematic-debugging / verification-before-completion，沿用现有规格作小范围调整，无子 Agent。
- 工作流 40099241832：Xcode 设备 Release 编译及 207 项模拟器 XCTest 全部通过，112 Swift 文件语法检查通过。仅固定等待调整，未增加镜像实现的测试。Headroom 压缩云端日志节省 7,137 tokens（19.3%），原文保留。
- 桌面 E:/桌面/Lan-Agent-build46-unsigned.ipa，4,985,868 bytes；SHA256 d0c46aae0589e087349e78018d81d478ab64b7113405f124ae8f02a8a7d4d47d。包/Widget build、中文开关、ZIP、无模型 key 和桌面 SHA256 核对通过。build 45 保留回退。
- 证据 ../out/build46-watch-speed/{verification.json,baseline-timing.json,optimized-timing.json,xcode-build-and-tests.log}。这些是源代码固定等待变化，不是实机加速比例。未安装/发真实消息/刷固件；下一步 T009/T013 真机验收并按 watch timing 对比模型、任务、回报耗时。

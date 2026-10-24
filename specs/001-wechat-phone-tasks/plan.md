# 实施计划

基线：`b28465de9a480983eb9e3095b53fc16aecf4725e`，App build 44，工作树原本干净。
实际代码：`E:/AgentStorage/esp32/iphone-agent-build13`；不要误改旧的 `esp32-iphone-agent` 工作树。

- 在 `WatchSettings` 增加默认关闭的手机任务权限与纯函数资格判断，要求会话和发言人均完全匹配，且逐条检查本轮消息。
- 微信内任务保留原路由；跨 App 模式将授权消息原文交给同一个 `watchRun → AppModel.run → AgentLoop`。沿用隐私检查与任务步数设置。
- 在 `WatchView` 增加开关、使用说明及中文本地化。
- 用一个持久化的待回报项保留执行结果，发送失败仅重试回报；不实现额外任务队列、后台服务或新协议。守候单线程已经串行执行。
- 执行期间清除原会话的输入框坐标。回报强制通过查找原会话的完整发送路径；停止与权限撤销优先。
- 先用原有 API 的回归测试重现「仍限定在微信」；修复后跑同一工作流的设备 Release 编译与完整模拟器测试。Windows tree-sitter 只作为语法预检。
- 使用原有私有 GitHub 仓库的 `Unsigned IPA` 工作流。测试和构建证据、IPA、SHA256 存到 E 盘，桌面放最终可签名安装包。

路由：共享 skill-routing-reminder、direct-execution、systematic-debugging、spec-kit-orchestration、test-driven-development；ponytail 控制改动范围。Spec Kit 1.0.6 已在实际工作树初始化，Codex/Claude 事件均关闭，无社区扩展或运行钩子。未派子 Agent。

## build 46 响应速度调整（2026-10-24）

用户反馈慢。代码时序核对发现：完成任务后首次回报仍继承 6 秒画面冷却、回报成功后仍退避 20 秒，以及 2 秒守候轮询、1 秒任务完成轮询、后台启动仍等待 0.8 秒不可见动画。
采用小范围调度调整：首次回报立即进入既有发送路径；成功后冷却 6 秒、失败仍退避 20 秒；轮询改为 0.5 秒与 0.1 秒；已在后台时略过不可见出发动画。2 秒持续变化确认、5 秒检查限流、权限/停止/隐私/文字和发送核对均保留。仅记录阶段名和耗时用于分析，不加入消息正文。
使用 systematic-debugging 定位及 verification-before-completion 验证；属于低影响固定等待调整，不增加镜像实现的测试，运行现有完整 XCTest。源代码时序变化不能冒充真机耗时测量。

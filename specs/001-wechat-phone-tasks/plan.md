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

## build 47：按日志 21 修复实际瓶颈

本地分析 59 个 trace 中最后 14 个运行，调用时间、动作与截图交叉核对，报告保存在 ../out/logs21-performance/诊断报告.md。只将无消息正文的结果与设计写入仓库；原始日志/截图不上传。

- 后台钩子只在未成功解码新的可用帧时重建 GOP。比较真实 publish 时间 updated 与后台通知时间，同时沿用完整 usable 检查。旧静止帧或不可用帧仍恢复；其他故障恢复调用默认仍强制刷新。为旧行为提取策略后，RED 工作流 40102025495 的 210 项仅新健康解码案例失败。
- 多会话巡查使用现有 openTask 作为固定计划，省掉每轮初次 planner 调用；actor 仍看实际截图选择与核对，异常 replanning 保留。
- 启动时若 leaveApp 前已在 background，未执行离开动作，不等待不存在的新 Home 画面；继续 currentFrame 与 requireFrame(nil) 核验。前台离开、非 background 状态以及动作后新鲜度校验不变。
- 保留 stale plan 保护：日志中确有文件预览、控制中心和键盘/启动变化，不能把这些都算作误判。加入 decoder 决策及重建耗时记录，以新版真机日志验证实际省时。

## build 48：日志 22 的导航回归

build 47 将多会话原始目标直接作为固定计划，actor 进入目标会话后仍返回列表，未读红点被消耗后返回空结果，导致没有 read/decide。修复保留固定计划省去 planner，但改成先判断当前状态的分支步骤。导航专用 frameCompletion 在原有 gate、连接恢复及 requireFrame 后，用本机 OCR 读取顶部标题；仅完整且唯一匹配配置会话时结束导航，不能输入或发送。随后 readChat 独立核对真实微信会话和完整标题，失配不消费消息。普通任务与发送每次 run 都清除该回调。未识别、截断或歧义标题继续原 actor；不使用模糊前缀猜测。保留画面变化、文字验证、发出检查与防循环保护。

日志原文、截图与诊断数据只保存本机 out/logs22-diagnosis，不进仓库。路由沿用 systematic-debugging、TDD、verification-before-completion；不需要新增平台技能。

补充：多会话读取完成后继续本轮未读巡查，直到列表确认没有目标未读才进入等待；避免当前会话处理完就进入冷却，使其他已有未读等到下个定时周期。待回报仍优先，不重新执行任务。

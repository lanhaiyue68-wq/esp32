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


## build49：当前画面直接执行与条件等待（2026-10-25）

采用对照 Phone Agent 得出的两条适用原则：
- 已授权的微信手机任务以当前截图和原始完整目标直接调用 actor；固定导航／发送和普通任务仍保留既有起始策略。directStart 每次 run 显式赋值／清除。出现错误、停滞或 replan 仍调用 planner，所有动作继续走原 step、gate、stale、输入与目标校验。
- VideoFeed 复用完整 usable(after:) 条件做有界轮询，接受新的可解码画面，或 boundary 后 heartbeat 证明已解码的静止帧仍为 board 最新。不要等待不存在的变化帧直到 proof 过期。settled、帧时间／latest_ms／断链判断、恢复与快照回退均保留，取消时不启动下一次恢复。

Xcode26.6／现有iOS18+构建暂不引入要求iOS27的ScreenCaptureKit，不改固件／网络／配对。先以真实VideoFeed及合成H264做RED，再跑最终设备编译和完整XCTest。只将代码和无私有正文的文档推到private仓库。真实速度与可靠度由后续真机日志验收。


## build50：日志23的已处理会话返回边界
多会话读取与发送之后先排队一个独立返回阶段；完整新鲜标题提供原生返回按钮位置，列表标题和四个底部标签证明返回成功。最多4步模型导航为本机识别不足的恢复，模型done不代替最终列表证据。pending返回优先于读消息、发送和任务；返回失败20秒退避，四次失败停止，不重做已经发出的消息或完成的任务。单会话留在聊天页。最终源码cd4acaf，GREEN40112899851设备Release和231项XCTest通过；真实手机验收待日志。


### build51 review refinement
WatchListReturn改arrived/deferred/failed，仅真失败累加；列表要求标题和至少三个正确列tab，容忍漏认一个；WatchMode在模型失败/坏格式时回滚history并fail check，明确有效空回复仍正常记录。保留50版发送/返回分离、49提速和48先读消息顺序。
No architecture or permission expansion. RED238/5 and RED241/7; final Release and241/0 at f9d3a68. Physical-device acceptance remains T009.


### build52 bounded local navigation trial
新增WatchChatOpen：仅“仅指定会话”且名单只有1项，完整唯一名称+较小消息预览+已验证微信列表时点一次；必须动作后新鲜帧匹配目标标题，才交原readChat独立确认/读取。名称截断、重名、未知布局回原导航；多会话未读选择原样。点后错误/过期目的地停止本轮，不再点击/读/发送；前景暂停不累计检查失败。
Retains prior model navigation, independent model message read, privacy/permission/stop/send-dedup checks. No Android APK code or system permission integration. Validation: RED254/15 assertion failures, GREEN254/0 at551ef25. Keep desktop51 and independent verified backup as explicitly pinned rollback baseline. Physical-device performance remains T009.

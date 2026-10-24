# 微信手机任务入口实施清单

- [x] T001 定位指定 Claude 任务及实际 build 44 工作树，保存基线与需求。
- [x] T002 私有分支回归测试已出现预期失败：云端 203 项中仅新增项失败，原有 202 项通过。
- [x] T003 默认关闭的权限开关、严格资格判断、原文任务传递与执行路径。
- [x] T004 返回原会话、清除旧坐标、保存未发送结果与停止处理。
- [x] T005 设置界面、中文本地化及使用文档。
- [x] T006 五项回归测试通过：资格判断、群触发与原文顺序、待回报保存/清除、停止和撤权拦截、原始失败案例。
- [x] T007 工作流 40051367358：Xcode 设备 Release 编译成功，207 项 XCTest 全过；IPA build 45 和 SHA256 已核对。
- [x] T008 按 spec/plan/tasks 做收敛检查，更新 progress/tasks/bugs/HANDOFF，桌面交付 IPA、校验和及说明。代码无剩余差距，真机验收仍单独待办。
- [ ] T009 真机：开启守候，从另一台已授权设备发送备忘录任务，检查动作、回报、停止及回报失败恢复。（需要手机验收，不自动执行真实消息）

## build 46 提速

- [x] T010 核对调用链，保存 build 45 固定等待基线与 build 46 调度差异。
- [x] T011 减少首次回报冷却、成功后退避、轮询和后台动画等待；保留原校验并加分段耗时。
- [x] T012 工作流 40099241832：build 46 Xcode 设备编译、207 项回归全部通过，IPA 完整性和 SHA256 核对后桌面交付。
- [ ] T013 真机比较同一指令的接收、判断、任务和回报耗时；与 T009 合并验收。

## build 47 日志驱动提速

- [x] T014 本地解析日志 21、Headroom 压缩并核对实际截图，分清 trace 跨度与 done 耗时。
- [x] T015 RED 工作流 40102025495：210 项中仅新健康解码案例失败；旧静止/失效解码案例及原有 207 项通过。
- [x] T016 条件化后台 GOP 恢复、多会话固定计划和后台启动画面验证优化。
- [x] T017 工作流 40102487275：Xcode 设备编译、完整 210 项 XCTest 全过，IPA 校验与桌面交付完成。
- [ ] T018 新版真机同任务耗时对比及原有端到端验收。

## build 48 日志 22 回归修复

- [x] T019 分析 build 47 六轮巡查：26 次 actor 调用、五次空会话完成、一次来回切页失败，期间没有消息读取。
- [x] T020 增加五项导航/读取回归：已打开会话不返回、未识别沿用 actor、仅标题可完成、精确/歧义匹配、读取目标和范围核验；RED 工作流 40104949418：215项测试，只有新增4项失败（9条断言），原210项全部通过。
- [x] T021 状态分支计划、本机标题完成、读取目标独立确认和普通任务清除回调。
- [x] T022 工作流40105825214：设备Release编译、215项XCTest全部通过；包48版本/ZIP/SHA256核对，桌面交付后回收47的三份交付文件。
- [ ] T023 真机核对消息进入 read/decide、任务回报及同任务耗时，不以单元测试换算成功率。


## build49 速度路径（2026-10-25）
- [x] T019：RED 40108170022：原215项通过，新8项中4项失败，重现额外planner／等待与静止帧快照失败。
- [x] T020：实现基于完整画面证据的及时返回、手机任务directStart及planner恢复；新增8项行为测试。
- [x] T021：最终设备Release编译、完整223项XCTest、IPA版本／校验／桌面交付及回收48。
- [ ] T022：真机同任务对比模型请求、动作后帧等待、整体执行和回报耗时；不由模拟器推导加速百分比。


## build50 日志23返回修复
- [x] B50-01：定位18轮/91,732ms重复读取与Return发送跳过返回。
- [x] B50-02：8项返回回归覆盖列表证据、标题/按钮、已在列表、返回失败pending、模型done不足、画面/foreground门禁、停止边界。
- [x] B50-03：独立发送与优先pending返回阶段，统一多会话/回报/ChatTool路径；保留单会话与既有保护。
- [x] B50-04：GREEN40112899851设备Release、231项XCTest、包50校验、桌面交付和回收49。
- [ ] B50-05：真机多会话返回、没有重复读取/重发及整体速度验收。


### build51 recheck
- [x] Independently verify50 artifact/source correspondence; add10 regressions and reproduce7 failures.
- [x] Fix deferred returns, positioned/tolerant list proof and failed-decision history rollback.
- [x] Release +241/0 at f9d3a68; verify51 artifact and recycle desktop50.
- [ ] T009 physical-device double-chat return, foreground-resume, failed-decision retry and total latency acceptance remains open.


### build52 trial
- [x] Preserve verified desktop51, independent backup, source snapshot, rollback instructions and protected manifest.
- [x] Add13 tests (exact/duplicate/truncated/preview/scope, one-tap/freshness/pause, actual synthetic Vision); RED before implementation.
- [x] Implement single-target-only local open, exact post-action verification, original navigator fallback and foreground deferral.
- [x] Release +254/0 at551ef25; validate52 IPA and unchanged51 rollback baseline.
- [ ] T009 physical-phone comparison and real latency/accuracy acceptance; no global speed claim.

# 任务状态

- [x] 找到指定 Claude 任务、原始消息、build 44 工作树和可复用执行链。
- [x] 真实回归测试重现入口仍限定在微信；保留原有功能测试基线。
- [x] 实现 build 45 手机任务入口及仅重试结果的回报路径；添加五项针对性回归。
- [x] 本地 112 个 Swift 文件语法检查及资源格式检查通过。
- [x] 云端 Xcode 设备 Release 编译及 207 项 XCTest 全绿；新增五项回归全过。
- [x] 下载并核验 build 45 IPA，桌面交付、完成收敛和交接记录。
- [ ] 真机：跨 App 任务、回原会话、停止、发送失败恢复。此项需要手机验收，不能用模拟器单测冒充。


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

## 2026-10-25 日志 22 / build 48
- [x] 确认47导航回归与慢点，原始证据留本机。
- [x] 五项回归及本地114文件语法检查。
- [ ] RED/GREEN云端编译测试、48交付校验、桌面回收47。
- [ ] 真机读取/判断/执行/回报与耗时复核。

- [x] build48：RED40104949418确认失败、GREEN40105825214设备编译与215项测试成功；IPA和桌面副本SHA/版本已核对，47三份桌面交付文件已回收。
- [ ] build48真机用新消息验证读取、判断、动作和结果回报，提供日志再统计同任务耗时。


## 2026-10-25 影片比較
- [x] 檢視手機控制段並對照公開 Phone Agent 源碼。
- [x] 區分直接觀察、架構推論與未驗證的模型／成功率。
- [ ] 若進入下一輪速度開發：先用相同任務分段量測模型、輸入、新畫面等待，再核對 iOS27 原生擷取可行性。此為調查建議，本次未啟動架構遷移。


## 2026-10-25 build49
- [x] 当前画面条件满足即继续，手机任务省去初始planner；保留所有动作与会话保护。
- [x] RED证实问题，GREEN设备编译和223项XCTest通过，IPA校验／桌面交付／回收48完成。
- [ ] 真机按原BundleID覆盖签名安装，重启守候，使用新发的相同任务比较watch timing／frame wait／actor请求及总耗时。
- [ ] iOS27原生擷取另行评估系统与构建条件；本轮未实现。


## 2026-10-25 build50
- [x] 日志23定位Return发送提前完成、边缘滑动未验证和18轮重复读取。
- [x] 本机标题定位返回按钮、列表双重证据、导航恢复与停止边界，新增8项回归。
- [x] 分离发送与返回；pending导航优先，失败只恢复导航；保留48读取顺序和49提速。
- [x] 最终设备Release和全部231项XCTest、117Swift语法及包50校验通过；桌面交付后回收49三件套。
- [ ] 真机覆盖签名安装并重启守候，验证两个会话轮巡、无重复读取/重发、返回失败提示及同任务耗时。


## build51 / 50版交付后复查修复 — 2026-10-25
- [x] 重新核对50包/源码；补10测试，旧逻辑重现7失败。
- [x] 修复暂停、OCR位置/容错、决策失败历史回滚。
- [x] Release与241/0通过，核对51并回收桌面50。
- [ ] T009仍待真机：双会话新消息处理后返回、前景暂停恢复、模型失败重试、无重复发送及总耗时。


## APK性能参考分析 — 2026-10-25
- [x] 本地分析两APK的状态获取、操作、脚本、模型和等待，完成证据对照与适配建议。
- [ ] 若后续实施：先取得51版真机分段耗时，再按瓶颈扩展本机已验证操作/稳定短流程。当前只分析，未启动52开发。


## build52 / 保留51回退的本机单会话导航试验 — 2026-10-25
- [x] 核对51、桌面保留、独立备份并标记不可自动清理。
- [x] 新13项TDD回归，旧禁用快路先失败；实现保守单会话本机导航和原流程回退。
- [x] Release和254/0，核对52安装包及保留51；源代码/说明/回退指引已交付。
- [ ] T009真机对照：仅指定一个会话，在列表启动，核对准确打开/暂停恢复/不重复发送与总耗时。


## 2026-10-25 build58

- [x] 同次執行不重發已發文字；撞邊判斷放寬。296 測試通過。
- [ ] 真機：重跑主人任務確認只發一次並回報。

## 2026-10-25 build57

- [x] 無鍵盤拒絕輸入＋下次精準點；校準濾掉邊緣點、加底部探測點。294 測試通過。
- [ ] 真機：重新校準看 ±%，重跑主人任務。

## 2026-10-25 build56

- [x] 多會話本機打開、全會話本機發送、每階段模型次數。292 測試通過。
- [ ] 真機：看 watch timing 與 model call(s)，確認速度與準確度。

## 2026-10-25 build55

- [x] 口令＋私聊才有手機任務；發送前核對會話標題；同次執行不重複輸入。285 測試通過。
- [ ] 真機：設口令、私聊下任務、確認回報回到原會話。
- [ ] 固定流程腳本化（OCR 定位＋新幀驗證）與每步耗時統計。

## 2026-10-25 build54

- [x] 日誌25 根因：校準 span 失真導致點擊落點錯（點成 Watch）；Pointer.aim 改閉環、貼邊重量、stale 標記，279 測試通過。
- [ ] 真機：覆蓋安裝54、重新校準、守候能點中微信。

## 2026-10-25 build53
- [x] 修复首次守候、旧启动作废与标签输出解析。
- [x] 新增诊断容量/时间/次数限制、设置页清理与最近日志导出。
- [x] 按用户授权创建ChenQian-hub私人仓库并完成协作者接受、源码推送和编译恢复。
- [x] 设备Release、274XCTest、IPA校验、桌面交付与51回退保护。
- [ ] 真机确认首次守候出发、停止不续跑、清理保留配置及实际速度。
- [ ] 逐步对照主画面误认白板的点击落点与模型判断。


## 2026-10-26 — logs(32) repair / build71

- [x] Diagnose task traces and identify wrong-app paste, lost retry goal, Home loop and duplicate sends.
- [x] Implement targeted fixes and regression tests.
- [x] Compile unsigned Release, pass all 340 XCTest, validate IPA version/CRC/SHA256, and place build71 on desktop.
- [ ] Sign/install build71 through the existing user tool and physically retest Claude/「重新去做」/single-send behavior.


## 2026-10-26 — logs33 / build72

- [x] Trace file-name/history drift and mixed old-file/passcode command downgrade.
- [x] Implement per-message task routing, attachment normalization/reply suppression, and paste comparison correction.
- [x] Prove new cases fail before fixes; pass full 348 XCTest and unsigned device build; verify/copy build72 IPA.
- [ ] Sign/install on the iPhone and retest old files plus a new authenticated Claude command, no irrelevant file reply, and single-send behavior.


## 2026-10-26 — logs34 / build73
- [x] 对照 Claude 输入、清空、粘贴切换和回微信回报的日志。
- [x] 排除键盘候选计数、取消两个输入路径的破坏性回退并保留视觉交接。
- [x] 验证候选词/输入框真实 Vision OCR、已输入内容交接发送、明确错字修正、未确认输入不重贴；359测试通过。
- [x] 校验 build73 IPA 并放桌面，保留旧版，更新 PR与交接。
- [ ] 使用原有签名方式安装后真机复测 Claude 你好：文字保留、只发一次、有结果后完成；需要粘贴时核查跨 App 画面。

## 2026-10-27 视频对照
- [x] 核对原视频、作者隧道评论与官方控制接口资料。
- [ ] 后续：建立同任务分阶段耗时基准，验证画面时效与中文输入通道；尚未实施。

## 2026-10-27 直接取屏方案
- [x] 评估iOS27 ScreenCaptureKit、现有ScreenSource接口与参考项目。
- [ ] 尚未实施：直接取屏跨App最小验证；通过后再增加高速/精准/自动策略。

## 2026-10-27 无线运行与token要求
- [x] 修正USB假设，明确全程无线与充电口保留；澄清每次回复6动作。
- [ ] 实施前核对板上实际无线控制固件与协议，再接入iOS27直接取屏。
- [ ] 分离本地采帧与云端请求；用相同任务对照调用数、token、耗时和成功率。

- [ ] 速度验收须使用相同任务、模型、网络和成功标准，对比旧链路/直接取屏的总时长、模型次数、帧年龄与成功率；历史失败过程不作成功速度基准。

- [ ] 日志35：补齐视频回传→组帧→解码边界证据与当前完整OS版本；处理后台首帧启动20+30秒重试造成的长等待。全程无线，保留新鲜度检查；实际恢复仍待真机验证。


## 2026-10-27 — build74 iOS27 direct capture preview

User-approved native whole-display preview completed; existing wireless controls and build73 input safeguards preserved. Skills: spec-kit-orchestration + test-driven-development + ponytail; review used scoped source inspection, Jev advisory scoring and CI. Spec/plan/tasks/quickstart/review: specs/002-ios27-direct-capture. Source8e8248645be1276daf5333b975c369225126a061; final CI40407538020 passed 8 policy + 368 simulator tests and device Release. Artifact E:/桌面/Lan-Agent-build74-unsigned.ipa, SHA256c1f1ee76575e01610e03f2e3bed9421ebfc5f4ab77e8018e9c9c79e548c2aaca. Inspected build74/SDK27.1/backgroundscreen-capture/linked framework/no signature/ZIP integrity. No new firmware, hardware, USB or cloud frame-streaming requirement. Device-only system consent/cross-app/background/cursor/gestures/input/CPU/thermal and matched speed comparison remain pending user-installed signed build plus exported logs. User asked storage: existing bounded app-owned diagnostic retention was verified and explained, no Photos writes introduced.


## 2026-10-27 logs36 / build75

- [x] Trace correct greeting, incorrect mouse correction, send guard and Chinese homophone to independent evidence.
- [x] Reproduce failures against old code before repair.
- [x] Implement transport checks, resilient keyboard recognition, exact text verification, long Chinese paste preference and bounded draft recovery.
- [ ] Complete final CI and review duplicate-send/false-completion boundaries.
- [ ] Inspect final unsigned build75 IPA, copy to desktop, report real-device validation limits.


## 2026-10-27 build75 scope extension
- [x] Create private compilation repository under user-designated account and accept main account Write invitation.
- [x] Implement generic exact text routing and inspectable real learning stores; expose Home/Settings entry, provenance, request counts and per-item controls.
- [x] Compile device Release for commit124bcb6 on new account.
- [ ] Confirm baseline RED evidence and fix remaining input boundary failures; run complete green simulator suite.
- [ ] Converge feature003, review, inspect and deliver final build75 IPA; physical phone validation remains external.

- [x] Finish build75 exact-SHA full CI on new private build repository, converge feature003, verify IPA build75/hash, refresh draft PR and deliver unsigned IPA to E:/桌面. No physical-phone validation claimed.

- [x] Clean old ESP32 Agent install/build outputs while retaining build75 and active source (500,557,380 bytes freed).


## 2026-10-27 logs37 / build76
- [x] Correlate version, HID commands, unchanged drafts and visible actual pointer endpoint.
- [x] Reproduce first-send, precision click and export failures before implementation.
- [ ] Verify real pixel probe endpoint regression, complete bounded repair, run full simulator/device CI.
- [ ] Verify final build76 IPA/hash, refresh PR, deliver and remove superseded/failed build outputs.

- [x] logs37/build76: complete first-send visual aim, post-probe endpoint check, strict click boundary, two-frame bounded unchanged-draft recovery and bounded-history export.
- [x] Confirm401+8 zero-failure tests, inspect final artifact, deliver build76, remove superseded/failed/duplicate packages.
- [ ] External acceptance: physical-phone arbitrary text/send task after signing build76; CI does not establish that result.


## logs38 repair
- [x] Inspect actual build76 phone trace and send frames; identify acknowledgement/execution coupling.
- [ ] Verify focused RED regressions, repair receipt and authenticated task gate, then full CI.
- [ ] Review and deliver build77; clean superseded packages only after verification.


## logs38 verification completed
- [x] Observe RED, implement independent authorized task gate and anchored send receipt, preserve cancellation/duplicate guards.
- [x] Release build +408 simulator +8 capture tests; verify build77 IPA and desktop hash, remove old install packages and temporary CI selector/branch.
- [ ] Physical iPhone verification after signed build77 installation (not available in this environment).


### 2026-10-27 logs39 checkpoint
logs39 pending: reproduce five failures; implement consistent calibration/runtime motion; multi-point <=1.5% acceptance; full build78 CI; verify IPA; replace desktop old package only after successful build.


### 2026-10-27 build78 implementation checkpoint
- Active goal: repair logs39 calibration >2% and native stop-sharing alert after top-left back taps.
- Source 6ea708b758758e5183dfa83a5f5b8732315a4c12. Build78 full CI 40441518572 running; device compile previously passed at 9751904, final adds homing consistency for gesture starts.
- Changed ProbeMap/ProbeMotion, Pointer provisional persistence/motion version, AutoCalibrator, TouchCalibration, WatchListReturn. No capture or firmware changes; wireless only.
- RED f011955 / 40439396466: all five regression tests failed, seven assertion failures. Final suite adds thirteen regression methods.
- Raw logs and frames remain outside Git: E:/AgentStorage/esp32/log39-inspection. Sanitised diagnosis: docs/logs39-pointer-calibration.md.
- Next: inspect full CI results, repair failures if any, verify IPA build/hash/arm64/ScreenCaptureKit, deliver desktop build78, delete superseded77 and temporary cloud test artifacts only after verified new package. Update PR1 and final docs. No physical phone verification available.


### 2026-10-27 build78 delivered
- Source 6ea708b758758e5183dfa83a5f5b8732315a4c12; CI 40441518572 passed Release build, 421 simulator tests (13 new regressions), 8 capture-policy tests, zero failures.
- Verified desktop E:/桌面/Lan-Agent-build78-unsigned.ipa, 5,267,769 bytes, SHA256 072d43b2f0756558fcc88173720fcc50d77d2c0a337cecf956a00bad5c1afd30. Build78/arm64/ScreenCaptureKit and ZIP integrity confirmed.
- Removed obsolete desktop77, duplicate downloaded78, and old cloud build/test artifacts after new package verification. Preserved source/Git and original diagnostic ZIPs.
- Fixed measured movement mapping, provisional multi-point calibration <=1.5%, legacy calibration migration, gesture homing consistency and middle-edge WeChat return. No USB/firmware/capture API changes.
- Remaining: actual phone installation/calibration/task validation; no physical phone attached. Do not claim real HID accuracy from simulator results.


## 2026-10-27 build79 / logs40 checkpoint
- Goal: fix repeated build78 calibration residual 2.1% without loosening accuracy.
- Evidence: v34 metrics curve=true rev20; identical move 140 265 differs by 5.1% in x. Matching firmware uses random Bezier paths even for axis-only move commands.
- Change cb6d2f2: query curve before mapped home, disable and require off acknowledgement; explicit unsupported-command only permits old straight firmware; invalidate old motionVersion1; 7 sampling + 4 fresh checks, optional bounded refinement.
- Validation: RED run40444842738 reproduced 7 failing tests / 10 assertions out of8. Final build79 Release and complete tests pending.
- Skills/routing: systematic-debugging + test-driven-development. Spec-kit triage resolves to bounded bug fix after logs40 identifies firmware mode, so no core model rewrite. Headroom processed log40 calibration evidence locally.
- Paths: ios/IPhoneAgent/Agent/ProbeMap.swift, Pointer.swift, App/TouchCalibration.swift, tools/pointer-motion-tests, docs/logs40-straight-motion.md. Raw evidence stays E:/AgentStorage/esp32/calibration78-inspection.
- Next: inspect CI, repair failures, verify IPA build/arch/hash, then replace78 and clean old outputs. No physical phone attached; no USB/firmware changes.

- build79 CI attempt1: Release + both policy suites passed. Simulator runner restarted during Logs36RegressionTests.testLongChineseReportUsesExactPasteBeforeHomophonePronePinyin; no assertion failure shown. Distinct passing tests: 422. Full job attempt2 restarted with identical cb6d2f2 source; package delivery remains blocked on successful validation, not user approval.

- build79 verified/delivered: CI40445212700 attempt2 all423 simulator +8 motion +8 capture tests passed; prior interrupted Chinese paste case passed9.938s. Source cb6d2f2. Desktop E:/桌面/Lan-Agent-build79-unsigned.ipa, 5269969 bytes, SHA256 8c3f2d71cea78493ed471ea473a3c95ad2a2fe9f2e1b2779edd1ca2abb22a016. ZIP/arm64/ScreenCaptureKit/build79/extension79 verified. Old78 + checksum and duplicate download removed after hash check. Raw logs retained outside Git. Physical iPhone landing accuracy still needs installed-device validation; no USB or firmware change. Permanent motion tests live in ipa.yml; temporary RED workflow removed.

- 2026-10-27 build80 in validation: user requires Bezier preserved; build79 persistent curve-off withdrawn. logs41 confirms repeated y=.09 -> .109 despite straight mode. Plateau midpoint pooling and invented zero-origin low inverse reproduced RED (run40450951228); fix retains measured flat intervals and low-end gain. All real scatter and 1.5% fresh-validation requirement retained; no firmware/USB/raw-log upload. Source6f213bd, CI40451309403 running; no package delivered yet.

- build80 complete: CI40451309403 attempt1 passed Release +423 simulator +12 Bezier/map +8 capture tests. Desktop E:/桌面/Lan-Agent-build80-unsigned.ipa (5269123 bytes), SHA256 c2795d45fbb81e1f6df82729e0340fc586573c600a36d886e4a772d72ddd1b76; ZIP/arm64/capture/build80/extension80 verified. Source6f213bd. Superseded79 desktop/cloud package and duplicate downloaded IPA removed after new hash check. Bezier restored for calibration/runtime; real landing accuracy still needs installed-phone confirmation. Key source ios/IPhoneAgent/Agent/ProbeMap.swift; record docs/logs41-bezier-calibration.md. No firmware/USB/raw-log upload.

- logs42 follow-up: build80 still fails eight fresh rounds; curve on confirmed. Identical150/150 varies X0.541–0.604; per-axis map cannot certify random/coupled motion. Reusing existing bounded visual aim for measured curved calibration/runtime; no curve/firmware change. RED source f9b616c; run40455498579 in new private caoshihui5211314-cloud/esp32-iphone-agent-build, main account invitation accepted. Production unchanged pending RED. Local evidence E:/AgentStorage/esp32/logs42-inspection; plan docs/logs42-feedback-positioning.md.


## 2026-10-27 logs42 / build81
- [x] Reproduce variable Bezier landings and unsafe clicks without feedback before modifying production.
- [x] Persist mandatory endpoint feedback, retain raw scatter, verify four real calibration clicks within1.5%.
- [x] Correct observed nudge displacement and preserve system border gestures without relaxing ordinary taps.
- [x] Migrate private build mirror, run full simulator/policy suites and Release build, verify/deliver build81.
- [x] Clean obsolete desktop/cloud IPA and temporary diagnostic artifacts after new package verification.
- [ ] Physical iPhone: install signed build81, recalibrate once, confirm real operation. No physical-device success claimed.
- [x] logs43: stop withholding unseen ordinary taps; plain calibration board for checks; deliver build82 (CI 40461232391).
- [x] logs44: calibration checks correct from real click landings; deliver build83 (CI 40463137744).
- [x] logs46: dark keyboard detection, edge swipe tolerance, bring-back tasks; deliver build84 (CI 42024739284).
- [x] build85: learned routes replay + lesson cleanup (CI 42032226698).
- [ ] Physical iPhone: install signed build85; run the same task twice (second run should log "route: replayed"); test dark-mode reply and the Claude bring-back task; send logs.
- [ ] Check why an unrelated lesson is applied to the WeChat watch task.
- [x] build86: paste hop return check (unread count, banner retry, app-order reset), stripped Release, iPhone only, unused images removed.
- [x] build87: keyboard 发送 tap → Return; ordinary taps without pointer search.
- [ ] User: senders whitelist must say 主人蓝海乐 (the private chat's name); switch the keyboard to 拼音-全键盘; install signed build94 and run phase A (keyboard ①②③ with the board attached; Plus sign-in, models, one ask); export logs (search "phase A", "keyboard bridge").
- Keep (user 2026-11-06): App Shortcuts/saved intents/demo recording, ChatTool + knowledge base, demo data, board Wi-Fi mirroring. Not used yet only because the core is still being stabilised; never remove them to slim the app.
- [x] build95 phase B: keyboard typing everywhere, `open APP` with learned places, screen text list for the model.
- [ ] User: phase B on the phone — open Claude, type 你好, send; the second time it must go straight to Claude without Search (if Claude is on a Home Screen page, not only in the dock).
- [x] build96: hold globe → pick Lan Agent in the keyboard menu; click again in place on the same spot.
- [ ] Device test build96 (Lan Agent via menu; does the menu stay after release; board Enter sends with our keyboard up; in-place repeat clicks).
- [ ] build97 candidates (user 11-08): nearby moves from the current pointer spot (keep Bezier, no corner every tap); WeChat only enters chats with a red unread number, never resumes an already-read chat or a saved old report; keyboard-switch method remembered (self-learning of fixed steps).

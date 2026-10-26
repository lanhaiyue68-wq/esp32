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

## 2026-10-25：build 47 多会话漏读与反复切页
症状：目标未读会话打开后又退出，返回 {"chat":""}；一轮29.6秒并失败 kept going back and forth between two screens。根因：把多会话原始目标直接作为固定计划，缺少“已到目标则完成”状态分支。修复：状态计划＋本机完整标题导航完成，仍必须独立读取确认会话；不删除防循环/失效画面保护。验证：五项新增回归及云端完整测试进行中；手机端修复效果待新版日志验证。

验证补充：上述47导航回归的build48修复在最终源码0f1315e、CI 40105825214通过215项XCTest与设备编译；已完成桌面交付。真机验证待办，不声称测得成功率或总提速比例。47已消耗未读的旧消息不自动补执行。


## 2026-10-25 速度調查補充（未新增產品修改）
- 影片快慢不能歸因於 ESP32 算力；公開對應架構縮短畫面傳輸鏈路，模型往返仍有成本。
- 本專案已知導航回歸由 build48 修復且離線測試通過，真機速度和可靠度尚待新版日誌。不得由 215 項測試或演示影片推導成功率百分比。
- 影片作者精確版本、模型和網路條件未確認；直接取畫面遷移尚未實作或驗證。


## 2026-10-25 build49：有效静止画面等待与多余初始规划
- RED真解码合成帧重现：动作后已收到有效heartbeat仍耗时1.838秒；currentFrame只等新pixels，确认信号过期后进入snap并报snapshot did not decode a new frame。
- 修复轮询时持续使用完整usable(after:)条件，确认即可继续，画面落后／证据早于动作／broken仍拒绝。手机任务直接调用actor以省去额外初始planner，恢复路径保留。
- 最终设备编译和223项XCTest通过，包含48版导航回归等既有215项。测试不代表真机速度或成功率百分比；需49日志确认。原生iOS27擷取未接入，现有模型延迟／镜像带宽仍会影响总耗时。


## 2026-10-25 build50：聊天页退不回列表／重复耗时
- 根因：发送checked paste+Return在AgentLoop中直接done，发送计划的返回没有执行；无须回复时直接goBack但吞掉错误并忽略屏幕，失败仍立即继续扫同一会话。日志23重现18次/约92秒循环，读消息占约61秒。
- 修复：发送只发送，独立pending返回以本机完整标题定位左上返回按钮，核对列表标题和四底部标签；单次本机动作不成才做有界模型导航；返回未确认不再读/发/执行任务，退避20秒、四次失败停止。
- 首轮新增代码的MainActor默认参数编译错误已修；最终设备编译、231项XCTest全通过（保留原223项），117Swift语法与交付包50核对通过。原始日志只本机；真实手机行为和整体速度待新版日志验收，不能用测试换算成功率。


## build51 / 50版交付后复查修复 — 2026-10-25
- 已修：前景/操作中暂停误计导航失败；列表OCR要求四标签过严且未验横向列；既存模型决策超时/坏JSON提前消耗消息历史。
- WatchListReturn改arrived/deferred/failed，仅真失败累加；列表要求标题和至少三个正确列tab，容忍漏认一个；WatchMode在模型失败/坏格式时回滚history并fail check，明确有效空回复仍正常记录。保留50版发送/返回分离、49提速和48先读消息顺序。
- RED1 40113904071：238项5失败，原231通过；RED2 40114372304：241项7失败（加模型超时/坏格式2）。新增10测试包含真实iOS Vision读取合成画面；GREEN1 40114949695编译检出缺await，已修复。
- 设备Release与241项XCTest全通过，GREEN40115040451，源码f9d3a6801fae7f310d9a4c0a4bf94d1f6254c120；118Swift语法、13JSON、4plist/entitlements和diff通过。App/Widget51、ZIP、minimumOS18、无模型预设、新二进制路径和桌面hash均核对。
- 未操作真机微信；实际返回、暂停恢复、模型失败重试及整体速度待真机日志验收，不能给出实际容错率/提速百分比。未改固件、网络、账号、模型或签名。


## APK性能分析限制 — 2026-10-25
- 无新增App改动；静态分析不构成性能测量。肉包/尖椒存在部分反编译失败，关键机制已核对，不对未恢复路径或云端行为作确定性结论。51真机验收仍待日志。报告../out/apk-performance-review-20261025/APK性能机制对照.md。


## build52 / 保留51回退的本机单会话导航试验 — 2026-10-25
- 改善候选：51在单会话列表页先试readChat，随后导航再读取，存在可避免模型调用；52确认列表行后直接点一次并核对目标。实际收益待真机日志。
- 防护：预览提名、同名/截断拒绝快路；过期/错误目的地不能继续读/发送；前景暂停不记检查失败。
- RED40129055561：254项中15个预期断言失败，均为新快路测试，原241通过。GREEN40129446177：设备Release与254项XCTest全部通过，源码551ef25368e7de76095914abd41089ed3a5305bc；含新增13项和真实Vision读取合成列表画面。120Swift语法、13JSON、4plist/entitlements、diff、App/Widget52、ZIP、minimumOS18、空模型预设及桌面hash核对通过。
- 本轮没有改固件、网络、模型、账号权限或签名。没有真机测速，不能承诺全任务提速比例。新增快路主要省单一目标从列表进入时的试读/导航调用；51原有已在单一聊天直接读取的行为保留，不把它当新提升。多会话及复杂跨App任务本版没有新增快路。


## 2026-10-25 build58

- 日誌28：主人任務重複發送「你好」；角落小偏差誤標校準失效。已修，待真機確認。

## 2026-10-25 build57

- 日誌27：輸入框點偏、無鍵盤仍輸入、校準學了邊緣探測點（x ±4%）。已修，待真機確認。

## 2026-10-25 build56

- 多會話打開與發送都靠 agent run（慢）；已改本機 OCR＋紅點＋標題核對。限制：同名會話、預覽太短、紅色頭像可能誤判（誤判只多讀一次）。

## 2026-10-25 build55

- 日誌26：重複發送、回報發錯會話、暱稱可冒充主人。已修（build55），待真機確認。

## 2026-10-25 build54

- 日誌25：微信座標正確但落點錯；saved span 494x1110 vs 實際約 445x620，單次修正從角落跳到 Watch。已修（263999a），待真機確認。

## 2026-10-25 build53
- 已修复：52首次守候被前景暂停、停止后旧启动仍继续、明确THINK/DO标签同一行反复解析失败、截图/录影/历史执行及导出无限累积；新增20项测试，GREEN274项0失败。
- 已修复本轮编译错误：AboutView不能直接修改AppModel.log(private(set))，通过AppModel.clearLog()清空。
- 构建环境：旧仓库付款/额度阻止已记录；用户授权的新私人仓库运行成功。
- 未解决/需真机：模型将主画面误认白板画布；未验证实际点击落点、完整任务正确性或速度。51保护保留，53为测试版。


## 2026-10-26 — logs(32) / build71

Fixed in source (400d296): clipboard fallback hardcoded WeChat; OCR-joined QWERTY labels not recognized; bare retry「重新去做」lost original goal; planner records hid repeated unchanged gestures; automatic done after unverified send; failed send gestures recorded as sent. 340 XCTest pass and unsigned device build succeeds.

Known verification gap: no physical iPhone install/test yet. Clipboard restore requires matching fresh readable source content and layout; if the screen changes or cannot be verified it deliberately stops without pasting. No claim of universal task success.


## 2026-10-26 — logs33 / build72

Fixed in source d8555a1: an entire due-message batch required owner proof, so unverified old files blocked an individually valid task. Bare filename/[文件] OCR differences made historical cards look new; file-only cards triggered irrelevant replies. Acknowledgements now reference the selected command.

Build71 regression addressed: paste fingerprint included the input field, so transient Pinyin/clearing state could reject the same conversation. Fresh source capture and comparison above the input field pass a targeted regression. Exact internal source frames are absent from logs33, so device confirmation is still required; wrong-app rejection remains. 348 XCTest and device build pass.

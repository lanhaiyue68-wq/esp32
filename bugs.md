# 问题与验证

## 2026-11-14 build 132 回歸問題（133 已改，未編譯）

c3 京東沒裝，連喊失敗用光額度、第 16–20 項沒做（A1）；c2 沒鍵盤打「首尔」被記成已打、重打被擋（A2）；c3 美團加號不計次、一份加到 10 件（A3）；g4、c1「未完整读取／未确认」沒被退回（A4）；g5、g7 游標被讀成待收貨角標（A5）；c3 星期幾算錯（A6）。明細 docs/build133-summary.md。

## 2026-11-13 build 131 回歸問題（132 已改，未 commit）

Codex 兩帳號都不能用時，豆包規劃的最後一段 done 只交一項（V）；帳號 1「模型不支援」每幾分鐘重試、帳號 2 到頂固定休息 30 分鐘不看 resets_at（W）；重讀主畫面先清空位置、過熱讀到 0 頁後全部走搜尋且 3 天不重讀（J2）；使用者測試中開 Lan Agent，0.5 秒前剛有動作被當成自己開的、連按兩次回主畫面後被停（X）；共享螢幕時每張畫面都讓整頁重畫，黃色按鈕按了沒反應（Y，使用者回報）；群裡舊訊息讓模型以為發過（N2）。明細 docs/build132-summary.md。

## 2026-11-13 build 128 兩輪回歸問題（129 已改，未編譯）

完成檢查拿本輪自己發的訊息推翻「最新三條」（3 次）；微信聊天一開停在舊位置讀錯最新三條；外賣最便宜的一份是加購品就判做不到（2 次）；購物車跨輪累加被當成多加而去減數量；Safari 搜尋後舊頁還沒換就讀結果；備忘錄寫完上下來回捲 15 次；右欄圖示在 App 重開後漏點（右邊框修正值從 0 學起）。

## 2026-11-10 build 113 第二輪問題（115 已改，未編譯）

沿用記下的路線換群時發錯聊天（路線沒有「點進哪個群」這步）；邊緣滑動在動畫背景頁面不捲動卻被當成有變化；完成檢查只看最後 40 筆而漏掉開 App 紀錄；一次回覆重複開同一 App。iPhone 計算機不吃 HID 鍵盤輸入（實測）。

## 2026-11-10 build 112 真機問題（113 已修，待真機驗證）

自動點取消誤判：點擊後 0.2 到 0.4 秒內還有最後一張畫面（Pointer.answerIfAsked）。從角落到右側目標中位數短少 0.07（Pointer.beyondReach）。輸入後無效位置標記不解除，連續被拒絕 48 次（AgentLoop.step）。未修：豆包在設定走錯路、點 Dock 圖示沒反應、中文輸入切換 App 迷路後停下來等人、手機發熱、系統寫入量偏高。

## 2026-11-09 build 111 真機問題（112 已修，待真機驗證）

指針修正撞到上緣後原路退回，多走 160 單位，之後每次跳點都偏（Pointer.look）。頂部細長目標跳點常不準（Pointer.tapNow）。點到左上紅色時鐘會跳出停止共享視窗，畫面全停且看不到視窗（Pointer.answerIfAsked）。完成檢查不知道日期、看不到點擊，誤退正確答案（AgentLoop.wrongClaim）。未修：豆包給錯計算機座標、點錯頻道後不一定退回、手機發熱。

## 2026-11-09 build 110 真機問題（未修）

Codex 逾時後默默換豆包且每個任務都卡 76 秒（PlusChat.swift:40、ChatGPTPlus.swift:198）；假完成 5 題（e02、f09、f12、f13、f16）；滑動會變點擊（原因未查清，安全問題）；滑動起點容差過嚴，連 3 次偏離就中止（Pointer.swift:15）；擷取重開反而弄丟共享；繞圈保險誤殺。證據與修法：docs/stress-2026-11-09-build110-report.md。

## 2026-11-09 iOS 擷取停住，App 仍顯示共享中

現象：07:23 起 frame_age 一直增加，所有任務啟動時「直接取屏尚未就绪」。根因：系統 SCStream 不再送畫面也不報錯（replayd Health：screenframeCount=0，_screenTimeSeconds 不動）。修法（build110，未上真機）：等畫面時 3 秒什麼事件都沒有，就用已同意的 filter 重開一條串流（VideoFeed.restartCapture、NativeScreenCapture.restart），15 秒最多一次。其餘 14 類原因見 docs/stress-2026-11-09-report.md。

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


## 2026-10-26 — logs34：正确输入被自动删除并改用粘贴（build73修复）
- 根因：旧 shows 把候选词和输入框一起计数。候选你好→输入框你好且候选改变时，前后同为1，被判输入失败；typedQuickly 和 quickSend 自动 Cmd+A/Backspace 后粘贴，未确认粘贴也会被删掉重打。
- 日志：14:05:08Z拼音，14:05:11Z清空，14:05:31Z粘贴目标内容不匹配后paused；未执行发送。原始内部源/返回画面没导出，无法从这份附件确定返回错App还是同App画面/OCR变化。
- 修复：键盘以上核验完整文字；识别不确定时保留输入、继续视觉核查，拒绝盲目重打，明确修正后恢复；快速发送保留输入交接。不确定不再自动清空、重贴或将其计为拼音失败。
- RED357测试12失败→最终359测试0失败，unsigned设备版编译成功。补粘贴源/返回本机诊断和具体失败回报；仍保持目标不明停止输入。真机导航、候选和发送仍需设备验证。

## 2026-10-27 性能分析补充
日志34的75.743秒/13次actor调用属于单次失败样本；视频不足以证明模型更强或量化速度倍数。build73处理误删和输入保留，画面延迟及整体执行效率仍需实机验证。详见视频对照报告。

## 2026-10-27 可行性边界
用户当前为iOS27，不能再根据旧日志26.7.1将其判为系统不支持。直接取屏有助于移除视频绕行，但中文输入、任务完成判定和模型耗时仍需单独处理。当前6动作计划遇tap会重新取景，不能为提速全局取消。

## 2026-10-27 硬件推断纠正
此前根据检出源码USBHID示例断言用户实际USB连接，已由用户否定。实机无线，禁止以USB作为运行前提；实际固件版本/协议待核对。修正docs/ios27-capture-feasibility-2026-10-27.md，未对尚未验证的无线适配或token节省比例作完成声明。

速度统计注意：metrics.steps是累计数据，本轮用相邻导出共同前缀一致性检查隔离新增13步；不能将此前任务计时重复算入当前过程，也不能将页面稳定等待和暂停等待全部当成传输耗时。

日志35新增：启动前台可通过，退后台后画面落后板约67.583秒，snap传输失败/超时，0模型调用。错误文案称无法解码但decode_errors为0，不能以此认定iOS27不支持H264。旧MetricKit报告不是本次证据。未修复，禁止宣称73已通过任务验收。


## 2026-10-27 — build74 iOS27 direct capture preview

User-approved native whole-display preview completed; existing wireless controls and build73 input safeguards preserved. Skills: spec-kit-orchestration + test-driven-development + ponytail; review used scoped source inspection, Jev advisory scoring and CI. Spec/plan/tasks/quickstart/review: specs/002-ios27-direct-capture. Source8e8248645be1276daf5333b975c369225126a061; final CI40407538020 passed 8 policy + 368 simulator tests and device Release. Artifact E:/桌面/Lan-Agent-build74-unsigned.ipa, SHA256c1f1ee76575e01610e03f2e3bed9421ebfc5f4ab77e8018e9c9c79e548c2aaca. Inspected build74/SDK27.1/backgroundscreen-capture/linked framework/no signature/ZIP integrity. No new firmware, hardware, USB or cloud frame-streaming requirement. Device-only system consent/cross-app/background/cursor/gestures/input/CPU/thermal and matched speed comparison remain pending user-installed signed build plus exported logs. User asked storage: existing bounded app-owned diagnostic retention was verified and explained, no Photos writes introduced.


## 2026-10-27 logs36: confirmed bugs, repair under validation

- Mouse finder accepts a blinking insertion caret as a nudge, causing a large wrong correction and typing p instead of sending. Reproduced caret coordinate is (0.1683, 0.4840), closely matching the observed false mouse location.
- A successfully acknowledged click is mistaken for successful sending; corrections are blocked even with the same corrupted draft visible. Recovery is now limited to positive draft-corruption evidence and a bounded number of attempts.
- Prefix matching wrongly verifies 你好p as 你好; IME first candidates turn long report prefixes into homophones. Full-text checks and exact clipboard preference address these separately.
- Missing OCR keys hide a visible keyboard and contaminate text counts with suggestions. Ordered-key recognition now tolerates omissions.
- Final CI and phone validation are pending; details in docs/logs36-input-send-review.md.


## 2026-10-27 build75 additional findings
- Ordinary tasks bypassed exact text routing because fastText defaulted false. Multiline code and short unsupported scripts now enter the common paste path. JSON quoting preserves code text that the old line protocol truncated/stripped.
- Existing learning was real but hidden; added observable provenance, use counts, eligibility/review status and bounded clear/delete/disable protection. Legacy lesson JSON arrays still decode.
- Remaining regression checks include punctuation/operator preservation and stopping before keyboard Enter/Tab fallback when exact paste is unavailable. Pending simulator outcomes; no claim of physical phone accuracy.

- Build75 boundary fixes: retain punctuation/operators when verifying OCR text; refuse multiline/unsupported keyboard fallback when exact paste fails. Device build passed; full simulator result pending a98364c. The temporary test-only inaccessible task setter was corrected before delivery.

- Build75 final: logs36 and shared text/learning regressions pass with full CI (393 simulator + 8 capture tests). No remaining failure observed in automated checks. Actual iPhone input/tapping and app-specific behavior remain unverified. Old build outputs cleaned at user's request; latest build75 re-hashed afterward.


## 2026-10-27 logs37: confirmed defects under repair
- First send tap takes the open-loop path; acknowledged HID delivery is mistaken for sending. A complete unchanged draft cannot recover and expires in read-only verification.
- Precision aiming falls through to click when no pointer is found, a correction loses it, or corrections do not converge. RED regression confirms all three.
- Five internal report/navigation runs hide owner task frames from export. Retain the existing bounded run history without increasing local or export byte limits.
- Physical Claude outcome is not reconstructible because its frames are absent. Do not claim this export proves the exact Claude landing or a completed real-device repair.

- logs37/build76 code defects closed by sourcef9531e9 and passing CI1926117: open-loop first send, unverified precision-click fallthrough, wrong post-probe position, unchanged-draft lock, missing task export window.401+8 tests pass. Actual Claude outcome in logs37 is still unknown because its frames were missing; build76 phone behavior remains for external acceptance.


## logs38 confirmed regression
- A visible new acknowledgement is rejected by the actor; WatchMode requires sent=true and discards the authorized owner task. Fix independent receipt verification and remove acknowledgement as authorization prerequisite. Pointer withholding occurred once but second verified send succeeded; do not conflate it with root execution failure.


## logs38 repair validated in CI
- Fixed lost owner task after a false acknowledgement failure; confirmed receipts complete before the actor can retype. Full-reply anchor tests reject stale/missing request, wrong operators and same-prefix messages. All408+8 automated tests pass at480db61. Phone behavior remains unverified; do not equate simulator/CI success with physical completion.


### 2026-10-27 logs39 checkpoint
logs39 confirmed: maxCheckError=5%; applyProbe saved before verification; missing check tap returned success; interior OLS offset extrapolated into status region; watch returned with unverified top-left tap. Same X units show Y-dependent landing, incompatible with separable constant-speed diagonal assumptions.


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
- Root cause: original Bezier long moves have variable gain and cross-axis effects; a fixed independent-axis map could look fitted while fresh physical checks missed by1.6–6.7% (one12.9%). No curve disabling or tolerance inflation used.
- Fixed in source70e5094: feedback-required calibration persisted through restart; normal click/press withheld on missing/uncorrected endpoints; raw scatter retained independently of corrected real-click quality.
- Fixed pixel finder: subtract actual observed nudge translation/2, rather than guessed shift/2.
- Review regression reproduced then fixed: exact centre-at-edge requirement blocked back/app switching. Scoped system gesture inset validation and recheck after bottom pin preserve these gestures; normal taps/calibration remain exact.
- Validation CI40457162983:434 simulator +20 independent policy tests passed,0 failures; unsigned Release and app/extension81 metadata/hash/arm64/framework verified.
- Remaining: physical iPhone execution not available locally; no promise of hardware precision from simulation. Raw evidence stays E:/AgentStorage/esp32/logs42-inspection, outside Git.

## logs43 / build82
- build81 withheld every ordinary tap the pixel finder could not see; the home screen hides the translucent pointer, so every watch run failed at step 1 and calibration checks failed on grid/probe dots. Fixed in 3959f4d (unseen ordinary tap → calibrated estimate; plain board during checks). Precision taps stay strict.
- Fixed in build85: unrelated lessons reached the watch task (bigram Jaccard ≥ 0.2 now required); self-learned lessons reset once.

## logs 2026-11-06 / build85 → build86
- 10 of 12 paste hops ended "lost, original target unverified": no reply ever went out. Three causes in the trace frames: (1) the back button's unread count changed 321 → 322 during the hop and the return check compared it as text; (2) WeChat banners for other groups covered the title on the return frame; (3) 8 s spent aiming in Lan Agent, iOS re-ordered the app switcher, the reverse swipe did nothing and the hop threw "did not leave Lan Agent".
- Fixed in build86: number-only OCR pieces not compared; up to 3 looks (0/2/4 s), each fresh and equally strict; reverse swipe that stays in Lan Agent is followed by one forward swipe, source check unchanged.
- Not code: watch chats ["测试群","主人蓝海乐"] with senders ["蓝海乐"] → owner false, phone tasks never ran (app already warns in the log); the phone uses 9-key Pinyin, which forces every Chinese reply through the paste hop.
- Release builds were never stripped (`xcodebuild build`): 79k symbols / 5.95 MB of the 9.6 MB binary. Fixed in build86 (DEPLOYMENT_POSTPROCESSING) with a CI guard.

## logs 2026-11-06 evening / build86 → build87
- Nothing sent: the paste hop now filled (3rd look matched), the text was in the box, but the confirm-send run tapped the keyboard's 发送 key (0.863, 0.886) as a precise tap; the dark keyboard hid the pointer, 6× "pointer not found", withheld, "3 errors in a row" (76 s, 16 model calls). Owner task "去给测试群发个消息" typed 你好 and stuck the same way. Fixed in build87: a tap on the keyboard's bottom-right key with a keyboard up is sent as Return.
- Jitter: requiresFeedback made every ordinary tap search for the pointer; 31 searches found it 6×, ~5 wiggles per tap, 4.6–6 s per tap; 13 "lost during correction" then clicked at the estimate; all 10 taps still landed. Fixed in build87: ordinary taps open-loop on the map; precise taps / edge gestures still aim; app switch aims once.
- Learning: RouteBook replayed 6 navigation runs without the model (1 stopped at a changed label); lessons are only text tips and could not fix a mechanical failure.

## logs 2026-11-06 night / build87 → build88
- Sends now work (Return): "pressing Return instead" → "sent message verified", 测试群 你好 sent.
- Back-and-forth in 主人蓝海乐: the unread-check task text never changes, so RouteBook learned "tap 主人蓝海乐" and replayed it each check ("route: replayed 1/1" → 0 new messages → return → again). Fixed: learnedRoutes off for the unread check and the return fallback.
- Back swipe: 13/13 edge swipes failed, each followed by a model run tapping the chevron (55,86) 7/7. Fixed: WatchListReturn taps the verified chevron first, swipe second. The return fallback had also learned a junk route (label "20:21").
- Claude 发送 at (0.908, 0.543): above the keyboard, so not Return; precise + pointer unseen → withheld 17× → fail. Fixed: unseen precise taps click at the estimate while calibration is trusted; seen-off-target and stale calibration still withheld.
- First send run opened 小柳 and another group (model's row guess). Fixed for watch send runs: list taps snap to the target chat's OCR row.

## logs 2026-11-06 21:03 / build89 → build90 ("Claude 你好" twice)
- Learned send button worked on run 2 ("send: the learned send button … score 1.00"; Claude part 35 s → 29 s), but round 2 took 207 s vs 156 s.
- Ack paste hop: Claude sat between WeChat and Lan Agent in the app order; 2 swipes there, the 2 reversed swipes stopped in Claude; return check refused 3× (correct) → 65 s model run (Home ×4) failed the same way. Fixed: watched WeChat chats are reopened by weixin:// after filling the pasteboard.
- Owner-task route never replayed: learned from inside WeChat, run 2 started on the Home Screen. Fixed: RouteBook.entry joins at the step learned on the current screen. An old route's anchor "20:20" stopped replays: times/counts never anchors.
- Walk back after the phone task tapped (0.06, 0.088) twice in Claude (its menu). Fixed: afterPhoneTask skips blind back taps.

## speed / build90 → build91 (same logs, "second run barely faster")
- build89 session: 44 steps, frame wait 40.7 s, LLM 85.6 s, HID 33.6 s; 18 steps waited ~2.07 s (the settle cap), 11 stale plans, 53 model calls.
- Cause: direct capture publishes every changed pixel; the blinking caret kept `updated` fresh, so settled() always hit `most` (2 s per action, 4 s at task start). Fixed: VideoFeed.changedAt from a 24×48 look below the status bar (cell diff > 16), settled() waits on it.
- Same caret made plans stale (Vision.changed fine pass ≥ 6 px). Fixed: stale check passes caret: true (one thin upright stroke is no change); action results keep counting it.
- Ack "收到，我去处理。" (8 chars > 6) always pasted. Now WatchSettings.taskAcknowledgement = "收到", typed as pinyin.

## logs 2026-11-06 21:51 + 2026-11-07 22:59 / build91 → build92
- Reports never sent (11-07): after the phone task used Clock and a drawing app, Lan Agent was 3+ apps back; 6 hops "Lan Agent not reached after 2 switches", watch stopped. Fixed: second attempt opens Lan Agent through Search (Home, swipe down, type "Lan Agent", Return) when the source is a watched WeChat chat (reopened by weixin://).
- 2/5 weixin:// returns failed "stable content text not matched" (11-06; frames rotated out). Fixed: watched WeChat chat verified by its navigation title; input box tapped (0.45, 0.925) when the keyboard is down.
- Unread checks went to the model every time (target 蓝海乐 rarely in view → .unknown): 2 calls, 7–11 s, opened 主人蓝海乐 4× with 0 new, once 虾笔刀陪跑学员元群(93). Fixed: out-of-view listed chats are not unread.
- Alarm + draw + message task failed twice at the step limit: ~35 swipes on the hour wheel (hold-swipes still overshoot in curve mode). Fixed partly: AgentLoop refuses the 2nd wheel swipe (thought mentions 滚轮/wheel/picker) with "tap the centre number, type 0800", twice per run. Not verified that the Clock wheel takes typed digits on iOS 27.
- "你去给我画一个" (11-06) also hit the step limit; trace rotated out, not analysed.
- Route anchors "它" and "可按住转文字" stopped replays; 1-char anchors dropped (placeholder text still possible).

## logs 2026-11-08 00:01 / build92 → build93 ("doesn't work, slower")
- Model service slowdown, not app: doubao-seed-2-1-lite first token 11.5 s avg (15–16 s headers), vs 1.3–1.4 s on 11-06/11-07 with the same prompt size (~4.4k tokens). Two report runs took 68 s / 155 s and were stopped by the user.
- App-side waits were fixed as intended: step frame waits 0.15–0.9 s (was ~2.1 s), start settle 3.4 s (was ~7 s). Paste hop with weixin:// filled.
- A report pending at Start went to a model run from the Home Screen (quickSend requires Lan Agent in background). Fixed: within 15 s of Start, hopToWeChat opens WeChat by URL, then the quick send.
- 4 stale-plan drops in one report, each a 7–15 s model call. Fixed: an action with a target acts on the first stale look when nothing changed near it (Build14ReviewTests updated).

## logs 2026-11-08 00:24 / build93 — analysis only (user: stop fixing, discuss first)
- Worked: local unread checks 0.3–0.5 s, 0 model calls; wheel guard → model tapped centre and typed 08/00, alarm set to 8:00; WeChat by URL at Start; URL return in the paste hop.
- Failed: (1) ack "收到" 45 s — quick pinyin typed but not confirmed by OCR → inspection run (6 calls). (2) Result report never delivered: Lan Agent unreachable after the multi-app task, Search route failed 4/4 (no frames saved; cause unknown), then direct capture dropped ("超过 2 秒未收到系统画面确认") and the watch stopped. (3) Alarm+sun+message: 308 s, 42 calls, step limit; ~20 steps only to open Clock (pinyin 时钟→始终, then "clock" → Google → App Store). (4) App relaunched 9 s after the first Start, during a walk tap; no crash report in the export. (5) Model first token avg 5.1 s (29/70 > 5 s), vs 1.3 s on 11-06.
- Structural: Chinese text depends on the paste hop (Lan Agent must come to the front), which breaks whenever other apps were used; multi-part phone tasks do not fit 40 steps at ~7 s/step; failures without saved frames cannot be diagnosed.

## 2026-11-09 build95 phase B notes
- Our keyboard shows no letter keys, so "keyboard up" checks miss it: focusBox (quick send) and the paste hop's box tap now skip when the keyboard reports in, else the tap would land on its 空格/換行 key.
- Known limit: apps in the dock have no label under the icon, so `open` cannot learn their spot; they are opened by Search each time.
- To confirm on the phone: board Enter sends in WeChat/Claude while Lan Agent's keyboard is up (phase A ③ typed, sending not yet confirmed).

## 2026-11-08 logs(9) build95
- Globe taps did not switch to Lan Agent: a pointer click on the globe opens nothing/menu toggling; menu needs a long press (user). Fixed build96 (hold + menu pick).
- Every tap re-homed to the corner (Pointer.moveTo rehomes whenever ProbeMap is set; X then Y moves). build96 only fixes same-spot repeats; nearby moves pending (build97).
- WeChat resumed old work: WatchTaskReply persisted in UserDefaults is resent at watch start; navigator prompt "already in a chat in scope → done, don't check unread" picked out-of-scope 小柳、. Pending build97.
- Mirror never connected: board waited for xiaomi_804/HUAWEI-510, not on the phone's Wi-Fi within 30 s. Needs user's network info.
- Alarm task: model did not use `open`, pinyin typed 始终, wandered to Google/App Store, step limit.

## 2026-11-08 logs(11) build96
- No reaction to a second task: watch baseline dropped while the direct capture was quiet (mirroring false). Fixed build97 (watchable).
- Lan Agent keyboard reports in >1.5 s after the menu pick on first start; Return right after the keyboard's text did not send. Fixed build97 (4 s / 0.6 s).
- Redundant report "已在微信会话…中回复收到" after a reply-only owner task. Open.

## 2026-11-09 build98
- App send button blocked with direct capture ("Start Screen Mirroring"): checked the board's AirPlay state only. Fixed build98.
- Keep-awake never nudged a still direct-captured screen (live needs ≤2 s confirmation): could lock, watch blind after 3 min. Fixed build98.
- One listed chat was tapped without a red mark. Fixed build98 (one list path for all).
- Redundant report after a reply-only task: by design (sent after the task finishes, user 11-09). Closed.

## 2026-11-08 logs(12) build98
- Owner's task never seen on the list: top row (0.145) and long previews (to 0.94) were outside the row filter; preview heights not smaller; OCR misread one char. Fixed build99.
- Taps past the calibrated x range (0.864) overshot (0.899 → 0.975): alarm ✓ never hit. Fixed build99 (right-border approach).
- Watch start ran the model with Lan Agent in front (opened an unlisted group, then a listed chat with no red mark). Fixed build99 (WeChat by URL, local list).

## 2026-11-08 live test (build99)
- open App by Simplified name on a Traditional phone: never found. Fixed build100.
- Alarm ✓ missed 0.027 low, clicked again in place until the step limit. Fixed build100 (taps around a dead spot; y last).
- Mid-run "直接取屏尚未就绪" pause: 1-unit nudge invisible. Fixed build100.

## 2026-11-08 build104 live session (fixed in build105)
- WeChat banner covering the title → model read the banner's sender as the chat → group talk answered into 主人蓝海乐 (privacy risk). Fixed: centred navigation title via local OCR, banner waited out.
- Reply stayed in the input box: board Enter does nothing while Lan Agent keyboard is up. Fixed: keyboard return (newline), board Enter fallback.
- flickhome sometimes opens the app switcher; page scan swiped into the App Library; app opening failed for 备忘录/美团/微信. Fixed: Home verified on screen, App Library search.
- Part done refused by whole-task checks; refused count not reset after help; single-part tasks never reached Codex. Fixed.

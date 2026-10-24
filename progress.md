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


## 2026-10-25 build50：日志23返回失败与重复读取修复
- 日志23确认build49及directStart／frame-wait路径生效；返回手势未成功但未核对结果，18轮重复读同一会话合计91,732ms，读消息模型61,225ms。Return发送的快捷完成也跳过发送计划的返回步骤。原始日志/截图仅保留本机out/logs23-diagnosis。
- WatchListReturn：新鲜帧及完整会话标题确认后，点原生导航栏左上返回按钮一次；只有列表标题与四个底部标签均可见才结束。识别不确定时用最多4步导航actor并再核对列表，不能仅凭模型done。
- watchLoop优先处理pending返回；返回失败只恢复导航，不读消息/重发/重做任务，20秒退避，连续4次失败停止。普通回复、任务回报、ChatTool和无须回复的多会话读取统一排队返回；单会话留在会话页。先读后退出和49提速路径保留。
- RED40112190894：旧一滑即成功的行为触发新测试失败；测试自身有一处可空数组强制解包导致主机重启，已改为安全断言，不据RED宣称完整基线通过。首轮GREEN40112733914发现默认回调的MainActor编译问题，已修。最终GREEN40112899851：源码cd4acaf7b32788b131e31b2f22bfdce08e6f70b4，Xcode26.6设备Release与全部231项XCTest（新增8项）通过，117Swift语法/JSON/plist/entitlements/diff核对通过。
- 桌面E:/桌面/Lan-Agent-build50-unsigned.ipa，4,999,422 bytes，SHA256 912159ce44551cafd789d2d6bd15035f6bc5c1d6533aa245e979e395adf183cf；App/Widget50、MinimumOS18、ZIP、无模型预设、新路径及桌面hash已核对；49的IPA/sha/说明三件套已回收。
- 路由systematic-debugging/TDD/verification-before-completion，沿用spec；无子Agent。仅private远端推源码与通用记录，不上传私人日志/图片。备份E:/Backups/esp32-before-build50-20261025.zip。证据../out/build50-chat-return/{verification.json,checkpoint.json,red-ci.log,green1-ci.log,green-ci.log,implementation-plan.md}；Headroom分别省8223/5348/7123 tokens。
- 没有操作真实手机，真机返回及总耗时仍待同任务新日志；测试数不代表容错率/成功率或速度百分比。没有改固件、网络、账号和模型设置。


## build51 / 50版交付后复查修复 — 2026-10-25
- 用户不放心要求重审。独立核对桌面50与已测CI完全一致，仍发现：前景/操作中暂停误计导航失败；列表OCR要求四标签过严且未验横向列；既存模型决策超时/坏JSON提前消耗消息历史。
- WatchListReturn改arrived/deferred/failed，仅真失败累加；列表要求标题和至少三个正确列tab，容忍漏认一个；WatchMode在模型失败/坏格式时回滚history并fail check，明确有效空回复仍正常记录。保留50版发送/返回分离、49提速和48先读消息顺序。
- RED1 40113904071：238项5失败，原231通过；RED2 40114372304：241项7失败（加模型超时/坏格式2）。新增10测试包含真实iOS Vision读取合成画面；GREEN1 40114949695编译检出缺await，已修复。
- 设备Release与241项XCTest全通过，GREEN40115040451，源码f9d3a6801fae7f310d9a4c0a4bf94d1f6254c120；118Swift语法、13JSON、4plist/entitlements和diff通过。App/Widget51、ZIP、minimumOS18、无模型预设、新二进制路径和桌面hash均核对。
- 桌面E:/桌面/Lan-Agent-build51-unsigned.ipa，5,003,989 bytes，SHA256 8fee0ad21175c75ebde0f8051f552e8ef754e01219e904f552f42170518e4969；校验码/说明同目录，旧50三件套已送回收筒。证据../out/build51-review-fixes；备份E:/Backups/esp32-before-build51-20261025.zip。
- 未操作真机微信；实际返回、暂停恢复、模型失败重试及整体速度待真机日志验收，不能给出实际容错率/提速百分比。未改固件、网络、账号、模型或签名。


## APK参考方案静态分析 — 2026-10-25
- 用户提供尖椒1.0.2与肉包1.4.0 APK，已本地静态分析。确认肉包Shizuku本机截图/input及系统返回；尖椒无障碍控件树、id/文字定位及参数化命令脚本。肉包仍有截图后500ms、首轮动作后5s/后续2s和多阶段模型调用，不能据此声称必然更快。
- 可借鉴：扩展现有本机可验证动作、稳定短流程、细分耗时与模型次数；Android权限不能原样移植iPhone。51已有directStart/新鲜帧/本机返回OCR，本轮未改程序或发布52。
- 详细报告和本地证据：../out/apk-performance-review-20261025/APK性能机制对照.md。JADX部分方法还原失败，关键肉包协程另用simple指令输出核对；APK/反编译代码只保存在项目外out，未上传。没有运行APK或实测端到端速度。


## build52 / 保留51回退的本机单会话导航试验 — 2026-10-25
- 用户授权先做一版并明确保留当前51供回退，覆盖原“新版到桌面回收旧包”的本次默认规则。
- 新增WatchChatOpen：仅“仅指定会话”且名单只有1项，完整唯一名称+较小消息预览+已验证微信列表时点一次；必须动作后新鲜帧匹配目标标题，才交原readChat独立确认/读取。名称截断、重名、未知布局回原导航；多会话未读选择原样。点后错误/过期目的地停止本轮，不再点击/读/发送；前景暂停不累计检查失败。
- RED40129055561：254项中15个预期断言失败，均为新快路测试，原241通过。GREEN40129446177：设备Release与254项XCTest全部通过，源码551ef25368e7de76095914abd41089ed3a5305bc；含新增13项和真实Vision读取合成列表画面。120Swift语法、13JSON、4plist/entitlements、diff、App/Widget52、ZIP、minimumOS18、空模型预设及桌面hash核对通过。
- 桌面E:/桌面/Lan-Agent-build52-unsigned.ipa，5,008,240 bytes，SHA256 ed0426c0c7b567a45e6a88f70161ada756cb0f47f07582a252c805f7b39d1aea；校验和使用说明同目录。51三件套未改未删，SHA仍8fee0ad21175c75ebde0f8051f552e8ef754e01219e904f552f42170518e4969；另备份E:/Backups/esp32-build51-rollback-20261025，含源码快照/rollback.txt/受保护manifest；本地回退分支codex/rollback-build51。
- 本轮没有改固件、网络、模型、账号权限或签名。没有真机测速，不能承诺全任务提速比例。新增快路主要省单一目标从列表进入时的试读/导航调用；51原有已在单一聊天直接读取的行为保留，不把它当新提升。多会话及复杂跨App任务本版没有新增快路。
- 证据../out/build52-local-navigation；下一步同一单会话/同网络模型对比51与52“列表到读消息”耗时、对象准确性、暂停恢复和无重复发送。


## 2026-10-25 — build57：沒鍵盤不准輸入、校準不學邊緣探測點、輸入框精準點（Claude Code）

日誌27（build56）：主人任務「你现在给测试群发个消息我看一下」點輸入框 (0.42,0.925) 實際落在 y≈0.885，鍵盤沒彈出，模型連打 7 次 nihaoya；quickSend 同因貼上不顯示，退回 agent（多 20–30 s）；第二輪本機打開點後標題未出現即判 unverified。校準探測點 2 卡在 x=0.998 卻進了 seen，x 修正崩掉（重放：0.5 落 0.532；只用可用點 0.498），所以 probe check 一直 ±4%。最後螢幕鏡像中斷（snap: no video）。
源碼 2027c77：AgentLoop.keyboardGuard（watch runs 開啟；無鍵盤拒絕 type 並 aimNext，連續 2 次放行）；Pointer.applyProbe 只學 ProbeFit.usable 的軸；TouchCalibration 加 (0.5,0.9) 探測點；quickSend 點輸入框 aim；WatchChatOpen 點後標題沒出現再看一次。
驗證：run 40144177481 設備 Release + 294 XCTest 全過（新增 TapAccuracyTests 2 項）。未真機驗證。
交付：E:/桌面/Lan-Agent-build57-unsigned.ipa，5,069,511 bytes，SHA256 ab7a5a8fc75be8cda168edd24c52cdf9de178f0b02217f2cb2b53204b9984968；56 回收，51 保留。
下一步：使用者裝 57 後重新校準（應 ±1–2%），再跑同一任務回傳日誌。

## 2026-10-25 — build56：多會話本機打開、全會話本機發送、每階段模型次數（Claude Code）

依日誌26耗時盤點：多會話打開 6–35 s、發送 15–76 s 都是 agent run（兩條本機快路只限單一會話）。
源碼 ee3b586：WatchChatOpen.unread（列表 OCR＋頭像紅點像素 Vision.redShare，選最上面的名單內紅點會話，點一次後標題核對；全部可見且無紅點→nothing；同名/截斷/不在畫面→模型）；quickSend 不再限單一會話：輸入框（鍵盤收起時 y 0.85–0.98）學一次全會話共用（WatchSettings.inputBox 持久化），貼上前核對標題；返回列表仍為獨立驗證階段。watch timing 加 model call(s)（LLMClient.requests）。
驗證：run 40142549400 設備 Release + 292 XCTest 全過（新增 WatchLocalFlowTests 7 項，含真實 Vision OCR 合成列表＋紅點）。首次 run 40142234871 失敗：合成預覽「在吗」太短 OCR 讀不到，改長後通過——實機最新預覽很短時也會退回模型。未真機驗證。
交付：E:/桌面/Lan-Agent-build56-unsigned.ipa，5,069,885 bytes，SHA256 2dcc655e7b2f7403d07a11e2b3704227de5b547cb05399ecdf7d442d73fb2246；55 回收，51 保留。
下一步：真機日誌看 watch timing 各階段 ms 與 model call(s)；使用者列表有兩個「蓝海乐」，建議改唯一備註並同步名單；建議 iOS 設定微信允許從其他 App 貼上。

## 2026-10-25 — build55：手機任務只限私聊＋口令；發送前核對會話、不重發（Claude Code）

日誌26：回覆「好的，我这就去给测试群发你好」先按發送發出，模型又輸入一次再 Return（重複）；測試群任務的回報被輸入進測試群（模型說「I am in the 测试群 chat … so I type」）；主人權限只看暱稱，群裡任何人都能改成同名。
源碼 a2cb548 + 測試修正（HEAD 見 git log）：WatchSettings.ownerPIN（鑰匙圈）；isOwner＝白名單發言人＋私聊＋帶口令（masked 讀取時去掉口令並標記 proven，群聊不算）；phoneRequest 與 owner 任務都改用 isOwner。發送執行（sendReply）的 outgoing 守門：畫面標題不是目標會話就拒絕輸入；同一次執行中文字出現次數比首次輸入時多就拒絕再輸入。WatchView 加口令欄與提示。
驗證：run 40141494070 設備 Release + 285 XCTest 全過（新增 OwnerPasscodeTests 6 項、改寫 WatchPhoneTaskTests）。前兩次 run 失敗是我寫壞的測試字串與一項舊測試假設（未帶口令仍可下任務），已修。未真機驗證。
交付：E:/桌面/Lan-Agent-build55-unsigned.ipa，5,069,823 bytes，SHA256 3852625e310e93364712841689383d016a90c8a661b6d13b30f9f26355717d55；54 送回收筒，51 保留。
下一步：使用者設口令、私聊下指令實測；另開始「固定流程腳本化」（本機 OCR 定位＋新幀驗證，模型後備）與每步耗時統計。

## 2026-10-25 — build54：點擊閉環對準、貼邊重量、大偏差標記校準失效（Claude Code）

日誌25（06:19，跑的是52/51）：模型給的微信座標 (0.85,0.59) 正確，但存著的 span 494x1110 與手機實際約 445x620 不符；home→move 420 655 卡在右下角，單次修正 move -49 -464 落到 Watch，守候一直打不開微信。日誌24「主畫面被說成白板」很可能同源（誤開無邊記）。
源碼 263999a：Pointer.aim 改為最多3次「修正→再找→用實際位移重量比例」；游標被邊緣擋住時先 home、走一半重量；偏差>maxMiss 或貼邊即 stale（持久化，之後所有 tap 自動 aim，AutoCalibrator.needed 為真，重新校準清除）。滑動/拖曳仍用舊 span。
驗證：run 40138959029（chen-private，workflow_dispatch）設備 Release 編譯與279項 XCTest 全過（新增 PointerAimTests 5項，以日誌25數據模擬）。未另跑 RED（新測試依賴新介面，舊碼無法編譯）；未真機驗證。
交付：E:/桌面/Lan-Agent-build54-unsigned.ipa，5,053,059 bytes，SHA256 a12684c85dfa1e7d29a2062d0c6ba95d5977b0e017ba8b9eb4ffd0430d641faf；App/Widget 54、iOS 18、無內建 key。桌面52/53已送回收筒，51保留。證據 ../out/build54-aim-closed-loop。
下一步：覆蓋安裝54 → 設定裡重新校準 → 守候查未讀，看日誌是否出現 "calibration marked stale" 及能否點中微信。

## 2026-10-25 — build53：守候启动/停止修复、诊断清理与私人仓库切换

用户授权使用Edge已登录的ChenQian-hub新建私人仓库并邀请lanhaiyue-web，已建立 https://github.com/ChenQian-hub/esp32-iphone-agent-app 。邀请339533511已接受，API确认PRIVATE/WRITE；本地新增chen-private，当前分支上游与remote.pushDefault切换到chen-private，原private和origin保留，禁止推送origin。未上传手机日志或付费APK文件。

源代码：2534ba9db049809b836ff61d5a3b140d42380e5f（实现03f808e后修正AppModel日志清理访问）。修复首次守候被前景暂停挡住、停止时旧启动仍续跑、明确标签同一行THINK/DO导致重复请求。设置→日志与缓存，提供占用与空闲清除/导出。自动保留20次/7天/80MiB诊断；单次录影120帧/8MiB、截图12MiB、文字2MiB，系统报告10份/5MiB；默认导出最近5次、无录影、最多20MiB文件内容。保护活动执行、符号链接、导入执行与非诊断设置/配对/校准/知识。

验证：新仓库RED run40136509180编译通过，270项测试中13项新增测试出现15处断言失败，证明能抓到回归/缺失行为；GREEN run40136677665（source2534ba9）设备Release与274项XCTest通过，0失败；124Swift语法/13JSON/4plist及diff检查通过。IPA ZIP有效、App/Widget均53、最低iOS18、无内置模型凭据，runner与本机SHA一致。首次GREEN run40136545880因UI直接修改private(set)日志失败，已改为AppModel.clearLog()并重测通过，不交付失败产物。旧repo run40134910674因付款/用量限制未启动，已通过新仓库恢复。

交付：E:/桌面/Lan-Agent-build53-unsigned.ipa，5,047,349字节，SHA256 6e37b9eca1d856e53129cda47ebd79a77893e0f03b34afe8347776cd02eb4c31，旁有.sha256与使用说明。51与52未删除，51独立保护备份E:/Backups/esp32-build51-rollback-20261025，SHA重新确认不变，禁止自动清理。覆盖安装沿用当前Bundle ID签名，不先卸载。

已知问题：日志24中模型把实际主画面误称为白板画布，未确定是点击落点/打开App动作还是模型理解导致。53不宣称复杂任务全部恢复，也未真机测速；下一步需真机逐步对照。用户可继续使用51，53作为可回退测试版。

路由/工具：共享skill-routing-reminder与Agent Router预检；实际使用systematic-debugging、test-driven-development、verification-before-completion、computer-use；官方gh CLI、Edge CUA、Headroom先压缩长证据、Swift tree-sitter语法检查。未安装新技能/插件，未改模型、固件、网络或权限。证据在E:/AgentStorage/esp32/out/build53-stability-log-cleanup（verification.json、workflow.json、red-verification.json、green-ci.log、*.headroom.json、checkpoint.json、diagnosis-and-changes.md、协作者完成截图）。

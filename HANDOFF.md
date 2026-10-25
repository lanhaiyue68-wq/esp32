## 2026-10-25 — build59＋韌體 v33/v34：PC 實測結論進 App（Claude Code）

App（源碼 7f51659）：每次 tap 都先 home（相對移動會漂 5–7%）；stale 不再讓每下都 aim（像素找游標在畫面變化時誤判，logs29）；quickSend 點輸入框不 aim；送出前清框（cmd+a、backspace：草稿、滑過鍵盤的亂碼）；watch 打字先試「拼音分詞每段 space 取首選、最後整句核對」（CandidatePicker.shows，跨行合併比對），對不上就清框改原貼上；九宮格鍵盤偵測並記錄提示（CandidatePicker.nineKey）；設定「發送日誌到電腦」（預設關）取代 Debug 專用的 ENABLE_APP_RELAY。
韌體：v33 藍牙回角落 6 報告送完才回 ok；v34 App 的 log 只從有線口輸出、app 指令只收有線口（out/v34/v34-app.bin，經 COM6 寫 0x10000；v31/v32/v33 備份在 out/）。
驗證：run 40154261139 設備 Release＋302 XCTest 全過（新增 Build59Tests 6 項、改寫 stale 測試）。IPA 5,091,483 bytes，SHA256 dbff3630633c55ea5a9b3a6295d788cc35157306922fc8fcedc5c0bd83dbdc1f，App/Widget 59，iOS 18，無內建 key；桌面只放 IPA，58 回收，51 保留。真機尚未驗證：需使用者安裝 59、鏡像切回小板、開「發送日誌到電腦」，再由 PC 經 COM6 看 App 日誌並下 app run。

## 2026-10-25 — build58：同一次執行不重發已發文字；角落小偏差不算撞邊（Claude Code）

日誌28（build57）：校準 ±0.2%（修好）。主人任務「你现在给测试群发个消息我看一下」在測試群用發送鍵發了「你好」，又輸入再發一次，第三次輸入中被 loop 保護判失敗。build55 的發送防呆只在 sendReply 執行；主人任務沒有。另：瞄準返回鍵 (0.06,0.09) 找到游標 (0.034,0.069) 被當成撞邊 → 誤標校準失效。
源碼 6c12872：AgentLoop sentTexts（watch runs：type 後遇 Return 或右下發送區點擊即記為已發，同次執行再 type 同文字拒絕並提示 done；typedKey 去空白和引號）；Pointer.stopped 改為超過目標 maxMiss 才算撞邊。
驗證：run 40145211665 設備 Release + 296 XCTest 全過（新增重發防呆、角落小偏差測試，改寫近邊目標測試）。未真機驗證。
交付：E:/桌面/Lan-Agent-build58-unsigned.ipa，5,070,256 bytes，SHA256 32e491f0bee27879198852b46acd38bfa0503402fb7a3c1f1be847429b68c5e6；57 回收，51 保留。

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


---

## 最新交付：build52 / 保留51回退的本机单会话导航试验 — 2026-10-25

- 工作树E:/AgentStorage/esp32/iphone-agent-build13，分支codex/wechat-phone-tasks，仅private；最终测试源码551ef25368e7de76095914abd41089ed3a5305bc，后续仅文档。
- 新增WatchChatOpen：仅“仅指定会话”且名单只有1项，完整唯一名称+较小消息预览+已验证微信列表时点一次；必须动作后新鲜帧匹配目标标题，才交原readChat独立确认/读取。名称截断、重名、未知布局回原导航；多会话未读选择原样。点后错误/过期目的地停止本轮，不再点击/读/发送；前景暂停不累计检查失败。
- 关键文件WatchChatOpen.swift、WatchMode.swift、WatchChatOpenTests.swift、Shared.xcconfig。
- RED40129055561：254项中15个预期断言失败，均为新快路测试，原241通过。GREEN40129446177：设备Release与254项XCTest全部通过，源码551ef25368e7de76095914abd41089ed3a5305bc；含新增13项和真实Vision读取合成列表画面。120Swift语法、13JSON、4plist/entitlements、diff、App/Widget52、ZIP、minimumOS18、空模型预设及桌面hash核对通过。
- 桌面E:/桌面/Lan-Agent-build52-unsigned.ipa，5,008,240 bytes，SHA256 ed0426c0c7b567a45e6a88f70161ada756cb0f47f07582a252c805f7b39d1aea；校验和使用说明同目录。51三件套未改未删，SHA仍8fee0ad21175c75ebde0f8051f552e8ef754e01219e904f552f42170518e4969；另备份E:/Backups/esp32-build51-rollback-20261025，含源码快照/rollback.txt/受保护manifest；本地回退分支codex/rollback-build51。
- 明确保留51为回退基准，禁止自动回收；这是用户对旧包默认清理规则的最新覆盖要求。原APK分析记录仍保留，未复制他人代码。
- 本轮没有改固件、网络、模型、账号权限或签名。没有真机测速，不能承诺全任务提速比例。新增快路主要省单一目标从列表进入时的试读/导航调用；51原有已在单一聊天直接读取的行为保留，不把它当新提升。多会话及复杂跨App任务本版没有新增快路。
- 已按共享reminder执行开发/收尾路由；router偏向OCR候选，现有Swift/Vision足够，无需新工具或技能安装。使用systematic-debugging、test-driven-development、verification-before-completion；Headroom压缩源码与CI日志。无子Agent；无私人截图/日志或APK源码上传。
- 证据../out/build52-local-navigation/verification.json、checkpoint、implementation-plan和CI原日志/Headroom。下一步同一单会话对照验收；保留51直到用户明确同意丢弃。

## 最新交付：build51 / 50版交付后复查修复 — 2026-10-25

- 工作树E:/AgentStorage/esp32/iphone-agent-build13，codex/wechat-phone-tasks，仅private远端；测试源码f9d3a6801fae7f310d9a4c0a4bf94d1f6254c120，后续仅文档。
- 独立核对50包匹配已测CI，仍发现：前景/操作中暂停误计导航失败；列表OCR要求四标签过严且未验横向列；既存模型决策超时/坏JSON提前消耗消息历史。
- WatchListReturn改arrived/deferred/failed，仅真失败累加；列表要求标题和至少三个正确列tab，容忍漏认一个；WatchMode在模型失败/坏格式时回滚history并fail check，明确有效空回复仍正常记录。保留50版发送/返回分离、49提速和48先读消息顺序。
- 关键文件WatchListReturn.swift、WatchMode.swift、WatchListReturnTests.swift、WatchDecisionRecoveryTests.swift、Shared.xcconfig。
- RED1 40113904071：238项5失败，原231通过；RED2 40114372304：241项7失败（加模型超时/坏格式2）。新增10测试包含真实iOS Vision读取合成画面；GREEN1 40114949695编译检出缺await，已修复。
- 设备Release与241项XCTest全通过，GREEN40115040451，源码f9d3a6801fae7f310d9a4c0a4bf94d1f6254c120；118Swift语法、13JSON、4plist/entitlements和diff通过。App/Widget51、ZIP、minimumOS18、无模型预设、新二进制路径和桌面hash均核对。
- 桌面E:/桌面/Lan-Agent-build51-unsigned.ipa，5,003,989 bytes，SHA256 8fee0ad21175c75ebde0f8051f552e8ef754e01219e904f552f42170518e4969；校验码/说明同目录，旧50三件套已送回收筒。证据../out/build51-review-fixes；备份E:/Backups/esp32-before-build51-20261025.zip。
- 路由读取共享skill-routing-reminder并执行router；router误报web_frontend，按实际原生Swift审核选择requesting-code-review、systematic-debugging、test-driven-development、verification-before-completion。使用Headroom压缩源码/CI日志，recent_code保护时透传；按用户规则不派子Agent。私有截图/原始日志未上传。
- 未操作真机微信；实际返回、暂停恢复、模型失败重试及整体速度待真机日志验收，不能给出实际容错率/提速百分比。未改固件、网络、账号、模型或签名。 下一步沿用Bundle ID签名覆盖并重启守候，验收双会话返回/暂停恢复/模型失败重试/无重复发送及总耗时。

## 最新交付：build50 / 日志23聊天返回与重复读取 — 2026-10-25

- 工作树E:/AgentStorage/esp32/iphone-agent-build13，codex/wechat-phone-tasks；最终测试源码cd4acaf7b32788b131e31b2f22bfdce08e6f70b4，仅private远端。
- 用户问题：进入聊天后无法返回且仍慢。日志23是49；18轮重复读取约92秒，其中read模型61秒；边缘滑动失败未验证；Return发送快捷done跳过返回。49提速路径确实生效，不能因此声称真实任务整体已提速。
- 新WatchListReturn在新鲜帧确认完整会话标题后点导航栏左上返回按钮；核对列表标题+四底部标签，不确定时最多4步导航actor，最终仍需可见列表证据。watchLoop优先pending返回，失败只恢复导航，20秒退避／四次失败停止。
- sendReply固定发送计划不再夹带返回，成功后独立排队。普通回复、任务回报、ChatTool、无须回复的多会话读取都覆盖；导航失败不重发/重读/重做任务；单会话留在聊天页；48先读后退出和49加速保留。
- 关键文件WatchListReturn.swift、WatchMode.swift、AppModel.swift、WatchListReturnTests.swift、Shared.xcconfig。路由systematic-debugging/TDD/verification-before-completion，沿用spec，无子Agent。
- RED40112190894：旧一滑即成功触发新断言失败，测试自身强制解包已修，不推断完整旧基线通过。GREEN1 40112733914默认回调MainActor编译失败已修；最终GREEN40112899851：Xcode26.6设备Release与231项XCTest全通过，117Swift语法／JSON／plist／entitlements／diff通过。
- 桌面E:/桌面/Lan-Agent-build50-unsigned.ipa（4,999,422 bytes），SHA256 912159ce44551cafd789d2d6bd15035f6bc5c1d6533aa245e979e395adf183cf；App/Widget50／ZIP／minimumOS18／无模型预设／新二进制路径／桌面hash均核对；49三件套已送回收筒，仅留50。
- 证据../out/build50-chat-return/verification.json、checkpoint.json、implementation-plan.md及CI日志；原始私有数据../out/logs23-diagnosis（不要上传）。备份E:/Backups/esp32-before-build50-20261025.zip。
- 未操作真机，下一步沿用Bundle ID签名覆盖并重启守候，两个会话发新消息核对返回、无重复读取／重发及总耗时。测试不能换算真实容错率/提速百分比。无固件/网络/账号/模型修改；iOS27原生取画面仍未实现。

## 最新交付：build49 / 直接执行与有效画面及时返回 — 2026-10-25

- 工作树 E:/AgentStorage/esp32/iphone-agent-build13；codex/wechat-phone-tasks；已测试App源码24a22f586d46506cd26340647595f158a0c9e330。仅private远端，未推origin/main。
- 用户授权：结合Phone Agent优点给现有App提速；无新固件、配对、Wi-Fi、真实手机或发送授权动作。
- VideoFeed等候每50ms检查完整usable(after:)；新可用帧或动作后heartbeat证明已解码图仍最新就继续。settled与freshness／断链／取消／恢复／snap保留。
- 已授权微信手机任务directStart，让actor直接看当前帧与完整Goal，省去初始planner；遇到错误／卡住／replan仍用planner。普通手动任务、固定导航与发送不继承此标志。所有输入、标题与发出检查仍沿用。
- 关键文件 VideoFeed.swift、AgentLoop.swift、RunSession.swift、WatchMode.swift、SpeedTests.swift、Shared.xcconfig。路由 systematic-debugging／TDD／verification-before-completion，沿用现有spec，不派子Agent。
- RED40108170022：原215项通过，新8项中4项失败，重现多余planner、1.838s等待和静止画面snap错误。GREEN40108655015：Xcode26.6设备Release编译及223项XCTest全通过；115Swift语法／JSON／plist／diff通过。
- 桌面 E:/桌面/Lan-Agent-build49-unsigned.ipa（4,987,626 bytes），SHA256 7d3a9307af79bad1c360cc77fc070c096be8b6b5a46d13ac33f36bd081d72be9；App及Widget49，ZIP／MinimumOS18.0／无模型预设／新二进制路径已验证。48三件套已送回收筒，桌面只保留49。
- 证据 ../out/build49-speed/verification.json、checkpoint.json、red-ci.log、green-ci.log、implementation-plan.md；备份 E:/Backups/esp32-before-build49-20261025.zip。无私有消息／截图上传；88字节H264为合成黑图。
- 尚未做真机测速。用户沿用原BundleID签名覆盖安装，重启守候并新发相同任务，比较model／frame wait／report总耗时。不能把测试结果换算真实提速或成功率。
- iOS27 ScreenCaptureKit未接入，现有编译环境26.6；不要声称已经替换画面传输或使用蓝牙HID固件。

## 最新交付：build 48 / 日志22导航回归修复 — 2026-10-25

- 最新工作树 E:/AgentStorage/esp32/iphone-agent-build13，分支 codex/wechat-phone-tasks；应用测试源码 0f1315eb3634de0f70b5945e798ad28753e73f86，后续仅交付文档提交。仅 private remote，未推 origin/main。
- 已确认47回归：多会话原始目标当固定计划，打开未读后返回列表，红点消耗而没有read/decide。六轮巡查26次actor调用，五次空chat一次bounce失败。原始证据仅本机 out/logs22-diagnosis，不上传日志/截图。
- 48：状态分支计划；导航前本机完整唯一顶部标题完成（gate/帧恢复核验后），读消息独立确认完整实际会话；普通任务/发送清空回调；多会话读后继续已有未读巡查直到列表为空。47有效的启动/解码优化与文字、发出、stale、bounce保护保留。
- 关键代码 WatchMode.swift、RunSession.swift、AgentLoop.swift；新增 WatchNavigationTests.swift五项回归。路由：systematic-debugging、TDD、verification-before-completion；沿用现有spec，不新增平台技能，不使用子Agent。
- RED40104949418：原210通过，新4项失败/9条断言，另1新项通过。GREEN40105825214：最终源码设备Release编译成功，215项XCTest全部通过；本机114Swift语法检查通过。
- 桌面 E:/桌面/Lan-Agent-build48-unsigned.ipa，4,988,236 bytes，SHA256 dbde67367ad8ec7eba1eb3b3b7dc4fb9400d322d38f8912e50510561b29e6bcf；47的IPA/校验/说明已送回收筒，仅保留48。验证证据 out/build48-logs22-navigation-fix/verification.json。
- 用户长期偏好：每次新版验证交付桌面后，自动回收桌面旧IPA/校验/说明，无需再问；源码、日志和构建证据保留。
- 下一步：用户覆盖签名安装，重启守候并发一条新消息，采48日志验证read/decide/任务/回报及真实耗时。47已清红点但未处理的旧消息不自动补执行。没有操作真实手机，测试不可换算真实成功率。

## 最新用户偏好：桌面安装包仅保留最新已验证版
已于2026-10-24将 Lan Agent 桌面build44/45/46送回收筒，只留build48及对应说明和校验码。以后每次新版验证并交付桌面后自动回收桌面旧IPA/校验码/说明，无需重复确认；不扩展到源码、日志或构建证据。用户要求优先于之前「桌面保留旧版回退」记录。

# Codex 接手 ESP32 / Lan Agent — 2026-10-24

## 目标与范围
用户要求接手 Claude「ESP32 网络配置与日志分析」。原始会话 17c84dbc-debc-4306-8308-7ef8c39bfb2f，最后需求：微信作为主人手机任务入口，可操作其他 App 并回原会话报告结果。最新工作树是本目录，原基线 build 44 / b28465de9a480983eb9e3095b53fc16aecf4725e；不要误改旧 ../esp32-iphone-agent。

## 已交付
- build 45，已测试源码 57e066330899ff5882cedf8d852045ab56dddfe0。分支 codex/wechat-phone-tasks 已推 private remote lanhaiyue-web/esp32-iphone-agent-app；未推 origin、未合并 main。后续文档提交不改变已测试 App 源码。
- E:/桌面/Lan-Agent-build45-unsigned.ipa、.ipa.sha256、Lan-Agent-build45-使用说明.txt。IPA 4,980,087 bytes；SHA256 2456fa64652a02828fabfcf34c5f1bd9f5b1c8a31f016e6485a0b80ee66a51da。
- WatchMode.swift：显式权限、精确会话/发言人匹配、主人原消息交给 watchRun → AppModel.run → AgentLoop。跨 App 沿用完整文字校验、40 步上限和无人值守失败策略。
- AppModel.swift：一个持久化待回报项；失败只重试回报，不重做任务，三次失败后停止并保存供下次续发。停止不继续导航/发送，撤权拦截回报，离开聊天前清除旧输入框坐标。
- WatchView.swift 与字符串目录：默认关闭的开关和中文说明。空白名单、部分名字匹配、未列出会话及 ChatTool 代答均没有跨 App 权限。普通回复及微信内任务保留。
- 使用说明 docs/wechat-phone-tasks.md；需求/计划/清单真源 specs/001-wechat-phone-tasks/。

## 验证证据
- RED 工作流 40050688780：203 项中仅新回归失败，原有 202 项通过；日志 ../tmp/codex-watch-red.log。
- GREEN 工作流 40051367358：真实 Xcode 设备 Release 编译成功，207 项模拟器 XCTest、包括新增 5 项全部通过；对应上述完整源码 SHA。
- 112 个 Swift 文件语法、字符串 JSON、plist/entitlements 与 git diff --check 通过。IPA 的 App/Widget build 45、ZIP 完整性、中文开关、无内置模型凭据及 SHA256 核对通过。
- 原始构建日志、Headroom 压缩及 verification.json 在 ../out/build45-wechat-phone-tasks/。基线备份 E:/Backups/esp32-before-wechat-phone-tasks-20261024.zip。
- 按 spec/plan/tasks 做收敛检查，无待实施代码差距；T009 真机验收保留，不能把模拟器当真机。

## 路由和工具
已读取共享 skill-routing-reminder 并执行 Agent Router。采用 direct-execution、systematic-debugging、spec-kit-orchestration、TDD、ponytail 和 verification-before-completion。依用户规则未派子 Agent，自行核查调用链和代码。
Spec Kit 1.0.6 在本工作树初始化，Codex/Claude 集成校验通过、事件关闭。生成的 .agents/.claude/.specify 基础设施仅本地保留并加入本地 git exclude，未上传整套生成技能。无外部扩展 hooks。
Headroom 代码压缩受 recent_code 保护，节省 0；RED 日志节省 1,200 tokens，GREEN 日志节省 7,123 tokens；未改模型代理。

## 下一步和限制
软件交付完成，尚未安装到手机、未发送真实微信消息、未操控手机、未刷固件或更改 Wi-Fi/配对/校准/签名/模型配置。真机点击、镜像、结果回报、停止及发送失败恢复待独立验收。
使用者沿用原 Bundle ID 签名安装，在微信守候开启手机任务，把自己的私聊名加入会话范围及发言人白名单，保持镜像并启动守候。一次一条，等结果后再下一个任务。微信显示名/OCR 不构成强身份认证。
继续开发请保留本分支，不用旧 build 44 覆盖；合并主分支或安装均需相应用户要求。


## 2026-10-24 build 46 微信任务提速已交付
- 用户反馈慢；代码 f616a058a06abb9b6e2beec6b738303143f3974f，分支 codex/wechat-phone-tasks。去掉首次回报前 6 秒冷却；回报成功后 20 秒退避改正常 6 秒冷却（失败仍 20 秒）；守候/任务完成轮询改 0.5/0.1 秒；后台启动跳过 0.8 秒不可见动画。2 秒持续画面变化、5 秒检查限流、发送核对、文字校验、权限和停止检查均保留。
- 关键文件 WatchMode.swift、RunSession.swift、Shared.xcconfig；新增 watch timing 阶段耗时，不增加消息内容。路由 systematic-debugging / verification-before-completion，沿用现有规格作小范围调整，无子 Agent。
- 工作流 40099241832：Xcode 设备 Release 编译及 207 项模拟器 XCTest 全部通过，112 Swift 文件语法检查通过。仅固定等待调整，未增加镜像实现的测试。Headroom 压缩云端日志节省 7,137 tokens（19.3%），原文保留。
- 桌面 E:/桌面/Lan-Agent-build46-unsigned.ipa，4,985,868 bytes；SHA256 d0c46aae0589e087349e78018d81d478ab64b7113405f124ae8f02a8a7d4d47d。包/Widget build、中文开关、ZIP、无模型 key 和桌面 SHA256 核对通过。build 45 保留回退。
- 证据 ../out/build46-watch-speed/{verification.json,baseline-timing.json,optimized-timing.json,xcode-build-and-tests.log}。这些是源代码固定等待变化，不是实机加速比例。未安装/发真实消息/刷固件；下一步 T009/T013 真机验收并按 watch timing 对比模型、任务、回报耗时。


## 2026-10-24 build 47 日志 21 提速验证中
日志在 E:/AgentStorage/esp32/out/logs21-performance/，只本地读取。14 个最新运行中，回执输入动作 14.36 秒，背景重建 GOP 达 854 单元；多会话巡查每次重做 planner；后台无离开动作仍等待新画面。修复源码 744d3e7，条件化后台重建、复用固定巡查计划、保留当前帧验证的后台快速启动。RED 40102025495 的 210 项仅健康后台解码案例失败；GREEN 40102487275 正在跑。113 Swift 语法通过。暂不交付未验证 IPA；未改 stale plan/隐私/文字/停止/身份权限，未实机操作。路由 systematic-debugging/TDD/verification-before-completion，未派 Agent。下一步核对 GREEN 及包校验，交付 build47，更新记录，真机测速另待验收。


## 2026-10-24 build 47 日志 21 提速交付完成
- 已测试源码 744d3e727a647ed00ff134b46ab50eefdae2f415，分支 codex/wechat-phone-tasks。多会话巡查复用固定计划；后台钩子仅在没有成功解码的可用新帧时重建 GOP（其余恢复路径保留）；后台无离开动作时直接核验当前帧。包含 build46 等待提速。stale plan、文字/发送/隐私/停止/权限及动作后新帧验证均保留。
- 关键文件 ios/IPhoneAgent/Video/VideoFeed.swift、App/AppModel.swift、App/RunSession.swift、App/WatchMode.swift、IPhoneAgentTests/DecoderRecoveryTests.swift、Config/Shared.xcconfig。
- RED 工作流 40102025495：210 项仅新健康解码案例失败。GREEN 40102487275：Xcode 设备 Release 编译和 210 项模拟器 XCTest（含新增3项）全部通过。113 Swift 文件语法、JSON/plist、git diff --check 通过。设备上表现和速度仍需同任务对比，不能用单元测试代替。
- 桌面 E:/桌面/Lan-Agent-build47-unsigned.ipa、.sha256、Lan-Agent-build47-使用说明.txt。IPA 4,986,172 bytes；SHA256 0a9c978d042cbdea9ba988243337978f2e983162c941f1023d5d8d8d4bca16e3。App/Widget build47、ZIP、中文开关、无模型凭据和桌面 SHA256 均核对。旧45/46保留。
- 原日志和截图只在 E:/AgentStorage/esp32/out/logs21-performance/ 本地分析，未上传仓库。诊断报告区分 trace 跨度和动作done：39.17秒会话导航/52.87秒手机任务；输入动作14.36秒与854单元GOP恢复重叠。最后CancellationError对应用户手动停止。
- 证据 ../out/build47-logs21-speed/{verification.json,xcode-build-and-tests.log,checkpoint.json}。路由 systematic-debugging/TDD/verification-before-completion，沿用现有 Spec Kit 规格；未派子 Agent。Headroom 实际压缩诊断及CI日志（GREEN省7137、RED省7237 tokens），未更改模型代理。
- 下一步 T009/T013/T018：用户原BundleID签名安装47，真机同任务比较 watch timing / decoder 日志并验收低错误率。未安装、未发送真实消息、未修改硬件/网络/模型设置。没有其他待实施代码差距；仅真机验收待办。

# 当前进度

## 2026-11-13 23:05 131 回歸進行中；132 修正在本機（使用者換新視窗）
- 131 三波（chain131.sh：r131g 完、r131b、r131c 進行中）；第一波：修 O、R、N 真機生效；Codex 兩帳號都掛（帳號 1 方案降級）；修 J 過熱時清空 App 位置。
- 132 未 commit：V 答案從筆記補、W 帳號休息依錯誤種類、J2 重讀不清空；23:40 加 X（使用者開 App 不再硬按回主畫面）、Y（黃色按鈕按不到：畫面不再每張重畫整頁、狀態籤加大可按範圍）、N2、T 診斷日誌；版本號 132。見 docs/build132-summary.md。交接 E:/AgentStorage/agent-handoff/lan-agent-2026-11-13-night-handoff.md。

## 2026-11-13 晚上 130 測完四波 16 組；131 已編譯（IPA 在桌面，等安裝回歸）
- 130 四波 16 組結果與每個 bug：docs/build131-summary.md、docs/device-2026-11-12-build124-report.md 尾段。
- 131：commit 9592fcc＋f01dfd2（第一次 CI 編譯失敗：修 U 的變數 typedNow 與同一範圍重名，改名 pendingKey），CI 分支 build131-ci，run 43419650461 成功；E:\桌面\Lan-Agent-build131-unsigned.ipa（SHA256 9e2a4ecd…45f2，CFBundleVersion 131）。
- 下一步：使用者安裝 131（並換固定散熱）後，三波（q128g、q130b、q130c）再測。

## 2026-11-13 下午 129 回歸＋130 已編譯（IPA 在桌面，等安裝回歸）
- 129 同 4 組：1151／1245／1275 s、g8 失敗（337 s），約 58/80（全程 thermal serious）。所有問題總表 docs/build130-summary.md。
- 130：commit 1278d89，CI 分支 build130-ci，run 43377447245 成功；E:\桌面\Lan-Agent-build130-unsigned.ipa（SHA256 c3d724ae…ad32，CFBundleVersion 130）。
- 下一步：使用者安裝 130 後同 4 組回歸。

## 2026-11-13 128 兩輪回歸完成；129 已編譯（IPA 在桌面，等安裝回歸）
- 128（手機已裝）跑 q128g 兩輪（g1/g2/g4/g8）：第一輪 4443 s 約 77/80，第二輪 4524 s 約 73/80；127 同 4 組 5710 s 約 67/80。報告 docs/device-2026-11-12-build124-report.md 尾段（每組錯因、時間拆解、兩輪總表）。
- 129 本機改動：Pointer.swift（borderLiftY 起算 0.035＋存檔）、AgentLoop.swift（多件任務不套記住做法但主導者照舊、分段件數算 App 數、完成檢查不採信本輪自發訊息／原有購物車數量、同頁來回捲第三次轉向拒絕）、prompts/app-rules.md 5 條；測試 Build129Tests.swift、Build114Tests.swift。
- 129：commit bf4527a，CI 分支 build129-ci 推 private，run 43368629752 成功；E:\桌面\Lan-Agent-build129-unsigned.ipa（SHA256 9a3c56c1…775f，CFBundleVersion 129）。
- 下一步：使用者安裝 129 後同 4 組（q128g）回歸，對照 128 兩輪。

## 2026-11-11 build 122（已編譯，IPA 已放桌面，等使用者安裝後重測）
- 內容：121 真機自測 127 題找到的 28 個問題（第 17 項點讚／關注不擋留到 123），加使用者要的 Codex 剩餘額度與「成功：／失败：原因」回報。交付說明 docs/delivery-build122.md，問題經過見 docs/device-2026-11-11-build121-report.md。
- 編譯：第一次 run 43011686829 失敗（navigationTitle 屬於 WatchReport，寫成 WatchSettings）；修後 run 43012108153 成功，提交 f4cb9ac，IPA build 122，SHA256 3b37e0a6775b…。Build122Tests 12／12；Build121Tests 一項期望過時已改測試（未重編）。
- 推之前：CloudBridge 的 said／failureWords 改 nonisolated（WatchSettings 同步呼叫），AgentLoop／CloudRuns 被 Python 文字模式寫成 CRLF，已改回 LF。
- 桌面：Lan-Agent-build122-unsigned.ipa；121 保留，120 移到資源回收筒。
- 下一步：使用者安裝後重測 g01（分享要批准）、g02/g03（抖音口令路線）、g04（listen: audio 日誌）、i06（Codex effort low 的回應時間）、j03（淘寶第五個）、r05/r09（發錯群、驗證碼）、新浪／高德，再跑 32 題回歸和幾輪 6 個 App；主人號監看功能等使用者測。

## 2026-11-11 build 121（真機自測完：雲端 51 題＋資料頁；7 個問題的修法已提交未編譯，等使用者決定 122）
- 夜裡自測（使用者去睡）：a/b/c 三批 19 題＋32 題回歸（30／32，平均 77 s）＋主人資料頁。報告 docs/device-2026-11-11-build121-report.md。
- 問題與修法（提交 9b52221、3b3c4dc，只推 private，**沒編譯**）：開始監看時監看自己把語音權限點成「不允許」（改成先問、答完再開始）；只用雲端不會問權限；沒權限時聽太久還重聽（最多 20 秒、提示別重聽）；Safari 網址被當訊息（去 https/www 比對、題目提瀏覽器且不發訊息時不批准）；點圖示打開的 App 被當聊天 App（看題目點名的 App）；繁體微信資料頁寫「微信ID」導致核對永遠失敗；暱稱或簽名仿造 ID 可冒充（兩行以上不算）。
- 使用者要做：設定 › Lan Agent › 語音辨識打開；121 先別開「群裡核對微信號」。kd04 淘寶店名失敗是記住的路線帶著舊答案（usmile）誤導，未改。
- 收尾：USB 測試通道已 release＋disarm，模擬雲端已停，events.jsonl 裡含個資的一筆已刪。
- run 42928633232（ac4779d）：IPA build 121，SHA256 4975ce9a6da0…，語音辨識說明在包裡；Build121Tests 21／21 過。測試步驟這次換 TitleCheckTests 卡住（卡的永遠是跑到那個時間點的那一項），確定是 build75 機器問題。桌面 Lan-Agent-build121-unsigned.ipa，120 保留，119 移到資源回收筒。
- 使用者要求一次做好：看圖、看影片、讀抖音／快手／小紅書／視頻號連結的作者和數據、口播文案（listen：螢幕錄音＋語音辨識＋畫面字幕）、影片內容總結、群聊總結、自動盯著的群、主人身份（名字＋暗號＋微信號，微信號核對是開關）、主人工具（GitHub 倉庫、伺服器接口，非 GET 要回「確認」）。需求與決定見 docs/plan-2026-11-11-wechat-assistant.md。
- 審批只認「發一則／發到／回覆／留言／傳送／跟某人說／告訴某人」等真的要發的說法；「誰發的」「評論數」「轉發數」不再算。
- 只讀任務有自己的說明文字（不含 @ 和發送做法），否則在抖音搜尋會被當成要發訊息而清掉。
- 審 diff 修掉一個編譯錯（`await` 在 `?:` 裡）。新增 Build121Tests 19 項；build75 那台機器跳過已知只在它上面卡死的一項測試。
- 提交 a353127，推 build75 main（run 42922510878）：編譯、打包、上傳都過；單元測試只有 TapAccuracyTests 另一項在這台機器卡住（它沒設審批，和 121 的改動無關），Build121Tests 19／19 過。
- 查卡住那項時發現真正的退步：只認列出的說法，雲端任務「在测试群发你好」會**不經批准就發出**（違反客戶規格 §0.6）。改回「发」照算，只排除只讀或名詞用法（誰發的、轉發數、發布時間、發票等）；用 Python 照同規則模擬 32 題全對（含 s04 原題）。只讀任務說明的「发回」改成「交回」。提交 6a8e7f1，run 42925503559。build75 上跳過 TapAccuracyTests 兩項只在它上面卡的測試。
- run 42925503559：Build121Tests 20／20 過；TapAccuracyTests 又換一項卡住（第三項，跳過一項就換下一項，重啟後其餘都過），build75 上整組不跑。下載的 IPA 是 121，但**沒有語音辨識權限說明**：Info.plist 由 XcodeGen 依 project.yml 重寫，直接加在 Info.plist 的那行被蓋掉；開始監看時要權限就會閃退。改加在 project.yml，打包步驟和單元測試都檢查。提交 ac4779d，run 42928633232。
- 測試清單 docs/test-checklist-build121.md。

## 2026-11-11 build 120（已交付：監看只發一則，驗證通過）
- 使用者要求再壓力測試：6 道「一句話 3–5 件事」組合題，5 道完成且正確（條件分支、計算、發测试群各一則都對），s04 因題目有「誰發的」被當成發訊息題、輸入網址被要求批准而取消；第一次做的組合題由 Codex 帶路較慢（s01 701 s）。報告 docs/stress-2026-11-11-build120-compound.md。
- lanhaile 額度用完，改用使用者給的 winesettbumpas609-boop/esp32-iphone-agent-build（remote build75，11 月沒用過）。run 42875915106 的單元測試有一項（TapAccuracyTests.testAnActorThatKeepsTappingAfterSendingCannotActOrClaimSuccess）在這台機器卡住 2 分鐘，重跑也一樣（lanhaile 機器上 2.8 s 通過），IPA 因而沒上傳；ci 改成打包後先上傳 IPA（75f38a9），run 42883422995 拿到 IPA。桌面 Lan-Agent-build120-unsigned.ipa，SHA256 f804eae6…cb670ee；119 備用，118 回收。
- 真機：测试群「@蓝 现在几点了」回「现在是凌晨三点二十四分。」，只一則，3 秒確認送出。交付說明 docs/delivery-build120.md。USB 測試通道已 release＋disarm，模擬雲端已停。
- 使用者要求修好重複發送再交付。120 只改這一項：按過 return 但沒確認到就是「returned」，後續流程只准在輸入框還有字時按一次 enter，任何 type 都拒絕（noTyping）；回覆算已答覆，下一輪不再寫。提交 3a91dcd（新增 Build120Tests 2 項）。交付說明 docs/delivery-build120.md（SHA 待補）。
- CI 42870062188：「job was not acquired by Runner」，重跑後一直排隊；lanhaile686-git 額度看來用完（同時 artifact 下載流量也超限）。要使用者處理帳單或換帳號。

## 2026-11-11 build 119（真機：回歸 5／5、過熱延後通過；監看日期對但重複發送一次，待使用者決定）
- 回歸 5 題全對（天氣三天、上海、高德地鐵站、備忘錄都過）；/hot 開關下雲端收到 device_hot 並重排，關掉後照常跑完。監看：回覆日期正確，但送出後讀不到群名、判定沒送出，後備送出流程重打一遍 → 测试群兩則一樣的回覆。報告：docs/device-2026-11-11-build119-report.md。
- 使用者同意把 118 的 8 項改出 119：監看回覆帶手機日期星期；送出改成先打字、再單獨按鍵盤 return（沒看到再按一次，最後才開發板 Enter）；點進名單上的群沒立刻確認到標題時改由 readChat 讀（它等標題、只讀那個群），確認失敗的畫面存 Documents/diagnostics（最多 10 張）；Codex 重新規劃後迴圈保護清空；同方向兩次沒捲動就擋第三次並告訴模型反方向；不發訊息的題目在非聊天 App 搜題外詞不要批准；提示詞寫明上下方向和天氣底部列（左地圖、右城市列表）；測試通道 POST /hot 可把手機當成「危急」來驗證延後。
- 提交 688f407（CI 42859832388 編譯錯：參數名 tapped 被區域變數遮住）→ 006a573 改名 onTap；CI 42860264484：655／0（新增 Build119Tests 4 項）。gh run download 回 503 Egress over the account limit，改用 gh api artifacts/{id}/zip 下載成功。桌面 Lan-Agent-build119-unsigned.ipa，3,574,045 bytes，SHA256 67f520b3a21dfea8833ebaa4909baf95890e3e6c7854e671c0e285ad2af8727b；118 備用，117 移到資源回收筒。
- 測試已備好：live/q25.json 5 題（體感溫度→天氣三天驗方向、天氣上海、高德地鐵站驗批准、備忘錄）、live/hottest.py 過熱延後、監看 @蓝。

## 2026-11-10 build 118（真機：Codex 回來後重跑 4／5、監看能收能回、8 項待改，待使用者決定 119）
- Codex 恢復後重跑 5 題對 4（備忘錄、天氣三天、行事曆兩題）；天氣查上海仍失敗（地圖鈕當城市列表＋迴圈保護擋退路）。監看：@蓝 約 1 分鐘回覆、只送一則，但內容日期編成 2025-09-09；鍵盤 return 不送出要補送；名單外熱鬧群休息規則有效。
- 連跑 32 題（live/q23.json）約 35 分鐘：28 成功，平均 65 秒；溫度最高「嚴重」沒到「危急」，過熱延後沒觸發；0 卡頓。行事曆兩題步數用完、天氣上海來回、高德搜「下水徑地鐵站」被誤要批准。
- Codex 14:56Z 起 429 usage_limit_reached，這輪全程只有豆包。截圖遮蔽有效（序號塗黑）；體感溫度 27 s。天氣三天滑動方向搞反、備忘錄仍來回；監看群名修正有效，@蓝 觸發回覆並打好字，送出時被我關監看打斷，錯誤草稿（星期三）已清掉、沒送出。報告：docs/device-2026-11-10-build118-report.md。
- 使用者同意把 117 真機與監看找到的問題改出 118：監看群名去掉「（3人）」；名單外的群點開一次後休息 20 分鐘（本機紅點不看、開會話任務也叫模型別開）；截圖遮蔽改按畫面同一橫行配對標籤和號碼（含標籤和號碼在同一塊）；日期一行多給明天、後天的星期幾；同一答案被豆包檢查再駁回時請 Codex 看一次，Codex 說 OK 就不掛「未能核實」；提示詞：備忘錄標題在打開的備忘錄裡讀、天氣細節卡片在預報和地圖下面、畫面已有答案就當場完成。
- 提交 9429042；CI lanhaile686-git run 42829675711：651／0（新增 Build118Tests 5 項，一次通過）。桌面 Lan-Agent-build118-unsigned.ipa，3,567,474 bytes，SHA256 cc7ad45a8ba9c119f6cc7e028722f87d3583e2aec6971db2e2a464310e9fea75；117 留在桌面備用，116 移到資源回收筒。
- 測試已備好：live/q22.json 短回歸 4 題（備忘錄標題、天氣三天、體感溫度、關於本機遮蔽）→ 監看模式（测试群暗號）→ live/q23.json 32 題唯讀連跑約 40 分鐘看過熱延後。

## 2026-11-10 build 117（真機回歸 14／15 對；監看模式沒回任何訊息；7 項新問題待使用者決定）
- 微信監看（21:44–21:52）：使用者在测试群發兩則帶暗號的訊息，一則沒回。原因：標題「测试群（3人）」的「人」沒被去掉，判定不是测试群；另外每輪都點開名單外的熱鬧群「虾笔刀陪跑学员元群」。沒有發出任何訊息，已關監看。
- 回歸 15 題（live/q20.json）：14 對，h04 備忘錄在列表和內文間來回被擋下後失敗（不再卡住）。同一批題 116 只對 7 題；平均 241 秒 → 84 秒。報告：docs/device-2026-11-10-build117-report.md。
- 有效：下邊界瞄準（11 次）、分段滑動、計算機用鍵盤、多行答案、雲端不求助、搜尋詞換說法不批准、中文答案、明天讀今天下一行。
- 新問題：截圖遮蔽沒生效（OCR 把「序號」和號碼分成兩塊，只在同一塊配對）；備忘錄規則把它引回列表；完成檢查（豆包）算錯星期幾、看錯第一條；豆包不熟天氣版面；過熱延後未熱到危急、未驗證。
- 使用者同意把 116 四批找到的問題一起改出 117。改之前先用 USB 在真機上量過：
  - 天氣往上滑：一口氣拖完會把頁面甩出兩三個螢幕（跳過十天預報直達頁尾，之後再滑當然不動）；收尾抖動無效；每次 20 單位分段送出，捲動量約等於拖動量（10 單位同、40 單位約兩倍）。實體鍵盤方向鍵、Option+↓、空白鍵在天氣都捲不動。
  - 下邊界：推到底再往上退 20／40／60 單位，游標停在 y 0.97／0.94／0.91，40、60 正好在時鐘「碼錶」分頁上。
  - 計算機：鍵盤打 7*6=、128*0.85=、40.74-32.9= 都算對；esc 和 c 都清成 0。
- 改動：最下面一排從下邊界瞄準、右邊界從 x 0.75 起（微信圖示 0.848）；上下滑分段 20 單位（橫向翻頁不變）；press 先用鍵盤打，畫面沒變才點讀到的鍵；多行答案接成一行；雲端題不求助、直接失敗說原因；被駁回兩次後放棄就交出「未能核實」答案；完成檢查懂備忘錄標題、預報「明天」是今天下一行；搜尋詞少字或多一兩字不要批准；被拒題截圖在清草稿後；雲端截圖塗黑 IMEI／ICCID／序號／MAC；手機「危急」溫度時新雲端任務回 retry_pending（device_hot），最多等 5 分鐘；開 App 連兩次找不到才改搜尋；提示詞：答案用題目語言、滑動距離、App 殘留畫面先關。模擬雲端收到 retry_pending 會重新排隊。
- 提交 43db748；CI lanhaile686-git run 42810557976：646／0（新增 Build117Tests 10 項，一次通過）。桌面 Lan-Agent-build117-unsigned.ipa，3,558,548 bytes，SHA256 16e08c349f2b316d2d35825dd73c2c4826b7c66c3c1a45a0db86862609cdb70e；116 留在桌面備用，115 移到資源回收筒。
- 回歸題 15 題已備好（scratchpad live/q20.json：前四批失敗或慢的題，加查剩餘空間看遮蔽、微信發送）。下一步：使用者裝 117 → 跑 q20。

## 2026-11-10 build 116（真機已驗證四批：62／69 對，問題已併入 117）
- 第四批 19 題：18 對。g08 備忘錄完成檢查不懂「第一行是標題」→ 求助卡住超時；連跑 34 分鐘手機到「危急」溫度，App 被暫停 14 次；拼多多數字輪播讓答案掛「未能核實」；新設定題全走 Codex 要 114–135 秒。
- 第三批 18 題：14 對。3 題超時（時鐘分頁、Safari 網址列都點不到，計算機讀不到鍵，之後都求助卡住）；高德搜尋詞少一個「的」就要批准；備忘錄答案是英文；關於本機截圖含 IMEI 等識別碼。
- 第二批 17 題新問法：16 對；d02 天氣把下週三當明天。往上滑 29 次有 25 次沒反應，是天氣、股市慢的主因；多行答案只送出第一行；豆包 05:11 欠費 403 約 1 分鐘後恢復。
- Wi-Fi 雲端 15 題：14 題答對，c03 計算機卡住。報告：docs/device-2026-11-10-build116-report.md。
- 有效：灰色提示被擋、只有訊息要批准、拒絕後草稿清空、沒給城市用本地、不再「未能核實」、不點進商品頁。
- 速度：股市 185→45 s，搜狐 99→36 s，高德 53–72→36 s，四段價差題 371→66 s。
- 新問題：計算機 press 讀不到大部分鍵（type 算式可用）；雲端題求助時永遠 running；看不到游標時點偏（微信圖示每次多 10 秒）；被拒題截圖在清草稿前；天氣查指定城市仍慢；使用者打斷後美團被記成一律搜尋。
- 使用者同意「一次改完出一版」：115 累積的 10 項問題加提速 3 項一起改，提交 b6d6620；第一次 CI 編譯錯（`??` 右邊放了 await），已修，CI 改成失敗時印出錯誤行。
- 完成檢查：改用豆包（首字約 1.3 秒，Codex 約 12 秒）；認得從主畫面點圖示開的 App 和按 Enter 送出；簡繁字、即時跳動的數字不再算錯；沒指定城市時要用本地。
- 雲端：只有真的要發訊息才要批准（搜尋、網址、App 名稱不問）；拒絕後清掉輸入框草稿；截圖改拍任務完成那一刻的畫面。
- 搜尋框裡的灰色提示詞：在這個 App 還沒打字就按搜尋會被擋下，要先自己輸入。
- 計算機：新增 press 動作，用文字辨識找到標著這些字的鍵再點（豆包之前是把按鍵位置記錯，不是點偏）。
- 規則：搜尋結果在列表上讀，不點進商品頁；App 會留著上一題的狀態，沒指定城市就用本地。
- 提速：點輸入框後鍵盤出來就在同一回合接著打字、送出；開 App 沿用回主畫面時讀過的畫面，點圖示後畫面一變就往下走。
- CI lanhaile686-git run 42732890211：636/0（新增 Build116Tests 10 項），提交 7d12572。桌面 Lan-Agent-build116-unsigned.ipa，SHA256 301bc010f9908a57965b7c37b72a69406a0ba653008a327c467c090939ac3082。115 留作備援，113 已移到資源回收筒。
- 驗證題 15 題已備好（scratchpad live/q14.json，走 Wi-Fi 雲端，cloudq.py 支援 reject 旗標）。下一步：使用者裝 116 → 跑 q14 → 逐題對截圖。

## 2026-11-10 build 115（已交付，真機驗證過）
- 長時間 30 題（約 1 小時，後 20 題改走 Wi-Fi 雲端橋接）：29 題完成，可核對的都對；新發現 5 項（搜尋也要批准、雲端截圖拍到主畫面、App 狀態殘留、點進商品頁、發送誤判未核實）。報告 docs/device-2026-11-10-build115c-report.md。使用者確認：USB 只用於測試，實際使用不接電腦。
- 第二批 16 題全部正確，平均 109 秒（沿用路線的豆包 64 秒，有 Codex 的 183 秒），0 卡頓 0 斷線 0 閃退。累積問題 5 項與提速方案 7 項，見 docs/device-2026-11-10-build115b-report.md。使用者規則：有新問題先不改程式，等他回覆。
- 真機：驗證群發對（73 秒）、天氣查北京對（305 秒）；價差題淘寶部分搜成灰色提示詞「保温水壶」。雲端橋接用模擬伺服器全通過：查天氣附截圖、批准後才發、拒絕就不發（草稿留在輸入框）。報告 docs/device-2026-11-10-build115-report.md。
- 改在 lanhaile686-git/esp32-iphone-agent-app 編譯：CI 42675270731 626/0，提交 428bb36。桌面 Lan-Agent-build115-unsigned.ipa，SHA256 03abfe212b30ca9da3d33a17b7bbf5ee4ebdce45183a8291c8be99c3ea7e21cc。113 留作備援，112 已移到資源回收筒。
- 使用者要求：一輪測完不要馬上出版，先在現有版本多測，問題湊齊再一次改完只出一版。114 沒交付，修正併進 115。
- 113 再測 15 題：回報完成 13，對畫面都正確；天氣查北京超時、碼錶求助。113 自動點取消停止共享視窗成功（約 7 秒恢復）。
- 微信換群：測試群換一句話豆包 42 秒；改發验证群時豆包照舊路線把訊息發到测试群（完成檢查有抓到但仍以「未能核實」結束）。報告：docs/stress-2026-11-10-build113b-report.md。
- 115：發送前確認聊天對象、換群沿用路線並拿掉舊群名、邊緣滑動以文字判斷是否捲動、完成檢查保留所有開 App 紀錄、重複開 App 只做一次、模型回覆不進快取；加上客戶文件第 3 階段的雲端橋接（docs/cloud-bridge-protocol.md，模擬伺服器 tools/cloud-mock/mock_cloud.py 本機自測通過）。
- 提交 ced5e8d 已推上；GitHub Actions 兩次（42671475972、42671827781）都沒開始任何工作就失敗，疑似帳號額度或付款問題，要使用者查 GitHub 帳單頁。115 還沒編譯、還沒跑測試。

## 2026-11-10 build 113（待真機）
- 112 真機 18 題：回報完成 15，全部和畫面相符；失敗 3（m01、m08、m15）；平均 97 秒。Codex 全程逾時，這輪只有豆包。0 閃退、0 共享中斷。報告：docs/stress-2026-11-10-build112-report.md。
- 112 的自動點取消沒成功（最後一張畫面在點擊後才到），113 已改。另外修：x>0.85 從右緣回來、輸入後解除無效位置標記、連續被拒絕 3 次換計畫。
- CI lanhaiyue-web run 42644479650：610/0，提交 121fa42。桌面 Lan-Agent-build113-unsigned.ipa，SHA256 3587ef0d0892f78e714f1cbbb95c4830002cecc649ee0f3c4c2a81c736a7534d。112 留作備援，111 已移到資源回收筒。
- 下一步：使用者確認 Shadowrocket、裝 113、重新共享 → 驗證自動點取消與 Codex 連線，重跑 m01、m08、m15，再跑一批新題。

## 2026-11-09 build 112（待真機）
- 111 真機 15 題新題：回報完成 13，完全正確 10，有但書 3，失敗 1，被安全鎖攔下 1；沒有答案和畫面對不上卻回報完成的題目。64 分鐘 0 閃退、0 共享中斷、0 開發板斷線；畫面停超過 3 秒從 10.9% 降到 0.6%。報告：docs/stress-2026-11-09-build111-report.md。
- 112 修：頂部目標一律從角落出發；誤判指針改從角落重走；點左上角後畫面停止就自動點取消（使用者要求，絕不點停止）；模型知道今天日期，完成檢查看得到點擊。
- CI lanhaiyue-web run 42625923195：608/0，提交 5b6a942。桌面 Lan-Agent-build112-unsigned.ipa，SHA256 fe6b3f7c0b44e586ae417e63f091df4739f2e50125cd5608aefbb056f4f6919e。111 留作備援，110 已移到資源回收筒。
- 下一步：裝 112、重新共享（代理分流開著）→ 重跑 n07、n12、n15 這類題目，再跑一批新題，並故意叫出一次停止共享視窗驗證自動取消。

## 2026-11-09 build 111（穩定優先，待真機）
- 修：手勢排隊（崩潰）、擷取重開不丟共享、文字辨識移出主執行緒、Codex 連不上最多等 30 秒且跨任務休息、完成前獨立檢查、列表與翻頁從邊緣滑、指標容差與跳動讀值、繞圈保險有進展就重算。加 StallWatch 診斷，CI 保留 dSYM。
- CI lanhaiyue-web run 42596010283：597/0，提交 c8425ca。桌面 Lan-Agent-build111-unsigned.ipa，SHA256 c40c86fef3fd07a736e8536eccf44358d7a08d0f057052d5329a1e9f22716be6。**沒上過真機。** 110 留桌面當退路，108 已移到資源回收筒。符號檔 E:/AgentStorage/esp32/dsym/build111。
- 下一步：裝 111、重新共享（代理分流開著）→ 跑 15 題新題（scratchpad live/q6.json）→ 逐題核對、看 stall 日誌。

## 2026-11-09 build 110 真機測試
- 24 題回報完成 14 題，對畫面核實正確 9 題（38%），多任務 6 題對 2 題；5 題假完成。全程沒有付款、沒有下單。
- 重大更正：11-08 20:04Z 起 Codex 請求全部逾時，這輪和昨晚都是豆包代打；逾時佔三個多任務 36% 的時間。
- 報告與修法：docs/stress-2026-11-09-build110-report.md。程式未改，等使用者說改再一次改完。

## 2026-11-09 夜間壓力測試與 build 110 候選版
- build108 真機 33 個任務 16 個完成（48%），平均 296 秒；詳情與原因見 docs/stress-2026-11-09-report.md。
- build110 改了 15 類原因，CI lanhaiyue-web run 42530893553：584/0，提交 82b472f。桌面 Lan-Agent-build110-unsigned.ipa，SHA256 5d4f1ed2176a584bedd91f9e98f47965b730dcbd234de49d32dcb90f92dc3b6f。**沒上過真機。**
- 未完成：07:23 iOS 擷取停住，多任務 e01–e03 與第三批 20 個沒跑到，等裝 110 後跑。

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


## 2026-10-25 — build64：回報在手機上走回會話；回列表先看兩次（Claude Code）

計時（build62/63 即時日誌）：回報約 50 s（任務後 agent 一步步找主人私聊）、回列表約 10 s/3 次模型、開會話約 10 s（兩個同名「蓝海乐」；使用者已改唯一備註）。
源碼 3a311af：quickSend 先 walkToChat（在會話→直接；列表→WatchChatOpen.row(of:) 點該列；其他已知會話→點返回；不在微信→hopToWeChat 經 Lan Agent 開 weixin://），不明就交 agent；WatchListReturn 返回鍵不 aim、看兩次、再點一次返回才問模型。
驗證：run 40187376055，307 XCTest 全過。IPA 5,104,284 bytes，SHA256 edd130fba4c11230886683e86dcd607f03a8de53702b64ea281e6974f432b3a0；桌面只放 IPA，63 回收，51 保留。待真機量時間：使用者需把守候名單/白名單改成新備註名。

## 2026-10-25 — build63：沒權限不亂承諾；主人沒帶口令會被提醒（Claude Code）

PC 即時日誌看 build62：第一個任務（無邊記畫笑臉）完成並回報；第二則 @群主任務沒帶口令 → 依規不執行，但回話模型說「好的,我这就去测试群发消息.」後什麼都沒做（使用者以為卡住）。
源碼 606084b：composePrompt 非主人「不要答應去做」；主人私聊但未帶口令（needsPasscode）回「要我去做这件事，请在消息开头带上口令再发一次。」306 XCTest 全過（run 40186668033）。IPA 5,098,954 bytes，SHA256 2576ecf89e54e7618ee9fa9981b3cf0a58b1539eda57988e1298f4206dbe25ef；桌面只放 IPA，62 回收，51 保留。

## 2026-10-25 — build62：標題檢查讀得到真實標題；沒寫內容不發指令原文（Claude Code）

logs(31)（build61）：主人「给测试群发个消息」→ 把指令原文「给测试群发个消息」當內容發到測試群；回報到蓝海乐時，正確的私聊被標題檢查擋 15 次（"not the chat 蓝海乐"），三次跑到 step limit，守候自停。模擬器用 logs31 真實標題列重現：只給 0.055–0.135 的窄帶，Vision 只讀到「<」「•••」，讀不到「蓝海乐」。
源碼 1119c04：WatchReport.navigationChat(in:) 改給 0.02–0.22 的帶（仍只取標題列）；新增 TitleCheckTests＋Fixtures/logs31-title.jpg（只含標題列，無聊天內容）；手機任務沒寫內容時發「你好」並說明。quickSend「不在該會話」也用同一函式，之前 45 s 的回報繞路可能同因。
驗證：run 40185264037，305 XCTest 全過（標題測試先失敗後通過）。IPA 5,098,306 bytes，SHA256 46c45deb7febe5af6689905e2946f81337032299d0337de146ef6a59747061cf；桌面只放 IPA，61 回收，51 保留。待辦：列表兩個同名「蓝海乐」仍建議使用者改唯一備註；重裝後鏡像無 IDR 需自動恢復。

## 2026-10-25 — build61：同次執行不重打畫面上已有的字；日誌開關移出演示數據區（Claude Code）

PC 即時日誌看 build60 真機（關掉誤開的演示數據後）：私聊快速回覆約 8 s ✅；主人任務「给测试群发个消息」打「测试消息,发送成功.」→ 模型按輸入框旁綠色「发送」（y≈0.49，舊判斷要 ≥0.5 沒算到）→ 又打一次 → 留在輸入框（使用者確認：一則正常、一則草稿）。回報 45 s 才送出。
源碼 d341414：AgentLoop typedBase（watch runs 每段文字首次輸入時記錄畫面出現次數，之後變多就拒絕再打）；送出點擊判斷改 y≥0.4；設定「發送日誌到電腦」移到「隱私／日誌與緩存」區並有自己的說明。
驗證：run 40183032678，304 XCTest 全過（新增重打防呆測試）。IPA 5,096,287 bytes，SHA256 5535d20890618fbd6b7227b1e24747b56f80640bdae3c2938319199b4b9de5cd；桌面只放 IPA，60 回收，51 保留。待辦：回報路徑 45 s 偏慢（quickSend 不在該會話時走 agent）。

## 2026-10-25 — build60：快速發送看動作後的畫面；手機任務帶上微信 @／群主步驟（Claude Code）

在 PC 經「發送日誌到電腦」（韌體 v34）看 build59 真機：私聊回覆內容正確但花 48 s——quickSend 打完 0.5 s 拿「目前畫面」（安靜畫面板子約 2 fps，拿到打字前的）→ 核對失敗 → 清框、貼上兩次 → agent 重打才送出；下一則回覆 6 s 正常。主人任務「去虾笔刀群@群主说这不是简简单单吗」走手機任務，提示詞沒有 @／群主步驟，打字走模型挑候選：在真實群送出「这不是简简单单」（無 @、少「吗」），回報失敗。
源碼 bdbf512：quickSend look() 改用 feed.afterAction(since:)；手機任務提示加群主＝成員第一位、@ 流程（@→選擇提醒的人→搜尋拼音＋回車→點完全同名）、一字不差並只發一次；手機任務 fastText 也開（快打＋整句核對，失敗改貼上）。
驗證：run 40155406025 設備 Release＋303 XCTest 全過。IPA 5,092,225 bytes，SHA256 fe195cfcad100b205511f96697cdb3bc18773188ac0b5a4dc3266b7f262c66b5；桌面只放 IPA，59 回收，51 保留。真機待驗。

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

## 2026-10-25 build65
- 真機 build64：主人帶口令任務沒跑（私聊發言人被讀成「蓝海乐」，白名單是「主人蓝海乐」）；開會話標題看漏白等 20 s；回列表 4.4 s 0 次模型。
- build65：私聊發言人＝會話名、口令請求即任務、開會話不對準＋多看 3 次。308 XCTest 全過（run 40188830238）。IPA SHA256 65e22db90b37eed3409715a2d377f22c8c67c2e9ddc455416d513e5968eeea88。
- build66/67：口令請求不經模型直接執行、決定 JSON 寬鬆解析、導航名映射、口令全形/空格、開始守候記錄設定。310 XCTest 全過（run 40190002249）。IPA SHA256 ad5dcf93d2a36bedb81a38712dd89cd107cb0428cd5cf55d5dcae5ebe928eef5。
- build68：真機 67 跑通但 3 分 44 秒；第二任務已發出卻回報「没弄成」→ 改成如實回報＋發出後 5 步收工。311 XCTest 全過（run 40192373741）。IPA SHA256 872bf9d4e6afbf7fed49293c0e964435a2154602968c24692529c5d35c5d8bb7。
- build69：真機 68 @群主任務正確完成與回報；回報走回私聊改為先點返回。311 XCTest 全過（run 40194087422）。IPA SHA256 d8c6b5220ed5ec8c1b71144c0e86c998cf5bf027eaf9a3c7a94b6a0a782a980e。
- build70：redo＝上個任務、拼音錯兩次改貼上、每步動作進日誌。312 XCTest 全過（run 40196349637）。IPA SHA256 7256aa20393c591f0baff1c44b2036d1471dea94f4ae3479ad3585cfaf594f92。


## 2026-10-26 — logs(32) repair / build71

Implemented cross-app paste restoration/verification, merged keyboard OCR recognition, concrete retry inheritance, bounded Home recovery, and read-only send confirmation. Source commit: `400d296`. Unsigned Release device build and 340 XCTest passed: https://github.com/ChenQian-hub/esp32-iphone-agent-app/actions/runs/40323966996. Verified build71 IPA copied to `E:/桌面/Lan-Agent-build71-unsigned.ipa`; build70 preserved. Signing/install and physical iPhone retest remain. See HANDOFF.md for exact paths and evidence.


## 2026-10-26 — logs33 / build72

Fixed old file replies and mixed-batch owner downgrade; preserve per-message authority and original command text. Improved paste source freshness and input-field exclusion. Source d8555a1: device build + 348 XCTest passed (https://github.com/ChenQian-hub/esp32-iphone-agent-app/actions/runs/40332717515); 136 Swift syntax checks passed. Verified unsigned build72 IPA placed on desktop; builds70/71 preserved. Physical install/retest remains. Details: HANDOFF.md.


## 2026-10-26 — logs34 / build73 完成代码修复与交付
- 修复正常拼音输入后被清空重贴：核验排除键盘候选，普通执行和微信 quickSend 都保留不确定文字、交给视觉核对；执行器拒绝盲目重打，明确修正后可继续。
- 失败报告具体说明停在输入/粘贴核验，源和返回帧进入正常本机诊断；不放宽目标验证。
- RED 40339071043：357测试12失败；最终 https://github.com/ChenQian-hub/esp32-iphone-agent-app/actions/runs/40341342030：unsigned device build成功、359测试0失败；代码7a7c52b。本地137 Swift语法0错误，diff check通过。
- 桌面 E:/桌面/Lan-Agent-build73-unsigned.ipa，5,132,514 bytes，SHA256 f7f1127677e560fc8ec509932fe3737e9121c52986c96abd39eba58d94f6b295。App/Widget73、ZIP CRC/哈希通过，旧70/71/72保留。未签名安装或完成真机复测。

## 2026-10-27 视频对照分析
已逐段检查 Mobinono 抖音演示并核对 pymobiledevice3 官方文档。推测电脑端调试隧道控制，底层库未证实；不将演示视为同任务性能基准。报告：docs/douyin-mobinono-comparison-2026-10-27.md。无运行代码修改，无新增实机验证。

## 2026-10-27 iOS27方案核查
用户明确当前系统为iOS27，以此覆盖日志34历史版本。已读取指定ChatGPT讨论并核对苹果ScreenCaptureKit文档与源码：直接取屏可行，推荐先保留现有USB HID与固件做App侧验证。记录：docs/ios27-capture-feasibility-2026-10-27.md。未改生产代码或进行真机验证。

## 2026-10-27 无线约束与成本澄清
用户明确手机与板之间无USB，实机为Wi-Fi/蓝牙/镜像，手机充电口必须可用。此前本记录及答复中“保留USB HID”推断作废；本地USB HID示例不等于实机固件。6为单次回复动作上限，不是截图或任务总量。已修正可行性报告；本轮仅核查代码/官方图片计量文档，未改运行代码，未做新真机验证。

速度估算：日志34本次13轮actor合计32.11秒，frame等待7.736秒，HID6.985秒；75.743秒为失败过程，非build73正常任务基准。只换取屏的直接收益不能据此承诺倍速。详见可行性报告。

日志35核查：4次新尝试均0模型调用，73卡在取屏/后台首帧确认，完成记录分别33.251、13.480、71.569秒。用户升级后未试旧版，不能确认iOS27因果。72到73取屏及RunSession源码无变化；未改产品代码或发布新包。详见docs/logs35-startup-diagnosis-2026-10-27.md。


## 2026-10-27 — build74 iOS27 direct capture preview

User-approved native whole-display preview completed; existing wireless controls and build73 input safeguards preserved. Skills: spec-kit-orchestration + test-driven-development + ponytail; review used scoped source inspection, Jev advisory scoring and CI. Spec/plan/tasks/quickstart/review: specs/002-ios27-direct-capture. Source8e8248645be1276daf5333b975c369225126a061; final CI40407538020 passed 8 policy + 368 simulator tests and device Release. Artifact E:/桌面/Lan-Agent-build74-unsigned.ipa, SHA256c1f1ee76575e01610e03f2e3bed9421ebfc5f4ab77e8018e9c9c79e548c2aaca. Inspected build74/SDK27.1/backgroundscreen-capture/linked framework/no signature/ZIP integrity. No new firmware, hardware, USB or cloud frame-streaming requirement. Device-only system consent/cross-app/background/cursor/gestures/input/CPU/thermal and matched speed comparison remain pending user-installed signed build plus exported logs. User asked storage: existing bounded app-owned diagnostic retention was verified and explained, no Photos writes introduced.


## 2026-10-27 build75: logs36 correction checkpoint

- Evidence confirms native capture is live; send coordinates are correct, but a blinking caret is misread as the mouse and triggers a wrong correction. A misplaced click is then committed as sent, blocking recovery. Long Chinese IME text is also a homophone.
- Added regression tests. Old code fails the caret, disappearing-pointer, fragmented keyboard, long Chinese paste, extra-letter verification and missed-send cases in CI runs 40411177155 and 40411545507.
- Repair committed in c8d8a85; additional OCR boundary test in 94add13. Validation continues in 40412541122 and 40412668563; do not deliver their IPA before all assertions pass.
- Constraints: iOS27 direct display capture, Wi-Fi/BLE controls, no USB and no firmware changes. Raw diagnostics remain outside Git.
- Skills: systematic-debugging + test-driven-development. Next: resolve any observed boundary failures, full green CI, inspect and copy final build75 IPA to E:\桌面.


## 2026-10-27 build75: learning UI and build account checkpoint
- User extended scope to general input reliability and visible autonomous learning. Skills: systematic-debugging, TDD, spec-kit-orchestration and ponytail; native SwiftUI reuse, no automatic sub-agents. Spec truth: specs/003-reliable-input-learning.
- Source commit124bcb6 adds shared exact-paste routing, JSON-quoted text preservation, real LessonBook/ExperienceStore inspection and controls, bounded review journal, request-based reference counts and localized Home/Settings entry. Device Release compiled successfully in run40416810591; simulator validation pending.
- Original account billing prevented run40414661324 from starting. User authorized a new private compilation repository, winesettbumpas609-boop/esp32-iphone-agent-build; invited and accepted lanhaiyue-web with Write, pushed source to main. Native capture and wireless hardware constraints remain.
- Baseline regression run40415984720 and implementation/boundary run40416810591 are active. New operator/punctuation and refused-paste tests intentionally precede their final repair. Do not deliver artifacts from a failing run.

## 2026-10-27 build75 boundary verification checkpoint
- Scope remains shared text fidelity, logs36 input/send recovery and a real native Learning entry; keep iOS27 capture and BLE/Wi-Fi, no USB/firmware change.
- Private build repository winesettbumpas609-boop/esp32-iphone-agent-build is active; lanhaiyue-web has accepted Write collaboration. Original owner Actions billing remains blocked.
- Baseline run40415984720 proved missing Unicode/multiline routing, JSON text preservation and learning persistence/status behavior. Implementation run40416810591 compiled device Release and ran 393 tests; six assertions failed across four test methods. Root input and primary learning tests passed.
- Corrected symbol-preserving full-text OCR matching and refused unsafe keyboard fallback for newlines/Tab/unsupported Unicode. Corrected send fixture to isolate its fake keyboard path. Run40418603814 compiled device Release, but simulator build exposed an inaccessible task setter in a test fixture; a98364c removes that invalid test setup and preserves nil for an unnamed step-only task.
- Current source a98364c is pushed to original draft branch and new build main. Full simulator/device verification is pending; no IPA from a failing run may be delivered.
- Routing: systematic-debugging + test-driven-development; feature intent and tasks under specs/003-reliable-input-learning; final converge/review, artifact/version/hash verification and draft PR refresh remain pending. Raw diagnostics remain outside Git.

## 2026-10-27 build75 delivered and old build outputs cleaned
- Completed shared input fidelity, caret/pointer rejection, bounded corrupted-draft recovery, unsent completion protection and the native real Learning page. Key files: AgentLoop.swift, CandidatePicker.swift, Vision.swift, LessonBook.swift, ExperienceStore.swift, RunSession.swift, LearningView.swift, HomeView.swift, SettingsView.swift, PrivacyViews.swift and regression tests.
- Verified source a98364cf8df689bd7ca2a342ce54e25084e0202a: run40418981465 passed Release device build, 393 simulator tests and eight direct-frame policy checks, zero failures. Device tests do not establish physical phone operation.
- Delivered unsigned E:/桌面/Lan-Agent-build75-unsigned.ipa; SHA-256 94b139cb9432ff2ecd0508c7de96d7e15401ddaa37e696016cf911ed10b4300e. arm64, build75, native capture linkage and ZIP integrity verified. Signing remains necessary before installation.
- Updated original draft PR1 to the final build75 scope; no merge. Private build mirror and accepted Write collaboration are active.
- User-requested bounded cleanup deleted 1,633 old output/cache files, 500,557,380 bytes. Source/Git checkouts, original diagnostics and current build75 retained. Manifest outside Git: E:/AgentStorage/esp32/log36-inspection/cleanup-old-builds.json.
- Feature003 spec/plan/tasks convergence found no additional implementation gap; physical iPhone acceptance remains: install signed build75, test arbitrary text/send tasks and inspect actual Learning history. See docs/build75-final-review.md and docs/build75-reliable-input-learning.md.

- Build mirror cleanup complete: deleted failed-run artifacts 12696686292, 12695128022 and 12695094009; API confirms only verified build75 artifact12697905343 remains. Source and CI history retained.


## 2026-10-27 logs37 / build76 in progress
- Confirmed build75 on iOS27.0.1, live direct display capture. Included WeChat frames show a send tap landing near (0.97,0.98) instead of (0.863,0.887); correct draft remains. Actual Claude frames were excluded by five later internal runs.
- RED 40424580741, source560788b: 398 tests, 11 expected assertions in six new/updated regression methods; no unrelated failures. Pixel-probe regression RED is running at7f8e42d /40425693931.
- Bounded repair: visually aim send taps, withhold unverified precision clicks, recover only on positive same-draft/no-new-bubble evidence, export retained bounded history. Original logs stay outside Git. Native iOS27 capture and Wi-Fi/BLE retained; no USB or firmware changes.
- Routing: systematic-debugging + test-driven-development. Source under ios/IPhoneAgent/Agent/{Pointer,AgentLoop,CandidatePicker}.swift and Services/DiagnosticFiles.swift. Final CI/artifact validation and source review remain.

- logs37 checkpoint: RED2 run40425693931 confirmed rendered probe endpoint error (actualx0.8848,targetx0.863),401 tests/12 expected assertions. App source fixf9531e9 compiled for device. Its CIrun40426883061 stalled without test output; canceled/force-canceled, not counted as pass or app failure. Its unvalidated IPA was removed locally and from Actions. Desktop still retains build75.
- Current CIrun40428771305/source19261178cee60e645ce66efe4bee4117cc7aedf4: app sources identical to f9531e9; workflow streams test progress, bounds individual test execution and publishes only after tests pass. Final delivery remains pending this run. Update log37-inspection/deliver-build76.ps1 to final run/hash before execution.


## 2026-10-27 build76 delivered
- Final CI40428771305/source19261178cee60e645ce66efe4bee4117cc7aedf4 is GREEN: Release device compile,401 simulator tests and8 direct-capture tests, zero failures. App code matches f9531e9. Real rendered post-probe pointer regression passed.
- Desktop E:/桌面/Lan-Agent-build76-unsigned.ipa,5,262,281 bytes,SHA256 4bf606f017a5e9635fa028bdbb3b626e8efe0ca2965e51321541a65f3380f1c9; signing required. Physical iPhone results remain unverified.
- Local/cloud build75, RED and canceled candidate outputs cleared; duplicate final download removed. Only current desktop IPA and final cloud artifact12701835846 remain. Source/original diagnostics retained. Details:docs/logs37-missed-send-review.md.


## logs38 investigation (2026-10-27)
- Build76 direct capture is live. Acknowledgement is visibly sent but actor marks it unverified; sent=false prevents authorized owner execution. Subsequent own bubble hides request from pending selection. See docs/logs38-acknowledgement-regression.md.
- RED focused CI40433368981 at cad6c5e; implementation and full validation pending. No physical-phone success claimed.


## logs38 build77 delivery
- Fixed independent owner dispatch and anchored whole-reply confirmation in WatchMode/AgentLoop. App source480db61; full CI40434017643 passed408 simulator +8 capture tests, zero failures. RED before repair was7 tests/6 assertion failures.
- Delivered E:/桌面/Lan-Agent-build77-unsigned.ipa, SHA256 c04e0d4b9fac2215a474c2796c4fdbfcf58bbcf89f103efae5bfdc403d6a80b2. Superseded IPA/test artifacts cleaned. No phone/USB/firmware validation claimed.


### 2026-10-27 logs39 checkpoint
logs39: evidence confirms 2.20–4.18% fit RMS and near-origin back taps before screen-sharing interruption. Five regression tests running on source f011955. Implement settled axis positioning, edge interpolation, transactional multi-point validation, and middle-edge WeChat return. Phone validation remains outstanding.


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


## 2026-10-27 logs42 / build81 delivery
- Source 70e5094392dab44ba7f38ef38ff4f6d6069171df; native iOS27 capture and firmware Bezier remain enabled, wireless only.
- Variable/coupled curved landings are now corrected and visually confirmed before ordinary clicks/gesture starts. Four fresh physical calibration clicks still require <=1.5%; raw scatter is retained. Nudge localization uses observed displacement. System edge gestures allow only a bounded cursor-centre inset; ordinary taps keep exact tolerance.
- TDD evidence: build80 RED 17 tests/11 assertion failures; first GREEN17/0; review RED21/2 for border gestures; final full CI434 simulator +12 motion/map +8 capture tests,0 failures. Release build succeeded.
- New private build mirror caoshihui5211314-cloud/esp32-iphone-agent-build; lanhaiyue-web collaborator accepted. CI40457162983.
- Desktop E:/桌面/Lan-Agent-build81-unsigned.ipa: 5,271,490 bytes, SHA256 f75d56caf9a1d7883e366062b1f2ddc5f78b43dc0eb256ec2287c7a4a9f09cfc. App/extension81, arm64, ScreenCaptureKit and ZIP/hash verified. Unsigned; physical phone unverified, install/sign and recalibrate once.
- Removed verified superseded build80 desktop/cloud IPA and temporary diagnostic artifacts; removed duplicate new download after hash verification. User logs retained locally.
- Routing/plan/acceptance: docs/logs42-feedback-positioning.md; local checkpoint E:/AgentStorage/esp32/logs42-inspection/checkpoint.json.

## 2026-10-27 logs43 / build82 delivery (Claude Code)
- logs43 (build81 on phone): calibration failed 3/4 tries on check (0.06,0.50) ("pointer not found"/"lost"); both watch runs failed at step 1 — WeChat icon tap (0.85,0.59) on the home screen withheld 3x ("Pointer position could not be verified") → "3 errors in a row". build77 (open-loop) had completed the same watch task.
- Cause: Vision.pointer needs moved pixels to keep their values; the translucent pointer over icons/wallpaper/grid line/probe dots breaks that. Offline with the frame's own cursor on the logs43 home frame: found 30/300, fails at the WeChat icon; plain WeChat screens 250/300. Shape-only match rejected (>1.5% error in up to 1/4 of hits). build81 made this detector mandatory for every click.
- build82 (source 3959f4d): ordinary taps/gestures correct when seen, else click at the calibrated estimate; lost during correction → re-home and click at estimate; seen-but-still-off stays withheld; precision (aim:true) stays strict. Calibration board plain white (corner squares only) during the 4 checks.
- CI 40461232391 (caoshihui5211314-cloud/esp32-iphone-agent-build): Release + motion/capture policy + 436 simulator tests, 0 failures (4 new/rewritten Logs42 tests). Desktop E:/桌面/Lan-Agent-build82-unsigned.ipa 5,272,133 bytes, SHA256 a883a0346720bb822f44902cb6c1be4fa2ac86f949c2995ebdfae211727b0151; build81 recycled. Physical phone unverified. Notes: docs/logs43-unseen-pointer.md; raw logs E:/AgentStorage/esp32/logs43-inspection.

## 2026-10-27 logs44 / build83 delivery (Claude Code)
- logs44 (build82): try 1 probe click got no touch (app briefly went background); try 2 first check (0.06,0.50) unseen on the plain board, click landed (0.090,0.493) 3.0% → failed; try 3 user cancelled. Same curved command scatters up to 5% (move 140 75 → x 0.480 / 0.530).
- build83 (7b9f7b4): each calibration check corrects from the real click landing (move resting pointer by the measured miss, ≤2 re-clicks; pixel-aim failure clicks in place instead of failing); final landing still ≤1.5%; 0.4 s repaint wait before checks.
- CI 40463137744: 437 simulator tests, 0 failures. Desktop E:/桌面/Lan-Agent-build83-unsigned.ipa 5,275,728 bytes, SHA256 f50bba2fd3e8b0e8a81a7bd382d443234a34f4b0b019d07fc0eae8f09f129e07; build82 recycled. Physical phone unverified.

## 2026-11-05 logs46 / build84 delivery (Claude Code)
- logs46 (build83, 10-29 02:09–02:15 Taipei): calibration passed ±1.3% (landing correction 3.0%→0.2%). Phone in dark appearance: every type refused "no keyboard" with the keyboard up (OCR missed the dark keys) → paste hop; hop 1 withheld the home-bar swipe (pointer x 0.210 for 0.200, 0.8% tolerance), hop 2 never reached Lan Agent (previous app was Claude). Owner task "去 claude 说一句你好，并把 claude 回复的内容发给我" held after the first send by endAfterSend and failed with the reply on screen.
- build84 (34a4b01 + d4c45a9): Vision.letterKeyboard layout detector (offline 53/53 keyboard frames light+dark, 0/57 false positives) used before OCR in keyboardUp; edge swipes 3% along the border; bring-back phrases count as severalParts and the phone prompt says to finish with the reply in the answer. Fixed date-bound DiagnosticFilesTests (October run names expired by the 7-day limit).
- CI 42024739284: 443 simulator tests, 0 failures. Desktop E:/桌面/Lan-Agent-build84-unsigned.ipa 5,280,424 bytes, SHA256 33ad5958b1b088b942a559570b3df52f79b44bf9310e8415fe4fdd349fefc9c2; build83 recycled. Physical phone unverified. Notes: docs/logs46-dark-keyboard-and-bring-back.md.

## 2026-11-05 build85: learned routes + lesson cleanup (Claude Code)
- User: no learning felt; wants it for all apps, and lessons cleaned. Evidence: LessonBook only adds prompt advice; ExperienceStore never keeps successes; logs43/46 applied 4–5 lessons per run, the most-used (20×) unrelated ("先选择中间三个按钮的左边那个…"), several contradicting, some with coordinates.
- build85 (8a96bbd..b4bf415): RouteBook (Services/RouteBook.swift) keeps a done run's navigation up to the first typing (scene signature + OCR label per tap; detours/dead taps dropped; 发送/付款/删除… end a route); AgentLoop.replay walks a matching route without the model, hands over at the first differing screen/missing label/no-change step. Lessons: Jaccard ≥ 0.2 added to matching, coordinate lessons rejected, self-learned lessons reset once (selfLessonsReset85); Learning page shows/clears routes.
- CI 42032226698: 452 simulator tests, 0 failures (9 new). Desktop E:/桌面/Lan-Agent-build85-unsigned.ipa 5,308,591 bytes, SHA256 620d1d0064c226222325c3879858b86f4de27770db2bfa1197fa4b3d341ddece; build84 recycled. Physical phone unverified. Notes: docs/learned-routes.md.

## 2026-11-06 logs 11-06 / build86: paste hop + stripped release (Claude Code)
- logs (build85, 11-06 18:55–19:05 Taipei): 10/12 paste hops "lost" so replies never went out. Trace frames: back-button unread count 321→322 and WeChat banners for other groups broke the exact OCR match; once 8 s in Lan Agent let iOS re-order the app switcher, reverse swipe did nothing. Also owner false: chats ["测试群","主人蓝海乐"] vs senders ["蓝海乐"]; keyboard is 9-key Pinyin.
- build86 (a774996, pushed build81 main + chen-private): number-only OCR pieces not compared; return check looks up to 3× (0/2/4 s, fresh, equally strict); reverse swipe that stays in Lan Agent → one forward swipe; Release strips (DEPLOYMENT_POSTPROCESSING) with CI guard; iPhone only; duplicate Logo + unreferenced Discord/GitHub/X images removed. All features kept (user: intents/ChatTool/knowledge/demo/Wi-Fi mirroring will be used).
- CI 42210816847: 455 simulator tests, 0 failures (3 new); app binary 9.6 MB→3.97 MB (symbols 79,062→2,272), widget 916 KB→328 KB, Assets.car 2.6→1.3 MB; IPA 5.31→3.16 MB. Old-code RED not run.
- Desktop E:/桌面/Lan-Agent-build86-unsigned.ipa 3,156,457 bytes, SHA256 f5e3472426ee2d7b87cdddd270db5501a59f74b9f41518572f3acd7ea097159b; build85 to Recycle Bin. Physical phone unverified.

## 2026-11-06 evening logs / build87: send with Return, taps without pointer search (Claude Code)
- logs (build86, 19:40–19:47 Taipei): paste hop now filled on its 3rd look, but the confirm-send run tapped the keyboard's 发送 key as a precise tap; pointer unseen on the dark keyboard → 6× withheld → "3 errors in a row" (76 s, 16 model calls). Owner task typed 你好 and stuck the same way. 11 taps wiggled the pointer 104 times; the search found it 6/31; all 10 completed taps landed via the map estimate. RouteBook replayed 6 navigation runs without the model.
- build87 (39df6f6 + 8e7c75d, pushed build81 main + chen-private): tap on the keyboard's bottom-right key (x≥760, y 845–925) with a keyboard up → key enter; ordinary taps open-loop on the map (precise taps / edge gestures still aim); app switch aims once. Tests: 2 new (Return key, same spot without keyboard), Logs42 ordinary-tap test rewritten, 2 TapAccuracy send tests count Return.
- First CI 42214069074: 2 old send tests failed (counted taps; the send now is Return). Fixed tests only. CI 42215193701: 457 simulator tests, 0 failures; app symbols 2,271.
- Desktop E:/桌面/Lan-Agent-build87-unsigned.ipa 3,158,588 bytes, SHA256 0df7e360bb4eaebceffbd35cf79ef6ee7f635df7bc9c89aaf04cb30c901d9442; build86 to Recycle Bin. Physical phone unverified.

## 2026-11-06 night / build88 + build89: watch loop, back, Claude send, learned buttons (Claude Code)
- logs (build87, 20:18–20:29 Taipei): sends via Return worked. Problems: unread check replayed a learned "tap 主人蓝海乐" route every check (in/out loop); 13/13 edge back swipes failed, 7/7 model chevron taps worked; Claude 发送 (0.908, 0.543, above the keyboard) withheld 17× unseen → fail; first send run opened 小柳 and another group.
- build88 (d9f818e; CI 42219717381, 459 tests, 0 failures): learnedRoutes off for unread check + return fallback; WatchListReturn taps the verified chevron first, swipe second; unseen precise taps click at the estimate while calibration is trusted; watch send runs snap list taps to the target chat's OCR row.
- build89 (c017360; CI 42220795266, 467 tests, 0 failures, 8 new ControlBookTests): Services/ControlBook.swift learned buttons — 24×24 gray patch at 180 px width, NCC ≥ 0.88 with 0.03 margin, ±¼ screen around the learned row. send: learned at run end (done + sent by tap); used as prompt hint + snaps nearby send taps. back: learned from the first top tap (y ≤ 0.15) that changed the screen after a back swipe that did not; next back on a matching screen taps it. Failed twice and more than worked → forgotten. LearningView "Learned buttons" (学会的按钮), clear + switch wired.
- Desktop E:/桌面/Lan-Agent-build89-unsigned.ipa 3,177,491 bytes, SHA256 0ee3ec67b113f5aa3f3ee487195b1b6a9664dbb5a027a05c58a6a93a8fe93b02; build87 to Recycle Bin. Physical phone unverified.

## 2026-11-06 night / build90 + build91: second run faster (Claude Code)
- logs (build89, 21:03–21:12 Taipei), "Claude 你好" twice: learned send button worked (score 1.00; Claude part 35 → 29 s) but round 2 took 207 s vs 156 s (ack paste hop stopped in Claude → 65 s failed run; route not joined; walk tapped Claude's menu).
- build90 (b029823; CI 42224607864, 471 tests, 0 failures): RouteBook.entry joins a route at the step learned on the current screen; times/counts never anchors; watched WeChat chats reopened by weixin:// after the pasteboard is filled; afterPhoneTask skips blind back taps.
- build91 (1e45dce + a0f7bac; first CI 42226064273 had 1 failure, the stale-check cursor test on device JPEG; CI 42227329252: 476 tests, 0 failures): Vision.look/visiblyChanged (24×48 below the status bar, cell diff > 16); VideoFeed.changedAt drives settled() (cursor blink no longer forces the 2 s / 4 s cap); stale check ignores a caret-only change; WatchSettings.taskAcknowledgement = "收到" (typed as pinyin, no hop).
- Desktop E:/桌面/Lan-Agent-build91-unsigned.ipa 3,179,473 bytes, SHA256 51deea7759992d2d8d0fdc9fe832d3e0ca0f6ddc0f1b8f47c6a4dded029eb8f9; build89 to Recycle Bin. Physical phone unverified; expected ~100 s per round (from ~200 s).

## 2026-11-08 logs (build91, 11-06 21:51 + 11-07 22:59) / build92 (Claude Code)
- User: "every time a new problem". Full-session review found: 6 report hops never reached Lan Agent after a multi-app phone task (watch stopped); 2/5 weixin:// returns refused by content match; unread checks always delegated to the model because 蓝海乐 was out of view (2 calls, 7–11 s, wrong opens); alarm+draw+message task hit the step limit twice (~35 hour-wheel swipes); 1-char route anchors.
- build92 (d4be86b; CI 42386505086: 480 tests, 0 failures): PasteRoundTrip openAgent → AppModel.openLanAgentBySearch (Home, swipe down, type "Lan Agent", Return) as the second attempt for watched WeChat chats; WeChat return verified by navigation title, input box re-tapped when the keyboard is down; WatchChatOpen.unread treats out-of-view listed chats as not unread; AgentLoop wheel guard (2nd wheel swipe refused with "type 0800", twice per run); RouteBook drops 1-char anchors.
- Desktop E:/桌面/Lan-Agent-build92-unsigned.ipa 3,182,723 bytes, SHA256 e8ac244bf61a75a2d16785b63fea9ffc7656ee3245ab08dbdb416d31c87b3de5; build91 to Recycle Bin. Physical phone unverified. Unknowns: Clock wheel accepting typed digits on iOS 27; Spotlight top hit for "Lan Agent"; "你去给我画一个" failure not analysed (trace rotated).

## 2026-11-08 logs (build92, 00:01 Taipei) / build93 (Claude Code)
- User: "doesn't work, slower; check before delivering". Evidence: model first token 11.5 s avg (headers after 15–16 s) vs 1.3–1.4 s on 11-06/07 at the same prompt size → service-side slowdown. App-side: step frame waits 0.15–0.9 s (was 2.1 s), start settle 3.4 s (was 7 s), weixin:// paste hop filled. The watch kept starting with the 11-07 pending report as a model run from the Home Screen (quick send cannot run in front): 68 s and 155 s, stopped by the user.
- build93 (40b639e; CI 42390288036: 480 tests, 0 failures): deliverWatchTaskReply opens WeChat by URL within 15 s of Start (watchStartedAt) before the quick send; a stale look with a target acts at once when nothing changed near it (typing/keys keep the 2-drop rule; Build14ReviewTests updated). Self-review: full diff since build91 re-read; added the 15 s guard so a user-opened Lan Agent is never switched away; confirmed the stale/loop tests that pin a change under the target still hold.
- Desktop E:/桌面/Lan-Agent-build93-unsigned.ipa 3,185,251 bytes, SHA256 6e4d0a21e5a5eb943041aca7d6ca7547a68f7938d9d09c9042d17189559185fb; build92 to Recycle Bin. Physical phone unverified.

## 2026-11-08 new architecture decided / build94 phase A (Claude Code)
- After the Android "native Codex phone" video, user decided (specs/004-codex-style-agent/design.md): iPhone only; eyes = share entire screen; typing = Lan Agent keyboard; apps = search + remembered icon positions; brain in the iPhone app, ChatGPT Plus first, Doubao API fallback; multi-task parallel. Signing is 全能簽 → no App Group, keyboard talks to the app over 127.0.0.1.
- build94 (7c65365; CI 42396733674: 490 tests, 0 failures): LanAgentKeyboard extension (polls 127.0.0.1:47820 while shown, inserts text, optional return; needs Allow Full Access); KeyboardBridge in the app (each text handed out once, waits for DONE); ChatGPTPlus (device-code sign-in, token exchange/refresh, /models, streamed /responses with a screenshot, x-codex headers) following openai/codex rust-v0.167.0; Settings › 新架構測試（階段 A）. Plus is not an interface OpenAI offers to third parties; user accepted the account risk.
- Desktop E:/桌面/Lan-Agent-build94-unsigned.ipa 3,259,317 bytes, SHA256 87b2209a15ff172469f597b95e18d49a46df1dd221dd82283e7d4d9a7e34e02f; steps E:/桌面/Lan-Agent-build94-階段A測試步驟.md; build93 to Recycle Bin. Device unverified: does iOS show the keyboard while the board is attached as a hardware keyboard; does Plus sign-in/models/ask work.

## 2026-11-09 phase A results (build94 logs, 11-08 01:43–02:03 Taipei)
- Keyboard: works with the board attached. ① typed ×3, ② typed + return ×2, ③ typed + board Enter ×3, all ✅; full access true; picked up 0.4 s after the keyboard appeared, 21 ms when already on screen. Still to confirm from the user: whether WeChat sent on ② (keyboard "\n") and ③ (board Enter).
- Plus: device-code sign-in OK (second attempt; the first was abandoned when the app was swiped away/reopened at 01:52), account id present. Models: gpt-6.1-sol, gpt-6-astra, gpt-6.1-terra, gpt-6-sol, gpt-6-luna, gpt-5.6-sol/terra/luna, gpt-reserve, codex-auto-review. Ask with a screenshot on gpt-6.1-terra: first token 3.0 s / 1.9 s, total 3.4 s / 2.4 s. Quota headers: plan plus, 5 h window used 1% after 2 asks, 7-day window used 73% (resets in ~4.4 days), no credits.
- Conclusion: both phase A paths are feasible. Plus quota (weekly 73% used) means planner-only use as designed; per-step execution on Doubao.

## 2026-11-09 build95 phase B (specs/004)
- Typing: every Chinese/exact text the agent types and every WeChat reply/report/「收到」 goes through Lan Agent's keyboard first (globe key cycled until the keyboard reports in, ≤5 taps), board Enter sends; pinyin and the paste hop stay as fallback.
- `open APP` action: learned Home Screen page/spot (AppPlaces, UserDefaults appPlacesV1) → else OCR of the first 4 Home Screen pages → else Search typed by the keyboard (result label tapped, else Return). Apps only in the dock/App Library stay "by search".
- The model gets the screen's OCR text with coordinates (≤45 lines) and a note when our keyboard is up. Box taps are skipped while our keyboard reports in (it has no letter keys; the box's old spot is on it).
- Learning page: 学会的 App 位置 count, cleared with all learning records. Prompts: actor/app-rules/planner prefer `open`.
- Tests: IPhoneAgentTests/PhaseBTests.swift (open parse/step, keyboard typing + Return, ASCII still by board, screen text order/limit/prompt, AppPlaces, bridge onScreen).
- Delivered: commits cd2c070 + f73045c (first CI 42400684561 failed: screenText sort too complex to type-check; split). CI 42400902087 green: 501 tests, 0 failures (12 PhaseBTests), app symbols 2303, keyboard appex packaged. Desktop E:/桌面/Lan-Agent-build95-unsigned.ipa 3,279,441 bytes, SHA256 0aeac02d9731d4e0f84334556e68824ff7e4252434bc34059503fea444ce9575; steps E:/桌面/Lan-Agent-build95-階段B測試步驟.md; build94 recycled. Not yet tested on the phone.

## 2026-11-08 build96 keyboard menu + click in place (logs(9))
- logs(9) (build95, 10 runs): five globe taps never brought Lan Agent's keyboard up (frame showed the keyboard menu open, Lan Agent listed); every tap homed to the corner first (35 homes for 23 clicks, ProbeMap forces rehome).
- Change 1: `showLanAgentKeyboard` holds the globe key (Pointer.longPress, 0.8 s; user: a click shows no menu), then clicks "Lan Agent" in the menu (CandidatePicker.keyboardMenuEntry: row reading exactly "Lan Agent", left-aligned with a menu-only row such as English (US)/表情符號/鍵盤設定). A menu already open is used; a menu without that row is closed once and the caller falls back.
- Change 2: Pointer.tap/longPress on the spot just clicked (≤0.004, same tracked units, same board link, ≤60 s, not aimed) clicks in place without homing.
- Delivered: 3a5ae2c + 42e1615; CI 42404295947 green, 509 tests 0 failures (Build96Tests 9). Desktop Lan-Agent-build96-unsigned.ipa (3,286,128 bytes, SHA256 c86d7d21acc18c4dd0158cae3532b8b732e77c473d2dc6ddd0fa824cac8e570d; app + 2 appex build 96). build95 files recycled.

## 2026-11-08 build97 user's original asks (logs(11))
- logs(11) (build96): long press opened the menu and Lan Agent was picked on try 1, but the bridge reported only after >1.5 s (pinyin fallback sent 收到); Return 0.16 s after the keyboard's text did not send, 9 s later it did. A task sent 3:23–3:28 got no reaction: watch alive, no check for 5 min.
- Root cause of no reaction: direct capture sends nothing while the screen is still, so `feed.mirroring` (confirmation ≤2 s) went false and the watch loop dropped its baseline each quiet stretch; the frame carrying the new message became the baseline. Fix: `VideoFeed.watchable` (sharing on, frame, confirmation ≤180 s) for the watch loop and start; waits logged once; requireDirectFrame nudges the pointer once on a still screen.
- WeChat: WatchChatOpen returns `.inChat` when already inside a listed chat → watch goes back to the list (watchListReturn.pending) unless this watch opened it from its red number within 180 s (watchSelfOpened). Navigator prompt/plan: back to the list first, open only rows with a red unread number; the back-button number is the total. Start drops an unsent WatchTaskReply.
- Keyboard: wait ≤4 s after picking Lan Agent; 0.6 s after typed before Return.
- Pointer: plain taps hop from the last click's spot (ProbeMap.hop = units(for: inset+|d|), linear span otherwise), re-home after 6 hops, aimed taps and stale calibration always from the corner.
- Delivered: 70e5505; CI 42407470403 green, 510 tests 0 failures. Desktop Lan-Agent-build97-unsigned.ipa (3,287,818 bytes, SHA256 31ccae5821d698fc9655e4f238215f3c38974ca8442196c7495b23ee3d2f8ace; app + 2 appex build 97) + Lan-Agent-build97-測試步驟.md; build96 recycled.

## 2026-11-09 build98 user's answers (mirror, red marks, report)
- User: sending from the app asked for the board mirror; with direct capture there is none. HomeView's blocker (and IntentDetail's record button) checked only `board.status?.ap == "streaming"`. Now native mode counts `feed.watchable` (sharing on, a frame, confirmation ≤180 s); StatusChips, onboarding, AutoCalibrator, waitReady (Siri/debug) and startAgent too.
- Found while checking: keepAwake nudged only when `feed.live` (confirmation ≤2 s), so a still direct-captured screen was never nudged (could auto-lock; build97's watchable expired after 3 min). Now native nudges while `feed.watchable`.
- User: listed chats (owner 主人蓝海乐 and the chats/groups set in the app) are entered on a red number or a muted chat's small dot; every other chat with a red mark is opened and read only (even muted). WatchChatOpen: single and multi go through one list path (`unread` → `.row` listed first, else `.other`, skipping 订阅号/服务通知/文件传输助手…); single no longer taps its row without a mark. Other chats are verified by `WatchReport.navigationTitle` (list name may be cut with …), read, logged (ReadLog, ChatTool report), then back to the list; `WatchSettings.readOnly` (not listed and (onlyListed or group)). Red threshold 0.04 → 0.02 (muted dot ≈4–9 % of the badge area at 1280 high). A failed read of an unlisted chat is skipped, not a failed check.
- User: the report after a phone task is meant to go out after execution: it already does (watchTaskReply is saved after watchRun returns, delivered by the loop). No change.
- Delivered: 1c7538b; CI 42449961750 (515 tests, 0 failures) green. Desktop Lan-Agent-build98-unsigned.ipa (3,289,334 bytes, SHA256 a4d00267fabe27a30a975f291a0e3661bc7835631f021572112399763f9d6073); app + both appex build 98. build97 files to the Recycle Bin.

## 2026-11-08 build99 logs(12): the owner's task never seen; alarm ✓ missed
- In-app send works with direct capture (build98 confirmed: 05:32:28 the alarm task started from the app).
- No reaction: WatchChatOpen.listTitles read rows only in midY 0.16–0.83 and pieces ending by 0.87. The test phone (iPhone14,4 = 13 mini, iOS 27.0.1; not the 14 Pro Max seen on Bluetooth) list (592x1280) has no search bar: top row title at 0.145; previews run to 0.94. A chat with a new message moves to the top and a long task makes a long preview. Real-OCR CI replica also showed: a preview box can be as tall as or taller than its title (heights useless), and 主人蓝海乐 read as 主人监海乐. Now: pieces by minX 0.19–0.75, midY 0.10–0.90; preview by position only; a time read on the title line is cut (withoutTime); WatchReport.sameName allows one misread char for names ≥4 chars (titles, navigationChat, sameChat); official-account folders (官方账号/服务账号 variants) are not chats. Badge colour was fine (real frame: dot 8.4 %, threshold 2 %).
- Alarm failed at step limit: ✓ at x 0.899 needed 267 units, an extrapolation past the last calibrated landing (0.864); it landed at 0.975 (frame 035.jpg); pointer not found on the dark sheet; 14 dead-tap refusals. Pointer.point now goes past ProbeMap.reach via the right border (home, push right at the row, back units(for: 1 - x)); hops never land past reach.
- First watch check with Lan Agent in front opens WeChat by URL (hopToWeChat) and reads the list locally, not a 38 s model run.
- Delivered: 66a2570 + 974c1ff + 11864be; CI 42453356176 green, 519 tests 0 failures (Build99Tests 4, two on a real-Vision replica of logs(12)'s list). Desktop Lan-Agent-build99-unsigned.ipa (3,295,147 bytes, SHA256 e49e4addd6345f706e1a48a9b150429e51fdb9d50af7e4bc70879f2ef75f295d); app + both appex build 99. build98 files to the Recycle Bin.
- 2026-11-08 USB log pull (user OK): pymobiledevice3 11.47.0 via uv tool (deps --exclude-newer 2026-10-29, --no-build). `D:\AIProjects\agent-toolbox\bin\iphone-pull-logs.cmd [traces]` → E:\AgentStorage\esp32\device-pulls\<time>\ (debug.log + newest traces). Needs Apple Mobile Device Service (manual, admin) + Trust. Smoke: iPhone14,4 iOS 27.0.1, Lan Agent build 98 installed, debug.log 1.8 MB pulled.

## 2026-11-08 build100 live test over USB (build99 on the phone)
- Worked: the red mark on the top row was seen and the owner's chat opened locally (06:34:18); 收到 sent and verified; Lan Agent keyboard typed; most taps within 1 %.
- open 时钟/无边记 failed on the Traditional phone (~30 s each). AppNames: Search types the phone's own name (Locale.preferredLanguages: 時鐘, 無邊記, 設定…); labels match Simplified/Traditional/English (ICU Hans-Hant + a Taiwan/English table).
- Alarm ✓: x now right (0.889 for 0.895, right-border approach) but y 0.135 for 0.108 (0.027 low, just under the button); the same spot was clicked again until the step limit. Dead taps now go around the spot (AgentLoop.deadTapNudges: up, down, left, right 0.025) before the refusal; fromRightBorder moves y last (after the push it landed lower); a lost aim past reach takes the border way, not the extrapolated one.
- A report run paused mid-run ("直接取屏尚未就绪"): the nudge was move 1/−1 within one display frame, no pixel changed, and only when no frame-after was asked. Now move 4, 120 ms, move −4, any time; keep-awake the same.
- CI: caoshihui5211314-cloud's Actions job was not started (account payment failed / spending limit). The same workflow on ChenQian-hub/esp32-iphone-agent-app (remote chen-private) built it: run 42455900549, 522 tests 0 failures. Desktop Lan-Agent-build100-unsigned.ipa (SHA256 8dd1c95bed0288e14eb9ed894513c1fe3c418cb5ff7312f61afd18cb59e001f1); app + both appex build 100. build99 files to the Recycle Bin.
- Codex: ChatGPT Plus sign-in was only checked in phase A (11-07); every run so far used doubao-seed-2-1-lite for planner and actor (865 calls in this log). Plus as planner is phase C, not started.

## 2026-11-08 build101 phase C: ChatGPT Plus plans (the commander), Doubao acts
- PlusChat (Services/PlusChat.swift): a ChatModel that asks ChatGPT Plus (Codex backend, the phase A sign-in) with the planner's own instructions and the screen; RunSession wraps the planner with PlusChat.planner(fallback:). Not signed in / switched off / any failure → Doubao plans (429 rests Plus 30 min, others 2 min); the log says "planner: …" and "plus planner: …". Toggle + model on the phase A page (UserDefaults plusPlanner, plusPlannerModel; default gpt-6.1-terra).
- AgentLoop.stepBudget: 20 steps per numbered plan part, at least the old limit, at most 100.
- Includes build100's fixes. Commit 760a076; ChenQian-hub CI run 42457021487: 528 tests 0 failures. Desktop Lan-Agent-build101-unsigned.ipa (SHA256 d95807dc9ca5ffc768e5666c0da037060c89ad908710aa1c929989b5bc5117c7); app + both appex build 101; build100 files to the Recycle Bin.
- Not yet: the scheduler (think tasks in parallel, screen tasks interleaved: phase D) and per-part results; device test of Plus planning.

## 2026-11-08 build103: stop patching; the hand made right (closed loop) and measured
- User: stop patching, make it do the work. Plan agreed: (1) the hand accurate, proven by numbers; (2) Codex really commanding (per part, verifying, taking over); (3) tools before screen taps (AlarmKit etc.).
- Live test build101 over USB: Plus planned only 3 of 53 decisions (replans when stuck); Doubao 50. Owner tasks started with a fixed plan (no Plus split). Failures were all in the hand/actor.
- Root cause of misses (measured): open-loop moves land 3–7 % off. Calibration (pulled over USB: Library/Application Support/calibration.json, 11-06) has 7 x / 6 y knots; firmware v34 curves are random Bezier (esp_random) and iOS acceleration depends on per-report speed, so one command scatters up to 5 % (the calibrator's own note). ✓ (0.895, 0.108) reached at (0.890, 0.135); a hop meant for 0.395 at 0.461.
- Fix: Vision.arrival (frame before the move vs first frame after: the translucent disk changes every pixel under it and nothing just outside; centroid of the nearest disk). Prototyped in Python on the live test's real frames first (2 of 2 clean pairs right; fails only where the screen changed around it). Pointer.tap: move → arrive (see, correct by a short move, see again) → click; unseen → estimate as before; precise taps use the old wiggle aim only if arrival did not see it.
- AutoCalibrator.testAccuracy (Settings › 準度測試): 20 spots tapped like a task on the touch board; log lines "accuracy N: … miss X%" and a summary.
- Commits 0d25f3c + 8afb589; ChenQian-hub CI 42460246794: 533 tests 0 failures (Build103Tests 4 on synthetic 592x1280 frames). Desktop Lan-Agent-build103-unsigned.ipa (SHA256 66bfb8f3977442366b8b46dca89a198b3c6e8927feec14888eb5a28c7914a682); app + both appex build 103. build101 files to the Recycle Bin; build102 (patches) built but not delivered.

## 2026-11-08 build104 (not delivered): eye-checked taps, Codex as backstop, remembered ways
- Accuracy test with sharing on (device-pulls/20261108-213817): eye right to 0.1-0.2 % where it looked; 7/20 within 1 %, mean 1.6 % (blind: 4/20, 2.3-2.5 %). 9 taps never looked (stop frame before the move answered); corrections of 2-5 units held back by the board's 4-units-per-count remainder and never re-checked.
- 81816e9 no silent skip without a frame; accuracy test needs sharing. 04ca3f3 look-until-there loop (wait from move start, up to 3 per-axis corrections of at least one count, each checked against the pre-move frame, learned gain): CI 42481853634 537 tests 0 failures, simulated board 6/6 within 1 %.
- User: goal is a general 豆包手機; tests (alarm, sun, group message) are probes. 11f4696 removed the alarm wheel special case.
- User: Codex is the backstop; remember the way. 1bd79a4 + 924ac8d: Doubao works part by part with no routine Codex check; Codex drives on stall / 20 steps on a part / give-up (once, never after a send) until the part is done; RouteBook recipes keep the whole way of a finished run and a similar task follows it without the planner.
- ChenQian-hub Actions stopped by billing ("recent account payments have failed or your spending limit needs to be increased"); 1bd79a4/924ac8d never compiled. No IPA built.
- Delivered: CI moved to lanhaiyue-web/esp32-iphone-agent-app (remote `private`); 2293076 run 42484205661: 542 tests 0 failures. Desktop Lan-Agent-build104-unsigned.ipa (SHA256 2694991bafbabb7b5b9881986d2c40a00f51e315077e2966c9ba5e1f8b89590b); app + both appex build 104. build103 IPA and its extra files to the Recycle Bin.

## 2026-11-09 build105: fixes from the build104 live session (one build)
- Live session over USB (watch.sh + trace frames pulled from the phone): hand 0.3-0.8 % after corrections; remembered way halved a repeat (3:42 → 1:43, no planner); Codex drew the sun when Doubao could not.
- Found and fixed: part-level done held to the whole task's checks (3d8b283); refused-done count after help (db64365); one-part tasks never handed to Codex (0957d4f); accuracy spot on Back (a6de4bd); go Home after a task (00c5e38); WeChat banner taken for the chat title → reply into the wrong chat; chat now known by its centred navigation title via local OCR (1292a01); reply sent with Lan Agent keyboard's return, board Enter as fallback; agent Return through the keyboard while it is up (f010051); flick home leaving the app switcher and the page scan entering the App Library: Home verified on screen, App Library search (9196322).
- CI lanhaiyue-web 42493252147: 548 tests 0 failures. Desktop Lan-Agent-build105-unsigned.ipa (SHA256 dea7998883a98fc8470becfadfcca28f2e51587a7552abc08fc9c0d57a27a571); app + both appex 105. build104 to the Recycle Bin.
- Open: model thinking time and stale plans (10-13 per run), Doubao latency 7-60 s and timeouts, watch navigation needing Codex (4 min), x correction one count ~1-2.6 %.

## 2026-11-09 build106: USB test channel, so Claude tests on the phone itself
- User: goal is the Apple version of 豆包手機, the customer is pressing; approved Claude testing by itself ("好，你自己測").
- TestChannel (loopback 47821, token in Documents/testchannel.token, usbmux from the trusted PC): status, frame, steps, run, stop, gesture, board, share, watch, release. PC tool D:/AIProjects/agent-toolbox/bin/lan_usb.cmd. Test boundaries: no payment, no orders, WeChat only to 测试群, no deletions, no account changes. Remove with `lan_usb.cmd release` + `disarm`.
- Also: long press closed loop; every Home checked (app switcher left by its wallpaper); App Library field by contains; other words replace an unconfirmed field (30 refusals ended a run); non-plan replies keep the last plan; phone language told to the models; actor prompt leaves payment, orders and passwords to the user.
- CI lanhaiyue-web 42495900672: 553 tests 0 failures. Desktop Lan-Agent-build106-unsigned.ipa (SHA256 a68bea98804c6a8859e878a7b007d91267cc0730fc4a876fa4d7e7351fcfa814); app + both appex 106; build105 to the Recycle Bin.

## 2026-11-09 build107: measured on the phone over USB; Codex teaches, Doubao follows
- Facts measured with the channel: a flick from an app goes Home, from Home or Search it opens the app switcher and the next flick goes back to where it was, never to page 1; over a control the pointer's disk vanishes (hover lift), and the lift's corners or a clock's digits read as the pointer; Search + keyboard Return opens the top hit in under 3 s; Search is left by emptying it and tapping blank; board has no Home key over BLE; 4-unit nudges can send nothing (remainder).
- Fixed: Home decided by the screen; eye needs a quiet ring (fout ≥ 0.9); opening = page in front, then Search, then paging; nudges 8 units, repeated; Codex comes after 3 failed steps or 5 swipes in a row; wheels: tap the value; first-open terms accepted; payment, orders, passwords left to the user.
- User's design: a task not done before is driven by Codex from the start and remembered; then Doubao follows; Codex only if it stalls.
- Results on build106: brightness 159 s, note 129 s, timer 209 s (Codex one tap after 14 wrong swipes), calendar 43 s, all done; two others were cut by limits/pause. Doubao averages ~9 s a step.
- CI lanhaiyue-web 42500870800: 563 tests 0 failures. Desktop Lan-Agent-build107-unsigned.ipa (SHA256 b9a7dd4574a654e6b1d33d59a0e207cc13b1eed3ada500da8de38fe4e861b07f); app + both appex 107; build106 to the Recycle Bin.

## 2026-11-09 build108: Home Screen map, keyboard before the flick, Cmd+Space
- Measured: with a keyboard up the flick opens the app switcher; Cmd+Space opens Search from the Home Screen only; Return before the results opens nothing.
- Results on build107: note, brightness, web, timer each twice, all done; AMap 174 s, WeChat to the test group 259 s (bubble seen in the frame); Xiaohongshu cut by the limit, Meituan needs identity verification, Douyin failed on Home (fixed here).
- Added: every Home Screen page read once and every app's page and spot kept (user's idea), opened by page; Search only for apps on no page; recipes say each gesture's purpose; /ocr route.
- CI lanhaiyue-web 42507304259: 568 tests 0 failures. Desktop Lan-Agent-build108-unsigned.ipa (SHA256 5ea739181c069bd73840caa144f2c135d4d30ed694e5efb2c33162028f0b32f8); build107 to the Recycle Bin.

## 2026-11-12 builds 123, 124 (and 125 local)
- 123 (build75 run 43127228524) and 124 (run 43137255019) built first time, ~4-6 min each: unit tests now run only with [tests] in the commit message (GitHub quota ~10%).
- 123 on the phone: tap tolerance confirmed (2.06 -> 1.15 s a tap, 0 misses); regressions found and fixed in 124: a second send of one text into one chat, made-up results from apps never opened, steps not widened on remembered ways, a note swallowing the next action, a time label read into the chat title (the watch stopped itself), weather answered off the chat, a picture in WeChat taken for an app; voice messages are written out by WeChat (the owner's are commands, others' kept).
- 125 (local, not pushed by the user's word): 群收录 (docs/spec-group-archive-125.md, protocol section 6).
- Desktop: Lan-Agent-build124-unsigned.ipa (SHA256 4c3c9e14214a62eda62eae1559ab810bca9dc361bd8d8e779a02c2af2db63eab). Next: install 124 and run the regression in E:\AgentStorage\agent-handoff\lan-agent-2026-11-12-handoff.md. Device test scripts: tools/device-test/.

## 2026-11-14 03:45 132 已編
- 131 回歸：使用者 03:35 叫停（c3 第 164 步、c4 沒跑）；成績表在 docs/build131-summary.md 尾段。
- 132（d8659d2，build132-ci run 43484673225）：V、W/W2/W3、J2、X、Y/Y2/Y3、Z1–Z5、S2、N2、輸入提示、T 診斷；明細 docs/build132-summary.md。IPA：E:/桌面/Lan-Agent-build132-unsigned.ipa（CFBundleVersion 132，SHA256 e1dec042…a066）。

## 2026-11-14 07:55 132 回歸完成
- 三波 12 組：g1/g2/g8/g3/g6 20/20、g7 19/20、c1/c2 19/20、g4 18+2、g5 約 18、c4 約 19.5/22、c3 失敗（京東沒裝，連要失敗 3 次）。Codex 0 失敗。
- 133 候選 7 條見 docs/build132-summary.md。

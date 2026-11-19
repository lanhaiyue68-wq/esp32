# 任务状态

- [x] 148（D153–D160）已裝並回歸（11-19 13:16 – 11-20 00:34 首爾）：x 5/6＋x5 正確停下、y 3 題缺 App 依規則結束、n 15/16、h 19/21、s 5/10＋3（補測 6/10＋3）、h2 21/22（補測 20/22）、x 補測 5/6＋1。
- [ ] 149 本機已備（D161–D181，build123，未推）：等使用者點頭才推；推前把 ios/Config/Shared.xcconfig 的 CURRENT_PROJECT_VERSION 改 149。
- [ ] chain148c（n、h、y 在 148 再跑一次）結果整理。
- [ ] Safari 百度結果頁從天氣卡上起手的上滑被當點擊、打開天氣詳情頁（r148h2b h22 三次）：手機空檔實測再修。
- [ ] 淘寶購物車留有 148 h18 加的 2899 元穩定器（只加購沒結帳），依規則不刪，告知使用者。

- [x] 134 地獄級 y／z 兩輪與真人單句 q134h 跑完（11-15 01:20–14:32）。
- [x] 135 加 D16–D22（本機 build123，未推）。
- [x] 135 已編（run 43682371003，200c18b），IPA 在桌面，SHA256 95f44a0b…27bf。
- [x] 裝 135 後重跑地獄級（是／否兩輪 q135a／q135b，11-15 15:50–23:02），D16、D20 證實有效。
- [x] 136 寫好（D23–D35、F、規則 A B C G、版本 136；本機 build123 7b7cb1e，未推）。
- [x] 136 已編（build114 run 43722733231，afe1271），IPA 在桌面，SHA256 9de90448…1056。
- [x] 裝 136 後重跑地獄級、客戶場景、真人單句（11-16 臺北 00:00–08:24）；137 本機加 D36–D50（未推）。
- [x] 137 已編（build114 run 43784054492，單元測試 823 個 0 失敗），IPA 在桌面，SHA256 12e094b8…88ef。
- [x] 裝 137 後重跑地獄級 y／z、客戶場景與真人單句（11-16 臺北 09:30–20:25）；138 本機加 D53b、D56–D73（未推）。
- [x] 138 已編（build114 run 43867081019，6c71328），IPA 在桌面，SHA256 d52df386…da46；單元測試只有 D59 一個失敗（測試沒給 planner），本機已修（856b863，未推）。
- [x] 裝 138 後重跑真人單句、客戶場景、地獄級 y／z（11-16 臺北 21:09 – 11-17 11:21）；139 本機加 D74–D92（build123，未推）。
- [ ] z3–z6 因手機網路中斷沒跑完（臺北 12:32 補跑 z3 仍斷網；原因是手機上 Shadowrocket 的本機代理 127.0.0.1:1082 沒回應），使用者重連代理後補跑。
- [x] 推 139（build139-ci afb469c → build114 main，run 44020841388：編譯成功、856 個單元測試 0 失敗）；IPA E:/桌面/Lan-Agent-build139-unsigned.ipa（三個 bundle 皆 139；SHA256 6f98a90f20524a8b563c3c430845d9ed6d22343a6b6a24043a68c6094da752f4），138 的已送回收筒。
- [ ] 裝 139 後補跑 z3–z6，驗 D74–D92（z3 已跑：部分失敗，43 → D94；13:22 草稿被送出 → D93）。
- [x] 140 已編（run 44084828974，864 測試 0 失敗），IPA 在桌面。
- [x] 裝 140 重跑 z6：79 分鐘部分失败（8 項沒做完），D97/D98/D100/D101 實機有效，快取命中 56%。
- [x] 141 已編（run 44105681998，build114 main 5668b95）：869 測試 1 個失敗——D106 的列表解析（ICU 的 \p{Han} 把「、」也算進去，「北京、首」被當成一個名字）；本機 38fc133 改用 [\u4E00-\u9FFF]，下一版帶上。IPA 在桌面。
- [x] 142 已編（141＋D106 列表修正；run 44108998080，build114 main ddc41f3）：869 測試 0 失敗，IPA 在桌面。
- [ ] 裝 142 重跑 z 題量 D102/D105 提速；使用者配合實測 D104（先做／等会／不回）。
- [x] 143 推上 CI（D103b、D105b、D108、D109、D110；run 44130067456）。
- [ ] 144 本機加 D111（題目要發的話不准自己加字，除非題目說加時間）、D108b（上下滑在邊緣也從游標所在處出發）、Build117 測試更新；整輪 143 回歸結束、使用者點頭才推。
- [x] 144 已編（run 44250132452，882/0），IPA 在桌面。
- [x] 裝 144 後驗證：q143n、真人單句（結果見下）；D116 橫幅上滑仍待真機觸發；D104 使用者配合（未做）。
- [x] 144 日常回歸（11-18 15:35–17:20 首爾，散熱夾已拿掉）：q143n 兩輪＋真人單句 q134h 兩輪，共 74 題，核對後 66 題對、7 題錯或失敗、1 題存疑。iOS 溫度等級 15:3x 起一直 serious，App 被暫停 11 次共約 80 秒；r144h2 h15 回報「iPhone 溫度過高已暫停充電」。
  - 錯／失敗：n01 深圳明天下雨兩輪都讀成下週四（60%、17–24°；明天其實 17–20° 多雲）；r144h h01 今天讀成下週三（55%、19°；今天 19–28°）；r144n n08 高德答案對卻被「沒進過高德」退三次判失敗；r144n2 n16 第一屏已看到三條 143夜测一，往上翻後越翻越舊，答「沒找到」；r144h2 h03 微信停在上一題翻到的週日位置，把畫面底部當最新一條；r144h2 h21「北京明天最高13度」被測試腳本拒絕沒發出。
  - 存疑：h21 北京明天最高溫兩輪讀到 8° 和 13°，其中一次應是下週四那行（無截圖可證）。
  - 新動作：D120 同點三次拒絕觸發 2 次、有效；D113 截斷答案拒絕觸發 1 次；D116 橫幅上滑沒觸發（144 上只出現一次微信橫幅，2.5 秒自己收起）；D121 日曆快滑沒生效（手機上叫「行事曆」），月份要慢滑 4 次。
- [ ] 145 本機已修並提交（未推，等使用者點頭）：D121b 行事曆也快滑；D122 記住的路線點圖示帶標籤，算進過該 App；D123 往上讀照實寫讀到／到頂沒讀到／還沒讀到；D124 聊天裡想看較新的訊息卻手指往下滑：拒絕並說方向（每輪最多 2 次）；D125 問最後／最新一條、聊天是重開時停在原位：先拒絕一次要求滑到底；D126 天氣 10 天預報「今天」「明天」規則（App 規則＋收尾檢查）；D127 題目的「X 換成…」填好後就是題目要發的那句（手機端與 cloudq.py 都改）。
- [x] 144 情境題＋長任務（11-18 17:50–21:07 首爾，q144s 10 題、q133x 6 題）：情境 5 題對（京東、收藏、往上讀、小紅書步驟、抖音停在發布前），麥當勞沒裝、使用者規則拒絕下載；s1 丰巢要登入，發測試群被測試腳本拒絕，答案只剩「未獲批准」；s2 高德比 10 家川菜資料齊但查評價時清單位置跑掉、點「完成」沒反應而失敗；s3 建群在群資料頁與聊天頁來回 60 步、步數用完；s4 改備註**把兩個好友都改成 144测试备注**（原「137测试备注」與「主人蓝海乐」，第二個是誤改，需使用者決定是否改回）。長任務 x1、x2、x3、x6 做完（x3 建了兩條 X3组记录；x6 第 23–25 項讀錯：評分讀成評分人數、Safari 第一個結果讀成分頁標題、搜 X5组记录 把別的筆記當搜到），x4 第 14 項起整題失敗，x5 饿了么沒裝、拒絕下載後結束。
- [ ] 145 本機再提交 d4f51b1（未推）：D128 goalApps 加提醒事項／高德／Safari；D129 繞圈點擊的歷史與計數不跨項；D130 記失敗前先關掉已記錄的項（x4 把第 12 項記成未完成）；D131 天氣搜城市預覽頁（取消／加入）；D132 Codex 判定做不成（登入等）不扣跳過額度；D133 往上讀到某日期，一週內也找微信的「昨天／星期X」；D134 目標設的備註／名稱存檔後不准再輸入第二次；D135 「：未完成，原因」算有原因、「第3、4项」算引用別項；D136 備忘錄搜尋部分符合、Safari 第一個結果、App Store 評分 vs 人數；D137 訊息沒批准也回報已查到的內容。
- [x] 使用者 11-18 21:50「修好一次性推」：上一行剩下的也修了（4c03c6d）：D138 捲動筆記只在計畫項的 App 在前景時才標項號、同內容不換標籤重記；D139 往上讀的時間行補上算出的日期（昨天 晚上9:47（11月17日）），並要求照從舊到新寫；規則：微信從群成員建新群（选择一个群／搜尋，名字截斷照記）、高德清單會隨地圖重排（已記下的店用搜尋店名重開）、「如果…就發 A，否則發 B」條件查不到就兩句都不發。
- [x] 145 編好（11-18 21:50 首爾）：第一次 CI run 44303807174 有 2 個新測試失敗（numberedItems 要連號的測試寫法；D140 真 bug：搜尋字「深圳天气」「高德地图」被當成要進的 App），修好 72f5242 後重推 run 44305973195 全過（895 個測試）。IPA 在 E:\桌面\Lan-Agent-build145-unsigned.ipa，SHA256 da0b7a47ba2daf447f12169bd9f77538d2bfdb8e2e5bbf63b213485e0462ad71，CFBundleVersion 145。
- [x] 145 回歸（11-18 22:17 – 11-19 02:32 首爾，chain145）：日常 15/16（n01 天氣點到下週四）、真人單句 21/21、情境 4/10（s1 丰巢要登入停下＋不發送屬正確；s5 收藏為空、s9 沒裝麥當勞拒下載屬正確；s2 高德清單重排記了 15 家以上步數用完、s3「选择一个群」只開群名片、s7 小紅書結果重排＋拿早前運行的結果）、長任務 x1 x2 x6 成功，x3 01:04 iOS 停掉螢幕共享、x4 提前寫備忘錄（編造第 3、4 項）＋提前發「X4全部做完」＋跳過額度用完，x5 沒裝饿了么拒下載屬正確。144 的 IPA 已送回收筒。
- [x] 本機修好未推（03e6b66）：D141 先打結果／先發全部做完會被拒；D141b 跳過之後有新進展就退還額度；D142 拿早前運行的結果不算完成；D143 往上讀遇到不動先等再滑兩次；規則：天氣今天不在畫面、日詳情頂部日期列；微信建群用搜尋勾人；會重排的清單先從列表記；淘宝搜尋結果返回；計算器結果上方是算式。
- [x] x3、x4 重跑（11-19 02:33–03:43 首爾，r145x2）：x4 成功（28 項全做完，44 分鐘；第 17 項電池這次過了）；x3 失敗：美團要登入第 1–4 項跳過，第 6 項「X3外卖合计N元」沒有數字，模型自己編「X3外卖合计无法计算…」被拒，整題結束；「X3全部做完」也先發了。修在 42c299d（D144：有數字的指定訊息不照格式打會被拒，並教它記「未发送」說明原因）；先發全部做完由 D141 擋。
- [x] 使用者 11-19「先拉取到最新的執行記錄再寫新版本」：USB 接回後拉到 x3、x4 重跑的執行記錄（20261119-013308、20261119-015557），再修 a67cc2e：D145 沒發的指定訊息已在筆記說明就不再催發（x3 第 6 項）、D146 同一次不再新建第二條同標題備忘錄、D147 讀群訊息的筆記內含 1. 2. 3. 也能保住該項（x4 第 20 項被改成自己後來發的訊息）。
- [x] 使用者 11-19 04:00「都修好」：取消 CI run 44374491841，再修 3c11fb8：D148 加購成功的筆記帶上第N項（x4 第 6 項重做近 200 步）；規則：App Store 評分在 App 名稱下那排小資訊、清單裡標「广告／赞助／推广」的不算、設定裡底部那行點了沒反應先把清單往上移再點。螢幕共享斷掉：App 已有「等夠久就推通知」，iOS 不讓背景重開共享，只能使用者重開。
- [x] 146 編好（11-19 04:20 首爾）：CI run 44375290780 成功，單元測試 901 個 0 失敗。IPA 在 E:/桌面/Lan-Agent-build146-unsigned.ipa，SHA256 a3748c012540082d1b337aa2bec9603388c018bfe20ca21e7f749b3870d32caa，CFBundleVersion 146。
- [x] 使用者 11-19「token也是錢」「板子動作也優化一下加速」：146 不裝，改出 147。D149（1fb5575）每步少送重複文字：計畫只列沒做完的部分、已完成部分不重複結果（在筆記）、畫圖座標只給畫圖任務、400 字以上的題目放進系統提示詞走前綴快取；D150（2115452）板子：曲線模式每次連線只問一次、App 圖示連續點不中時改用搜尋 1→2→4 次（點中一次就恢復點圖示）。145 實測：每步 1.6 萬輸入 token（快取 66%）、每步中位數 6.4 秒（截圖 0.6、模型 2.3、板子 1.9）。
- [x] 147 第二次 CI 44381158456 失敗：pointer-motion 測試包的 HIDDevice 沒有 links，且 testAResetBoardRestoresBezierBeforeAnotherGesture 要求每次手勢前都查曲線模式（板子被重設成 off 要先改回）。D150a 撤回（fdae942），D150b 保留。
- [x] 使用者 11-19「必須走曲線…起點不固定…只有終點固定對了就行」「現在改進 147」：韌體已是隨機貝塞爾（轉折點 30–59%、控制點 80–119%，終點準）；取消 CI 44382015083，加 D151（a75b244）：右側（x>0.75）與最下排（y>0.9）的點擊也從游標停的地方出發，只有看到游標在目標上才點，看不到或偏了就照舊走邊框。145 裡 603 次點擊有 338 次先回角落（右側 198、最下排 110）。
- [x] 147 CI 44383333103：IPA 編出來了，但 StressNightTests.testAPartPassesOnWhatItFound 失敗（D149 把「部分 -> 查到的」拆開了）。修在 46d5517：partFocus 保留「部分 -> 查到的」，改成執行模型的筆記裡不重複那條。
- [x] build114 額度用完（CI run 44385883281 沒開跑）；使用者 11-19 給新倉庫 lanhaile6868-star/esp3200，設 remote build3200。
- [x] 147 編好（11-19 06:40 首爾）：build3200 CI run 44387620919 成功，單元測試 909 個 0 失敗。IPA 在 E:/桌面/Lan-Agent-build147-unsigned.ipa，SHA256 9ac85eb8c2c8e22eac1f0eeed522a6e5f463393110bbf855818d908c5c506640，CFBundleVersion 147。146 IPA（沒裝過）已送回收筒。
- [ ] 裝 147 後驗證：q143n、q134h、q145s、q133x；逐題比 145 的 token、用時與點錯率（右側、最下排）。145 的 IPA 等 147 跑過再送回收筒。下次推送 `git push --force-with-lease=main:f699943 build3200 buildNN-ci:main`。
- [x] 143 回歸問題清單（改完併進 144）：
  - 真人單句 21/21；客戶場景 5/10（s1 丰巢要授權、s5 收藏是空的、s9 沒裝麥當勞＝照規則停；s4、s7 是真失敗）。
  - s4 改備註：豆包把前幾輪留下的「137测试群」當「测试群」點進去還照做；收尾檢查擋下後，Codex 進了正確的「测试群（4人）」也一直以為成員資料來自錯的群，來回 20 多次到步數用完。方向：進到題目點名的群時明確告訴模型「現在就在題目的群」；豆包看到標題不是題目的群就不要照做。 → D115 已本機修：在聊天 App 裡每一步都說現在開著的群（或從它進的聊天信息頁）是不是題目點名的群；「137测试群」明說是別的群。
  - s7 小紅書：搜尋結果每次看都不同，收尾檢查拿現在的前三篇對照先前記的，判定記錯，重找到步數用完（142 z6 第 35 項抖音同因）。方向：收尾檢查規則——推薦／搜尋結果會變，先前記下的不因現在列表不同算錯。 → D117 已本機修：收尾檢查加規則，推薦／搜尋列表現在不同不算記錯。
  - D108b 已本機修（上下滑在邊緣也直接出發）。
  - z1（143）：75 分鐘部分失败；未完成 15（天氣逐時讀不到下午 3 點）、29（前 4 個最便宜＋規格無法核實）、30（拼多多單買／拼單價分不清）、35（購物車種類沒數完）、43（缺店名、月銷量）。y1 依使用者要求取消。
  - z2（143）：65 分鐘，48 項做完約 39；未完成 6、12、17、20、29、36、38、43。
  - z3（143）：78 分鐘，49 項做完約 40；未完成 16、19、24、27、34、37、41、45；33 發「Z3验证6:38」時頂部已是 6:39。
  - z4（143）：59 分鐘，48 項做完約 41；未完成 17、23、26、29、31、37。
  - z5（143）：41 分鐘做到約第 22 項，豆包帳戶欠費（AccountOverdueError）中斷；z6 與 q143n 第一題 15 秒就失敗，09:43（首爾）停測。
  - D112 已本機修：z5 第 11 項回報「意外加購兩次」是誤報。店鋪頁的「5000+人已加购」被當成加購成功提示；實際兩下是點店名和返回，沒有加購。
  - D112b 已本機修：卡住後規劃器為淘寶學到「點加入购物车看規格」的做法並存了；一個規格的商品點了就直接加購。會加購、下單、付款的做法不再保存，已存的也不再給。
  - 11-18 充值後：使用者決定 z5、z6 不重跑（z1–z4 已夠），只跑新日常單句 q143n。
  - q143n（143）：16/16 回報成功，14:14–14:33（首爾）共 19 分鐘，平均約 70 秒一題。逐題核對 13 題對；n12 答錯群（把测试群最新一條當成验证群的）；n07 小紅書標題、n15 抖音作者名帶「…」被截斷。
  - D113 已本機修：單句任務的 done 答案帶「…」截斷，退回一次要它點進去讀全。
  - D113b 已本機修：AgentLoop 跟 App 同生命週期，D107 截斷、括號算式、計算機筆記的「已退回」從沒清空，同一項目編號整個 App 期間只退回一次；改成每個任務重設。
  - D114 已本機修：單句任務只讀某個群，結束時畫面頂部群名不是那個群（或被橫幅擋住讀不到）就退回一次，並說先把橫幅往上滑掉、回聊天列表再進群。
  - D116 已本機修：n12 的 10001 簡訊橫幅一直不消失（「1分鐘前」），D103 等 6 秒後照點。現在真的橫幅（右邊有時間）等 6 秒還在，就在游標移過去前往上滑掉一次；滑不掉才當畫面本身的。要裝 144 真機驗。
  - z2–z4 未完成逐題查完（logs_143/traces 本機副本；手機上的已被覆蓋）：
    - D118 已本機修（z3 #27 淘寶排序）：跳點沒看到游標、點偏「綜合」；頁面卡片在動，每下都算「有變化」，不會改精準點。模型說上一下沒效果又點同一處 → 這下精準點。
    - D119 已本機修（z3 #34 天氣下午 3 點）：同一點按住 15 次都落在 5 點。按住也套「同點 3 次就拒絕」，並教它按時間標籤換算往左／右移。
    - D120 已本機修（z3 #13）：在微信視頻號裡以為不在微信，連續 open 微信 9 次。同一 App 連續第 3 次 open 拒絕，說明它就在這個 App 裡、用返回鍵。
    - D121 已本機修（z3 #24、#37 日曆）：月份視圖慢滑沒速度會彈回 11 月，連滑 7 次不動。日曆改快速一劃。
    - 規則（z2 #43、z3 #16）：小紅書視頻筆記上滑會切下一支，評論要點右下評論圖示。
    - 規則（z4 #31、z2 #12）：有附註的結果（仅看有票、起、只聽到一部分、只有字幕）算完成，不寫未完成。
    - z3 #41 淘寶加購卡住：根因是同任務前面「N人已加购」被誤算成加購一次（D112 已修）。
    - 不是 bug：listen 沒聽到口播的那幾支（視頻號 7 秒純音樂、新聞現場聲）照實回報；z2 #12 抖音播完自動切下一支。
    - 改不了：淘寶購物車被歷次測試加到 111 件，數種類要滑完整個購物車；拼多多頁面不顯示拼單價；App Store 載入不出；淘寶不顯示單品月銷量。
- [ ] 141 實機測 D104（使用者配合）：微信值守派外賣任務（只到確認訂單頁），中途在测试群發一條新指令 → 應問「要现在先做你这件吗」；(a) 回「先做」：外賣停下、先做新指令並回報、再接著做外賣到確認訂單頁並回報；(b) 回「等会」：外賣做完回報後再做新指令；(c) 不回：同 (b)。
- [ ] 裝 138 後重跑（z 組改用 q135y2.json），驗 D56–D73；D59 測試修正跟下一次推送一起跑。
- [ ] 豆包帳戶欠費：11-16 19:01（臺北）一次；11-18 約 09:41（首爾）又欠費，z5 中斷，等機主充值後接著跑 z5、z6、q143n、q134h、q137s。
- [ ] 改寫 17 個標 XCTExpectFailure 的過時測試（14 個 123 點名 App 守門、3 個 129 邊緣抬高）。
- [ ] 131 三波回歸跑完後逐組核對、整理 131 vs 130（group_report.py）。
- [x] 132 已編（run 43484673225，d8659d2），IPA 在桌面。
- [ ] 裝 132 驗：黃色按鈕一次就有反應、暫停提示每頁都看得到、Codex 頁顯示帳號名字／email／方案、帳號 1 自動用 gpt-6-luna、主畫面讀 0 頁不再全走搜尋、「stale plan: dropping」分布。
- [x] 132 三波 12 組跑完（11-14 04:01–07:51）：5 組全對、逐項約 93%；表與 133 候選在 docs/build132-summary.md 尾段。
- [x] 133 修正寫好（A1–A6；候選 6 重查不是 bug），docs/build133-summary.md。
- [x] 133 已編（run 43557478140，bd82e0c），IPA 在桌面。
- [x] 133 回歸＋高難度＋地獄級（docs/build133-regression.md）。
- [x] 134 已編（run 43613022596），IPA 在桌面。
- [ ] 裝 134 後重跑地獄級 q133y（chain133y.sh 改輸出 r134y），再跑舊三波。
- [x] 查：測試中使用者打開 Lan Agent，有時 holding、有時 home swipe 後 stopped（g2 vs g8）→ 132 修 X。
- [ ] Safari 在 Dock 只能搜尋打開（平均 50 秒）：移到主畫面或做圖示比對。
- [x] 128 兩輪 q128g 回歸（11-13）：約 77/80、73/80，數據在報告尾段。
- [x] 推 129 編譯：run 43368629752 成功，IPA 在桌面。
- [x] 129 同 4 組回歸：約 58/80，g8 失敗；問題總表 docs/build130-summary.md。
- [x] 130 編譯：run 43377447245 成功，IPA 在桌面。
- [x] 130 測四波 16 組（q128g、q130b、q130c、q128g）：總表 docs/build131-summary.md。
- [x] 131 編譯：run 43419650461 成功，IPA 在桌面。
- [ ] 使用者安裝 131 後三波再測。
- [x] 改用 lanhaile686-git 倉庫編譯 115：626/0，已放桌面。
- [x] 裝 115 後真機驗證：雲端橋接全通過；驗證群、天氣查北京對；價差題淘寶搜錯詞。
- [ ] 下一版一起改：灰色提示詞當成已輸入、主畫面點圖示開的 App 完成檢查認不出、拒絕發送後清掉輸入框。
- [ ] 碼錶類計時任務、豆包按錯計算機鍵、開發板偶爾斷線、發熱原因：未解決。
- [x] 112 真機 18 題逐題核對；build 113 修完，CI 610/0。
- [ ] 裝 113 後驗證：自動點取消、Codex 連線、m01、m08、m15，再跑一批新題並逐題核對。
- [ ] 查 Codex 為何全程逾時：先確認手機 Shadowrocket。
- [x] build 112 一次修完（指針、停止共享視窗、完成檢查），CI 608/0。
- [x] 裝 112 後驗證：淘寶搜尋欄、行事曆下週三都過；自動點取消沒過，113 已改。
- [ ] 手機 11 分鐘就到 thermal serious：確認客戶實際使用會不會有影響。
- [x] build 111 一次修完，CI 597/0；有 Codex 的 12 題對照完成。
- [x] 裝 111 後跑 q6 15 題新題並逐題核對：docs/stress-2026-11-09-build111-report.md。卡頓只剩 2 次 5 秒，最後的觸發點仍未證實。
- [ ] 使用者確認聯絡人權限（照片為完整取用）。
- [x] 裝 build110 後跑 q2e、q3，逐題核對畫面：docs/stress-2026-11-09-build110-report.md。
- [ ] 使用者恢復手機連 chatgpt.com 的網路，確認聯絡人權限；之後驗證真正的 Codex 表現。
- [ ] 使用者說改後，一次修完報告列的問題，只出一版；先查清滑動為何會變點擊。
- [ ] 全部測完：lan_usb release + disarm；新版驗證過後把桌面舊版移到資源回收筒（112 先留著）。

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
- [x] build97: watch sees new tasks on a still screen; WeChat red numbers only, no resuming read chats or old reports; keyboard waits; nearby pointer hops.
- [ ] Device test build97 (two tasks in a row; in-chat goes back to list; start drops old report; Return sends once; hop accuracy).
- [ ] Open questions: mirror "can't send commands in the app" + phone Wi-Fi; muted groups' red dot; redundant report after a reply-only task.
- [x] build98: app sends without a board mirror (direct capture); keep-awake while sharing; red marks (number or muted dot) open any chat, listed first, others read only.
- [ ] Device test build98 (send from the app; owner/listed task on red mark; muted group dot; other chat read only and back to list; phone stays awake).
- [x] build99: top list row and long previews seen; one misread char allowed; taps past the calibrated range from the right border; first watch check opens WeChat by URL.
- [ ] Device test build99 (owner's long task from the list; alarm ✓ hit once; watch start goes straight to WeChat).
- [x] Read the test phone over USB: iphone-pull-logs.cmd (pymobiledevice3 11.47.0).
- [x] build100: phone's own app names; dead taps tried around the spot; right-border y last; visible still-screen nudges.
- [ ] Device test build100 (alarm end to end, live over USB).
- [ ] caoshihui5211314-cloud Actions billing (user's account): until fixed, take IPAs from ChenQian-hub/esp32-iphone-agent-app.
- [x] Phase C (part): ChatGPT Plus plans, Doubao acts, Doubao fallback; steps per plan part (build101).
- [ ] Device test build101 (Plus signed in; the 3-part owner task end to end, live over USB).
- [ ] Phase C/D rest: scheduler, think parts in parallel, per-part results.
- [x] build103: closed-loop taps (Vision.arrival) + accuracy test.
- [ ] User runs Settings › 準度測試 on build103; pull "accuracy" lines over USB. Target: 20/20 within 1 %.
- [ ] Then step 2: Codex commanding per part (split, verify each part, take over when stuck); step 3: tools (AlarmKit, EventKit, URL schemes).
- [x] build104 built on lanhaiyue-web (542/0) and delivered.
- [ ] Live USB session: varied everyday tasks in several apps; collect all failures, fix by cause in one build.
- [x] build105 delivered (548/0).
- [ ] Next: stale plans / model latency (largest time sink), app icons learned from every scanned page, watch navigation speed.

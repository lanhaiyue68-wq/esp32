# 交接：小藍 iPad 版＋兩塊板子（2026-11-25 凌晨 2:10 首爾，Claude Code）

使用者睡前關掉視窗，明早開新視窗接著做。先讀這份，再讀 `progress.md` 最上面幾段。

## 一、使用者定案（不要再改方向）
- **小藍＝安卓 Echo，大藍＝iOS Pilot**（記憶 xiaolan-dalan-naming）。使用者要的是「**小藍 iPad 版**」：小藍的**全部功能**搬到 iPad，App 名字就叫小藍。**不要再做大藍**（使用者兩次糾正）。
- iPad 是客戶租的 **iPad 9（iPad12,1），已升 iPadOS 27.2.1**。介面要 **iPad 原生全螢幕**、不能有大黑邊（使用者特別提醒）。
- 要 **iOS 27 正式版**（有「共享整個螢幕」＝ScreenCaptureKit，`IPhoneAgent/Video/NativeScreenCapture.swift`，@available iOS 27），不要只給鏡像版。
- 語音板：大家共用，先叫先做、後叫自動排隊，**不准回「稍後再試」**；要發語音時才自動連。
- 計畫書：`docs/xiaolan-ipad-port-plan.md`（6 期：個微發訊息核心→個微群與好友→個微查詢→企微全套→守候接茬→通話朋友圈）＋技術設計段。

## 二、小藍 iPad 版現況
- 專案 `E:\AgentStorage\esp32\iphone-agent-build13`，分支 **build123**（不要 git switch main）。
- 新 target **XiaoLan**（`ios/project.yml`）：同一套原始碼、`PRODUCT_BUNDLE_IDENTIFIER $(IA_BUNDLE_ID).xiaolan`、輸入法 target **XiaoLanKeyboard**（`.xiaolan.keyboard`）、圖示 `Assets.xcassets/XiaoLanIcon`、編譯旗標 `XIAOLAN`（還沒用到）、`TARGETED_DEVICE_FAMILY "1,2"`、直向；兩個 target 都 `excludes: [Info.plist]` 避免帶到大藍的。版本 160。
- 還沒做的小藍功能：指令層。大藍已有 `Services/ChatToolLink.swift`（連 `ws://<電腦>:8881/webserver/wechat/<機器人ID>`，收 203 發訊息、由微信守候打字）→ 從這裡擴充成小藍全部指令；首頁換小藍畫面；接語音板協定。
- **應急版已出**：`E:\桌面\XiaoLan-build160-unsigned.ipa`（SHA256 745f7964…cf9b23c1），Xcode 26.3 編、**沒有**共享整個螢幕（二進位查過無 ScreenCaptureKit）。使用者說直接要 iOS 27 版，應急版可能沒裝。

## 三、CI（重要）
- 舊倉庫 `build3200`（lanhaile6868-star/esp3200）從 11-24 23:30 起 xcode-27 拿不到機器（158 是最後成功的）。
- **新 CI 倉庫：remote `build477` = https://github.com/lan477699-code/esp32 （私人，使用者給的）**。`main` = build123 的內容（直接 `git push build477 build123:main`，不用再疊 4fe5701 那個 CI 提交）。
- `ipa.yml`：推送預設**只編小藍**（commit 訊息含 `[pilot]` 才編大藍、含 `[tests]` 才跑測試）；手動觸發 `-f app=xiaolan|both`；失敗會印 log 尾。
- **自動重送**：`retry-xiaolan.yml` 每 30 分鐘（GitHub 的 Linux 機器跑）檢查 main 最新提交有沒有成功的 IPA、有沒有在排隊，都沒有就再送一次小藍。成功後自己停。
- 應急分支 `xiaolan-x26`：macos-15＋Xcode 26.3（探測：只有 macos-15 排得到；xcode-27／macos-26／macos-27／macos-latest 都排不到）。
- 睡前狀態：main 最新 0cff700，ipa run **45443865625** 排隊中（xcode-27）。

### 早上第一步
1. `gh run list -R lan477699-code/esp32 --workflow ipa.yml -L 5` 看有沒有 success。
2. 有就 `gh run download <id> -R lan477699-code/esp32 -n IPhoneAgent-unsigned-ipa -D <資料夾>`，核對 `ipa.sha256`，再確認 `Payload/XiaoLan.app/XiaoLan` 裡有 `ScreenCaptureKit.framework` 字串（有才是 iOS 27 正式版），Info.plist：小藍、UIDeviceFamily [1,2]、min 17.0。
3. 放桌面 `E:\桌面\XiaoLan-build160-ios27-unsigned.ipa`，請使用者用**爱思助手 › IPA簽名 › Apple ID**（帳密使用者自己輸入）裝到 iPad；新 App 要在「一般 › VPN 與裝置管理」信任；開發者模式已開。
4. 還是沒排到：繼續等（推測首爾上午美國下班後比較容易排到），不要動到別的帳號；可以先請使用者裝應急版測介面。

## 四、iPad 與測試通道
- iPad 用 USB 接電腦（pymobiledevice3：`%APPDATA%\uv\tools\pymobiledevice3\Scripts\python.exe`）。已裝：爱思全能版（com.ownbook.notes，允許電腦傳檔）、微信 8.0.80、企業微信、騰訊視頻HD、大藍 158（com.example.esp32agent.67AUY82AXY，Apple ID 開發簽名 7 天到期約 12-01）。
- 測試通道工具：`tools/ipad/lan_usb_ipad.py`（BUNDLE 已改成 iPad 上的大藍）。用法 `arm`／`status`／`frame out.jpg`／`board <板子指令>`／`g '<手勢 JSON>'`。**小藍裝好後要把 BUNDLE 改成小藍實際的 bundle id**（爱思簽名會在後面加一段，用 `pymobiledevice3 apps list --type User` 查），然後 `arm` 一次、小藍要完全重開才會開測試通道。
- 實測：板子 Wi-Fi＋AirPlay 鏡像通（大藍收到 720×960 畫面，`tools/ipad/ipad-pilot158-frame.jpg`）；大藍 iPhone 版在 iPad 是縮放視窗 → 校正時滑鼠「歸零」推左上角，使用者說會把通知中心拉下來。滑鼠推左緣沒副作用。**待測**：小藍全螢幕＋iOS 27 直接截屏下，`home`（推左上角）會不會拉下通知中心；會的話要改 iPad 的歸零角（`Agent/Pointer.swift`、`ProbeMotion.home`），座標是從左上角起算，改動要小心。
- 使用者不在 iPad 前時，不要用測試通道亂移滑鼠。

## 五、兩塊板子
- **滑鼠板** S3 N16R8「ESP32 Agent CEED」（韌體 v34，`E:\AgentStorage\esp32\esp32-iphone-agent`，藍牙 HID、只認一個主人）：已用 BOOT 長按 2 秒登記 **iPad 為主人**（iPhone 不能再用這塊，使用者之後另買一塊）。板子 Wi-Fi 由使用者在大藍設定頁設好。序列埠（COM5，原生 USB）要開 DTR 才回話：`E:\AgentStorage\esp32\voice-board\tools\serial_cmd.py COM5 --dtr '1 status'`；`tools/s3_watch.py` 看連線狀態。
- **語音板** WROOM-32E「Lan Voice 1DAE」（`E:\AgentStorage\esp32\voice-board`，ESP-IDF v5.5.6 在 `D:\AIProjects\esp-idf-env`，`.\idf.ps1 -p COM7 build flash`；燒錄偶爾要重試）：韌體 v2＝傳統藍牙耳麥（HFP）＋藍牙 LE 指令通道，多裝置共用排隊；協定 `docs/app-protocol.md`；已和 iPad 做過耳機配對（00:81:2a:2e:0a:a5）；iPad 的 LE 配對要等小藍 App 做好。目前播內建測試語音，之後改播 App 上傳的錄音（客戶聲音克隆要客戶書面同意）。
- 兩塊板子睡前接在電腦上或行動電源都可以。

## 六、安卓那邊（不要再碰）
- K40、K20 Pro 上的個微測試號都已被微信標記（空節點）；安卓個微自動化停止（記憶 android-wechat-automation-ban）。K20 Pro 上有改過伺服器位址的 WChat Tool（`E:\AIProjects\chattool-wechat-robot\signed\wcweb-4.3.7.5-localhost8881.apk`），已停。adb reverse 都拔了。

## 七、規矩
- 推送新版、改伺服器、出版前都要使用者點頭（這次「出新版」「直接一步到位」已同意 160 這一版）。
- 微信只在「测试群」測、看到安全提示立刻停、不代登入、不輸入任何密碼／Apple ID。
- 回覆用繁體中文；對使用者講 iOS 版叫「小藍 iPad 版」，別再叫大藍。

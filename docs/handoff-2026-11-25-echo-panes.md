# 新視窗交接：Echo（小藍 iPad）174 — 快又準、不碰上左下邊、刪除會話（2026-11-25 傍晚更新，Claude Code）

> **最新狀態（17:55）**：174 已編好（CI 45578426817，971 測試 0 失敗，Xcode 27.1），桌面只剩 `E:\桌面\XiaoLan-build174-ios27-unsigned.ipa`（173 已刪）。滑鼠板已是 v38。下一步：使用者用愛思裝 174 → 開 Echo、共享整個螢幕、校準 → 讀日誌 `ipad home: the arrow at`、`probe feedback check`、`slow pace ratio` → 分屏守候實測 → 找可刪的聊天實測「删除会话」（工具箱 290）。**173 在 v38 板子設定下不要校準。** 細節看第六節與 progress.md 最上面 174 段。

回覆一律繁體中文。先讀這份，再讀 `progress.md` 最上面四段（171、172、173）、`docs/xiaolan-engine-logic.md`。
上一份交接 `docs/handoff-2026-11-25-echo-ipad-night.md` 的事（滑鼠板備份、v35 燒錄、170 安裝）都已完成。

## 一、現在的狀態
- **桌面只有 `E:\桌面\XiaoLan-build173-ios27-unsigned.ipa`**（App 名 Echo，CI 45558705843，967 測試 0 失敗）。**iPad 上還是 170**：171／172／173 都還沒裝、沒實機測過。使用者用愛思簽名安裝（愛思「排隊中」＝覆蓋安裝前先備份 App 資料，現在約 81 MB，會慢）。
- 滑鼠板：v35 已燒、藍牙配對保留、`step` 指令正常，**可拔**。整片備份 `E:\AgentStorage\esp32\backups\mouse-board-v34-20261125\`（README 有 sha256 和燒回法；明天新板子燒這份給 iPhone 大藍，燒完長按 BOOT 2 秒重新認主人）。韌體 v35 原始碼改動**還沒提交**（`E:\AgentStorage\esp32\esp32-iphone-agent\hardware\hid_bridge\hid_bridge.ino`）。
- 模擬伺服器（node ×2，聽 0.0.0.0）：個微 `http://192.168.3.79:18971/zwt`、企微 `http://192.168.3.79:18970/qiwei`，代號 `xiaolan_ipad`，已經用 USB 填進 Echo（170）。只有訊息含「测试回复」才回「【模拟服务器】收到：…」。不在跑就照上一份交接第一節第 3 點重開。
- 程式：倉庫 `E:\AgentStorage\esp32\iphone-agent-build13`，分支 build123（別 switch），推 `git push build477 HEAD:main`（CI 在 lan477699-code/esp32）。最新提交 173。

## 二、這輪改了什麼（照使用者實測）
1. **171 指標**：170 校準全是直線、誤差 >1.5%（168 是 ±0.5%）。原因：iPad 歸零用 abort，板子不知道角落 → 板子畫的曲線只在方框內＝直線；170 移動 40、推邊 10，iPadOS 指標加速讓快的每格走 ~1.5 倍 → 歸零推不到角落（擬合偏移 0.15／0.20）。
   - 改成 iPad 所有移動同一步幅 10（`CommandChannel.padStep`，每次連線先送 `step 10`；測試通道 `/padstep` 可換步幅實測）；長於 300 單位、知道位置、沒按住的 `move` 改成 App 畫的貝塞爾曲線（`Board/PadCurve.swift`，偏 10–18%、方向隨機、控制點都在螢幕內）一個 `stroke` 送出；推邊仍直線。
   - 速度靠使用者把 iPad 跟踪速度拉最快（日誌：螢幕從 3900×5300 變 ~1733×2380 單位）。**還沒實機驗證準度與曲線。**
2. **171 守候**：按守候後停在 Echo 主頁（那一刻 iOS 在問區域網路權限，跳微信那步被略過，之後 Echo 在前就一直暫停）→ Echo 在前面時自己用網址開微信。
3. **172 分屏同時守候**（使用者：個微企微都要、同時、左右不固定、寬窄不一定、中間有縫）：
   - `App/XiaoLanPanes.swift`：找縫切兩個視窗（兩條貼近的全高直邊）、視窗底到 Dock 上緣、分頁列認 App（通讯录＋发现＝微信；工作台／邮件＋文档＝企微）、列表／聊天判斷（企微標題下的「外部群｜群主」不算標題）、頭像右上角紅點（行业资讯、企业微信团队等系統項目略過）、輸入框由下往上找白框（企微上面那排白按鈕不點）。
   - `App/XiaoLanPaneWatch.swift`（`#if XIAOLAN`，iPad 時 startWatch 改跑 `paneWatchLoop`）：每輪兩個視窗都看（~1 秒一輪）；紅點→點開→讀新訊息→回報該 App 伺服器（101＋QA）；伺服器回覆／203 在該 App 視窗打字（小藍輸入法）送出並確認；聊天安靜 8 秒回列表。
   - 實測截圖量的數值寫在 `XiaoLanPanes.swift` 開頭註解（960×1280 frame：縫 0.494–0.506、視窗到 0.898、微信聊天底 237、企微底 (236,237,241)）。
4. **173**：
   - 誰發的泡泡改看頭像在哪邊（`WatchOCR.bySide/avatarSide`，企微泡泡兩邊都可能白；縫旁視窗陰影不算頭像；用兩張真截圖驗 6 例全對）。
   - 分屏搜尋：列表看不到的會話點該側搜索框→小藍輸入法打名字→點結果；搜尋頁（有「取消」）不當聊天讀，守候看到就按取消回列表。

## 三、下一步（照順序）
1. 使用者用愛思簽名裝 173 → 開 Echo、共享整個螢幕 → **重新校準**。看日誌：`ipad: the screen is about W x H units`、`probe N … → (x, y)`、`calibration: touch probe span … residual`（要 ~1% 以下）、`calibration: ±x%`；使用者看移動是不是曲線。若 10 準但嫌慢：`lan_usb_ipad.py padstep 14`（或 20）再 `calibrate`，找最快還準的步幅。
2. 守候實測：微信、企業微信左右分屏（設定 › 多任务与手势 › 窗口化 App；三個小圓點選左／右半邊），兩邊停在列表，兩邊鍵盤都切小藍 → Echo 按守候 → 用手機在 测试群、企微测试群 各發「测试回复 你好」→ 應各自回「【模拟服务器】收到：你好」。讀 `debug.log` 的 `watch:` 行；模擬伺服器記錄在 `E:\AIProjects\worktool-lan-watch\tests\device-tools\mockgeren.jsonl`／`mockqiwei.jsonl`。
3. 依實測修：紅點誤判（頭像本身有紅色）、企微「我」的泡泡、小藍輸入法在企微能不能打字、Echo 在前面時只開微信（分屏能不能自己恢復未驗證）、搜尋結果頁版面。
4. 之後：@ 成員、其他指令固定步驟、總網關接茬、首次設定精靈還是大藍頁面、提交韌體 v35。

## 四、工具（電腦端）
- pymobiledevice3 的 python：`%APPDATA%\uv\tools\pymobiledevice3\Scripts\python.exe`；工具 `tools\ipad\lan_usb_ipad.py`：`status`、`frame <檔>`（共享畫面截圖）、`steps`、`servers '<json>'`、`padstep N`、`calibrate`（**會動 iPad 游標，只在使用者在場時用**）、`board '<指令>'`。
- Echo 在背景被 iOS 暫停時測試通道連不上（usbmuxd Connect 被拒）：請使用者點開 Echo 一下再切回分屏（通道用過一次會保持背景音訊不被暫停）。
- 讀 iPad 日誌：house_arrest 讀 `/Documents/debug.log`（`lan_usb_ipad.afc()` 再 `get_file_contents`）。
- 截圖、量顏色：PIL；這輪的截圖在本機暫存，可能被清掉，需要就重截（使用者已同意為守候截 iPad 畫面）。

## 五、定案（不要再改方向）
- 名稱 Echo、K40 小藍圖示；**不用模型**（照智微兔／智企微行）；接茬等由總網關叫模型（未接）。
- 滑鼠：貝塞爾曲線、從上一點出發、要快但要準；推邊只推一點點、直線。
- 個微＋企微**分屏同時守候**，左右與寬度每次從畫面判斷。
- 出新版刪舊版（桌面同 App 只留最新）；推送前問使用者（這輪都同意過）。

## 六、2026-11-25 傍晚（Claude Code 新視窗）：曲線與速度
- 原因：v35 韌體每格「每軸各最多 N」→ 斜走 (N,N) 比直走快 1.41 倍，曲線成 45°＋直線階梯，iPad 加速讓曲線落點偏 4–7%。
- **韌體 v36 已燒**（只燒 0x10000 程式區，配對保留；`build-v36/`，原始碼未提交）：新指令 `round on|off`（不存，開機 off）＝每格沿線、等長，各方向同速。主機測試 `hardware/tests/test_motion_curve.cpp` 已過（g++ 在 C:\msys64\ucrt64\bin）。燒法：使用者按住 BOOT 點 RST → COM4 → `esptool --chip esp32s3 -p COM4 --before no_reset --after no_reset write_flash 0x10000 build-v36/hid_bridge.ino.bin` → 使用者按 RST 回 COM5。自動重置進不了下載模式。
- **App 174 未推**（Shared.xcconfig=174）：每次連線送 `round on`；iPad 回角落改一段 `move -(x+m) -(y+m)`；iPad 滑動照大拇指（左半往左彎、右半往右彎、橫滑往下彎，PadCurve.thumbEnd/thumbPieces，WatchModeTests 有測）。
- 實測（round on，Echo 校準畫面，frame 中位數背景找箭頭）：每格 10 落點檢查 0.5/1.0/0.8/3.3%；**每格 20**：從上一點跳 0.3–1.3%、回角落後 1.8–3.9%，±0.7%，比 173 快一倍；每格 25/30/40 校準失敗。
- **新發現**：每格 ≥25 快速往左推邊會叫出「台前調度」左側最近 App 列（校準點擊被擋＝25/30 失敗主因）→ 推邊（左／上／下）一律要慢。
- 每格 30 純移動（不推邊）非常穩：≥480 單位線性 0.349 px/單位（960 寬 frame）；短的起步少走：120→26、240→63.6、360→106、480→169 px；20 次只 1 次多走 +20 px。每格 40：每格約 72 px，但約 1/7 次多走 +35 px（約 3.6% 寬）。
- 使用者嫌每格 20 仍慢（要 170 直線那種速度）。下一步建議：移動用每格 30（短距離查表）＋推邊用慢速（推邊距離要換算慢速增益），或先試 `coex bt` 看每格 40 的多走是否消失（量到一半 iPad 畫面被切到設定，資料作廢）。

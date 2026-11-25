# 新視窗交接：Echo（小藍 iPad 版）＋滑鼠板韌體 v35（2026-11-25 深夜，Claude Code）

先讀這份，再讀 `progress.md` 最上面幾段、`docs/xiaolan-engine-logic.md`。回覆一律繁體中文。

## 一、舊視窗還在跑的（新視窗先檢查，不要重複跑）

用 `tasklist | findstr /i "esptool arduino-cli node"` 看。

1. **滑鼠板完整備份（最重要）**：esptool 正在把滑鼠板整片 16 MB 快閃讀出來，讀完才寫檔：
   `E:\AgentStorage\esp32\backups\mouse-board-v34-20261125\mouse-board-v34-full-16MB.bin`
   - 板子（S3 N16R8「ESP32 Agent CEED」，MAC 44:1b:f6:fd:ce:ec）在**下載模式、COM4**（平常跑韌體時是 COM5）。**完成前不要拔、不要按 RST。**
   - 若被中斷（esptool 不見了、檔案不存在或不是 16,777,216 bytes）就重跑：
     `D:\AIProjects\esp-idf-env\.espressif\python_env\idf5.5_py3.13_env\Scripts\esptool.exe --chip esp32s3 -p COM4 --before no_reset --after no_reset read_flash 0 0x1000000 <上面的檔名>`
     （板子若已不在下載模式：請使用者按住 BOOT、按一下 RST、放開 BOOT；自動重開機的方式對這塊板子都無效，試過 1200 鮑率、usb_reset、default_reset。）
   - 讀完要**驗證**：`… verify_flash 0 <檔名>`（或再讀一次比 sha256），把 sha256 寫進同資料夾 `README.txt`，並寫明燒回方法：`esptool --chip esp32s3 -p COMx write_flash 0 mouse-board-v34-full-16MB.bin`。
   - 用途：**明天新板子到了，燒這份給 iPhone（大藍）用**；燒完新板子會以為主人是這台 iPad，要長按 BOOT 2 秒重新認 iPhone 當主人。
   - 同資料夾已有 `hardware-source-v34.zip`（改 v35 前的整份韌體原始碼）與 `source-git-head.txt`。
2. **v35 韌體已編好**：`E:\AgentStorage\esp32\esp32-iphone-agent\hardwareuild-v35\`（`hid_bridge.ino.merged.bin` 8 MB 從 0x0 燒；二進位內有「v35」與 `step 2..127`）。工具 arduino-cli 1.6.0 在 `D:\AIProjectsrduino-cli`（設定檔 arduino-cli.yaml：資料、下載、建置快取都在 D 槽；核心 esp32:esp32@3.3.12、NimBLE-Arduino@2.5.1，與之前建置相同）。**坑**：預設暫存在中文使用者資料夾，連結器寫不出檔 → 一定要加 `--build-path D:/AIProjects/arduino-cli/build/hid_bridge`。重編指令：
   `D:\AIProjectsrduino-clirduino-cli.exe --config-file D:/AIProjects/arduino-cli/arduino-cli.yaml compile -b "esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=8M,PSRAM=opi,PartitionScheme=default_8MB" --build-property "compiler.cpp.extra_flags= -include E:/AgentStorage/esp32/esp32-iphone-agent/hardware/hid_bridge/nimble_cfg.h" --build-property "compiler.c.extra_flags= -include E:/AgentStorage/esp32/esp32-iphone-agent/hardware/hid_bridge/nimble_cfg.h" --build-path D:/AIProjects/arduino-cli/build/hid_bridge --output-dir E:/AgentStorage/esp32/esp32-iphone-agent/hardware/build-v35 E:/AgentStorage/esp32/esp32-iphone-agent/hardware/hid_bridge`
3. **電腦模擬伺服器**（node ×2，聽 0.0.0.0）：個微 `http://192.168.3.79:18971/zwt`、企微 `http://192.168.3.79:18970/qiwei`。舊視窗關掉就會停，重開：在 `E:\AIProjects\worktool-lan-watch\tests\device-tools` 設 `WS_MODULE=E:\AIProjects\worktool-lan-watch\suite\backends\zhiqiweixing\node_modules\ws`、`MOCK_HOST=0.0.0.0`，分別 `MOCK_PORT=18971 MOCK_LOG=mockgeren.jsonl` 與 `MOCK_PORT=18970 MOCK_LOG=mockqiwei.jsonl` 跑 `node mockqiwei.js`。它有 `/robot/robotInfo/get`（回調指回自己）與 `/qa`（**只有訊息含「测试回复」才回**「【模拟服务器】收到：…」）。Windows 跳防火牆詢問要使用者按允許。

## 二、接下來（照順序）
1. 備份完成並驗證 → 告訴使用者備份好了。
2. **燒 v35**（使用者已同意）：板子在下載模式時 `esptool --chip esp32s3 -p COM4 write_flash 0 build-v35/hid_bridge.ino.merged.bin`（或分開燒 bootloader 0x0、partitions 0x8000、boot_app0 0xe000、app 0x10000），再請使用者按 RST；回到 COM5 後用 `E:\AgentStorage\esp32\voice-board\tools\serial_cmd.py COM5 --dtr '1 status'` 看版本 v35、`step` 回 `ok 40`。確認後才告訴使用者可以拔板子。
3. 使用者裝 **170**（`E:\桌面\XiaoLan-build170-ios27-unsigned.ipa`，App 名「Echo」），iPad 接 USB：
   `py tools\ipad\lan_usb_ipad.py servers "{\"serverOn\":true,\"serverURL\":\"http://192.168.3.79:18971/zwt\",\"robot\":\"xiaolan_ipad\",\"weworkOn\":true,\"weworkURL\":\"http://192.168.3.79:18970/qiwei\",\"weworkCode\":\"xiaolan_ipad\"}"`
   （用 pymobiledevice3 的 python：`%APPDATA%\uv\tools\pymobiledevice3\Scripts\python.exe`；工具的 BUNDLE 已是 com.example.esp32agent.xiaolan.67AUY82AXY）
4. 使用者把 iPad「设置 › 辅助功能 › 触控 › 辅助触控 › 跟踪速度」拉到最快 → 在 Echo 重新校準（共享整個螢幕要開）。讀日誌：`ipad: the screen is about W x H units`、`probe …`、`calibration: ±x%`。日誌讀法：house_arrest 讀 `/Documents/debug.log`。
5. 测试群實測：守候讀訊息、工具箱發消息、QA（發「测试回复 你好」）。iPad 微信鍵盤要切「小藍」輸入法。

## 三、這兩天的定案（不要再改方向）
- 名稱 **Echo**、圖示照 K40 安卓小藍（深藍底 #0B1030、大藍圓、小淺藍圓、白點）。
- **不用模型**：照智微兔／智企微行（`docs/xiaolan-engine-logic.md`）。回覆由伺服器 QA 回調或指令決定；讀聊天用裝置上文字辨識＋泡泡底色；發訊息用搜尋＋輸入框＋快速發送；其他指令沒固定步驟前回「還沒有固定步驟」，不偷叫模型。接茬這類由總網關叫模型（還沒接）。
- **滑鼠**：貝塞爾曲線、從上一次的位置直接過去、要快（記憶 pointer-curve-from-last-spot）。iPad 推過頂邊太多拉通知中心、推過底邊太多回主畫面、韌體高速 home 也會；推邊只推螢幕高 ~5.7%，而且用慢步幅（v35 `step slow`）。
- **出新版就刪舊版**（記憶 delete-old-builds-on-release）；推送／出版前問使用者（這輪都同意過）。

## 四、版本與位置
- 專案 `E:\AgentStorage\esp32\iphone-agent-build13`，分支 build123（別 switch main），CI remote `build477`（lan477699-code/esp32）main。最新程式提交 5017efd（170），CI 45547991191：965 測試 0 失敗。
- 170 內容：iPad 移動一段曲線（ProbeMotion.onePiece）、校準只開頭歸零一次之後從上一點出發、定位多點一下量螢幕單位、推邊量按比例、v35 推邊切慢、測試通道 `/servers`、Echo 名稱圖示、QA 回調、文字辨識讀聊天、搜尋發訊息。
- 韌體 v35 改在 `E:\AgentStorage\esp32\esp32-iphone-agent\hardware\hid_bridge\hid_bridge.ino`（**未提交**；那個倉庫原本就有一堆未提交的 v34 修改）。
- 電腦 IP 192.168.3.79（WLAN）。iPad 9、iPadOS 27.2.1。

## 五、還沒做
- 其他指令的固定步驟（@ 成員、群資訊、建群、改群…）、企微守候讀訊息、總網關接茬、首次設定精靈還是大藍頁面、v35 實機速度與準度驗證。

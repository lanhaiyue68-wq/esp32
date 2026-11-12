# 雲端橋接介面（iPhone 執行端）

依據客戶 2026-11-10 的《个人 AI 总调度与多设备助理系统》第 4.4、6.2、9 節。這份是 iPhone App（build 115 起）實際使用的介面；之後做雲端伺服器時，要照這份實作，或兩邊一起改。

目前沒有正式伺服器。測試用的模擬伺服器是 `tools/cloud-mock/mock_cloud.py`。

## 連線

- App 設定 > 云端任务：開關、伺服器網址、設備編號（預設 `home_iphone_01`）、設備金鑰。
- 金鑰存在 iOS 鑰匙圈，不寫進程式。每個請求都帶 `Authorization: Bearer <設備金鑰>`。
- 內容一律是 JSON。正式伺服器請用 HTTPS（客戶文件第 9.4 節）。
- 開關關掉時，App 不再發出任何請求；如果有雲端任務正在執行，會先停掉並回報 `cancelled`。

## 1. 心跳與領任務

`POST /api/v1/devices/{device_id}/heartbeat`，App 開關打開時每 5 秒送一次。

請求：

```json
{
  "device_id": "home_iphone_01",
  "app_build": "115",
  "timestamp": "2026-11-10T03:00:00Z",
  "running_task_id": "（正在執行時才有）",
  "capabilities": {
    "screen_capture": "available | unavailable | unknown",
    "hid_board": "available | unavailable | unknown",
    "pointer": "available | unavailable | unknown",
    "model": "available | unavailable | unknown",
    "app_foreground": "available | unavailable | unknown",
    "agent": "idle | busy"
  }
}
```

回覆：

```json
{
  "task": null,
  "cancel": ["要取消的 task_id"]
}
```

`task` 不為空時就是派給這支手機的任務：

```json
{
  "task_id": "uuid",
  "type": "phone_task",
  "input": {"instruction": "在微信打开测试群，发一句：你好", "want_screenshot": false},
  "requires_approval_before_external_action": true,
  "idempotency_key": "..."
}
```

- `instruction` 是要手機做的事，用一般說話的方式寫。
- `requires_approval_before_external_action` 沒給時，當成 `true`。
- `want_screenshot` 為 `true` 時，結束回報會附上最後畫面。

手機一次只做一個任務。伺服器在收到 `accepted` 之前，不應把同一個任務再派給別支手機。

## 2. 回報進度

`POST /api/v1/tasks/{task_id}/events`

每筆回報都帶 `task_id`、`device_id`、`timestamp`，再加上 `status` 和其他欄位：

| status | 什麼時候 | 其他欄位 |
| --- | --- | --- |
| `accepted` | 手機接下任務 | |
| `running` | 開始執行；之後約每 15 秒一次 | `progress.steps` |
| `retry_pending` | 手機在忙，或缺必要能力，沒有接 | `error_code`：`device_busy` 或 `capability_unavailable`；`detail` |
| `waiting_approval` | 要發送訊息，停在發送前等批准 | `approval_request: {"action": "send_message", "text": "..."}` |
| `succeeded` | 完成 | `result: {"answer": "...", "steps": n}` |
| `failed` | 沒做成 | `error_code`（原因）、`result` |
| `cancelled` | 被取消、被手機總開關停掉，或訊息沒獲批准 | `error_code`：`not_approved`、`stopped` 等 |

- 截圖欄位是 `screenshot_jpeg_base64`，只在任務要求時附上。
- 必要能力是 `screen_capture`、`hid_board`、`pointer`，任一項不是 `available` 就不接任務，回報 `retry_pending`。

## 3. 發送前批准

1. 雲端派來的任務要發送訊息時，App 停在按「發送」之前，先回報 `waiting_approval`。
2. App 每 3 秒查一次 `GET /api/v1/tasks/{task_id}`，看回覆裡的 `approval` 欄位：
   - `"approved"`：按下發送，回報 `running`，繼續做。
   - `"rejected"`，或任務 `status` 變成 `cancelled`：不發送，任務以 `cancelled` + `not_approved` 結束。
   - 10 分鐘內都沒有答覆：當作拒絕。
3. 同一則訊息批准一次就好，不會重複問。

## 4. 不重複執行

- 手機記住最近 100 個做完的 `task_id` 和它最後一筆回報。
- 同一個 `task_id` 再派過來，手機不會再做一次，只把上次的最後一筆回報再送一次。

## 5. 做不到的事（客戶文件第 6.2、13.8 節）

- 手機鎖屏、App 被系統關掉、或螢幕共享中斷時，收不到任務；心跳裡的 `capabilities` 會如實反映，伺服器應該排隊或降級處理。
- App 只在前台或背景還活著時送心跳。伺服器超過約 30 秒沒收到心跳，就當成離線。

## 6. 群收錄：上傳每日知識（build 125 起）

手機守候白名單裡的群時，會把群裡的圖片、影片、連結、檔案、轉發卡片在空閒時點開看，每天整理一次「乾貨」（行業經驗、資源連結、使用心得），用同一個伺服器位址和設備金鑰上傳：

`POST /api/v1/knowledge`

```json
{
  "date": "2026-11-12",
  "device_id": "home_iphone_01",
  "source": "wechat_group_archive",
  "items": [
    {"title": "一句話標題", "content": "要點（誰的經驗、什麼情況、怎麼做、結果）", "links": ["https://…"], "source": "测试群·张三"}
  ]
}
```

- 回 2xx 表示伺服器已收下，手機就刪掉那一天的原始紀錄和整理結果（手機只當暫存）。
- 回其他狀態碼或連不上：手機保留，約一小時後再傳。
- `items` 可能是空陣列（那天沒有乾貨），也請回 2xx。
- 伺服器收下後要存到它的知識庫、GitHub 或 Obsidian，由客戶自己決定。

## 7. 模擬伺服器用法

```
set MOCK_TOKEN=<一串夠長的隨機字>
py -3 tools/cloud-mock/mock_cloud.py --port 8787
py -3 tools/cloud-mock/mock_cloud.py --add "打开天气，告诉我现在的气温"
py -3 tools/cloud-mock/mock_cloud.py --approve <task_id>
py -3 tools/cloud-mock/mock_cloud.py --show <task_id>
```

模擬伺服器收到上傳時，會把那一天存成 `tools/cloud-mock/knowledge-<日期>.json`。

App 端：伺服器網址填 `http://<電腦的區網 IP>:8787`，設備金鑰填同一串 `MOCK_TOKEN`。手機和電腦要連同一個 Wi-Fi。iOS 對區網的 http 連線有限制，見下方「注意」。

## 注意

- iOS 預設不允許 App 用 http 連線（App Transport Security）。App 原本就為了連電腦上的 ChatTool 和知識庫，允許區網內的 http（`NSAllowsLocalNetworking`），所以模擬伺服器能直接用；連區網時 iOS 可能先問「是否允許尋找區域網路上的裝置」，要按允許。正式伺服器一定要用 HTTPS。

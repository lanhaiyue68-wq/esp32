# 智微兔／智企微行的底層邏輯（拆包結果）與小藍 iPad 版的對應（2026-11-25）

使用者要求：小藍要照智微兔、智企微行原本的邏輯做，「正常回覆不需要大模型，接話、監察這類模式才在後台連大模型」。以下是拆兩個包得到的結論與證據。

## 一、兩個引擎是同一套架構

| 項目 | 智微兔（個人微信） | 智企微行（企業微信） |
|---|---|---|
| 指令連線 | WebSocket `…/webserver/wechat/<機器人ID>` | WebSocket `…/webserver/wework/<編號>` |
| 機器人設定 | `GET /robot/robotInfo/get?robotId=` → `callbackUrl`（存成 `qaUrl`）、`openCallback`、`replyAll`、`robotType` | 同樣的 `qaUrl`、`openCallback`、`replyAll`、`replyStrategy`、`autoReply` |
| 手機裡有沒有大模型 | **沒有**（全包搜不到 deepseek／openai／gpt／大模型 等字樣） | **沒有** |

證據：個微 `chattool-apk-recovery/out/20260807-enhanced/jadx-deobf`（`e2/C1143a`、`i2/C1421g`、`j2/C1500t`、`j2/C1495o`、`com/example/wcweb/model/CustomMessageQueue`）；企微 `worktool-lan-watch/work/embedded-enterprise/apk/smali`（同名欄位 `qaUrl`、`spoken`、`rawSpoken`、`atMe`、`info`、`text`）；`chattool-apk-recovery/BACKEND_API_CONTRACT.md`。

## 二、手機做的四件事（都不用大模型）

1. **讀新訊息**：看聊天列表的紅點，進會話讀出新訊息（安卓用無障礙讀畫面上的文字節點）。
   - `autoReply`＝讀新訊息的總開關；`replyStrategy`／`replyAll`＝全部回或只回 @我；`robotType == 2` 關掉自動回覆。
2. **上報**：
   - WebSocket 送 `type 101`（訊息列表：會話名、roomType、每則訊息）。
   - 有設 `qaUrl` 就 HTTP POST 到 QA 回調，每則一筆：`{spoken, rawSpoken, receivedName, groupName, groupRemark, roomType, atMe, textType}`（`i2/C1421g`「推送消息列表到QA接口」）。
3. **照伺服器的回覆發訊息**：QA 回調當場回 `{"code":0,"data":{"info":{"text":"…"}}}`，`text` 不是空的，就組一個 `type 203`（發到同一個會話）丟進本地指令佇列執行（`j2/C1500t`「QA接口返回回复，加入本地发送队列」）。回空字串＝不回。
4. **執行伺服器指令**：WebSocket 收到 `socketType 2` 的指令（203 發訊息、206 建群…），照每個指令的**固定步驟**一步步點（`CustomMessageQueue` → `s3/ni` 的 `REQUEST sendMessage/initGroup/updateGroup…`），做完回 `socketType 3` 結果。

**回覆內容由伺服器決定**：簡單的走固定規則（關鍵詞、招呼），複雜的、接話（接茬）、監察這類模式才由後台叫大模型（使用者自己的後台：`worktool-lan-watch/suite/README.md`「自動回覆由北京總網關決定…複雜問題依可用性選 DeepSeek、豆包或 Codex」；智微兔銷售引擎在後台用 `ARK_API_KEY`）。

## 三、小藍 iPad 版 162 跟這套哪裡不一樣（要改的）

| | 引擎原本 | 小藍 162 | 要改成 |
|---|---|---|---|
| 回覆誰決定 | 伺服器（QA 回調） | iPad 上叫大模型寫回覆 | 照引擎：QA 回調，iPad 不寫回覆 |
| 讀新訊息 | 無障礙讀文字節點 | 截圖交給大模型讀 | 不叫大模型（見下） |
| 執行指令 | 固定步驟、找按鈕文字再點 | 交給大模型決定點哪裡 | 固定步驟（照 `s3/ni` 每個指令的步驟） |
| QA 回調、機器人設定 | 有 | 沒做 | 補上 `qaUrl`、`robotInfo/get`、`replyAll`、`autoReply` |
| 要不要填模型 | 不用 | 要 | 不用（大模型留在後台） |

**唯一不能原樣照搬的一點**：安卓的無障礙可以直接讀到「這裡是『發送』按鈕、這段字是誰發的」；iPhone／iPad 系統不准任何 App 讀別的 App 的畫面結構。小藍在 iPad 上只拿得到畫面影像，所以「讀畫面上的字」要靠 iPad 系統內建的文字辨識（Apple Vision，手機上離線執行、免費、不連網，小藍裡已經在用）來代替無障礙。其餘——固定步驟、QA 回調、指令格式、結果回報、大模型只在後台——全部照引擎原樣。

## 四、建議的施工順序

1. QA 回調與機器人設定（`robotInfo/get`、`qaUrl`、`replyAll`、`autoReply`、`robotType`），讀到的新訊息照引擎格式上報、照回覆發送。
2. 小藍不再要求填模型；守候的「讀新訊息」改成不叫大模型。
3. 指令執行照 `s3/ni` 的固定步驟逐個改寫（先 203／204／205、查群成員，再其他），每一步用畫面上的文字確認；每個都在 iPad 的測試群實測。

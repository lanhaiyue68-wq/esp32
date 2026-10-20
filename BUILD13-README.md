# iPhone Agent build 13：給 Mac 上 Codex 的編譯說明

使用者會自己處理簽名。你的工作是：產生工程、編譯、跑測試、出 IPA，並照實回報結果。

## 這是什麼

這是 iPhone Agent App 的完整工程，本身就是 git 倉庫。底子是原版 `onehumanbeing/esp32-iphone-agent` 的 68751e4，
上面依序套了歷次交付的補丁，每份補丁一個 commit：

| commit | 內容 | 來源 |
|---|---|---|
| 68751e4 | 原版 | GitHub |
| b8d60b6 | App v10＋配合固件 v21 的協定（Codex，由 68751e4 起算的累積版） | esp32-v21-app-v10-reliability.zip |
| 46aa8a6 | trace17 改進（Codex） | iphone-agent-trace17-improvements.zip |
| e0fcb85 | trace18 學習機制（Codex） | iphone-agent-learning-trace18.zip |
| b8333f8 | trace19 前台影像預檢（Codex） | iphone-agent-trace19-video-start.zip |
| 123faae | 審查修正：快照模式不開串流、斷線不算失敗、預檢後才播離場動畫（Claude Code） | iphone-agent-trace19-addendum.zip |
| （最新） | build 號改為 13、加入本說明與匯出設定範本 | — |

已在 Windows 核對過：
- 五份補丁依序都乾淨套上。
- 到 trace19 為止，`ios/` 和 `prompts/` 共 157 個檔，與 Windows 上 Codex 的工作樹逐檔一致。
- 97 個 Swift 檔的語法樹檢查（tree-sitter-swift 0.7.4）都沒有錯誤。
- **但從來沒有在 Xcode 編譯過。**

它**不是**手機上那個 build12 的原資料夾。Mac 端合併時若有過本機修改（編譯修正、版本指紋程式、簽名設定），這裡都沒有。

小板保持固件 v21，不用燒錄。`hardware/` 是原版 68751e4 的程式，不是板子上跑的 v21，不要拿去燒。

## 前置

- Xcode，需含 iOS 18 以上的 SDK（工程的最低版本是 iOS 18.0）
- XcodeGen：`brew install xcodegen`

## 步驟

### 1. 放好、核對

解壓到一個新資料夾，例如 `~/esp32-agent/iphone-agent-build13`，不要覆蓋任何現有資料夾。

```bash
cd ~/esp32-agent/iphone-agent-build13
git log --oneline -7     # 要和上表一致
git status --short       # 要是乾淨的
```

### 2. 簽名（使用者處理）

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

在 `Local.xcconfig` 填 `DEVELOPMENT_TEAM` 和 `IA_BUNDLE_ID`。

- **`IA_BUNDLE_ID` 必須和手機上 build12 的 Bundle ID 相同。** 相同才會覆蓋安裝，並保留 App 裡的模型設定、校準和學習紀錄。
  不同的話手機上會多出第二個 App，資料不會帶過來。
- 查手機上的 Bundle ID：iPhone 接上 Mac，執行 `xcrun devicectl list devices` 找到裝置，再執行
  `xcrun devicectl device info apps --device <裝置>`。也可以在 Xcode → Window → Devices and Simulators 的已安裝 App 清單裡看。
- `IA_ENTITLEMENTS`、`IA_WIDGET_ENTITLEMENTS`：一鍵加入熱點、Live Activity 共用 App Group 需要這兩項。build12 有開的話就照開。
  一鍵加入熱點需要付費開發者帳號，免費帳號就留空。
- `Local.xcconfig` 已被 git 忽略，不要提交。裡面如果有 `CURRENT_PROJECT_VERSION`，刪掉或改成 13。

### 3. 產生 Xcode 工程（必做）

```bash
cd ios
xcodegen generate
```

git 裡的 `IPhoneAgent.xcodeproj` 是原版的，不包含後來新增的 6 個檔：

- `IPhoneAgent/Services/ExperienceStore.swift`
- `IPhoneAgentTests/ExperienceTests.swift`
- `IPhoneAgentTests/ReliabilityTests.swift`
- `IPhoneAgentTests/Trace17Tests.swift`
- `IPhoneAgentTests/Trace18Tests.swift`
- `IPhoneAgentTests/VideoStartupTests.swift`

不重新產生工程，這些檔就不會被編進去。產生後 `git status` 會顯示 `project.pbxproj` 有變動，這是正常的。

### 4. 編譯＋測試（用模擬器，不需要簽名）

```bash
xcrun simctl list devices available | grep -m3 iPhone      # 挑一台模擬器
xcodebuild -project IPhoneAgent.xcodeproj -scheme IPhoneAgent \
  -destination 'platform=iOS Simulator,name=<上面挑的名稱>' test 2>&1 | tail -60
```

- 預期全部測試通過，其中 `VideoStartupTests` 應有 12 項。
- 遇到編譯錯誤：只做最小修正，不改行為。每一處記下「檔案:行號＋原因」，另外開一個 commit。
- 測試失敗：照實回報失敗原文，不要為了讓測試通過而改測試。
- 全部通過後提交重新產生的工程：`git add -A && git commit -m "ios: xcodegen for build 13"`

### 5. 出 IPA（簽名就緒後）

```bash
cp ExportOptions.plist.example ExportOptions.plist     # 填 teamID；method 的說明見檔內註解
xcodebuild -project IPhoneAgent.xcodeproj -scheme IPhoneAgent -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/IPhoneAgent.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/IPhoneAgent.xcarchive \
  -exportPath build/ipa -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

IPA 會在 `ios/build/ipa/`。如果只是要裝到自己的手機，也可以在 Xcode 裡選手機直接 Run，不一定要出 IPA。

### 6. 真機驗收

1. 裝上的是 build 13：匯出的 trace 裡應記錄 App 1.0 build 13，Xcode 的 Devices and Simulators 已安裝 App 清單也看得到。
2. 串流模式、鏡像正常時按開始：先播離場動畫 → 回主畫面 → 任務正常開始。
3. 重現 trace19：重開 App 但不重開鏡像，再按開始。應該不播動畫、不離開 App，幾秒內提示「停止鏡像再重選 ESP32」。
   照提示做完再按開始，要能正常跑。
4. 快照模式按開始：日誌和 startup 紀錄裡不應出現 `stream on`。
5. 任務中途關掉板子電源或熱點：應進入「等待板子」暫停，恢復後繼續，不應出現「3 errors in a row」。
6. 導出一次啟動失敗的 trace：startup 紀錄、error 步驟裡的 video 欄位、`metrics.json` 都要在。

## 不要做

- 改功能或加功能
- 燒固件
- 推送到任何遠端
- 提交 `Local.xcconfig`、`ExportOptions.plist` 裡的 teamID 或任何金鑰
- 宣稱畫圖精度已經修好。重開 App 後仍需手動重開鏡像，這個問題本版也沒有根治。

## 回報給使用者（繁體中文）

- `git log --oneline -8`
- xcodegen、編譯、測試的實際結果：通過數、失敗數、失敗原文
- 有沒有做編譯修正；有的話列出每一處
- IPA 路徑，或改用 Xcode 直接 Run 安裝的結果
- 第 6 節 1–6 項的真機驗收結果
- 沒做到或沒驗到的，照實寫

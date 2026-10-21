# iPhone Agent build 14：Mac 上的一次性编译说明

用户没有 Mac，每编译一次都要借电脑。这一版把要改 App 的东西一次改完，**以后改规则、改提示词不需要再编译**（见“以后不用 Mac 的更新方式”）。

## 这一版改了什么

1. **只走同一个 Wi-Fi，不再连小板热点**（配合固件 v22 以上，小板现在是 v23）
   - 删除 App 自动加入小板热点（NEHotspotConfiguration）的全部代码。
   - “同一个 Wi-Fi”的判断：小板报告已连上 Wi-Fi，并且手机的视频 TCP 已连到小板（状态里的 `tcp`=1）。不需要读取 Wi-Fi 名称的权限。
   - 引导页和 设置 › 开发板 里新增“把这个 Wi-Fi 发给开发板”：填 Wi-Fi 名称和密码，经加密蓝牙发给小板。小板连不上就一直等，不开热点。
   - 小板如果还是旧固件（会开热点），App 会提示升级固件，不会去连它。
2. **会从错误里学习（LessonBook）**
   - 回顾里写的备注、插入的步骤，自动变成“经验”，之后类似的任务（任何 App）会自动带进规划器和执行器的提示词。不需要“存为意图”。
   - 备注开头写 `通用：` 就对所有任务生效。
   - “让 AI 优化”点“接受”后，优化出的提示也会进经验库。
   - **每次任务结束自动自学**：模型复盘这次的全部步骤，找出偏差（点了没反应、点错目标、重试、撤销、重新规划、出错、求助、把不是自己做的结果当成果），
     每条经验写成“某 App 某处：不要……；改为……”，这次后来自己改对的，记改对的做法；禁止把错误本身写成规则；没有可靠教训就不记。最多 3 条，下次类似任务自动带入。
     它不允许自称“成功了”；自学经验排在用户经验之后（每次最多带 4 条，总共最多存 60 条）；用户在回顾里把这次某一步标错，这次的自学经验自动作废。
     每次任务多一次模型调用（约 1–2k token）。设置 › 隐私 的学习开关同时控制。
   - 设置 › 隐私 里的学习开关和“清除”同时管这部分。
3. **意图的提示现在也给规划器**（以前只给执行器，所以计划常常无视提示）。
4. **“重试”用回顾里最新的指令和提示**（以前用的是最初那句话，AI 优化的结果根本没用上）。
5. **画面一直在变时不再无限丢弃计划**：连续两次 stale plan 后按最新画面执行（trace 里曾白白浪费 30 秒）。
6. 执行器提示词加一条通用规则：本次操作之前就已经在屏幕上的结果不算自己的成果，不能据此报告完成。
7. **任务期间后台静音保活（BackgroundAudio）**：开始任务、离开 App 前播放静音（与其他音频混音，听不到、不打断音乐），任务结束即停。
   App 操控的是自己所在的 iPhone，工作时一定在后台；以前只有蓝牙后台模式，iOS 几秒就暂停 App，Wi-Fi 画面断掉、改走蓝牙而延迟，开始时常报 no verified current video frame。
   来电时让出、挂断后才恢复；铃声、通知、闹钟、其他 App 的音乐照常；不申请麦克风、不录音、不用听筒、不改输出路线；扬声器不独占（数字静音＋混音器音量 0，与其他声音混音）；任务开始时若正在通话，启动失败后每 5 秒重试。
   `UIBackgroundModes` 新增 `audio`。只适用于自签名/企业分发，上架 App Store 会被拒。
8. build 号改为 14；新增 21 条简体中文界面文字。

## 以后不用 Mac 的更新方式

App 的“文稿”文件夹（文件 App › 我的 iPhone › 本 App）里放文件即可生效：

| 文件 | 作用 | 何时生效 |
|---|---|---|
| `rules.md` | 追加给规划器和执行器的规则 | 每次任务 |
| `prompts/actor.md`、`prompts/planner.md`、`prompts/app-rules.md` | 整份替换内置提示词 | 下次打开 App |

## 步骤

### 1. 放好

解压到新文件夹，例如 `~/esp32-agent/iphone-agent-build14`，不要覆盖 build13 的文件夹。
把 build13 文件夹里的 `ios/Config/Local.xcconfig` 复制过来（签名设置，git 不收录）。没有的话：

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # 填 DEVELOPMENT_TEAM 和 IA_BUNDLE_ID
```

`IA_BUNDLE_ID` 必须和手机上现有 App 相同，才会覆盖安装并保留模型设置、校准和学习记录。
这一版不再需要“热点配置”权限，免费开发者账号也可以。

### 2. 生成工程、编译、测试

```bash
cd ios
xcodegen generate
xcrun simctl list devices available | grep -m3 iPhone
xcodebuild -project IPhoneAgent.xcodeproj -scheme IPhoneAgent \
  -destination 'platform=iOS Simulator,name=<上面挑的名称>' test 2>&1 | tail -60
```

- 新测试：`SameWiFiTests`（3 项）、`BackgroundAudioTests`（1 项）、`LessonBookTests`（8 项）；`ReviewTests` 里提示测试改名为 `testIntentHintsReachThePlannerAndTheActor`。
- 编译错误：只做最小修正，不改行为，记下“文件:行号＋原因”。
- 测试失败：照实回报原文，不要改测试去迁就。

### 3. 安装

Xcode 里选手机直接 Run 即可（或照 build13 说明出 IPA）。

## 真机验收（小板已是固件 v23，不用再烧）

1. 手机和小板连同一个 Wi-Fi：引导页“和开发板连同一个 Wi-Fi”打勾，屏幕镜像能选到 ESP32 Agent。
2. 关掉这个 Wi-Fi：小板状态显示在等这个 Wi-Fi；手机**不会**跳去连 ESP32Agent 热点；Wi-Fi 恢复后小板自己连回。
3. 设置 › 开发板 › 把这个 Wi-Fi 发给开发板：换一个 Wi-Fi 也能连上。
4. 跑完任务后导出 trace：`steps.jsonl` 末尾应有 `"kind": "learned"`，列出自学到的经验；`debug.log` 有 `learned: N lesson(s)`。再跑一次类似任务，开头的 `"kind": "lessons"` 里应出现上次自学的经验。
   在回顾里给某一步写备注；再跑一次类似任务，导出 trace：`steps.jsonl` 开头应有一条 `"kind": "lessons"`，列出这条备注；`debug.log` 有 `lessons: N applied`。
5. 在“文件”App 里放一个 `rules.md`，下一次任务生效。
6. **后台保活**：跑一次任务后导出日志，`debug.log` 应有 `background audio: playing silence`；trace 的 `metrics.json` 里 `background_alive_s` 接近整个任务时长、`suspensions` 为 0、`ble_kbps_app` 很低（画面走 Wi-Fi）。任务中途来电挂断后应看到 `background audio: restarting`。

## 不要做

- 加功能或改行为（编译修正除外）
- 推送到任何远端；提交 `Local.xcconfig` 或任何密钥
- 宣称画图精度已修好

## 回报给用户

- xcodegen、编译、测试的实际结果（通过数、失败数、失败原文）
- 做过的编译修正（每一处）
- 安装结果和手机上看到的 build 号

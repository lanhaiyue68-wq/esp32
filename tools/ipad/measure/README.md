# iPad 滑鼠量測小工具（2026-11-25，Claude Code）
全部用 pymobiledevice3 的 python 跑（`%APPDATA%\uv\tools\pymobiledevice3\Scripts\python.exe`），分析用 `py -3.12`（要 PIL、numpy）。
- `calrun.py`：從測試通道觸發校準，輪詢 debug.log 直到 `calibration: ±`／failed，印出關鍵行（輸出有中文時先 `set PYTHONIOENCODING=utf-8`）。
- `getlog.py <out>`：用 house_arrest 讀 iPad 上 Echo 的 `/Documents/debug.log`。
- `swipe.py "cmd1;cmd2;..."`：同一支程式連續送多個板子指令（間隔 ~50 ms）。分開呼叫 lan_usb_ipad.py 每次 >1 秒，企微會把「按下…移動」當長按。
- `meas3.py <dir> <tag> '<plan json>'`：設 step 60／pace 30／round on，依計畫送直線 `m` 或曲線 `c`，每步截圖；`ana.py <dir> <tag>` 用中位數背景量位移（會被文字干擾，箭頭尖端用 `arrowtest.py`）。
- `arrow.py`：Swift `Vision.arrows` 的 Python 對照版（找箭頭尖端）；`arrowtest.py <這資料夾> <dir> <tag>` 驗證。
量測結論寫在 progress.md 的 174 段。

# 问题与验证

## 2026-10-24 微信指令无法执行微信外任务

根因：WatchSettings.composePrompt 与 ownerTask 都明确限定微信内操作；主页任务执行器本身支持其他 App。

修复：显式开关 + 精确匹配的会话/发言人范围，跨 App 使用本轮授权消息原文。模型只决定是否要执行，不能替换主人指令。回报保存为单独待发项，失败只重试回报。

RED 证据：工作流 40050688780；WatchPhoneTaskTests.testAnEnabledOwnersRequestCanBecomeATaskOutsideWeChat 断言失败；其余 202 项通过。日志及 Headroom 压缩证据位于 ../tmp/codex-watch-red.log 和 .headroom.json（节省 1,200 tokens / 35.5%）。

GREEN 证据：工作流 40051367358，57e066330899ff5882cedf8d852045ab56dddfe0；设备 Release 编译成功，207 项 XCTest、包括新增 5 项回归全过。完整日志和包校验在 ../out/build45-wechat-phone-tasks；Headroom 对构建日志节省 7,123 tokens / 19.3%。

当前限制：微信显示名/OCR 不是强身份认证；一次下一个任务，等结果后再发下一条；真实手机点击、镜像与发送尚未验收。发送回报失败最多三次会停止守候，待回报保留供下次开始时续发。没有新增固件变更或设备设置改动。

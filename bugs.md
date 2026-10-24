# 问题与验证

## 2026-10-24 微信指令无法执行微信外任务

根因：WatchSettings.composePrompt 与 ownerTask 都明确限定微信内操作；主页任务执行器本身支持其他 App。

修复：显式开关 + 精确匹配的会话/发言人范围，跨 App 使用本轮授权消息原文。模型只决定是否要执行，不能替换主人指令。回报保存为单独待发项，失败只重试回报。

RED 证据：工作流 40050688780；WatchPhoneTaskTests.testAnEnabledOwnersRequestCanBecomeATaskOutsideWeChat 断言失败；其余 202 项通过。日志及 Headroom 压缩证据位于 ../tmp/codex-watch-red.log 和 .headroom.json（节省 1,200 tokens / 35.5%）。

当前限制：功能代码尚待真实 Xcode 构建与测试验证；微信显示名/OCR 不是强身份认证；真实手机点击、镜像与发送尚未验收。没有新增固件变更或设备设置改动。

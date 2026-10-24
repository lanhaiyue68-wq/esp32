# Codex 接手 ESP32 / Lan Agent — 2026-10-24

## 目标与边界

用户要求接手 Claude「ESP32 网络配置与日志分析」。对应原始会话 `17c84dbc-debc-4306-8308-7ef8c39bfb2f`，最后需求是把微信当作手机任务入口，允许主人通过微信要求 App 操作其他 App。实际最新工作树是本目录，基线 build 44 / `b28465de9a480983eb9e3095b53fc16aecf4725e`；旧 `../esp32-iphone-agent` 不是最新 App。

不改固件、设备网络、配对、模型配置或签名，不在开发阶段发送真实微信消息或安装 App。

## 路由与工具

已读取共享 skill-routing-reminder，并执行 Agent Router。使用 direct-execution、systematic-debugging、spec-kit-orchestration、TDD，ponytail 控制范围。无子 Agent。Headroom 已实际调用本机 `_compress_content`，hash `f95bc13e6b27b1757bfd3f3c`；因 recent_code 保护 19,464 tokens 原样保留，节省 0。压缩存档位于 `../tmp/codex-watch-handoff-headroom.json`，之后使用定向读取。

固定审查过的 Spec Kit 1.0.6 已初始化本工作树；Codex、Claude 集成校验通过、事件关闭；无外部扩展或 hooks。

## 当前里程碑

- 原因：`WatchSettings.composePrompt` 和 `ownerTask` 把任务限制在微信；已有 `watchRun → AppModel.run → AgentLoop` 可复用。
- 工作分支：`codex/wechat-phone-tasks`，仅使用 private remote `lanhaiyue-web/esp32-iphone-agent-app`，不推 origin 上游、不合并 main。
- RED 测试提交 `eba86c4`：只增加原有 API 回归测试。云端工作流 `40050688780` 已完成设备 Release 编译，模拟器测试进行中。它仍是 build 44 的基线测试产物，不得当成新版本交付。
- 需求、设计、验收在 `specs/001-wechat-phone-tasks/{spec,plan,tasks}.md`。新增权限默认关闭，要求聊天范围及发言人精确匹配，跨 App 使用本轮消息原文；待回报保存结果，不重复执行。
- 本地测试文件已有后续测试草稿，尚未全部同步远端或编译。生产功能代码尚未修改，等初始回归测试出现预期失败后再实施。

## 下一步

1. 读取 RED 工作流结论与断言证据。
2. 在 WatchMode、AppModel、WatchView 与本地化中实现任务桥接和单项结果回报。
3. 完成测试，递增 build，使用同一私有分支工作流做真实 Xcode 编译与完整 XCTest。
4. 下载通过验证的 unsigned IPA，核对 build/SHA256，桌面交付；更新项目记录及 spec 收敛。真机点击、镜像、真实消息回报须独立验收。

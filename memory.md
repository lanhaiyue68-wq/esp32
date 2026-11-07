

## 2026-10-24 用户偏好：桌面只留最新安装包
用户明确要求每次新版本交付后删掉旧版。对 Lan Agent：先确认新版编译/测试、IPA版本和SHA256通过并放到桌面，再将桌面旧版IPA、对应校验码和使用说明送资源回收筒，只留最新已验证版本。不要在桌面保留多个历史版本；本规则不扩大到项目源码、原始日志或构建验证证据。无需再次询问同一清理动作。


## 发布与回退保留规则 — 2026-10-25
用户明确指定回退基准时，必须同时保留旧IPA、校验码和使用说明，并做独立校验备份；该基准不受“交付新版自动回收旧包”的默认清理规则影响，直到用户明确同意丢弃。本次固定build51作为build52试验的回退基准，记录见E:/Backups/esp32-build51-rollback-20261025/rollback-manifest.json。

- 用户要求 ESP32 Agent 的旧版本不要长期积压：新 IPA 经完整测试及版本/hash 核验交付后，清理已确认的旧安装包和可再生成构建缓存；保留最新可用 IPA、活动源代码/Git 历史和原始诊断资料。清理前校验绝对路径，排除 Git 目录和 Junction/ReparsePoint。

- User explicitly requires the existing Bezier pointer motion to remain enabled. Calibration repairs must preserve this behavior and must not silently persist curve-off or substitute straight runtime motion.

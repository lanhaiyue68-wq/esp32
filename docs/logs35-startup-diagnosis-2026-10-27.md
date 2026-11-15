# 日志35：build73启动无反应核查（2026-10-27）

结论：可以确认启动阻塞在镜像画面回传/新鲜度验证，不能确认是升级iOS27导致。用户当前系统以其明确陈述的iOS27为准，且用户确认升级后未测试旧版，缺少控制变量对照。本轮没有修改运行代码、发布新包或做真机验证。

## 直接证据

- debug.log记录app launched 1.0 (73)。本包另包含日志34时期旧运行20261026-220416，必须与四次20261027新尝试分开统计。
- 四次新尝试均无LLM记录，模型调用为0；不能用本包评价73输入误删修复或新旧任务完成速度。
- 050511：前台验证曾成功；退到后台后，在verifying first task frame卡住。snap返回err ble send failed，33.251秒后启动失败，错误文字称画面无法解码。
- 050554：镜像连接状态有变化，前台画面检查13.480秒后超时。
- 050614：只记录video preflight，随后App出现新启动；没有本次系统崩溃报告，不能断言为系统杀进程。
- 050638：前台以cached GOP通过，后台首帧检查失败；snap先等20秒，再重试30秒，71.569秒后失败。末次状态decoded_ms=216957，latest_board_ms=284540，相差67.583秒；frame_age_s约73.09秒，蓝牙状态心跳仍新鲜。
- stream on、flickhome和home有成功应答；Wi-Fi视频TCP曾成功连接，也发生过board has no connection的重连。说明不是整个板完全失联。
- metrics.decode_errors=0、background_decode_errors=0、decoder_note为空；已有错误文案不能单独证明新系统不支持H264解码。回传阻塞/积压、重放旧GOP、后台解码行为仍需更细边界证据。
- 人工查看两次错误保存的JPEG：050511仍是Agent自己的退出页面且有明显花屏；050638仍是Agent界面。它们不能作为已切到微信后的有效当前画面。

## 对照与排除

- 用git比较build72源码d8555a1与build73文档HEAD ac02fb1，ios/IPhoneAgent/Video及App/RunSession.swift没有改动。73的输入修复未触及该取屏/启动实现，但这不能完全排除其他模块的间接影响。
- 73还没有接入讨论中的iOS27 ScreenCaptureKit，仍走现有AirPlay与板回传。原计划的直接取屏收益尚不能从这份日志验收。
- 附带MetricKit报告来自旧build61/69与iOS26.7.1，不能拿来否定用户现用iOS27，也不能当作本次73崩溃证据。当前启动日志未记录运行系统完整版本，这是诊断信息缺口。
- 用户明确全程Wi-Fi/蓝牙/镜像，无手机到开发板USB连接；日志中usb ok字段不证明实际插线，不据此要求改用USB。

## 下一步

1. 优先定位画面从板到手机、组帧到解码的停顿，并为后台启动增加可见状态和有界等待；不能取消画面新鲜度检查后盲点。
2. 如做现场恢复验证，停止任务与镜像、给板断电重启，再重新连接并单独确认预览是否随页面更新；本次日志已经出现两次镜像重连，不能宣称单纯重连一定能修好。
3. 要确认系统因果，需要同系统下旧版/73对照或直接取屏原型的同任务真机验证。用户未试旧版，当前不作系统定罪。
4. 可继续按无线与充电口约束验证原生直接取屏；它能避开当前视频绕行，但不等于已解决问题或实测兼容。

验证：结构化解析四次新运行，断言其均无模型调用；对比源码取屏/启动差异为空；人工检查两张错误帧。长debug输出先用本机Headroom压缩，2312→1619 token，关键错误再按时间戳核对原文。使用systematic-debugging；Agent Router误路由web_frontend，未采用无关UI技能。没有运行产品测试（未改产品代码）。

相关原文：
- RunSession.swift：verifying first task frame后调用currentFrame()，此处不继承前台snapLimit=10，允许20+30秒重试。
- VideoFeed.swift：currentFrame、refreshDecoder、VideoTCP；H264Decoder.swift：GOP重放与回调。
- 机器可读证据：logs35-startup-evidence.json。
- 官方版本说明仅作排查参考：https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes ，未找到足以确认本例因果的公开条目；不把其他AirPlay问题当作本例证明。

import SwiftUI

/// Tasks from the cloud (CloudBridge): the on/off switch, where the server is, which device this phone is, its key.
struct CloudSettingsView: View {
    @ObservedObject var cloud: CloudBridge

    var body: some View {
        Form {
            Section {
                Toggle("接收云端任务", isOn: $cloud.enabled)
                LabeledContent("状态", value: cloud.state)
                if let task = cloud.current {
                    LabeledContent("当前任务", value: task.instruction)
                }
            } footer: {
                Text("关闭后不再接收新任务，正在执行的云端任务会停止。")
            }
            Section("连接") {
                TextField("服务器地址（https://…）", text: $cloud.server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("设备编号", text: $cloud.device)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("设备密钥", text: $cloud.token)
            }
            Section {
                Text("手机锁屏、App 被系统关闭或屏幕共享中断时收不到任务；会把这些状态逐项回报给服务器。云端任务要发送消息时，先等服务器批准。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("云端任务")
    }
}

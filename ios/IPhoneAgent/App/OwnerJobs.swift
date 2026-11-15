import SwiftUI

/// D29, user 11-15 (客户场景 H: 每个月去麦当劳、肯德基、小程序、买菜 App 申请发票): the owner's invoice details, given to
/// any task about 发票 (AgentLoop.invoiceFacts). Kept on this phone only.
struct InvoiceProfile: Equatable {
    var kind = "单位"  // 单位 or 个人
    var title = ""
    var taxID = ""
    var email = ""

    static let kindKey = "invoice.kind", titleKey = "invoice.title", taxIDKey = "invoice.taxID", emailKey = "invoice.email"

    static func load(_ defaults: UserDefaults = .standard) -> InvoiceProfile {
        InvoiceProfile(kind: defaults.string(forKey: kindKey) ?? "单位", title: defaults.string(forKey: titleKey) ?? "",
                       taxID: defaults.string(forKey: taxIDKey) ?? "", email: defaults.string(forKey: emailKey) ?? "")
    }
}

/// D29: a task Lan Agent runs by itself once a month (day 1–28, at a time of day), while it is running in the background
/// as for cloud tasks. It runs unattended: no pause for help, nothing published, a missing app noted as missing.
struct ScheduledJob: Codable, Identifiable, Equatable {
    var id = UUID()
    var task: String
    var day: Int
    var hour: Int
    var minute: Int
    var enabled = true
    var lastRun: Date?

    /// This month's time for it (the day kept within 1–28, so every month has it).
    func dueDate(in month: Date, calendar: Calendar = .current) -> Date? {
        var c = calendar.dateComponents([.year, .month], from: month)
        c.day = min(max(day, 1), 28)
        c.hour = min(max(hour, 0), 23)
        c.minute = min(max(minute, 0), 59)
        return calendar.date(from: c)
    }

    /// Due: this month's time has come and it has not run since.
    func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let due = dueDate(in: now, calendar: calendar), now >= due else { return false }
        return lastRun.map { $0 < due } ?? true
    }
}

/// D29: the owner's monthly jobs, kept in UserDefaults.
@MainActor final class ScheduleBook: ObservableObject {
    static let key = "scheduledJobs.v1"
    private let defaults: UserDefaults
    @Published var jobs: [ScheduledJob] { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([ScheduledJob].self, from: data) {
            jobs = saved
        } else {
            jobs = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(jobs) { defaults.set(data, forKey: Self.key) }
    }
}

extension AppModel {
    /// D29: every minute, a monthly job that is due runs like a task typed here, unattended; one at a time, never over a
    /// run already going (it waits for the next minute).
    func startSchedules() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.runDueJob()
            }
        }
    }

    private func runDueJob() async {
        guard !agent.running, !startingAgent, !recorder.recording, !recorder.inferring else { return }
        let now = Date()
        guard let i = schedules.jobs.firstIndex(where: { $0.isDue(at: now) }) else { return }
        schedules.jobs[i].lastRun = now
        let job = schedules.jobs[i]
        DebugLog.write("schedule: monthly job due (day \(job.day) \(job.hour):\(job.minute)): \(job.task.prefix(60))")
        await run(job.task, askHelp: false)
    }
}

/// D29: Settings › 发票资料.
struct InvoiceSettingsView: View {
    @AppStorage(InvoiceProfile.kindKey) private var kind = "单位"
    @AppStorage(InvoiceProfile.titleKey) private var title = ""
    @AppStorage(InvoiceProfile.taxIDKey) private var taxID = ""
    @AppStorage(InvoiceProfile.emailKey) private var email = ""

    var body: some View {
        Form {
            Section {
                Picker(selection: $kind) {
                    Text(verbatim: "单位").tag("单位")
                    Text(verbatim: "个人").tag("个人")
                } label: { Text(verbatim: "抬头类型") }
                TextField(text: $title) { Text(verbatim: "发票抬头（公司名或个人姓名）") }
                if kind == "单位" {
                    TextField(text: $taxID) { Text(verbatim: "税号") }
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                TextField(text: $email) { Text(verbatim: "收发票的邮箱") }
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text(verbatim: "提到“发票”的任务会用这里的资料填写开票信息。资料只存在这支手机上，会随任务发给规划和执行的模型。")
            }
        }
        .navigationTitle(Text(verbatim: "发票资料"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// D29: Settings › 定时任务 (monthly).
struct ScheduleSettingsView: View {
    @ObservedObject var book: ScheduleBook
    @State private var draft = ""
    @State private var day = 1
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()

    static let invoiceExample = "帮我申请上个月的电子发票：依次打开麦当劳、肯德基、买菜的 App 和微信里用过的小程序，在订单里找到上个月还没开发票的订单，"
        + "申请电子发票，抬头、税号和邮箱用设置里的发票资料，提交后告诉我每家申请了几张、金额多少；没有订单或者已经开过的就跳过"

    var body: some View {
        Form {
            Section {
                if book.jobs.isEmpty {
                    Text(verbatim: "还没有定时任务。").foregroundStyle(.secondary)
                }
                ForEach($book.jobs) { $job in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Toggle(isOn: $job.enabled) { Text(verbatim: job.task).lineLimit(3) }
                        Text(verbatim: Self.when(job)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { book.jobs.remove(atOffsets: $0) }
            } header: {
                Text(verbatim: "每月自动做")
            } footer: {
                Text(verbatim: "到时间时 Lan Agent 要开着、屏幕共享和板子要连着（和云端任务一样）。自动做的任务没人看着：不会停下来等你，不会发布，也不会下载 App。")
            }
            Section {
                TextField(text: $draft, axis: .vertical) { Text(verbatim: "要做的事") }
                    .lineLimit(2...6)
                Stepper(value: $day, in: 1...28) { Text(verbatim: "每月 \(day) 号") }
                DatePicker(selection: $time, displayedComponents: .hourAndMinute) { Text(verbatim: "时间") }
                Button { add() } label: { Text(verbatim: "加入") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { draft = Self.invoiceExample } label: { Text(verbatim: "填入示例：每月申请发票") }
            } header: {
                Text(verbatim: "新增")
            }
        }
        .navigationTitle(Text(verbatim: "定时任务"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        // First run at the next time it comes round, not at once for a day already past this month.
        book.jobs.append(ScheduledJob(task: draft.trimmingCharacters(in: .whitespacesAndNewlines), day: day, hour: c.hour ?? 9,
                                      minute: c.minute ?? 0, lastRun: Date()))
        draft = ""
    }

    static func when(_ job: ScheduledJob) -> String {
        "每月 \(job.day) 号 " + String(format: "%02d:%02d", job.hour, job.minute)
            + (job.lastRun.map { "，上次 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
    }
}

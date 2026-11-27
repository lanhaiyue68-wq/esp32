import Foundation

/// 193 (user 11-27: 「在小藍設定加一個窗口選『Codex 為主（豆包副）』或『豆包為主（Codex 副）』，隨時互換；套用在看圖、看影片、
/// 學新指令」): which model goes first where 小藍 uses one — looking at a picture, a video's frames or a web page, and
/// planning an order it has no fixed steps for (its runs kept to be learned). The other is asked when the first fails,
/// answers nothing, says it cannot see, or its quota is spent. Finding where to click on each step (the actor) stays
/// 豆包: it must be quick and give a place. Watching, reading and sending messages stay fixed steps, no model.
enum LeadModel: String, CaseIterable {
    case codex, doubao

    static let key = "xiaolanLeadModelV1"

    static var current: LeadModel {
        get { UserDefaults.standard.string(forKey: key).flatMap(LeadModel.init(rawValue:)) ?? .codex }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var label: String { self == .codex ? "Codex 為主（豆包為副）" : "豆包為主（Codex 為副）" }

    /// Who is asked, in turn: the lead first when it can be asked (Codex signed in and switched on; a 豆包 key set),
    /// then the other.
    static func order(_ lead: LeadModel, codex: Bool, doubao: Bool) -> [LeadModel] {
        let both: [LeadModel] = lead == .codex ? [.codex, .doubao] : [.doubao, .codex]
        return both.filter { $0 == .codex ? codex : doubao }
    }
}

/// A model that never answers: Codex's own fallback when 小藍 asks it to look, so its failure comes back to the caller,
/// which asks 豆包 itself.
@MainActor final class NoAnswerModel: ChatModel {
    let model = "none"
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        throw LLMError(message: "no second model here")
    }
}

extension PlusChat {
    /// 193: Codex to look at a picture (one image a call): nil when it is switched off or not signed in. Its failure is
    /// thrown back (no 豆包 inside), so the lead/second order stays the caller's.
    static func looker(defaults: UserDefaults = .standard) -> ChatModel? {
        let on = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard on, ChatGPTPlus.saved != nil else { return nil }
        let model = defaults.string(forKey: modelKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        return PlusChat(model: model, fallback: NoAnswerModel(), rest: .shared, second: secondAccount,
                        listed: { ChatGPTPlus.listedModels(slot: 0) }, readModels: { try await ChatGPTPlus.readModels($0, slot: 0) })
    }

    /// 193: the planner with the lead model first: Codex leading is the planner as it was (Codex, then 豆包); 豆包 leading
    /// asks 豆包 first and Codex when 豆包 fails.
    static func planner(fallback doubao: ChatModel, lead: LeadModel, defaults: UserDefaults = .standard) -> ChatModel {
        let codexFirst = planner(fallback: doubao, defaults: defaults)
        guard lead == .doubao, codexFirst is PlusChat else { return codexFirst }
        DebugLog.write("planner: 豆包 leads (\(doubao.model)), Codex if it fails")
        return ModelChain([doubao, codexFirst])
    }
}

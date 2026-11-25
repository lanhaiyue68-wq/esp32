import Foundation

/// 小藍's tool box (162): every order of both engines, typed in by hand on the iPad like Android 小藍's 工具箱
/// (worktool-lan-watch LanWatchActivity: 常用操作, 按用途瀏覽). A form fills the order's fields; ChatToolLink.enqueueLocal
/// queues it and watch does it like a server's order. 跟圈 (260–265) is left out: it needs its backend's run.
enum XiaoLanTools {
    struct Field: Hashable, Identifiable {
        enum Kind: Hashable { case text, list, long, toggle, lines }
        var key: String  // "friend.phone" goes into the friend object; "messages" becomes messageList
        var label: String
        var kind = Kind.text
        var id: String { key }
    }

    struct Tool: Hashable, Identifiable {
        var type: Int
        var hint: String
        var id: Int { type }
        var apps: [XiaoLanOrders.App] {
            [XiaoLanOrders.App.wechat, .wework].filter { XiaoLanOrders.label(type, $0) != nil }
        }
        var title: String { XiaoLanOrders.label(type, apps.first ?? .wechat) ?? "\(type)" }
    }

    struct Group: Identifiable {
        var title: String
        var tools: [Tool]
        var id: String { title }
    }

    static let common: [Tool] = [
        Tool(type: 203, hint: "輸入會話和文字，可在群聊 @ 成員"),
        Tool(type: 512, hint: "輸入群名，取得成員清單"),
        Tool(type: 218, hint: "輸入會話和檔案網址，小藍下載後發送"),
    ]

    static let groups: [Group] = [
        Group(title: "訊息操作", tools: [
            Tool(type: 203, hint: "文字，可 @ 成員"), Tool(type: 204, hint: "長按原訊息選「引用」再回覆"),
            Tool(type: 205, hint: "把一則訊息轉發給其他會話"), Tool(type: 226, hint: "撤回自己剛發的訊息"),
            Tool(type: 229, hint: "依序發多則訊息"), Tool(type: 230, hint: "多行內容合成一則發送"),
            Tool(type: 227, hint: "多選訊息逐條轉發（企業微信）"), Tool(type: 228, hint: "多選訊息合併轉發（企業微信）"),
        ]),
        Group(title: "群聊與聯絡人", tools: [
            Tool(type: 206, hint: "選成員建群，可設群名與公告"), Tool(type: 207, hint: "改群名、公告、備註，拉人或移人"),
            Tool(type: 219, hint: "解散群聊"), Tool(type: 214, hint: "讀出群名、群主、人數與成員"),
            Tool(type: 212, hint: "把待通過的好友申請都通過"), Tool(type: 213, hint: "用手機號搜尋並加好友"),
            Tool(type: 220, hint: "從群成員裡加好友"), Tool(type: 221, hint: "改好友備註（微信）／設為待辦（企業微信）"),
            Tool(type: 225, hint: "改我在群裡的暱稱（企業微信）"), Tool(type: 234, hint: "刪除聯絡人（企業微信）"),
            Tool(type: 236, hint: "刪除已把我刪掉的聯絡人（企業微信）"), Tool(type: 243, hint: "用二維碼圖片進群（微信）"),
        ]),
        Group(title: "檔案與通話", tools: [
            Tool(type: 218, hint: "圖片／影片存相簿，其他檔案存小藍資料夾後發送"), Tool(type: 210, hint: "分享小程式到會話"),
            Tool(type: 208, hint: "從微盤發圖片（企業微信）"), Tool(type: 209, hint: "從微盤發檔案（企業微信）"),
            Tool(type: 211, hint: "分享在線文檔（企業微信）"), Tool(type: 224, hint: "發連結（企業微信）"),
            Tool(type: 231, hint: "發起語音通話"), Tool(type: 232, hint: "發起視訊通話"),
            Tool(type: 233, hint: "用二維碼圖片掃一掃（企業微信）"),
        ]),
        Group(title: "朋友圈", tools: [
            Tool(type: 241, hint: "發文字或圖片朋友圈（微信）"), Tool(type: 242, hint: "刪除自己的一條朋友圈（微信）"),
        ]),
        Group(title: "查詢", tools: [
            Tool(type: 501, hint: "群資訊"), Tool(type: 512, hint: "群成員"), Tool(type: 502, hint: "好友資料"),
            Tool(type: 503, hint: "本機帳號資料"), Tool(type: 504, hint: "群二維碼（截圖）"), Tool(type: 505, hint: "最近會話"),
            Tool(type: 507, hint: "全部好友"), Tool(type: 508, hint: "全部群"), Tool(type: 506, hint: "可切換的企業（企業微信）"),
            Tool(type: 511, hint: "接下來的會議（企業微信）"), Tool(type: 509, hint: "小藍資料夾裡的檔案"),
        ]),
        Group(title: "帳號與其他", tools: [
            Tool(type: 222, hint: "打卡（企業微信）"), Tool(type: 223, hint: "切換到另一個企業（企業微信）"),
            Tool(type: 215, hint: "新建防騷擾規則（企業微信）"), Tool(type: 216, hint: "修改防騷擾規則（企業微信）"),
            Tool(type: 217, hint: "刪除防騷擾規則（企業微信）"), Tool(type: 235, hint: "點開推薦項（企業微信）"),
            Tool(type: 237, hint: "清理企業微信快取"), Tool(type: 513, hint: "電量、記憶體與儲存空間"),
            Tool(type: 510, hint: "最近的日誌"), Tool(type: 514, hint: "某段時間的日誌"),
        ]),
    ]

    static func matches(_ tool: Tool, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || tool.title.contains(q) || tool.hint.contains(q) || "\(tool.type)" == q
    }

    private static let titles = Field(key: "titleList", label: "會話名稱（多個用逗號隔開）", kind: .list)

    /// The form's fields for an order on one app (the fields its engine reads; see XiaoLanOrders.problem).
    static func fields(_ type: Int, _ app: XiaoLanOrders.App) -> [Field] {
        switch type {
        case 203: return [titles, Field(key: "receivedContent", label: "內容", kind: .long), Field(key: "atList", label: "@ 誰（選填，多個用逗號）", kind: .list)]
        case 204: return [titles, Field(key: "receivedName", label: "原訊息是誰發的（選填）"), Field(key: "originalContent", label: "原訊息", kind: .long),
                          Field(key: "receivedContent", label: "回覆內容", kind: .long)]
        case 205: return [Field(key: "titleList", label: "原訊息所在的會話", kind: .list), Field(key: "receivedName", label: "原訊息是誰發的（選填）"),
                          Field(key: "originalContent", label: "要轉發的訊息", kind: .long), Field(key: "nameList", label: "轉發給（多個用逗號）", kind: .list),
                          Field(key: "extraText", label: "附言（選填）")]
        case 206: return [Field(key: "selectList", label: "成員（多個用逗號）", kind: .list), Field(key: "groupName", label: "群名（選填）"),
                          Field(key: "groupAnnouncement", label: "群公告（選填）", kind: .long), Field(key: "groupRemark", label: "群備註（選填）")]
        case 207: return [Field(key: "groupName", label: "群名"), Field(key: "newGroupName", label: "新群名（選填）"),
                          Field(key: "newGroupAnnouncement", label: "新群公告（選填）", kind: .long), Field(key: "groupRemark", label: "群備註（選填）"),
                          Field(key: "selectList", label: "拉進群（選填，多個用逗號）", kind: .list), Field(key: "removeList", label: "移出群（選填）", kind: .list),
                          Field(key: "showMessageHistory", label: "新成員可看歷史訊息", kind: .toggle)]
        case 208, 209, 211: return [titles, Field(key: "objectName", label: "檔名"), Field(key: "extraText", label: "再發一句話（選填）")]
        case 210: return [titles, Field(key: "objectName", label: "小程式名稱"), Field(key: "extraText", label: "標題或留言（選填）")]
        case 213: return [Field(key: "friend.phone", label: "手機號"), Field(key: "friend.markName", label: "備註名（選填）"),
                          Field(key: "friend.leavingMsg", label: "申請留言（選填）"), Field(key: "friend.tagList", label: "標籤（選填）", kind: .list)]
        case 214: return [Field(key: "titleList", label: "群名", kind: .list)]
        case 215, 216, 217: return [Field(key: "objectName", label: "規則名稱"), Field(key: "extraText", label: "規則內容（選填）", kind: .long),
                                    Field(key: "titleList", label: "適用的群（選填）", kind: .list)]
        case 218: return [titles, Field(key: "fileUrl", label: "檔案網址（http 或 https）"), Field(key: "objectName", label: "檔名（選填）"),
                          Field(key: "fileType", label: "類型 image／video／file（選填）"), Field(key: "extraText", label: "再發一句話（選填）")]
        case 219, 501, 504, 512: return [Field(key: "groupName", label: "群名")]
        case 220: return [Field(key: "groupName", label: "群名"), Field(key: "friend.name", label: "群成員名字"),
                          Field(key: "friend.leavingMsg", label: "申請留言（選填）"), Field(key: "friend.markName", label: "備註名（選填）")]
        case 221 where app == .wechat:
            return [Field(key: "friend.name", label: "好友名字"), Field(key: "friend.markName", label: "新備註（選填）"),
                    Field(key: "friend.markExtra", label: "描述（選填）"), Field(key: "friend.phone", label: "電話（選填）"),
                    Field(key: "friend.tagList", label: "標籤（選填）", kind: .list)]
        case 221: return [titles, Field(key: "receivedName", label: "那則訊息是誰發的（選填）"), Field(key: "originalContent", label: "那則訊息", kind: .long)]
        case 223: return [Field(key: "objectName", label: "企業名稱")]
        case 224: return [titles, Field(key: "receivedContent", label: "連結"), Field(key: "objectName", label: "標題（選填）"),
                          Field(key: "extraText", label: "說明（選填）")]
        case 225: return [Field(key: "groupName", label: "群名"), Field(key: "newGroupName", label: "我在本群的暱稱")]
        case 226: return [titles, Field(key: "originalContent", label: "要撤回的訊息", kind: .long)]
        case 227, 228: return [Field(key: "titleList", label: "原會話", kind: .list), Field(key: "messages", label: "要轉發的訊息（每行一則）", kind: .lines),
                               Field(key: "nameList", label: "轉發給（多個用逗號）", kind: .list)]
        case 229, 230: return [titles, Field(key: "messages", label: "訊息（每行一則）", kind: .lines)]
        case 231, 232, 290: return [titles]
        case 233, 243: return [Field(key: "fileUrl", label: "二維碼圖片網址")]
        case 234, 236: return [Field(key: "friend.name", label: "聯絡人名字")]
        case 235: return [Field(key: "objectName", label: "推薦項名稱")]
        case 241: return [Field(key: "originalContent", label: "朋友圈文字", kind: .long), Field(key: "fileUrl", label: "圖片網址（選填，多張用逗號）")]
        case 242: return [Field(key: "originalContent", label: "那條朋友圈的內容", kind: .long)]
        case 502: return [Field(key: "titleList", label: "好友名字", kind: .list)]
        case 514: return [Field(key: "startDate", label: "從（例如 2026-11-25 09:00）"), Field(key: "endDate", label: "到（選填）")]
        default: return []
        }
    }

    /// The order from what was typed: lists split on commas, 頓號 and new lines; `friend.*` into the friend object;
    /// `messages` (one per line) into messageList.
    static func order(_ type: Int, app: XiaoLanOrders.App, values: [String: String], toggles: [String: Bool]) -> [String: Any] {
        var item: [String: Any] = ["type": type]
        var friend: [String: Any] = [:]
        func split(_ s: String, lines: Bool) -> [String] {
            let separators: CharacterSet = lines ? .newlines : CharacterSet(charactersIn: ",，、\n")
            return s.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        for field in fields(type, app) {
            let raw = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let value: Any?
            switch field.kind {
            case .toggle: value = toggles[field.key] ?? false
            case .list: value = raw.isEmpty ? nil : split(raw, lines: false)
            case .lines: value = raw.isEmpty ? nil : split(raw, lines: true).map { ["originalContent": $0] }
            case .text, .long: value = raw.isEmpty ? nil : raw
            }
            guard let value else { continue }
            if field.key.hasPrefix("friend.") { friend[String(field.key.dropFirst(7))] = value }
            else if field.key == "messages" { item["messageList"] = value }
            else { item[field.key] = value }
        }
        if !friend.isEmpty { item["friend"] = friend }
        return item
    }
}

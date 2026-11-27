import Foundation

/// 小藍 iPad 版 (161): every order the two engines inside Android 小藍 take — 智微兔 (personal WeChat, ChatToolLink
/// channel `wechat`) and 智企微行 (WeCom, channel `wework`) — turned into one agent task on the iPad: look at the screen,
/// move the board's pointer, type with 小藍's keyboard. Android does them by reading WeChat's controls; iOS lets no app
/// read another app's, so only the protocol is copied: the same order fields (WeworkMessageBean), the same results
/// (ExecCallbackBean, ChatToolLink) and, for reads, the same data beans sent back as socketType 2.
///
/// Field use per order comes from the decompiled engines: personal — chattool-apk-recovery jadx CustomMessageQueue /
/// s3/ni.java (REQUEST sendMessage, initGroup, updateGroup, …); WeCom — worktool-lan-watch WTPro2 WeworkMessageBean.
/// 跟圈 (260–265) is the owner-gequan backend's run protocol (meta: runId, params, resultUrl/resultToken).
/// Orders whose fields the engines do not show (215–217, 225, 230, 235, 305) are read the plainest way; check them on
/// the iPad before a customer relies on them.
enum XiaoLanOrders {
    enum App: String, Equatable {
        case wechat, wework
        var name: String { self == .wechat ? "微信" : "企业微信" }
    }

    /// Where an order's files go before the agent picks them: images and videos into Photos, other files into
    /// 小藍's Documents (Files › On My iPad › 小藍 › orders).
    enum MediaKind: Equatable { case none, photos, files }

    /// Orders answered by the app itself, without touching the screen.
    enum Local: Equatable { case files, log, resources, logRange(String, String) }

    /// 跟圈 run: where its result goes (owner-gequan /gequan/result/<run>?robotId=…&token=…) and where its pictures
    /// go (/gequan/upload/<run>?robotId=…&token=…, answered {"url": …/files/<sha>.jpg}).
    struct Moments: Equatable {
        var runId: String, robotId: String, resultUrl: String, resultToken: String, friend: String
        var uploadUrl = "", uploadToken = ""
        var resultURL: URL? { Self.signed(resultUrl, robotId, resultToken) }
        var uploadURL: URL? { Self.signed(uploadUrl, robotId, uploadToken.isEmpty ? resultToken : uploadToken) }
        private static func signed(_ s: String, _ robot: String, _ token: String) -> URL? {
            guard !s.isEmpty, var c = URLComponents(string: s) else { return nil }
            c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "robotId", value: robot), URLQueryItem(name: "token", value: token)]
            return c.url
        }
    }

    struct Job: Equatable {
        var label: String
        var task = ""
        var steps = 25
        var readOnly = false
        /// Done's answer is one line of JSON that becomes the order's data bean (dataBean).
        var query = false
        /// What will be typed: each goes through the privacy check before the run.
        var texts: [String] = []
        var media: [String] = []
        var mediaKind = MediaKind.none
        var local: Local?
        var moments: Moments?
    }

    /// One order's fields as the server sent them.
    struct Fields {
        let d: [String: Any]
        init(_ raw: String) { d = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:] }
        init(_ d: [String: Any]) { self.d = d }
        func s(_ k: String) -> String {
            let v = d[k] as? String ?? (d[k] as? NSNumber)?.stringValue ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func list(_ k: String) -> [String] {
            if let one = d[k] as? String { return one.isEmpty ? [] : [one] }
            return (d[k] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        func bool(_ k: String) -> Bool? { d[k] as? Bool }
        var friend: Fields { Fields(d["friend"] as? [String: Any] ?? [:]) }
        /// 跟圈: `meta` (owner-gequan) or `metaJson` (Android 小藍's own bridge), a JSON string or an object.
        var meta: Fields {
            for k in ["meta", "metaJson"] {
                if let o = d[k] as? [String: Any] { return Fields(o) }
                if let s = d[k] as? String, let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] { return Fields(o) }
            }
            return Fields([String: Any]())
        }
        var params: Fields { Fields(d["params"] as? [String: Any] ?? [:]) }
        /// A multi-message order's texts: messageList[].originalContent, or its items' text joined.
        var messages: [String] {
            (d["messageList"] as? [[String: Any]] ?? []).compactMap { m in
                let own = (m["originalContent"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !own.isEmpty { return own }
                let items = (m["itemMessageList"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
                return items.isEmpty ? nil : items
            }
        }
    }

    // MARK: - Catalog

    /// What each channel takes (Android's two engines). 201, 202, 303–305 are the link's own; the rest become tasks.
    static let personal: [Int: String] = [
        201: "停止并回首页", 202: "读取新消息", 203: "发消息", 204: "引用回复", 205: "转发消息", 206: "创建群", 207: "修改群",
        210: "发小程序", 212: "通过好友请求", 213: "手机号加好友", 214: "展示群信息", 218: "发文件", 219: "解散群",
        220: "从群里加好友", 221: "修改好友备注", 226: "撤回消息", 231: "语音通话", 232: "视频通话", 241: "发朋友圈",
        290: "删除会话", 242: "删除朋友圈", 243: "扫码进群", 260: "跟圈：读好友朋友圈", 261: "跟圈：发图文", 263: "跟圈：发视频", 265: "跟圈：发链接",
        304: "清空排队", 501: "读取群信息", 502: "读取好友信息", 503: "读取本人资料", 504: "读取群二维码", 505: "读取最近会话",
        507: "读取全部好友", 508: "读取全部群", 509: "读取本机文件", 512: "读取群成员",
    ]
    static let wework: [Int: String] = [
        201: "停止并回首页", 202: "读取新消息", 203: "发消息", 204: "引用回复", 205: "转发消息", 206: "创建群", 207: "修改群",
        208: "发微盘图片", 209: "发微盘文件", 210: "发小程序", 211: "发在线文档", 212: "通过好友请求", 213: "手机号加好友",
        214: "展示群信息", 215: "新建防骚扰规则", 216: "修改防骚扰规则", 217: "删除防骚扰规则", 218: "发文件", 219: "解散群",
        220: "从群里加好友", 221: "设为待办", 222: "打卡", 223: "切换企业", 224: "发链接", 225: "修改群成员信息", 226: "撤回消息",
        227: "逐条转发", 228: "合并转发", 229: "发多条消息", 230: "合并发送", 231: "语音通话", 232: "视频通话", 233: "扫二维码",
        234: "删除联系人", 235: "点推荐项", 236: "删除单向联系人", 237: "清理缓存", 290: "删除会话", 303: "连接测试",
        304: "清空排队", 305: "移除排队指令", 501: "读取群信息", 502: "读取好友信息", 503: "读取本人资料", 504: "读取群二维码",
        505: "读取最近会话", 506: "读取企业列表", 507: "读取全部好友", 508: "读取全部群", 509: "读取本机文件", 510: "上传日志", 511: "读取会议",
        512: "读取群成员", 513: "读取设备资源", 514: "读取日志片段",
    ]

    static func label(_ type: Int, _ app: App) -> String? { (app == .wechat ? personal : wework)[type] }

    /// One task per chat of titleList (each counted in the order's successList / failList).
    static let perChat: Set<Int> = [203, 204, 208, 209, 210, 211, 218, 224, 226, 229, 230, 231, 232]

    /// The chat or group an order is about, for the status line and the result lists.
    static func target(_ type: Int, _ f: Fields) -> String {
        if let first = f.list("titleList").first { return first }
        let candidates = [f.s("groupName"), f.friend.s("name"), f.friend.s("phone"), f.meta.params.s("friendName"), f.s("objectName")]
        return candidates.first { !$0.isEmpty } ?? label(type, .wechat) ?? label(type, .wework) ?? "\(type)"
    }

    /// Why an order cannot run as sent (a missing field), or nil.
    static func problem(_ type: Int, _ app: App, _ f: Fields) -> String? {
        func need(_ ok: Bool, _ what: String) -> String? { ok ? nil : "缺少\(what)" }
        let titles = !f.list("titleList").isEmpty, group = !f.s("groupName").isEmpty
        switch type {
        case 203: return need(titles, "会话名称（titleList）") ?? need(!f.s("receivedContent").isEmpty, "消息内容（receivedContent）")
        case 204: return need(titles, "会话名称（titleList）") ?? need(!f.s("originalContent").isEmpty, "被回复的原消息（originalContent）")
            ?? need(!f.s("receivedContent").isEmpty, "回复内容（receivedContent）")
        case 205: return need(titles, "原会话（titleList）") ?? need(!f.s("originalContent").isEmpty, "要转发的消息（originalContent）")
            ?? need(!f.list("nameList").isEmpty, "转发对象（nameList）")
        case 206: return need(!f.list("selectList").isEmpty, "群成员（selectList）")
        case 207, 219, 501, 504, 512: return need(group, "群名称（groupName）")
        case 208, 209, 211: return need(titles, "会话名称（titleList）") ?? need(!f.s("objectName").isEmpty, "文件名（objectName）")
        case 210: return need(titles, "会话名称（titleList）") ?? need(!f.s("objectName").isEmpty, "小程序名称（objectName）")
        case 213: return need(!f.friend.s("phone").isEmpty, "手机号（friend.phone）")
        case 218: return need(titles, "会话名称（titleList）") ?? need(!f.s("fileUrl").isEmpty, "文件地址（fileUrl）")
        case 220: return need(group, "群名称（groupName）") ?? need(!f.friend.s("name").isEmpty, "群成员名字（friend.name）")
        case 221 where app == .wechat: return need(!f.friend.s("name").isEmpty, "好友名字（friend.name）")
        case 221, 226: return need(titles, "会话名称（titleList）") ?? need(!f.s("originalContent").isEmpty, "那条消息（originalContent）")
        case 223: return need(!f.s("objectName").isEmpty, "企业名称（objectName）")
        case 224: return need(titles, "会话名称（titleList）") ?? need(!(f.s("fileUrl") + f.s("receivedContent")).isEmpty, "链接")
        case 225: return need(group, "群名称（groupName）")
        case 227, 228: return need(titles, "原会话（titleList）") ?? need(!f.list("nameList").isEmpty, "转发对象（nameList）")
            ?? need(!f.messages.isEmpty || !f.s("originalContent").isEmpty, "要转发的消息（messageList）")
        case 229, 230: return need(titles, "会话名称（titleList）") ?? need(!f.messages.isEmpty || !f.s("receivedContent").isEmpty, "消息（messageList）")
        case 231, 232, 290: return need(titles, "会话名称（titleList）")
        case 233, 243: return need(!f.s("fileUrl").isEmpty, "二维码图片地址（fileUrl）")
        case 234, 236: return need(!(f.friend.s("name") + f.list("titleList").joined()).isEmpty, "联系人名字（friend.name 或 titleList）")
        case 241: return need(!(f.s("originalContent") + f.s("fileUrl")).isEmpty, "朋友圈内容（originalContent）或图片（fileUrl）")
        case 242: return need(!f.s("originalContent").isEmpty, "那条朋友圈的内容（originalContent）")
        case 260, 261, 263, 265:
            let m = f.meta
            return need(!m.s("runId").isEmpty && !m.s("resultUrl").isEmpty, "跟圈任务信息（meta）") ?? need(!m.params.s("friendName").isEmpty, "好友名字（friendName）")
        case 502: return need(titles || !f.friend.s("name").isEmpty, "好友名字（titleList）")
        default: return nil
        }
    }

    // MARK: - Tasks

    private static func q(_ items: [String]) -> String { items.map { "“\($0)”" }.joined(separator: "、") }

    /// The task for one order (for perChat orders, one chat of it). nil: not one the agent does.
    static func job(type: Int, app: App, f: Fields, chat: String) -> Job? {
        guard let name = Self.label(type, app) else { return nil }
        let a = app.name
        #if XIAOLAN
        // 192 (B14; user 11-27: the model learns the orders first, its runs then written into fixed steps): on the
        // iPad both apps are open side by side; the model works in its app's window only
        let start = "iPad 屏幕左右分屏：一边是微信，一边是企业微信（看窗口顶部的标题和底部的标签分辨）。这个任务只在\(a)那一边的窗口里做，"
            + "不要点另一边的窗口，不要回主屏幕，不要关掉、缩小或切换窗口和 App。"
        let end = "\n做完后让\(a)那一边回到消息列表，然后完成（done）；做不到就 fail，并写明原因。"
        let listBack = "\(a)那一边的消息列表"
        #else
        let start = app == .wework ? "先打开企业微信（open 企业微信）。" : ""
        let end = "\n做完后回到微信的聊天列表，然后完成（done）；做不到就 fail，并写明原因。"
        let listBack = "微信的聊天列表"
        #endif
        let open = "在\(a)里打开会话“\(chat)”（不在这个会话就回到消息列表找，列表里没有就用顶部搜索）"
        let look = "只看不改：不要发送任何消息、不要改任何设置。"
        func job(_ task: String, steps: Int = 25, texts: [String] = []) -> Job {
            Job(label: name, task: start + task + end, steps: steps, texts: texts.filter { !$0.isEmpty })
        }
        func read(_ task: String, json: String, steps: Int = 30) -> Job {
            Job(label: name, task: start + look + task + "\n读完后回到" + listBack + "，用 done 完成，answer 只写一行 JSON：" + json
                    + "\n读不到就 fail，并写明原因。", steps: steps, readOnly: true, query: true)
        }
        func message(_ who: String) -> String {
            let sender = who.isEmpty ? "" : "“\(who)”发的"
            return "找到\(sender)这条消息（不在屏幕上就往上翻聊天记录）：\n\(f.s("originalContent"))\n"
        }
        let content = f.s("receivedContent"), extra = f.s("extraText"), object = f.s("objectName")
        let caption = extra.isEmpty ? "" : "，再在这个会话里发一条文字：\n\(extra)\n"

        switch type {
        case 203:
            let at = f.list("atList") + f.list("at")
            let atPart = at.isEmpty ? "" : "先在输入框输入“@”，在弹出的成员列表里选中\(q(at))（选完一个再输入“@”选下一个，“所有人”就选“所有人”），然后接着"
            return job(open + "，点底部输入框，\(atPart)输入下面这段内容并发送，一字不改（上面已经有一样的话也要再发）：\n\(content)", texts: [content])
        case 204:
            return job(open + "，" + message(f.s("receivedName")) + "长按它，选“引用”，然后在输入框输入下面这段内容并发送，一字不改：\n\(content)", texts: [content])
        case 205:
            return job(open + "，" + message(f.s("receivedName")) + "长按它，选“转发”，逐个选中这些转发对象（可多选）：\(q(f.list("nameList")))"
                       + (extra.isEmpty ? "" : "，留言填：\(extra)") + "，然后发送。", texts: [extra])
        case 206:
            var t = "在\(a)里发起群聊（右上角“+”→“发起群聊”），逐个选中这些成员：\(q(f.list("selectList")))，建群。"
            if !f.s("groupName").isEmpty { t += "建好后在群聊信息里把群名改为“\(f.s("groupName"))”。" }
            if !f.s("groupAnnouncement").isEmpty { t += "发布群公告：\n\(f.s("groupAnnouncement"))\n" }
            if !f.s("groupRemark").isEmpty { t += "把这个群的备注设为“\(f.s("groupRemark"))”。" }
            if !f.s("groupTemplate").isEmpty { t += "使用群模板“\(f.s("groupTemplate"))”。" }
            return job(t, steps: 40, texts: [f.s("groupName"), f.s("groupAnnouncement"), f.s("groupRemark")])
        case 207:
            var t = "在\(a)里打开群“\(f.s("groupName"))”，进入右上角的群聊信息，做这些修改："
            if !f.s("newGroupName").isEmpty { t += "群名改为“\(f.s("newGroupName"))”；" }
            if !f.s("newGroupAnnouncement").isEmpty { t += "群公告改为：\n\(f.s("newGroupAnnouncement"))\n；" }
            if !f.s("groupRemark").isEmpty { t += "群备注改为“\(f.s("groupRemark"))”；" }
            if !f.list("selectList").isEmpty {
                t += "点“+”拉这些人进群：\(q(f.list("selectList")))" + (f.bool("showMessageHistory") == true ? "（勾选可查看历史消息）" : "") + "；"
            }
            if !f.list("removeList").isEmpty { t += "点“-”把这些人移出群：\(q(f.list("removeList")))；" }
            if !f.s("groupTemplate").isEmpty { t += "使用群模板“\(f.s("groupTemplate"))”；" }
            return job(t, steps: 45, texts: [f.s("newGroupName"), f.s("newGroupAnnouncement"), f.s("groupRemark")])
        case 208, 209:
            return job(open + "，点输入框右边的“+”→“微盘”，找到\(type == 208 ? "图片" : "文件")“\(object)”并发送到这个会话" + caption, texts: [extra])
        case 210:
            return job("在\(a)里搜索并打开小程序“\(object)”，点右上角“…”→“转发”/“发送给朋友”，选会话“\(chat)”"
                       + (extra.isEmpty ? "" : "，标题或留言填：\(extra)") + "，发送。", steps: 30, texts: [extra])
        case 211:
            return job("在企业微信的“文档”里找到“\(object)”，点“…”→“分享”/“发送给同事或群”，选会话“\(chat)”，发送" + caption, texts: [extra])
        case 212:
            return job("在\(a)里打开“新的朋友”" + (app == .wework ? "（通讯录→新的客户/新的联系人）" : "（通讯录最上面）")
                       + "，把还没通过的好友申请逐个点“接受/通过”并完成确认，直到没有待通过的申请。", steps: 40)
        case 213:
            let fr = f.friend
            var t = "在\(a)里添加好友：右上角“+”→“添加朋友”，搜索手机号“\(fr.s("phone"))”，打开搜到的人，点“添加到通讯录”。"
            if !fr.s("leavingMsg").isEmpty { t += "申请留言填：\(fr.s("leavingMsg"))。" }
            if !fr.s("markName").isEmpty { t += "备注名填“\(fr.s("markName"))”。" }
            if !fr.s("markCorp").isEmpty { t += "备注企业填“\(fr.s("markCorp"))”。" }
            if !fr.s("markExtra").isEmpty { t += "描述填：\(fr.s("markExtra"))。" }
            if !fr.list("tagList").isEmpty { t += "标签选\(q(fr.list("tagList")))。" }
            t += "然后发送申请。搜不到这个号就 fail。"
            return job(t, steps: 30, texts: [fr.s("leavingMsg"), fr.s("markName"), fr.s("markCorp"), fr.s("markExtra")])
        case 214, 501:
            return read("在\(a)里打开群“\(type == 501 ? f.s("groupName") : chat)”，进入群聊信息，读出群名、群主、人数、群公告、群备注和全部成员（成员多就点“查看更多”往下翻完）。",
                        json: #"{"groupName":"","groupOwner":"","groupNumber":0,"groupAnnouncement":"","groupRemark":"","nameList":["成员名"]}"#, steps: 40)
        case 215, 216, 217:
            let verb = type == 215 ? "新建" : type == 216 ? "修改" : "删除"
            var t = "在企业微信的“客户群”管理（工作台→客户群→防骚扰）里\(verb)防骚扰规则“\(object.isEmpty ? f.s("groupTemplate") : object)”。"
            if type != 217, !extra.isEmpty { t += "规则内容：\(extra)。" }
            if type != 217, !f.list("titleList").isEmpty { t += "适用的群：\(q(f.list("titleList")))。" }
            return job(t, steps: 40, texts: [extra])
        case 218:
            let kind = Self.mediaKind(fileType: f.s("fileType"), url: f.s("fileUrl"))
            let pick = kind == .photos
                ? "点输入框右边的“+”→“相册”/“照片”，选相册里最新的那一个（刚存进去的）发送"
                : "点输入框右边的“+”→“文件”，在“我的 iPad › 小藍 › orders”里选“\(Self.fileName(f))”发送"
            var j = job(open + "，" + pick + caption, steps: 30, texts: [extra])
            j.media = [f.s("fileUrl")]
            j.mediaKind = kind
            return j
        case 219:
            return job("在\(a)里打开群“\(f.s("groupName"))”，进入群聊信息，" + (app == .wework ? "点“解散群聊”并确认。" : "把所有成员移出后点“删除并退出”（只有群主才能解散）。"), steps: 40)
        case 220:
            let fr = f.friend
            var t = "在\(a)里打开群“\(f.s("groupName"))”，进入群聊信息的成员列表，找到“\(fr.s("name"))”，打开资料，点“添加到通讯录”。"
            if !fr.s("leavingMsg").isEmpty { t += "申请留言填：\(fr.s("leavingMsg"))。" }
            if !fr.s("markName").isEmpty { t += "备注名填“\(fr.s("markName"))”。" }
            if !fr.list("tagList").isEmpty { t += "标签选\(q(fr.list("tagList")))。" }
            return job(t + "然后发送申请。", steps: 30, texts: [fr.s("leavingMsg"), fr.s("markName")])
        case 221 where app == .wechat:
            let fr = f.friend
            var t = "在微信通讯录里找到好友“\(fr.s("name"))”，打开资料，点右上角“…”→“设置备注和标签”："
            if !fr.s("markName").isEmpty { t += "备注改为“\(fr.s("markName"))”；" }
            if !fr.s("markExtra").isEmpty { t += "描述改为：\(fr.s("markExtra"))；" }
            if !fr.s("phone").isEmpty { t += "电话号码填“\(fr.s("phone"))”；" }
            if !fr.list("tagList").isEmpty { t += "标签设为\(q(fr.list("tagList")))；" }
            return job(t + "保存。", steps: 30, texts: [fr.s("markName"), fr.s("markExtra")])
        case 221:
            return job(open + "，" + message(f.s("receivedName")) + "长按它，选“设为待办”。")
        case 222:
            return job("在企业微信的“工作台→打卡”里点打卡（上班或下班，按页面上可点的那个），看到打卡成功。", steps: 20)
        case 223:
            return job("在企业微信左上角点企业名称，切换到企业“\(object)”。", steps: 15)
        case 224:
            let link = f.s("fileUrl").isEmpty ? content : f.s("fileUrl")
            let text = [object, extra, link].filter { !$0.isEmpty }.joined(separator: "\n")
            return job(open + "，点底部输入框，输入下面这段内容并发送（链接会自动变成可点的）：\n\(text)", texts: [text])
        case 225:
            var t = "在企业微信里打开群“\(f.s("groupName"))”，进入群聊信息，"
            t += f.s("newGroupName").isEmpty ? "按这个要求修改群成员信息：\(extra)" : "把“我在本群的昵称”改为“\(f.s("newGroupName"))”"
            return job(t + "。", texts: [f.s("newGroupName"), extra])
        case 226:
            return job(open + "，找到我自己发的这条消息（不在屏幕上就往上翻）：\n\(f.s("originalContent"))\n长按它，选“撤回”。超过撤回时间就 fail。")
        case 227, 228:
            let picked = f.messages.isEmpty ? [f.s("originalContent")] : f.messages
            return job(open + "，长按其中一条消息选“多选”，勾选这些消息：\(q(picked))，然后点“\(type == 227 ? "逐条转发" : "合并转发")”，"
                       + "逐个选中转发对象：\(q(f.list("nameList")))，发送。", steps: 40)
        case 229, 230:
            let texts = f.messages.isEmpty ? [content] : f.messages
            if type == 230 {
                let all = texts.joined(separator: "\n")
                return job(open + "，点底部输入框，输入下面这段内容作为一条消息发送，一字不改：\n\(all)", texts: [all])
            }
            let list = texts.enumerated().map { "第\($0.offset + 1)条：\n\($0.element)" }.joined(separator: "\n")
            return job(open + "，按顺序一条一条发送下面这些消息，每条都一字不改、单独发送：\n\(list)", steps: 20 + 8 * texts.count, texts: texts)
        case 290:  // 174 (小藍 only, user 11-25): on an iPhone or iPad a chat is deleted from the list by a swipe, not a long press
            return job("在\(a)的会话列表里找到「\(f.list("titleList").first ?? "")」那一行（不要点开它），在这一行上向左滑，"
                       + "右边会露出按钮，点红色的“删除”；如果再弹出确认，就点确认里的“删除”。这一行从列表消失就完成。", steps: 15)
        case 231, 232:
            return job(open + "，点输入框右边的“+”→“\(type == 231 ? "语音通话" : "视频通话")”" + (app == .wechat ? "（再选“\(type == 231 ? "语音" : "视频")通话”）" : "")
                       + "，发起后看到正在呼叫就完成，不要挂断。", steps: 20)
        case 233, 243:
            var j = job("在\(a)里点右上角“+”→“扫一扫”，点右下角的相册图标，选相册里最新的那张二维码（刚存进去的）"
                        + (type == 243 ? "，进群页面点“加入群聊”。" : "，按页面提示完成（如“加入”“确认”）。"), steps: 25)
            j.media = [f.s("fileUrl")]
            j.mediaKind = .photos
            return j
        case 234, 236:
            let names = f.friend.s("name").isEmpty ? f.list("titleList") : [f.friend.s("name")]
            return job("在\(a)通讯录里逐个找到这些联系人：\(q(names))，打开资料，点右上角“…”→“删除”并确认。"
                       + (type == 236 ? "只删已经把我删掉的（单向）联系人：打开会话发不出消息或资料显示需要验证的才删，不是就跳过。" : ""), steps: 20 + 12 * names.count)
        case 235:
            return job("在企业微信里找到推荐项“\(object.isEmpty ? extra : object)”（工作台或消息页上的推荐卡片），点开它。", steps: 20)
        case 237:
            return job("在企业微信的“我→设置→通用”里找到清理缓存（存储空间→清理缓存），清理并确认。", steps: 25)
        case 241:
            var j = job("在微信“发现→朋友圈”点右上角相机图标，" + (f.s("fileUrl").isEmpty ? "长按相机图标发纯文字朋友圈，" : "“从相册选择”刚存进去的最新图片或视频，")
                        + "文字填：\n\(f.s("originalContent"))\n然后点“发表”。", steps: 30, texts: [f.s("originalContent")])
            j.media = f.list("fileUrl").flatMap { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
            j.mediaKind = j.media.isEmpty ? .none : .photos
            return j
        case 242:
            return job("在微信“我→朋友圈”里找到我发的这条朋友圈：\n\(f.s("originalContent"))\n打开它，点删除并确认。", steps: 30)
        case 260:
            let p = f.meta.params, screens = Int(p.s("maxScreens")) ?? 6
            var j = read("在微信里打开好友“\(p.s("friendName"))”的资料页，进入“朋友圈”，从最新一条往下读，最多往下翻\(screens)屏，每条读出：正文、是否视频、是否链接、图片张数。",
                         json: #"{"entries":[{"text":"正文","summary":"没有正文时写看到的内容","isVideo":false,"isLink":false,"imageCount":0}]}"#, steps: 20 + 6 * screens)
            j.moments = moments(f)
            return j
        case 261, 263, 265:
            let p = f.meta.params, text = p.s("text"), locate = p.s("locateText").isEmpty ? text : p.s("locateText")
            var t: String
            if type == 261 {
                let images = p.list("imageUrls")
                t = "在微信“发现→朋友圈”点右上角相机图标，" + (images.isEmpty ? "长按相机图标发纯文字朋友圈，" : "“从相册选择”刚存进去的最新\(images.count)张图片（按顺序），")
                    + "文字填：\n\(text)\n然后点“发表”。"
            } else {
                t = "在微信里打开好友“\(p.s("friendName"))”的朋友圈，找到这条：\n\(locate)\n"
                    + (type == 263 ? "打开视频，长按选“保存视频”，然后回到“发现→朋友圈”，点相机图标“从相册选择”刚保存的视频，"
                                   : "点开里面的链接，点右上角“…”→“分享到朋友圈”，")
                    + "文字填：\n\(text)\n然后点“发表”。"
            }
            var j = job(t, steps: 40, texts: [text])
            if type == 261 { j.media = p.list("imageUrls"); j.mediaKind = j.media.isEmpty ? .none : .photos }
            j.moments = moments(f)
            return j
        case 502:
            return read("在\(a)通讯录里找到“\(chat)”，打开资料页，读出名字、备注、微信号/账号、电话、企业、描述和标签。",
                        json: #"{"name":"","markName":"","userId":"","phone":"","markCorp":"","markExtra":"","tagList":[]}"#)
        case 503:
            return read("在\(a)里打开“我”的个人信息页，读出名字、微信号/账号、性别、电话、职务、企业、个性签名。",
                        json: #"{"name":"","alias":"","gender":"","phone":"","job":"","corporation":"","sumInfo":""}"#)
        case 504:
            // Stays on the code: the app keeps that screen as the bean's qrcode, then goes back (runOrder).
            return Job(label: name, task: start + look + "在\(a)里打开群“\(f.s("groupName"))”，进入群聊信息，点“群二维码”，"
                           + "让二维码完整显示在屏幕上，停在这个页面不要返回，用 done 完成，answer 只写一行 JSON：" + #"{"groupName":""}"#
                           + "\n打不开就 fail，并写明原因。", steps: 25, readOnly: true, query: true)
        case 505:
            return read("在\(a)的消息列表里从上往下读出最近的会话名称（读两屏）。", json: #"{"titleList":["会话名"]}"#)
        case 506:
            return read("在企业微信左上角点企业名称，读出可以切换的全部企业名称（看完就关掉这个列表）。", json: #"{"nameList":["企业名"]}"#)
        case 507:
            return read("在\(a)通讯录里从上往下翻到底，读出全部联系人名字。", json: #"{"nameList":["名字"]}"#, steps: 80)
        case 508:
            return read("在\(a)通讯录里打开“群聊”（保存到通讯录的群），从上往下翻到底，读出全部群名。", json: #"{"titleList":["群名"]}"#, steps: 60)
        case 509: return Job(label: name, local: .files)
        case 510: return Job(label: name, local: .log)
        case 511:
            return read("在企业微信的“会议”里读出接下来的会议（时间和主题）。", json: #"{"nameList":["时间 主题"]}"#)
        case 512:
            return read("在\(a)里打开群“\(f.s("groupName"))”，进入群聊信息，点“查看更多群成员”，从上往下翻到底，读出全部成员名字。",
                        json: #"{"groupName":"","nameList":["成员名"]}"#, steps: 60)
        case 513: return Job(label: name, local: .resources)
        case 514: return Job(label: name, local: .logRange(f.s("startDate"), f.s("endDate")))
        default: return nil
        }
    }

    /// After a task that stays on a page (504, 跟圈 pictures).
    static let backToList = "回到微信的聊天列表（企业微信就先回到微信），然后完成。"

    /// 跟圈 260, a post with pictures: its first picture opened full screen, where the app keeps each picture as shown.
    static func openMomentPicture(friend: String, locate: String) -> String {
        "只看不改：不要发送任何消息、不要点赞评论。在微信里打开好友“\(friend)”的资料页，进入“朋友圈”，找到这一条：\n\(locate)\n"
            + "点它的第一张图片，让图片全屏显示，停在这个页面不要返回，用 done 完成。找不到这条就 fail。"
    }

    private static func moments(_ f: Fields) -> Moments {
        let m = f.meta
        return Moments(runId: m.s("runId"), robotId: m.s("robotId"), resultUrl: m.s("resultUrl"), resultToken: m.s("resultToken"),
                       friend: m.params.s("friendName"), uploadUrl: m.s("uploadUrl"), uploadToken: m.s("uploadToken"))
    }

    static func mediaKind(fileType: String, url: String) -> MediaKind {
        let t = fileType.lowercased(), ext = (URL(string: url)?.pathExtension ?? "").lowercased()
        if t.contains("image") || t.contains("video") || t == "1" || t == "2" { return .photos }
        return ["jpg", "jpeg", "png", "gif", "heic", "webp", "mp4", "mov", "m4v"].contains(ext) ? .photos : .files
    }

    /// The name a downloaded file gets in Documents/orders: objectName when given, else the URL's last part.
    static func fileName(_ f: Fields) -> String {
        let named = f.s("objectName"), last = URL(string: f.s("fileUrl"))?.lastPathComponent ?? ""
        let raw = named.isEmpty ? (last.isEmpty ? "file" : last) : named
        return raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    }

    // MARK: - Reads

    /// The first {...} in a done answer, as an object.
    static func object(_ answer: String) -> [String: Any]? {
        guard let open = answer.firstIndex(of: "{"), let close = answer.lastIndex(of: "}"), open < close else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(answer[open...close].utf8))) as? [String: Any]
    }

    /// A read order's data bean, sent up as socketType 2 like the engines' (`{type:503, myInfo:{…}}`). nil: no JSON.
    static func dataBean(type: Int, chat: String, f: Fields, answer: String) -> [String: Any]? {
        guard let o = object(answer) else { return nil }
        switch type {
        case 502: return ["type": type, "titleList": [chat], "friend": o]
        case 503: return ["type": type, "myInfo": o]
        default:
            var bean = o
            bean["type"] = type
            if bean["groupName"] == nil || (bean["groupName"] as? String)?.isEmpty == true, !f.s("groupName").isEmpty { bean["groupName"] = f.s("groupName") }
            return bean
        }
    }

    /// 跟圈 260's entries with the fingerprints the backend dedupes on. A post with pictures starts incomplete; runOrder
    /// then opens each picture, keeps it as the screen shows it and uploads it (imageUrls, imagesComplete).
    static func momentEntries(friend: String, answer: String) -> [[String: Any]] {
        guard let list = object(answer)?["entries"] as? [[String: Any]] else { return [] }
        return list.compactMap { e in
            let text = (e["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = (e["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(text + summary).isEmpty else { return nil }
            let images = e["imageCount"] as? Int ?? 0
            var out: [String: Any] = ["fp": fingerprint(friend + "\n" + text + "\n" + summary), "text": text, "summary": summary,
                                      "locateText": text.isEmpty ? summary : text, "isVideo": e["isVideo"] as? Bool ?? false,
                                      "isLink": e["isLink"] as? Bool ?? false, "imageCount": images, "imageUrls": [String]()]
            if images > 0 { out["imagesComplete"] = false }
            return out
        }
    }

    /// FNV-1a 64, hex: the same text gives the same fingerprint on every launch (Swift's hashValue does not).
    static func fingerprint(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }
}

import Foundation

/// The screen feed is gone; acting now would be guessing.
struct BlindError: LocalizedError {
    var reason = "lost the phone screen: reconnect Screen Mirroring"
    /// Sharing is on and only a new frame is late: looking again is the fix, there is nothing for the user to do.
    var sharingOn = false
    var errorDescription: String? { reason }
}

/// The app is on no Home Screen page and Search lists no such app.
struct AppNotOnPhone: LocalizedError {
    let name: String
    var errorDescription: String? { name + " is not on this phone" }
}

struct InputNeedsVerification: LocalizedError {
    let expected: String
    let remaining: String
    var fieldMayBeComplete = false
    var errorDescription: String? {
        fieldMayBeComplete
            ? "Text was entered but local OCR could not confirm it. Inspect the CURRENT input field for \(expected). "
              + "Do not clear, retype, or paste over correct text. If it is already correct, send it once; "
              + "otherwise explicitly correct only the visible mistake before sending."
            : "Inspect the Pinyin candidates for \(expected); do not assume the first candidate is correct."
    }
}

/// Typed with no keyboard on the screen and nothing new showed: nothing went in (132 c2). Not kept as typed.
struct NothingTyped: LocalizedError {
    var errorDescription: String? { "Not typed: no keyboard is on screen" }  // the step says AgentLoop.noKeyboardReason
}

/// What AgentLoop does on the phone (Pointer, or a fake in tests).
@MainActor protocol Gestures: AnyObject {
    var device: HIDDevice { get }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws
    func drag(_ points: [CGPoint], hold: Bool) async throws
    func type(_ text: String) async throws
    func key(_ combo: String) async throws
    func goHome() async throws
    /// Press and hold (Pointer.longPress): WeChat's message menu (复制, 转发), an icon's menu.
    func longPress(_ x: Double, _ y: Double, seconds: Double) async throws
    /// D18: the same, running `whileHeld` while the finger is still down (a chart shows the value under it only then).
    func longPress(_ x: Double, _ y: Double, seconds: Double, whileHeld: @escaping @MainActor () async -> Void) async throws
    /// The next tap is for something this big (half width and height, 0-1): Pointer clicks a first stop inside it.
    func aimLoosely(_ halfX: Double, _ halfY: Double)
    func goBack() async throws
    func reset() async throws
    func typeQuick(_ text: String) async throws
    func answerSharingQuestion() async throws -> Bool
}

extension Gestures {
    func typeQuick(_ text: String) async throws { try await type(text) }
    func answerSharingQuestion() async throws -> Bool { false }
    /// Fakes in tests: a long press is recorded as a tap there.
    func longPress(_ x: Double, _ y: Double, seconds: Double) async throws { try await tap(x, y, aim: false) }
    func longPress(_ x: Double, _ y: Double, seconds: Double, whileHeld: @escaping @MainActor () async -> Void) async throws {
        try await longPress(x, y, seconds: seconds)
        await whileHeld()
    }
    func aimLoosely(_ halfX: Double, _ halfY: Double) {}
}

extension Pointer: Gestures {}

/// See-think-act loop: a planner model writes the plan, an actor model picks each step. Port of agent.py.
@MainActor final class AgentLoop: ObservableObject {
    struct Planned {
        var act: JObject
        var shot: Data?  // every action of one reply is drawn on the same screenshot
    }

    let phone: Gestures?
    let screen: ScreenSource?
    var actor: ChatModel?, planner: ChatModel?
    let trace: TraceStore?
    let maxSteps: Int, maxFailures: Int
    var metrics: Metrics?
    var experience: ExperienceStore?
    /// The user's corrections from earlier runs, as sentences for the planner and the actor (LessonBook).
    var lessons: LessonBook?
    var routes: RouteBook?
    /// Off for a run whose route depends on what is on screen: WeChat watch's unread check learned "tap 主人蓝海乐"
    /// and replayed it at every check, unread or not, so it kept opening and leaving that chat (logs 11-06, build87).
    var learnedRoutes = true
    /// Learned buttons (send, back), found again by their look; see ControlBook.
    var controls: ControlBook?
    private var sendTap: (point: CGPoint, frame: Data)?  // this run's send tap and the screen it was made on
    private var backMissed = false                        // the last back swipe changed nothing
    private var actFrame: Data?                           // the screen just before the latest action

    private var replayedRoute: String?  // the learned route this run started with
    private var learnedThrough = -1
    private var lessonRun = UUID().uuidString
    /// Plans dropped in a row because the screen moved while the model answered. A plan goes ahead when the
    /// model, looking at a newer screen, chose the same spot again (a live clock icon, a video or an animated
    /// background never hold still), or after two drops when nothing changed where it lands; after five, the
    /// planner looks again.
    private var staleRun = 0
    /// The plan dropped last time, to see whether the next look chose the same spot.
    private var lastStale: JObject?
    /// After a back-and-forth (see bounce): the move that would start it again (`stop`, refused) and its partner.
    /// Any other move ends it; refusing `stop` three times hands the run to the user.
    private var bounceGuard: (stop: JObject, other: JObject)?
    private var bounceRefused = 0
    /// D50: the guard holds the tap that opened the screen (the leave was let through), not the leave.
    private var bounceOpener = false
    /// "done" claims turned down because this run has not made what the task asks for (see unmadeResult).
    private var doneRejected = 0
    /// D16: new plans made for a goal of 10+ things whose plan ran out with things not done (see itemsLeft), and what
    /// was noted and sent at the last one (another comes only after something more got done).
    private var continuations = 0
    private var continuedAt: (notes: Int, sent: Int)?
    /// A Home flick that changed nothing gets one keyboard alternative, never another identical flick.
    private var homeRecoveryTried = false

    @Published private(set) var task = ""
    @Published private(set) var plan = ""
    /// The planner (Codex) as the backstop (user 11-08: "codex要做的是兜底…如果豆包api做不好就讓codex去做"). Its plan
    /// is a list of parts, each a result the screen can show; the executor (Doubao) works on one at a time. When the
    /// executor stalls, spends 20 steps on one part, or gives up, Codex looks again and drives itself until that part
    /// is done. A finished run's whole way is remembered (RouteBook recipe) and followed the next time, without asking
    /// the planner ("做完之後記住做的路徑，下次就可以快速做出來").
    private(set) var parts: [String] = []
    private(set) var partIndex = 0
    private(set) var doneParts: [String] = []
    /// What the agent read and wrote down in this run (a price, a title, a name). A task across apps forgot what it had
    /// read in the last one and went back for it, ten times over (over USB 11-09): this goes with every look.
    private(set) var notes: [String] = []
    /// The text read on the screen the last reply was made on (with where it is): what a tap lands on, and how big it is.
    private var readRows: [[CandidatePicker.Piece]] = []
    /// D86: the Calculator result a note was last refused for (a second note on the same result is kept).
    private var calcNoteRefused: String?
    /// D100: the goal's items a note on a sum in brackets was refused for (once each).
    private var bracketRefused: Set<Int> = []
    /// D107: the goal's items a note with text cut short on the screen was refused for (once each; 0: a note with no item).
    private var cutRefused: Set<Int> = []
    /// D174: each refused cut note's text, and how many notes there were then (kept once the run goes round instead).
    private var cutPending: [Int: (text: String, at: Int)] = [:]
    /// D114: a short goal that reads one group was refused once for ending where that group's title is not shown.
    private var groupTitleRefused = false
    /// D134: a name or remark the goal sets was refused once for being typed again after it was saved.
    private var setAgainRefused = false
    /// D141: refusals of text typed ahead of its items' results (typedAheadOfResults), per run.
    private var aheadRefusals = 0
    /// D144: refusals of a goal's message typed without the number it stands for (offPatternGoalMessage), per run.
    private var offPatternRefusals = 0
    /// D146: a second note with the same first line refused once (secondNoteHead), per run.
    private var secondNoteRefused = false
    /// D115: the last group chat title seen in this run, for a 聊天信息 page opened from it.
    private var lastGroupTitle: String?
    /// D124: finger-down swipes in a chat refused this run because the thought wanted newer messages (two at most).
    private var olderSwipeRefused = 0
    /// D125: a done telling a chat's latest message was refused once for a chat that may be scrolled up.
    private var bottomRefused = false
    /// How often each way off a screen was taken from that screen, in this run.
    private var departures: [(look: [UInt8], move: JObject, times: Int)] = []
    private var circleRefused = 0
    private var deadRefused = 0
    /// D18: the screen while the last hold was still down (see shownOnlyWhileHeld); nil once a look used it.
    private var heldFrame: Data?
    /// D17, D19: refusals of a round of taps (repeatsRound) or of a page scrolled back again (scrollsBackAgain) since
    /// the last change of plan.
    private var roundRefused = 0
    static let bigGoalRefusalLimit = 12
    private var untypedSearches = 0  // searches refused because nothing was typed (twice at most per run)
    private var blindLooks = 0
    private(set) var takeover = 0
    private var refusalRedirectAt = -1   // D35: the look whose refused reply already went to Codex
    private var stepsInPart = 0, rescued = false, troubles = 0
    /// 124 over the cloud 11-12 (g05): every type was refused, the part stalled, a new plan was made, and again, for ten
    /// minutes and ~290 steps with nothing on the screen moving. New plans in a row with nothing noted or finished between
    /// them; at stallLimit the run ends with what it found.
    private var stallsNoProgress = 0
    static let stallLimit = 3
    /// 125 stress test 11-12 (t06): typing was refused 110 times while Codex drove and new plans came 40 times, none of
    /// them through the executor's stall count. Refusals since the last note, part done or message sent; at refusalLimit
    /// the run ends with what it found.
    private var refusalsNoProgress = 0
    static let refusalLimit = 25
    /// 124 over the cloud 11-12 (e02): 行事曆 did not open, the model gave up, and 视频号, Bluetooth and Weather were never
    /// tried. In a goal of three parts or more, this many single things may fail and be written down; the run goes on.
    private var itemFailsLeft = 2
    /// D141b, x4 on 145 (28 things): five things were skipped one by one with things noted between them (3, 4, 5, 6, 8,
    /// 9, 15, 16), and the sixth stuck thing (17, 电池 not opening) ended the run with 18–28 never tried. A skip is given
    /// back once a thing not noted before is noted after it: only skips in a row with nothing got between run out.
    private var skipOwed = false
    /// D142: the part sent back once for a result taken from an earlier run (fromAnEarlierRun); -1: none.
    private var earlierRunRefused = -1
    /// 132 over the cloud 11-14 (c3): 京东 was not on the phone; Codex, driving, said fail three times in 14 s with nothing
    /// done between, each refusal took one of the two allowed, and the third ended a twenty-item run at item 15 (16–20
    /// never tried). A fail right after a refused one, with nothing done between, is the same item: it costs nothing
    /// (twice in a row at most). And a refused fail closes the part it was in, so the next part is worked on.
    private var failRefusedAt = -1.0, freeFailRefusals = 0
    static let oneThingFailedReason = "Not ended: one part could not be done; it is noted as 未能完成. Go on with the "
        + "other parts, then done, saying which part failed and why. Fail only if none of the rest can be done."
    /// The texts sent as messages into a chat (not a search's Return): only these are never typed again.
    private var messageSent: Set<String> = []
    /// Times the "added to the cart" toast came up in this run, and whether it showed on the last screen read.
    private var cartAdds = 0, cartToastShown = false
    /// The same toasts by the app they came in (AppNames.hans, lowercased; "" when no app is known).
    private var cartAddsIn: [String: Int] = [:]
    /// Steps up to here were looked at for a + in 美团 / 饿了么 (addsWithoutToast).
    private var cartTapsChecked = 0
    /// Looks in a row that showed the app's own network error page (appErrorShown).
    private var appErrorLooks = 0
    /// The done check sent the run back once for an item it said it had not done (skippedWithoutReason).
    private var skipAsked = false
    static func addedToCart(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        // 143 z5 (item 11): a shop page's "5000+人已加购" (how many people have it in their cart) was taken for the
        // toast twice, and the run told the user it had put the cup in the cart twice; nothing had been added.
        // D191, x1 on 151 (item 9): 美团's cart panel is headed "已加购商品" (the dishes in the cart). Each look at the cart
        // counted one more add: the notes said "第9项：已加入购物车…第12次" with one cup in it, the run opened and closed the
        // cart some 25 times to check, item 9 was taken for noted and 10 failed in its place. A heading is no toast.
        let text = AppNames.hans(rows.joined().map(\.text).joined())
            .replacingOccurrences(of: #"人\s*已加购|已加购\s*商品"#, with: "", options: .regularExpression)
        return ["加购成功", "已加入购物车", "成功加入购物车", "加入购物车成功", "已加购", "已添加到购物车"].contains { text.contains($0) }
    }
    /// Whether an "added to the cart" text in this app is a shop's toast: an app that sells things, or one not known
    /// (opened by its icon, or none opened yet), as before. In 备忘录, 微信 or Safari it is words someone wrote.
    static func sellsThings(_ app: String?) -> Bool {
        guard let app else { return true }
        let name = AppNames.hans(app).lowercased()
        return ["淘宝", "天猫", "拼多多", "京东", "美团", "饿了么", "闲鱼", "唯品会", "抖音", "taobao", "pinduoduo", "jd", "meituan"]
            .contains { name.contains($0) }
    }
    static func cartNote(_ n: Int) -> String {
        "购物车：第\(n)次看到加购成功的提示，这一件已经加进去了（这次任务一共加了\(n)次）。同一件不要再点加入购物车，每点一次就多一件；目标要几件就只加几次。"
    }

    /// A text already sent that this one is: the same, or (4 characters or more) inside it or holding it with little
    /// around it (an @name). 126 over the cloud 11-12 (g5): a note of ~900 characters quoting "G5买东西做完", sent a
    /// moment before, was refused as that message.
    /// 133 over the cloud 11-14 (y1): "在验证群发“Y1验证”加上现在手机顶部显示的时间" went out as Y1验证9:47 and, after a new
    /// plan, again as Y1验证9:50. A message the goal asks for once, with something added to it, was sent already.
    static func sameGoalMessage(_ typed: String, sent: Set<String>, task: String) -> String? {
        let asked = goalMessages(task)
        // 134 over the cloud 11-15 (y1): a note of the results ("…已在验证群发Y1验证01:45…") held Y1验证 and was refused
        // 42 times as the message again. Only the message with a little added (a time) is it, never a whole note.
        for g in asked where g.count >= 2 && typed.contains(g) && typed.count <= g.count + 12
            && asked.filter({ $0 == g }).count == 1 {
            if let s = sent.first(where: { $0.contains(g) }) { return s }
        }
        return nil
    }

    /// The words the goal says to search for (搜索“…”, 搜“…”, 查找“…”), as typedKey keys.
    static func goalSearches(_ task: String) -> [String] {
        let t = AppNames.hans(task)
        guard let re = try? NSRegularExpression(pattern: #"(?:搜索|搜|查找)\s*[“"「]([^”"」]{1,40})[”"」]"#) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { typedKey(ns.substring(with: $0.range(at: 1))) }
    }

    /// D91, z3 on 138 (item 36): in 验证群 to read its last five messages, Doubao typed Z3验证11:07 for item 33 again
    /// (Z3验证11:03 had gone out there at 11:04). The title was read as "（Ye）超亚死", not where it went, so it was typed;
    /// its Return was blocked as the wrong place, and it was left in the box. A text sent already is typed again only
    /// under the title of another group or chat the goal names: a chat title read that is none of them is no place for it.
    static func notAGoalGroup(_ title: String?, task: String, steps: [JObject]) -> Bool {
        guard let title, !namedGroups(task).isEmpty, !goalNamesChat(title, task: task) else { return false }
        return chatCheck(seen: title, task: task, steps: steps) != .right
    }

    static func sameMessage(_ typed: String, in sent: Set<String>) -> String? {
        guard !typed.isEmpty else { return nil }
        if sent.contains(typed) { return typed }
        return sent.first { s in
            min(s.count, typed.count) >= 4 && abs(s.count - typed.count) <= 12 && (s.contains(typed) || typed.contains(s))
        }
    }

    /// The thought says part `n` is finished ("第5部分完成", "part 5 done"), or the last numbered item of the part's
    /// text ("第18项完成" for a part that ends with "18. 新建一条备忘录…").
    static func saysPartDone(_ thought: String, part n: Int, text: String) -> Bool {
        let t = AppNames.hans(thought).lowercased().filter { !$0.isWhitespace }
        var marks = ["第\(n)部分完成", "第\(n)部分已完成", "part\(n)done", "part\(n)isdone", "part\(n)complete", "part\(n)finished"]
        let ns = text as NSString
        let items = ((try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[\.、．]"#))?
            .matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [])
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        // D68, y4 on 137: the part "第46项：… including the outcome of item 44." was closed by "第44项已完成，现在打开备忘录":
        // the 44. of its last words was taken for its number. A part that starts with its number is that number.
        let own = text.range(of: #"^\s*(?:第\s*)?\d{1,3}\s*(?:[项項]|[.、．](?!\d))"#, options: .regularExpression)
            .flatMap { Int(text[$0].filter(\.isNumber)) }
        if let last = own ?? items.max() { marks += ["第\(last)项完成", "第\(last)项已完成", "item\(last)done", "item\(last)isdone"] }
        return marks.contains { t.contains($0) }
    }

    /// How many things the goal puts in carts: for each clause that adds (加入购物车, 加购), its count (一件, 一份, 2杯;
    /// not 第一个 or 前5个), one when it gives none. At least one.
    static func cartWanted(_ task: String) -> Int { max(cartCounts(task).reduce(0, +), 1) }

    /// What the goal asks to put in the cart of this app: the parts (；) that name it (美团外卖 for 美团 too). The whole
    /// goal's count when no app is known or no part names it.
    static func cartWanted(_ task: String, in app: String?) -> Int {
        guard let app else { return cartWanted(task) }
        let name = AppNames.hans(app).lowercased()
        let counts = AppNames.hans(task).lowercased().components(separatedBy: CharacterSet(charactersIn: "；;\n"))
            .filter { !name.isEmpty && $0.contains(name) }
            .flatMap { cartCounts($0) }
        return counts.isEmpty ? cartWanted(task) : max(counts.reduce(0, +), 1)
    }

    /// The most the goal asks of any one thing it puts in a cart (一件 → 1), at least one.
    static func cartEach(_ task: String) -> Int { max(cartCounts(task).max() ?? 1, 1) }

    /// For each clause of the goal that adds to a cart, its count.
    static func cartCounts(_ task: String) -> [Int] {
        let numbers: [String: Int] = ["一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        let re = try? NSRegularExpression(pattern: #"(?<![第前])([0-9]+|[一两二三四五六七八九十])(件|份|杯|个|盒|瓶|袋)"#)
        var counts: [Int] = []
        for clause in AppNames.hans(task).components(separatedBy: CharacterSet(charactersIn: "，,；;。")) {
            guard clause.contains("加入购物车") || clause.contains("加购") else { continue }
            let ns = clause as NSString
            let n = re?.firstMatch(in: clause, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
            counts.append(n.flatMap { Int($0) ?? numbers[$0] } ?? 1)
        }
        return counts
    }

    /// A tap the thought says adds to the cart (点加入购物车, tap 加购), not one that closes the sheet, opens the cart,
    /// or takes one off.
    static func addsToCart(_ thought: String) -> Bool {
        let t = AppNames.hans(thought).lowercased()
        // 133 over the cloud 11-14 (x3): 美团 got the same 套餐 ×3 with no add counted; "tap the yellow Add to Cart button"
        // has 12 characters between: up to 16 now, and 加到 / 加进 / "add it to the cart" too.
        let adds = t.range(of: #"(点击|点|按|tap)[^，。,.]{0,16}(加入购物车|加到购物车|加进购物车|加购|add to cart|add (it|this|one) to (the )?cart)"#,
                           options: .regularExpression) != nil
        let other = ["关闭", "关掉", "close", "返回", "back", "减", "删除", "移除", "remove", "打开购物车", "去购物车", "进入购物车",
                     "open the cart", "go to the cart", "购物车图标", "cart icon"].contains { t.contains($0) }
        return adds && !other
    }

    /// 美团 and 饿了么 show no "added" toast: a dish's + puts it in, with a count beside it. 132 over the cloud 11-14 (c3):
    /// "把一份最便宜的加入购物车" became 10 things in 美团's cart (¥96.5), every + let through with no toast to count.
    static func addsWithoutToast(_ app: String?) -> Bool {
        guard let app else { return false }
        let name = AppNames.hans(app).lowercased()
        return ["美团", "饿了么", "meituan", "eleme"].contains { name.contains($0) }
    }

    /// A tap the thought calls a dish's + ("点它的绿色加号", "tap its green + button").
    static func tapsPlus(_ thought: String) -> Bool {
        let t = AppNames.hans(thought).lowercased()
        return t.range(of: #"(点击|点|按|tap)[^，。,.]{0,20}(加号|[+＋]|plus)"#, options: .regularExpression) != nil
            && !["减", "关闭", "返回", "minus", "close", "back"].contains { t.contains($0) }
    }

    /// An add to the cart: the words, or in 美团 / 饿了么 the + as well.
    static func addsDish(_ thought: String, in app: String?) -> Bool {
        addsToCart(thought) || (addsWithoutToast(app) && tapsPlus(thought))
    }

    /// 133 over the cloud 11-14 (x4, x5, x6, r133b2): 美团 answered "网络错误（H403#CS8#…）" from 20:30 on; reloading never
    /// helped and the runs went round until the loop guard ended them. An app's own error page on 3 looks in a row:
    /// the model is told to write the thing down as not done and go on.
    static func appErrorShown(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let text = AppNames.hans(rows.joined().map(\.text).joined())
        return ["网络错误", "网络好像不太给力", "网络不给力", "网络异常", "加载失败", "请求失败", "服务器开小差", "H403#"]
            .contains { text.contains($0) }
    }
    static let appErrorNote = "这个 App 一直显示网络错误，重新加载也没用：这一项现在做不成。把它记为未能完成（原因：App 报网络错误），"
        + "不要再重新加载，接着做下一项。"

    /// 133 over the cloud 11-14 (y5, 23:3x): "open 天气" showed Screen Time's limit page; the run opened 天气 again and
    /// again until the loop guard ended it. User 11-15: "該按忽略限制就按吧…除了替我輸密碼其他的都可以": the limit is
    /// lifted the least way (15 minutes, else today); a Screen Time passcode is never typed, and then the thing is not done.
    static func screenTimeShown(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let text = AppNames.hans(rows.joined().map(\.text).joined())
        return ["已达到时间限制", "时间限制", "停用时间", "屏幕使用时间", "Time Limit", "Downtime"].contains { text.contains($0) }
            && ["忽略限制", "Ignore Limit", "请求更多时间", "Ask For More Time", "15分钟后提醒我", "今天内忽略限制",
                "Remind Me in 15 Minutes", "Ignore Limit for Today"].contains { text.contains($0) }
    }
    /// 134 over the cloud 11-15 (y3): 高德's route asked for location, "继续关闭定位服务" closed the sheet, the route button
    /// brought it back, 29 times round. A route from here cannot be had with location off; Settings are not ours to change.
    static func locationOffShown(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let text = AppNames.hans(rows.joined().map(\.text).joined())
        return ["定位服务已关闭", "继续关闭定位服务", "打开定位服务", "Location Services Off", "Turn On Location Services"]
            .contains { text.contains($0) }
    }
    static let locationOffNote = "手机的定位服务关着：要“从现在位置/当前位置”出发的路线或“附近”的结果现在做不成。不要去设置里打开，"
        + "也不要再点路线按钮：把这一项记为未能完成（原因：定位服务已关闭），接着做下一项。"

    /// A Screen Time passcode is asked for (输入屏幕使用时间密码 / Enter Screen Time Passcode).
    static func screenTimePasscodeShown(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let text = AppNames.hans(rows.joined().map(\.text).joined())
        return ["屏幕使用时间密码", "Screen Time Passcode", "输入密码"].contains { text.contains($0) }
    }
    static let screenTimeNote = "这个 App 被手机的“屏幕使用时间”限制住了。机主允许解除：点“忽略限制”，再选“15分钟后提醒我”"
        + "（没有这一项才选“今天内忽略限制”），然后接着做。如果要输入屏幕使用时间密码，就不要输，退出来，把这一项记为未能完成"
        + "（原因：要屏幕使用时间密码），接着做下一项。"
    static let screenTimePasscodeNote = "这里要输入密码（屏幕使用时间或账号的密码）：密码不能代输。退出来，把这一项记为未能完成"
        + "（原因：要密码），接着做下一项。"

    /// Where the gray cursor disk is on this screen (0-1000), so what it covers is not read as a badge.
    static func cursorNote(_ at: CGPoint) -> String {
        "The gray cursor disk is at x \(Int((at.x * 1000).rounded())), y \(Int((at.y * 1000).rounded())): "
            + "it is not a badge or a count; what is under it is hidden."
    }

    /// D148, x4 on 145 (rerun): item 6 (淘宝, add the cheapest chair) was added at step 115; the note said only "购物车：第1次
    /// 看到加购成功的提示…", nothing was noted as 第6项, and stuck replans planned 6 again four times: about 200 steps going
    /// back to the chair and being refused at 加入购物车. An add is noted as the goal's item when the part names one.
    static func cartItemHead(part: String?, goalParts: Int) -> String {
        guard goalParts >= 3, let part, partItemRange(part) == nil,
              let r = part.range(of: #"^\s*(?:\d{1,2}\s*[.)、．]\s*)?第\s*\d{1,3}\s*[项項]"#, options: .regularExpression),
              let n = noteItems(String(part[r])).first else { return "" }
        return "第\(n)项：已加入购物车。"
    }

    static func cartTapNote(_ n: Int) -> String {
        "购物车：这个 App 加购不会弹提示，按加号算：这是第\(n)次加进购物车（这次任务一共加了\(n)次）。同一件不要再点加号，每点一次就多一份；目标要几份就只加几次。"
    }

    static func cartFullReason(_ n: Int) -> String {
        "Refused: the \"added to cart\" toast came \(n) time(s), as many as the goal asks: it is in the cart. Do not tap "
            + "加入购物车 again. Close the sheet (✕) and open the cart page (购物车) to check the count; tap − there if it holds too many."
    }

    /// A thought that drags a picture down to close it ("往下拖一下关闭", "drag it down to close it").
    static func saysDragDown(_ thought: String) -> Bool {
        let t = AppNames.hans(thought).lowercased()
        // Not 往下滑 / swipe down: said of a page, they mean its content goes up, the finger up.
        let down = ["往下拖", "向下拖", "下拉关闭", "下滑关闭", "drag it down", "drag down", "dragging it down",
                    "drag the picture down"].contains { t.contains($0) }
        return down && ["关", "close"].contains { t.contains($0) }
    }

    static func sentNote(_ text: String, to place: String?) -> String {
        "已在" + (place.map { "“\($0)”" } ?? "聊天里") + "发出：" + String(text.prefix(80))
    }
    private var sendIsMessage = false
    /// How many notes there were when the current part began, and the last part whose "done" was sent back once for
    /// having nothing written down (B8).
    private var notesAtPart = 0, emptyPartRefused = -1
    /// D69: the part whose items were found not all written down, and how often its "done" was sent back.
    private var rangeRefused = (part: -1, times: 0)
    /// The screen just before the last paste (B4: what the paste put in is read against it).
    private var pasteFrame: Data?
    /// Opens of the app the run is already in, refused (once a run).
    private var sameAppRefused = 0
    /// The app a picture is shown full screen in, after that refusal: the next Home or open of it taps the picture's
    /// middle instead. 124 over the cloud 11-12 (g06) and in the watch: after the refusal the model went Home and opened
    /// WeChat again, WeChat came back on the same Seoul screenshot, and both models took it for Weather until the run failed.
    private var pictureIn: String?
    /// A listen heard what an earlier one did: the video started over, and listening again is refused.
    private var listenedAll = false
    static let videoLoopedNote = "（视频已经从头重播：这次听到的和前面基本相同，口播已经听全。不要再 listen，直接用上面听到的内容作答。）"

    static func repeatsHeard(_ new: String, before: [String]) -> Bool {
        func grams(_ s: String) -> Set<String> {
            let c = Array(s.filter { !$0.isWhitespace && !$0.isPunctuation })
            guard c.count > 1 else { return [] }
            return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
        }
        let now = grams(new)
        guard now.count >= 20 else { return false }
        return before.contains { old in
            let was = grams(old)
            return !was.isEmpty && Double(now.intersection(was).count) / Double(now.count) >= 0.6
        }
    }
    /// The app a run is in when it starts without opening one: a task the WeChat watch gives starts in WeChat.
    private var startApp: String? { task.contains("微信会话") ? "微信" : nil }
    /// User 11-09: "未知的内容由codex先去完整走一遍并学会，然后后面交给豆包干". A task the phone has not done before is driven
    /// by the planner from the start and its way remembered; from then on the executor follows that way, and the planner
    /// comes only when it stalls. Fixed plans (watching WeChat) are not tasks of this kind.
    var plannerLeadsUnknown = false
    /// A finished task is looked at once more before it is reported (see wrongClaim). Fixed flows keep their own checks.
    var verifiesDone = false
    private var checksLeft = 2
    private var plannerLeads = false
    /// How this task was done the last time it finished (nil: never, or a fixed plan such as watching WeChat).
    private(set) var recipe: RouteBook.Recipe?
    @Published var steps: [JObject] = []
    @Published private(set) var shots: [Int: Data] = [:]  // step index -> screenshot the model decided on
    @Published private(set) var running = false
    private var pointerAt = CGPoint.zero  // last pointer position (screen fractions)
    /// When the last gesture ended: the model never decides on a frame from before it.
    private(set) var lastActed = 0.0
    /// Awaited before every look and every gesture (the app holds the run while its own UI is in front).
    var gate: (() async throws -> Void)?
    static let maxTokens = ["planner": 1500, "actor": 1000]
    // D25: a goal of 10+ things (its plan and its answer list every thing). User 11-15: "上限擡高到3萬吧". A server that
    // takes less says so in a 400, and LLMClient asks again under its limit.
    static let bigGoalTokens = 30000
    private var job: Task<Void, Never>?
    var onFinish: (() -> Void)?
    /// Paused for the board to come back (a line for the UI), or nil when going on.
    /// Recovery from a lost link: the link state (from the app), each stage as it changes (nil = live again),
    /// and what to redo once live (stream on, fresh frame, release, re-home).
    var link: (() -> Recovery.Link)?
    var onRecover: ((Recovery.Stage?) -> Void)?
    var restore: (() async throws -> Void)?
    var recoveryLimit = Recovery.limit
    var onStep: (() -> Void)?
    /// What the agent is busy with between steps, for the Dynamic Island (looking, thinking, about to act).
    var onDoing: ((Doing) -> Void)?
    enum Doing { case looking, waiting, planning, thinking, retrying, acting(JObject) }
    /// Hints from a saved intent's checklist, appended to the actor's system prompt (empty = the original prompt).
    var hints: [String] = []
    /// Reference text the user chose for this run (WeChat watch: the selected knowledge files), appended to the
    /// planner and actor prompts. Empty for ordinary runs.
    var reference = ""
    /// Phase B (specs/004): text typed by Lan Agent's keyboard into the focused field (true when it confirmed);
    /// whether that keyboard is on screen; and opening an app by name. Nil in tests and demo data.
    var keyboardType: ((String) async -> Bool)?
    var ourKeyboardOnScreen: (() -> Bool)?
    /// The keyboard's own Return while Lan Agent's keyboard is up: WeChat sends on it, and the board's Enter did
    /// nothing there (build104 live 11-08: "收到" stayed in the box twice). True when the keyboard pressed it.
    var keyboardReturn: (() async -> Bool)?
    var openApp: ((String) async throws -> Bool)?
    /// Give the model the screen's text with positions (off in tests whose fake frames carry no text).
    var readsScreenText = false

    /// The screen's text pieces, top to bottom and left to right, as `"text" x y` lines (0-1000); nil when none.
    /// At most `limit` lines, so a long list or chat does not crowd the prompt.
    static func screenText(_ rows: [[CandidatePicker.Piece]], limit: Int = 45) -> String? {
        func readsBefore(_ a: CandidatePicker.Piece, _ b: CandidatePicker.Piece) -> Bool {
            let dy: CGFloat = a.box.midY - b.box.midY
            if abs(dy) > 0.008 { return dy < 0 }   // another line: the higher one first
            return a.box.midX < b.box.midX         // the same line: left to right
        }
        let shown: [CandidatePicker.Piece] = rows.flatMap { $0 }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let pieces = Array(shown.sorted(by: readsBefore).prefix(limit))
        guard !pieces.isEmpty else { return nil }
        var lines: [String] = []
        for piece in pieces {
            let text = piece.text.replacingOccurrences(of: "\"", with: "'")
            let x = Int((piece.box.midX * 1000).rounded()), y = Int((piece.box.midY * 1000).rounded())
            lines.append("\"\(text)\" \(x) \(y)")
        }
        return lines.joined(separator: "\n")
    }
    /// A fixed plan (WeChat watch's open and send tasks, whose steps never change): used as is, without the
    /// planner's call. Empty for ordinary runs.
    var presetPlan = ""
    /// Begin an authorized phone task with the actor; the planner remains available for recovery.
    var directStart = false
    /// Navigation-only completion from a verified frame; message reading still checks the destination.
    var frameCompletion: ((Data) -> String?)?
    /// WeChat watch: fewer steps than maxSteps, and no pause for help (nobody is at the phone; a stuck task fails
    /// and the watch goes on). nil for ordinary runs.
    var stepLimit: Int?
    /// WeChat watch: text goes in without a model look per phrase (typeFast). Off for ordinary runs.
    var fastText = false
    /// Puts a reply on the pasteboard with Lan Agent in front for a moment (AppModel.hopToPaste); nil in tests.
    var pasteHop: ((String) async -> PasteHopResult)?
    /// What a paste would put in (UIPasteboard, set by AppModel): it is held for approval like typed text.
    var pasteboard: () -> String? = { nil }
    private var pasteHopOff = false  // a hop got lost once in this run: the rest of it types
    /// D47: the executor's account answered that it cannot be used (overdue, wrong key): Codex drives the rest of the run.
    private var actorClosed = false
    private var lastTap: CGPoint?    // the last tap (0-1), the input box when a type follows
    /// WeChat watch send: the target chat's row (0-1) when this frame is the chat list showing it once; nil otherwise.
    var rowTarget: ((Data) -> CGPoint?)?
    /// WeChat watch send: a reply pasted and seen in the box is sent with Return at once (no look to find 发送).
    var returnSends = false
    /// Where this run typed: the input box (0-1), for WeChat watch to send the next reply without a run.
    private(set) var typedInto: CGPoint?
    /// Whether this run's strokes have left a line yet; nil until one is checked.
    private var inkSeen: Bool?
    private var returnSent = false  // typeFast sent the message with Return: the run is done
    /// WeChat watch: a `type` with no keyboard on screen is refused and the next tap aims (logs27: the tap on the
    /// input box landed above it, and "nihaoya" was typed seven times into nothing while the model said the box was
    /// focused). Refused twice in a row, it goes through, in case the keyboard is one the check does not know.
    var keyboardGuard = false
    private var noKeyboard = 0
    private var aimNext = false  // the next tap finds the pointer on screen first
    /// WeChat watch: text this run typed and then sent (Return, or a tap on 发送 at the bottom right). Typing it again
    /// is refused: logs28's phone task sent "你好" to 测试群 twice and was typing it a third time.
    private var sentTexts: Set<String> = []
    /// The chat titles each sent text went to (read at the send; none when the title did not read).
    private var sentPlaces: [String: Set<String>] = [:]
    private var sendCorrections = 0
    /// What this run sent, for a run that ended without "done" (build 67: an @ went out, the model kept looking until
    /// the step limit, and the owner was told "这个我没弄成").
    var sent: [String] { sentTexts.sorted() }
    /// A single-message task gets this many read-only looks to verify a send; no confirmation means failure. nil: off.
    var endAfterSend: Int?
    /// Unsupported quick-Pinyin keyboards seen across runs; OCR uncertainty never disables normal typing.
    var pinyinMisses = 0
    private var quietSinceSend = 0
    private var pendingInput: String?
    private var pendingRefused = 0
    private var notesTypedRefused = false  // D183
    private var timeLineRefused = false  // D185
    /// Text already entered by a quick send, handed over for visual inspection without retyping.
    var inputToInspect: String?
    /// A destination-specific receipt, independent of the actor's next navigation/action guess.
    var sendReceipt: ((String) async -> Bool)?
    /// How often each text showed on screen when this run first typed it. Shown more often later, it was sent or is
    /// still in the box: typing it again is refused (60 on the PC harness: the model sent with WeChat's green 发送
    /// next to the box, which the tap check above missed, typed the text again, and left it in the box).
    private var typedBase: [String: Int] = [:]
    private var unsent: String?  // typed, not sent yet
    private var unsentApp: String?  // the app in front when `unsent` was typed
    private var boxCleared = false  // a send run emptied the box before its first type
    /// Taps that did nothing: each one after which the next stroke still left no line. A spot in here twice is
    /// refused: traces(44) tapped the New Board button at the bottom right a dozen times as if it were the pen.
    /// D153: each with the screen it did nothing on (Vision.experienceScene), so another screen's spot is never refused.
    private var deadTaps: [(tap: JObject, scene: [UInt8]?)] = []
    private var screenScene: [UInt8]? { screen?.frame.flatMap(Vision.experienceScene) }
    /// Checked before every `type`: a reason refuses the text (it is never typed) and goes into the steps, so the
    /// model rewrites it. WeChat watch uses it so private details never leave the phone.
    var outgoingGuard: ((String) -> String?)?
    /// What the video on screen says (speech to text) and the subtitles it shows, for up to so many seconds (AppModel's
    /// listenToScreen). nil in tests and where it is not wired.
    var listen: ((Double) async -> String)?
    /// "Needs your help": asked when the actor gives up or errors repeat; nil = end the run as before.
    var onHelp: ((String) async -> HelpChoice)?
    private var helpAsked = 0
    /// A task from the cloud: nobody is at the phone to answer "needs your help". Build 116 over the cloud 11-10: six tasks
    /// asked, and each stood "running" until the cloud gave up on it (up to 9 minutes). It fails at once, saying why.
    var noHelp = false
    /// The answer the done check last refused, for a run that then gives up (see the fail below).
    private var rejectedAnswer: String?
    enum HelpChoice { case resume, skip, stop }

    init(phone: Gestures?, screen: ScreenSource?, actor: ChatModel?, planner: ChatModel?, trace: TraceStore?,
         maxSteps: Int = 40, maxFailures: Int = 3) {
        self.phone = phone; self.screen = screen; self.actor = actor; self.planner = planner
        self.trace = trace; self.maxSteps = maxSteps; self.maxFailures = maxFailures
    }

    /// traceStarted: the caller already opened the run's trace folder (so a failed start is logged too).
    func start(_ task: String, traceStarted: Bool = false) throws {
        if running { throw DeviceError(message: "agent already running") }
        guard screen?.live == true else { throw DeviceError(message: "no phone screen: start Screen Mirroring first") }
        self.task = task; plan = ""; steps = []; shots = [:]
        pointerAt = .zero
        lastActed = 0
        learnedThrough = -1
        helpAsked = 0
        staleRun = 0
        lastStale = nil
        bounceGuard = nil
        bounceRefused = 0
        bounceOpener = false
        doneRejected = 0
        continuations = 0
        continuedAt = nil
        roundRefused = 0
        // D113b, q143n on 143: the loop lives as long as the app, and these were never emptied: an item number refused
        // once (cut text, a bracket sum, a calculator note) was never refused again in any later task.
        (cutRefused, bracketRefused, calcNoteRefused, groupTitleRefused, lastGroupTitle) = ([], [], nil, false, nil)
        (setAgainRefused, aheadRefusals, offPatternRefusals, secondNoteRefused) = (false, 0, 0, false)
        (olderSwipeRefused, bottomRefused) = (0, false)
        if !traceStarted { trace?.start(task: task) }
        running = true
        job = Task { [weak self] in
            await self?.run()
            self?.running = false
            self?.onFinish?()
        }
    }

    func stop() {
        if let job { job.cancel() } else { running = false }  // a shown (demo) run has no job
        if let device = phone?.device {
            Task { do { try await device.abort() } catch { DebugLog.write("stop failed: \(error.localizedDescription)") } }
        }
    }

    func clear() throws {
        if running { throw DeviceError(message: "stop the agent first") }
        task = ""; plan = ""; steps = []; shots = [:]
    }

    /// Called between two steps of a run (127, user 11-12): the watch tells the owner, who wrote again while this task
    /// goes on, that it will come to it after. Nil for a run with no one to answer.
    var betweenSteps: (() async -> Void)?

    /// Something done between two steps, outside this run (a reply in WeChat), written down so the model knows why the
    /// screen may have moved.
    func aside(_ text: String) { record(nil, ["action": .str("aside"), "reason": .str(text)]) }

    private func record(_ shot: Data? = nil, _ step: JObject) {
        if ["blocked", "refused", "loop"].contains(step["action"]?.str ?? "") { refusalsNoProgress += 1 }
        if let shot { shots[steps.count] = shot }
        steps.append(JObject([("t", .num(now())), ("shot", .bool(shot != nil))]).merging(step))
        trace?.write(kind: "step", step)
        // What each step did, on the computer too (build 69: "kept going back and forth between two screens", and the
        // log held only timings).
        let fields = ["x", "y", "text", "key", "reason", "answer"].compactMap { k -> String? in
            guard let v = step[k] else { return nil }
            let s = v.str ?? v.double.map { String(format: "%.0f", $0) } ?? ""
            return s.isEmpty ? nil : "\(k) \(s.prefix(40))"
        }
        DebugLog.write("act \(steps.count): \(step["action"]?.str ?? "?") \(fields.joined(separator: ", "))")
        onStep?()
        if ["loop", "part stalled"].contains(step["action"]?.str ?? "") { keepCutNotes() }
    }

    /// D174, 148 over the cloud 11-19 (x2 item 7, h22 rerun): a search result's title noted with "…" was refused (D107)
    /// to be opened and read whole; the run opened it (a video, a page), came back, opened it again, and never noted it
    /// again: x2 spent 400 s there, h22 ran out of steps. Once the run goes round, a cut note not noted again since is
    /// kept as it was first read.
    private func keepCutNotes() {
        let pending = cutPending
        cutPending = [:]
        for (n, p) in pending.sorted(by: { $0.key < $1.key }) {
            let later = notes.dropFirst(p.at)
            if (n > 0 ? later.contains(where: { Self.noteItems($0).contains(n) }) : !later.isEmpty) { continue }
            guard !notes.contains(p.text) else { continue }
            notes.append(p.text)
            record(nil, ["action": .str("note"), "text": .str(p.text), "by": .str("run"),
                         "reason": .str("kept as first read: the run went round instead of noting it again")])
            DebugLog.write("note: the cut note for item \(n) is kept as first read; the run was going round")
        }
    }

    /// The board or mirroring went away mid-run: pause ("waiting for the board") until the screen is live
    /// again, up to `reconnectWait` s, instead of failing the run.
    /// The screen is gone (board, hotspot or mirroring lost): pause the run until it is back, in stages.
    /// Returns how many seconds it took, or nil if the screen was there all along. Never ends the run for a
    /// lost link before Recovery.limit.
    func waitForScreen(poll: Double = 0.5) async throws -> Double? {
        guard let screen, !screen.live else { return nil }
        var recovery = Recovery(at: now(), limit: recoveryLimit)
        var shown: Recovery.Stage?
        var lastProbe = -Double.infinity
        defer { if shown != nil { onRecover?(nil) } }
        while true {
            try Task.checkCancellation()
            let state = link?() ?? Recovery.Link(connected: phone?.device.connected ?? true, sta: nil,
                                        ap: screen.live ? "streaming" : nil, frameAt: screen.live ? now() : 0)
            if state.connected, state.ap == "streaming", now() - lastProbe >= 10 {
                lastProbe = now()
                do {
                    try await screen.requireFrame(after: recovery.started)
                    try await restore?()
                    return now() - recovery.started
                } catch is CancellationError { throw CancellationError() }
                catch { DebugLog.write("recover: frame not yet verified: \(error.localizedDescription)") }
            }
            switch recovery.next(state, at: now()) {
            case .live where screen.live:
                try await restore?()
                await screen.settled()
                return now() - recovery.started
            case .live: break
            case .wait(let stage):
                if stage != shown { shown = stage; onRecover?(stage) }
            case .giveUp(let reason):
                throw BlindError(reason: reason)
            }
            try await Task.sleep(nanoseconds: UInt64(poll * 1e9))
        }
    }

    /// pinned: the frame the prompt's text was read from (nextActions), sent as the picture so both are one screen.
    private func ask(_ role: String, _ llm: ChatModel, _ system: String, _ prompt: String,
                     temperature: Double = 0, retryTimeout: Bool = true, pinned: Data? = nil) async throws -> (String, Double, Data?) {
        try await gate?()
        var prompt = prompt
        let lost = try await waitForScreen()
        if let lost {
            record(nil, ["action": .str("reconnected"), "reason": .str(String(format: "connection lost for %.0f s and restored", lost))])
            prompt += "\n\nNote: the connection was lost and restored; re-check the screen before acting."
            try await gate?()  // the user may have opened this app while it was paused
        }
        guard let screen, screen.live else { throw BlindError() }  // never let the model act blind
        try await screen.requireFrame(after: nil)
        let frame = (lost == nil ? pinned : nil) ?? screen.frame, started = now()
        if role == "actor", let frame, let answer = frameCompletion?(frame) {
            DebugLog.write("agent: navigation title found locally; handing off to message verification")
            return ("THINK: The navigation destination is visible; read and verify it next.\nDO: done \(answer)", 0, frame)
        }
        // Retrieve against the very frame sent with this request, after freshness/recovery checks.
        if let frame, let scene = Vision.experienceScene(frame), let image = Vision.image(frame) {
            let aspect = Double(image.width) / Double(image.height)
            prompt += experience?.context(goal: task, scene: scene, aspect: aspect) ?? ""
            if role == "actor" {
                let example: JObject = ["action": .str("circle"), "x": .int(500), "y": .int(450), "r": .int(180)]
                if Self.drawsOnScreen(task, steps: steps), let bounds = Actions.drawingBounds(example, aspect: aspect) {  // D149
                    prompt += String(format: "\n\nScreen width/height = %.4f. Circle R is in width units; vertical radius = R * %.4f."
                        + " For example, circle 500 450 180 covers x 320..680, y %.0f..%.0f. Place parts using these actual bounds.",
                        aspect, aspect, bounds.minY, bounds.maxY)
                }
                for step in steps.suffix(8) {
                    if let b = Actions.drawingBounds(step, aspect: aspect) {
                        prompt += String(format: "\nRecent circle %@ has bounds x %.0f..%.0f, y %.0f..%.0f (0-1000 screen units).",
                            PyJSON.dumps(Actions.key(step)), b.minX, b.maxX, b.minY, b.maxY)
                    }
                }
            }
        }
        onDoing?(retryTimeout ? .waiting : .retrying)
        let reporting = llm as? ModelProgressReporting
        reporting?.onProgress = { [weak self] progress in
            switch progress {
            case .waiting: self?.onDoing?(retryTimeout ? .waiting : .retrying)
            case .receiving: self?.onDoing?(role == "planner" ? .planning : .thinking)
            }
        }
        defer { reporting?.onProgress = nil }
        let reply: ChatResult
        do {
            let quoted = lessons?.relevant(to: task).filter { system.contains($0.text) } ?? []
            lessons?.markUsed(quoted, run: trace?.dir?.lastPathComponent ?? lessonRun, task: task)
            // D25, 135 over the cloud 11-15 (y1): the final answer of 49 things stopped at item 28 ("…差价"), cut at the
            // actor's 1000 tokens. A goal of 10+ things gets room for its whole answer.
            let room = Self.goalParts(task) >= 10 ? Self.bigGoalTokens : (Self.maxTokens[role] ?? 1000)
            let sys = Self.systemWithGoal(system, task: task, prompt: prompt)  // D149
            reply = try await llm.chat(system: sys, text: prompt, image: frame, maxTokens: room, temperature: temperature)
        } catch {
            if !Task.isCancelled, llm === actor, let planner, planner !== llm, ModelRequestFailure.isAccountClosed(error) {
                // D47, 136 over the cloud 11-16 (z5, z6): Doubao answered 403 AccountOverdueError and two runs of 50 things
                // ended; a short task meanwhile went on with Codex after a replan. Codex drives the rest of this run.
                if !actorClosed {
                    actorClosed = true
                    DebugLog.write("actor: \(llm.model)'s account cannot be used (\(error.localizedDescription.prefix(80))); "
                                   + "Codex drives the rest of this run")
                    record(nil, ["action": .str("executor closed"), "reason": .str(String(error.localizedDescription.prefix(200)))])
                }
                return try await ask(role, planner, system, prompt, temperature: temperature, retryTimeout: retryTimeout, pinned: pinned)
            }
            guard retryTimeout, ModelRequestFailure.isTimeout(error), !Task.isCancelled else { throw error }
            DebugLog.write("model request timed out (\(role)); retrying once with a fresh screen")
            onDoing?(.retrying)
            try await Task.sleep(for: .seconds(2))
            // Re-enter the gate and screen checks before retrying; no gesture is repeated.
            return try await ask(role, llm, system, prompt, temperature: temperature, retryTimeout: false)
        }
        let seconds = ((now() - started) * 100).rounded() / 100
        metrics?.llm(first: reply.firstToken, total: reply.total)
        // 134 over the cloud 11-15: whole prompts (the 50-thing goal each time) filled the trace's 2 MB in ~15 minutes, and
        // the steps of where a long run got stuck were gone. The prompt is kept by its head and its tail (this look).
        var rec: JObject = ["role": .str(role), "model": .str(llm.model), "prompt": .str(Self.tracedPrompt(prompt)),
                            "reply": .str(reply.text), "seconds": .num(seconds)]
        if let first = reply.firstToken { rec["first_token_s"] = .num((first * 100).rounded() / 100) }
        if lastActed > 0 { rec["frame_after_action_s"] = .num(((screen.capturedAt - lastActed) * 100).rounded() / 100) }
        trace?.write(frame, kind: "llm", rec.merging(reply.diagnostics))
        return (reply.text, seconds, frame)
    }

    /// A lost board or mirror is not the agent's fault. VideoReadinessError says so directly; a bare
    /// DeviceError counts only once the screen is gone. A connected but undecodable mirror still counts.
    static func isLinkLoss(_ error: Error, screenLive: Bool?) -> Bool {
        if let video = error as? VideoReadinessError { return [.boardDisconnected, .mirroringDisconnected].contains(video) }
        return error is DeviceError && screenLive == false
    }

    /// A drawing or typing task is not done until this run has drawn or typed: a picture or text already on the
    /// screen (an old board, an earlier note, an app's opening animation) is not this run's result. nil = may finish.
    /// Only clear drawing/typing requests are checked, so other tasks are never held back.
    static func unmadeResult(task: String, steps: [JObject]) -> String? {
        let did = Set(steps.compactMap { $0["action"]?.str })
        if did.contains("takeover") { return nil }  // the user did part of it by hand
        let t = task.lowercased()
        let draws = t.range(of: #"[画畫](?=[一个個两兩三几幾只隻张張条條朵幅颗顆棵出上下画畫圆圓圈线線笑星心])"#,
                            options: .regularExpression) != nil
            || t.range(of: #"\b(draw|sketch)\b"#, options: .regularExpression) != nil  // not "drawer"
        if draws, did.isDisjoint(with: ["circle", "path"]) {
            return "Nothing has been drawn in this run yet; a drawing already on screen is from before and does not count. "
                + "Start a new blank canvas (a new board, note or page in this app) and draw it there."
        }
        // A message to send word for word must be typed in this run: the same words in a bubble above are an earlier
        // message (logs(19): an identical reply was "already sent", and the new message went unanswered). Only when
        // nothing was typed at all: a turned-down "done" after a message was sent made it send again (traces(32)).
        if task.contains("一字不改"), did.isDisjoint(with: ["type", "compose"]) {
            return "Nothing has been typed in this run; a bubble with the same words above is an earlier message, not "
                + "this one. Tap the input box, type the message and send it."
        }
        return nil
    }

    /// Apps a goal may name to go into, with the words a model's thought uses for them.
    static let goalApps: [(name: String, also: [String])] = [
        ("拼多多", ["pinduoduo", "pdd"]), ("淘宝", ["taobao"]), ("京东", ["jd.com", "jingdong"]), ("美团", ["meituan"]),
        ("抖音", ["douyin", "tiktok"]), ("小红书", ["xiaohongshu", "rednote"]), ("快手", ["kuaishou"]),
        ("微信", ["wechat", "weixin"]), ("备忘录", ["notes"]), ("日历", ["calendar"]), ("设置", ["settings"]),
        ("天气", ["weather"]), ("股市", ["stocks"]), ("计算器", ["calculator"]), ("时钟", ["clock", "alarm"]),
        // D128, q134h on 144 (h22): a run that began inside Safari said only "address bar" and "Baidu"; "never went into
        // safari" made it search all over again, 12 steps.
        ("提醒事项", ["reminders"]), ("高德", ["amap", "gaode"]),
        // D182, q134h again on 148 (h22): a remembered way opened Safari from the Dock, an icon with no label to go with
        // the step, and the thoughts spoke of "the Baidu results page" and "the weather.com.cn page": "never went into
        // safari" twice, a fresh Safari, 741 s for a right answer. A web page spoken of is the browser.
        ("safari", ["浏览器", "address bar", "url bar", "地址栏", "网址列", "百度", "baidu", "网页", "web page", "webpage"]),
    ]

    /// 123 over the cloud 11-12: a goal of nine parts in seven apps followed a remembered way, did only the weather, and
    /// finished with made-up results for the other eight (拼多多 ¥3.9, a 验证群 message nobody sent); the check said OK.
    /// An app the goal names that this run never went into cannot have given a result. nil = may finish.
    /// `answer`: an app the answer itself says was not done (a part with the app and 未完成 / 没做 / skipped) is not
    /// counted, so an honest answer can finish.
    /// `startedIn`: the app the run began in (the watch's check in 微信会话 never opens 微信; its executor need not name it).
    static func unvisitedReason(task: String, steps: [JObject], answer: String = "", startedIn: String? = nil) -> String? {
        let missing = unvisitedApps(task: task, steps: steps).filter { !Self.ownsNotDone(answer, about: [$0]) && $0 != startedIn }
        guard !missing.isEmpty else { return nil }
        return "This run never went into " + missing.joined(separator: "、") + ": whatever the answer says about them is not "
            + "from this run. Open each of them now and read it there, or answer that those parts were not done."
    }

    /// Whether a part of the answer (split at ；; 。 and line ends) names one of `words` and says it was not done or sent.
    static func ownsNotDone(_ answer: String, about words: [String]) -> Bool {
        // D145: "无法在微信测试群发送“X3外卖合计N元”" (x3 on 145) owns it too.
        let notDone = ["未完成", "未能完成", "没有完成", "没完成", "没做", "未做", "跳过", "做不到", "未发送", "没发送", "没有发送", "未发出",
                       "没发出", "无法", "没法", "not done", "skipped", "could not", "not sent", "wasn't sent", "was not sent"]
        return AppNames.hans(answer).lowercased().components(separatedBy: CharacterSet(charactersIn: "；;。\n")).contains { part in
            words.contains { !$0.isEmpty && part.contains(AppNames.hans($0).lowercased()) } && notDone.contains { part.contains($0) }
        }
    }

    /// 131 over the cloud 11-13 (r131b g5): after four new plans, item 12 (抖音 搜索“北京胡同”) was in none of them; the
    /// model saw it was missing only in 备忘录, answered "12. …：未执行，无记录", and finished, though nothing stood in its
    /// way. Items of a goal of 3+ things the answer says were not done, with no reason given (a login, verification, an
    /// app not installed, nothing found, the minimum order), and not a summary of other items. nil: none.
    /// `absent`: apps this run found are not on the phone (r131c c1: 京东, its item answered "未完成该项读取").
    /// 132 over the cloud 11-14: "配送费与合计金额未完整读取" (g4), "商品种类数未确认" (c1) went through: those words were not
    /// known, and g4's item also said "未支付", which counted as a reason. Each clause is judged with the ones before it
    /// (a reason after it is not its reason), and stopping before paying (未支付, 未提交订单) is what was asked, not a reason.
    static func skippedWithoutReason(_ answer: String, task: String, absent: [String] = []) -> String? {
        guard goalParts(task) >= 3 else { return nil }
        let notDone = ["未执行", "没执行", "没有执行", "未做", "没做", "没有做", "未进行", "没进行", "未完成", "没完成", "没有完成",
                       "无记录", "没有记录", "未记录", "没记录", "未确认", "没确认", "未完整读取", "未读取", "没读取", "没有读取",
                       "not done"]
        let reasons = ["登录", "登陆", "验证", "实名", "身份", "安装", "没装", "未装", "不存在", "找不到", "没找到", "没有找到", "未找到",
                       "无法", "不能", "不支持", "失败", "超时", "网络", "付款", "支付", "下单", "起送", "因为", "由于", "原因", "因",
                       "不要", "禁止", "要求", "卡住", "打转", "来回", "网络错误", "限制", "报错", "步骤用完"]
        let stopsBeforePaying = #"(未|没有|没|不)(提交订单|确认订单|确认支付|支付|付款|下单|提交)"#
        let skipped = numberedItems(answer).filter { item in
            let body = AppNames.hans(String(answer[item.body])).lowercased()
            // D135: "第3、4项无合计金额" points at other items as much as "第3项" does.
            guard body.range(of: #"第\s*\d{1,2}(\s*[、，,和与及到至~-]\s*\d{1,2})*\s*[项項]"#, options: .regularExpression) == nil,
                  !absent.contains(where: { app in
                      let name = AppNames.hans(app).lowercased()
                      return !name.isEmpty && body.contains(name)
                  }) else { return false }
            let clauses = body.replacingOccurrences(of: stopsBeforePaying, with: "", options: .regularExpression)
                .components(separatedBy: CharacterSet(charactersIn: "，,；;。（）()"))
            return clauses.indices.contains { i in
                guard notDone.contains(where: { clauses[i].contains($0) }) else { return false }
                // D135, x3 on 144: "1. 美团外卖搜索“汉堡”：未完成，美团外卖需登录才能浏览店铺" was sent back as no reason given,
                // and the run went back and made a second X3组记录 memo. A bare status after the colon ("：未完成") is
                // explained by the clause right after it; "店名未记录，后来因为网络慢退出" still is not.
                let tail = (clauses[i].components(separatedBy: CharacterSet(charactersIn: "：:")).last ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let upTo = notDone.contains(tail) ? min(i + 1, clauses.count - 1) : i
                return !reasons.contains { reason in clauses[...upTo].contains { $0.contains(reason) } }
            }
        }.map { $0.n }
        guard !skipped.isEmpty else { return nil }
        return "The answer says item " + skipped.map { String($0) }.joined(separator: "、") + " was not done, and nothing stopped "
            + "it (no login, no verification, nothing missing). Do it on the phone now, add its result, then finish again. If "
            + "something does stop it, say what in the answer."
    }

    /// D75, s7 on 138: "整理出一份设置步骤" (the steps to set it up, read in 小红书) was taken for the Settings app, which
    /// this run "never went into": its answer was refused three times and the run failed (137 passed only because a
    /// thought happened to say 设置). 设置 as setting something up (设置步骤, 怎么设置, 设置成) names no app.
    static func withoutSettingUp(_ goal: String) -> String {
        goal.replacingOccurrences(of: #"(怎么|如何|怎样)设置|设置(?=步骤|方法|教程|流程|过程|技巧|指南|攻略|好|成|为)"#,
                                  with: " ", options: .regularExpression)
    }

    static func unvisitedApps(task: String, steps: [JObject]) -> [String] {
        if steps.contains(where: { $0["action"]?.str == "takeover" }) { return [] }  // the user did part of it by hand
        var goal = Self.withoutSettingUp(AppNames.hans(task).lowercased().replacingOccurrences(
            of: #"(不要|不用|不必|别|勿|禁止)[^，,。；;！!？?\n]*"#, with: " ", options: .regularExpression))
        // D140, 145's CI: 用Safari搜索“深圳天气” asked for 天气 to be opened, and App Store 搜索“高德地图” for 高德. Words
        // searched for are no app to go into.
        goal = goal.replacingOccurrences(of: #"((?:搜索|搜|查找)\s*[“"「])[^”"」]{1,40}([”"」])"#, with: "$1 $2",
                                         options: .regularExpression)
        // Only what the model did and said while doing it: not the plan, nor this check's own words.
        // 130 over the cloud 11-13 (q130b g5): on 淘宝's cart the executor "remembered" items 5-8 as done and noted made-up
        // results for them (拼多多 ¥13.9, a message never sent), then typed them into the note: what a note or typing
        // says is no visit. The app opened, and what the model thought while acting in it, are.
        // D22, 134 真人单句 11-15 (h06): 京东 was not on the phone ("open failed"); the answer said 没装 as the goal asked,
        // and "never went into 京东" refused it three times: the run failed. An app this run found absent was looked for.
        let acted: Set<String> = ["open", "open failed", "tap", "type", "note", "swipe", "key", "hold", "listen", "press", "back",
                                  "home", "wait", "path", "readup"]
        var said: [String] = []
        // Fourth round (g8): the thought of "open 美团" said "now items 16 (美团) and 17 (时钟)"; Clock was never opened and its
        // answer made up. An open's thought is the plan ahead: only the app it opened counts.
        for s in steps where acted.contains(s["action"]?.str ?? "") {
            let keys = ["note", "type", "open"].contains(s["action"]?.str ?? "") ? ["app"] : ["thought", "thought_zh", "app", "text"]
            for key in keys { if let v = s[key]?.str { said.append(v) } }
        }
        let seen = AppNames.hans(said.joined(separator: "\n")).lowercased()
        var missing: [String] = []
        for app in goalApps where goal.contains(app.name) {
            var words: [String] = [app.name]
            words += app.also
            words += AppNames.variants(app.name).map { AppNames.hans($0).lowercased() }
            if !words.contains(where: { !$0.isEmpty && seen.contains($0) }) { missing.append(app.name) }
        }
        return missing
    }

    /// Actions that move the screen somewhere (a back-and-forth is made of these).
    private static let moving: Set<String> = ["tap", "swipe", "back", "home", "key"]
    /// D52: steps after which earlier moves are no part of a back-and-forth.
    private static let bounceEnds: Set<String> = ["open", "part done", "thing skipped"]

    /// The plan closes a back-and-forth: the last moves went A, B, A and this one is B again (enter a chat, go back,
    /// enter, go back). Each of them changes the screen, so `repeating` never sees it. Returns A.
    static func bounce(_ act: JObject, after steps: [JObject]) -> JObject? {
        guard moving.contains(act["action"]?.str ?? "") else { return nil }
        // D52, y4 on 136 (item 3): 淘宝's item ended with back (56 89) and taps at (247 765) twice; 微信 was opened for the
        // next item and its back at (56 89) closed "a back-and-forth" with 淘宝's taps: refused three times, the item
        // skipped. Moves before an app opened, a part done or a thing skipped are another screen's.
        let start = steps.lastIndex { bounceEnds.contains($0["action"]?.str ?? "") }.map { $0 + 1 } ?? steps.startIndex
        // D60, y1 on 137 (item 10): 微信 opened on 测试群; back, the back arrow, back again all left it where it was, and the
        // third was refused as "a back-and-forth already gone through" (then Codex's twice): the thing was skipped. A move
        // that changed nothing is no half of a back-and-forth (a dead tap has its own guard).
        let moves = Array(steps[start...].filter { moving.contains($0["action"]?.str ?? "") && $0["changed"] != .bool(false) }.suffix(3))
        guard moves.count == 3, sameSpot(act, moves[1]), sameSpot(moves[2], moves[0]), !sameSpot(moves[0], moves[1])
        else { return nil }
        return moves[0]
    }

    // No app's layout is written into these: the agent works out which control it is by trying, and what worked is
    // learned from the run that got there (any app, not only the ones someone described).
    static let noInkReason = "The stroke left no line on the canvas: no drawing tool is active, so the drag only moved the "
        + "canvas. Look at the controls on screen and work out which one is the drawing tool (a button you already tried that "
        + "changed nothing is not it), select it, then draw again. It is not done until lines show."
    static let sentAgainReason = "Not typed: this run already typed this text and sent it. Look for its bubble: if it "
        + "shows, the task is done, finish with done. If it is still in the input box, tap 发送 instead; never type it again."
    static let sendVerificationReason = "This run already issued the send command for the requested message. "
        + "Do not send it again, type anything, or navigate away. Inspect the CURRENT requested chat and confirm that "
        + "the newly sent message matches the original Goal; an older matching bubble is not confirmation. "
        + "Only wait, done after verification, or fail if the result cannot be verified. If the Goal also asks for "
        + "something to be brought back (a reply, a result), read it on screen and put it in the done answer: the "
        + "program delivers the answer, so never go back to WeChat yourself."

    /// The text as typed, for telling a repeat: quotes and spaces the model adds around it do not count.
    /// A run's outcome from what it sent, in the {"send": …} form WatchReport.sendAnswer reads.
    static func sentAnswer(_ sent: [String]) -> String {
        let words = sent.filter { $0.count > 1 }.map { "“\($0)”" }.joined(separator: "、")
        let text = words.isEmpty ? "消息已按要求发出" : "已发出\(words)"
        return #"{"send":""# + text.replacingOccurrences(of: "\"", with: "") + #""}"#
    }

    /// D183, h14 over the cloud 11-20 (148): "新建一条备忘录，内容写“133真人测试备忘”" made three notes of those words. The
    /// first held them as its title line; the model took the empty body for nothing typed, a paste hiccup brought a new
    /// plan from "新建一条空白备忘录", and its part 2 made another. Words this run already typed in 备忘录, typed there
    /// again, are refused once: the note holding them is in the list.
    static func typedIntoNotesBefore(_ text: String, steps: [JObject], startedIn: String?) -> Bool {
        guard let app = appInFront(steps, startedIn: startedIn),
              ["备忘录", "notes"].contains(AppNames.hans(app).lowercased().filter { !$0.isWhitespace }) else { return false }
        let key = typedKey(text)
        guard key.count >= 4 else { return false }
        return steps.contains { $0["action"]?.str == "type" && typedKey($0["text"]?.str ?? "") == key }
    }
    static let notesTypedAgainReason = "Refused: this run already typed these words in 备忘录, and the note holding them is "
        + "kept (its first line is its title; the body below it stays empty). Never make a second note with the same "
        + "words: go back to the list, open the note that starts with them and check it there, then go on."

    /// D185, n16 over the cloud 11-20 (150): "今天有没有发过“143夜测一”" was answered "发过，凌晨12:38". On the screen 143夜测一
    /// stood under 昨天 晚上11:41, and 凌晨12:38 was the line under it, over 133真人测试一 (two look-alike texts); the done
    /// check passed it. A chat's time line belongs to the messages under it. When the answer quotes a message seen on the
    /// screen and gives the time of a line under it, never the one above it, that is said, with the line above.
    static func timeLineMismatch(_ answer: String, rows: [[CandidatePicker.Piece]]) -> String? {
        func all(_ pattern: String, _ text: String, group: Int = 0) -> [String] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = text as NSString
            return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: group)) }
        }
        let clock = #"\d{1,2}[:：]\d{2}"#
        let times = { (t: String) in Set(all(clock, t).map { $0.replacingOccurrences(of: "：", with: ":") }) }
        let said = times(answer)
        let quoted = all(#"[“"「]([^”"」]{2,30})[”"」]"#, answer, group: 1)
        guard !said.isEmpty, !quoted.isEmpty else { return nil }
        let label = #"^(昨天|前天|今天|星期[一二三四五六日天]|周[一二三四五六日天]|\d{1,2}月\d{1,2}日|\d{4}年\d{1,2}月\d{1,2}日)?(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上)?\d{1,2}[:：]\d{2}$"#
        let lines = rows.filter { !$0.isEmpty }.map { row -> (text: String, label: Bool) in
            let text = row.map(\.text).joined().filter { !$0.isWhitespace }
            let box = row.dropFirst().reduce(row[0].box) { $0.union($1.box) }
            return (text, abs(Double(box.midX) - 0.5) < 0.2 && text.range(of: label, options: .regularExpression) != nil)
        }
        for message in quoted {
            let key = typedKey(message)
            let at = lines.indices.filter { !lines[$0].label && typedKey(lines[$0].text).contains(key) }
            guard key.count >= 3, let last = at.last else { continue }
            let above = at.compactMap { i in lines[..<i].last(where: { $0.label }) }
            if above.contains(where: { !times($0.text).isDisjoint(with: said) }) { continue }
            let below = lines[(last + 1)...].filter { $0.label }
            guard let wrong = below.first(where: { !times($0.text).isDisjoint(with: said) }), let right = above.last else { continue }
            return "Refused: on the screen the time line above “\(message)” is “\(right.text)”; “\(wrong.text)” is under it and "
                + "belongs to the messages after it. A message's time is the nearest time line above it. Answer again with that time."
        }
        return nil
    }

    static func typedKey(_ text: String) -> String {
        text.filter { !$0.isWhitespace && !"\"'“”‘’「」".contains($0) }
    }

    /// The messages the goal asks to send (发“…” / 发送“…”, not in a 不要… clause), as typedKey keys.
    /// D111: the goal's message this text is with something added after it, unless the goal says to add the time to it
    /// ("发“Z6验证”加上现在手机顶部显示的时间") or names the longer text too.
    static func paddedGoalMessage(_ typed: String, task: String) -> String? {
        let goal = AppNames.hans(task)
        let messages = goalMessages(task)
        guard !typed.isEmpty, !messages.contains(typed) else { return nil }
        for m in messages where !m.isEmpty && typed.count > m.count && typed.hasPrefix(m) {
            let quoted = "[“\"「]" + NSRegularExpression.escapedPattern(for: m) + "[”\"」][^；;]{0,40}(时间|时刻)"
            if goal.range(of: quoted, options: .regularExpression) != nil { continue }
            return m
        }
        return nil
    }

    static func goalMessages(_ task: String) -> [String] {
        let t = AppNames.hans(task).replacingOccurrences(of: #"(不要|不用|不必|别|勿|禁止)[^，,。；;！!？?\n]*"#, with: " ",
                                                         options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: #"发(?:送)?\s*[“"「]([^”"」]{1,40})[”"」]"#) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { typedKey(ns.substring(with: $0.range(at: 1))) }
    }

    /// D26, 135 over the cloud 11-15 (y1): "如果深圳…高10度以上，就在微信测试群发“Y1温差大”，否则发“Y1温差小”": 温差小 went out,
    /// the done check (every quoted message) refused the answer twice for "never sent Y1温差大", and the run sent that too.
    /// Messages the goal gives as one or the other (…发“A”…否则/不然/或者…发“B”), as typedKey keys.
    static func eitherMessages(_ task: String) -> [[String]] {
        let t = AppNames.hans(task)
        guard let re = try? NSRegularExpression(pattern: #"发(?:送)?\s*[“"「]([^”"」]{1,40})[”"」][^；;。]{0,30}?(?:否则|不然|要不然|或者|反之)[^；;。“"「]{0,20}?发(?:送)?\s*[“"「]([^”"」]{1,40})[”"」]"#)
        else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map {
            [typedKey(ns.substring(with: $0.range(at: 1))), typedKey(ns.substring(with: $0.range(at: 2)))]
        }
    }

    /// The other one of an either-or pair, already sent, when `text` holds one of the pair; nil otherwise.
    static func eitherPartnerSent(_ text: String, task: String, sent: Set<String>) -> String? {
        for pair in eitherMessages(task) {
            for m in pair where text.contains(m) {
                if let other = pair.first(where: { $0 != m && wasSent($0, sent, task: task) }) { return other }
            }
        }
        return nil
    }

    static func eitherReason(_ sent: String) -> String {
        "Refused: the goal asks for one of two messages, and “\(sent)” was already sent. Do not send the other one; go on "
            + "with the next thing."
    }

    /// The texts the goal says to write somewhere (写“…”, 写上 / 写入, a note's first line), as typedKey keys.
    static func goalWrites(_ task: String) -> [String] {
        let t = AppNames.hans(task)
        guard let re = try? NSRegularExpression(pattern: #"写(?:上|入|下)?\s*[“"「]([^”"」]{1,40})[”"」]"#) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { typedKey(ns.substring(with: $0.range(at: 1))) }
    }

    /// 130 over the cloud 11-13 (q130b g5): "8. 已在微信测试群发送G5买东西做完" — nothing was typed or sent; only a watch run
    /// (endAfterSend) checked its message. A message the goal asks for that this run never sent, unless the answer says so.
    static func unsentGoalReason(task: String, sent: Set<String>, answer: String) -> String? {
        let missing = goalMessages(task).filter { !wasSent($0, sent, task: task) && !ownsNotDone(answer, about: [$0])
            && eitherPartnerSent($0, task: task, sent: sent) == nil }  // D26
        guard !missing.isEmpty else { return nil }
        // 131 over the cloud 11-13 (g4): "G4全部做完" from an earlier day was in the group; told this, the model went 备忘录 ↔
        // 微信 (each time it saw the old bubble it took the message as sent) until the loop guard stopped it.
        return "This run never sent " + missing.map { "“\($0)”" }.joined(separator: "、") + ". The same words already in the "
            + "chat are an older message from an earlier run, not this run's: type and send each again now in the chat the "
            + "goal names (it is approved there), or say in the answer that it was not sent. When a number or fact the "
            + "message needs could not be found (a thing it comes from was 未能完成), send nothing made up in its place: "
            + "say in the answer that it was not sent and why."
    }

    /// D144, x3 on 145 (rerun): 美团 asked to log in, items 3 and 4 were skipped, and “X3外卖合计N元” (N from item 5) had no
    /// number; told it was never sent, the model typed "X3外卖合计无法计算（缺少第3、4项合计金额数据）", and the refused approval
    /// ended the run at item 6 of 26. Text typed as the start of a goal's message with a number in it (N, X) that does not
    /// keep to it: that message.
    static func offPatternGoalMessage(_ typed: String, task: String) -> String? {
        let t = typedKey(AppNames.hans(typed))
        for m in goalMessages(task) {
            guard let r = m.range(of: #"(?<![A-Za-z0-9])[NnXx](?![A-Za-z0-9])"#, options: .regularExpression) else { continue }
            let head = String(m[..<r.lowerBound])
            guard head.count >= 3, t.hasPrefix(head) else { continue }
            let pattern = "^" + NSRegularExpression.escapedPattern(for: head) + #"[0-9０-９][0-9０-９.,，]*"#
                + NSRegularExpression.escapedPattern(for: String(m[r.upperBound...])) + "$"
            if t.range(of: pattern, options: .regularExpression) == nil { return m }
        }
        return nil
    }

    /// D146, x3 on 145 (rerun): the memo "X3组记录" (item 23) was typed into a new note at step 262, and at 303 a second new
    /// note was started with the same first line to put in what was missing; 备忘录's search then found several. Text of
    /// several lines whose first line starts a text of several lines this run already typed: that first line.
    static func secondNoteHead(_ steps: [JObject], typed: String) -> String? {
        func head(_ text: String) -> String? {
            let lines = text.replacingOccurrences(of: "\\n", with: "\n").components(separatedBy: "\n")
            let first = lines[0].trimmingCharacters(in: .whitespaces)
            return lines.count >= 2 && first.count >= 2 ? first : nil
        }
        guard let h = head(typed) else { return nil }
        return steps.contains { $0["action"]?.str == "type" && head($0["text"]?.str ?? "") == h } ? h : nil
    }

    static func secondNoteReason(_ head: String) -> String {
        "Refused: a note starting “\(head)” was already written in this run. Do not start a second one: open that note "
            + "(search “\(head)” in 备忘录), tap at the end of its text and type only what is missing. If it is not there, "
            + "type it again."
    }

    static func offPatternReason(_ message: String) -> String {
        "Refused: the goal's message is “\(message)”, the letter standing for a number worked out on the phone. Type it only "
            + "with that number in its place. When the number could not be worked out (a thing it comes from was 未能完成), "
            + "send nothing in its place: note 未发送 with the reason and say so in the answer."
    }

    /// Whether a screen title is a chat the goal names ("测试群（4人）" for a goal that posts to 测试群).
    static func goalNamesChat(_ title: String, task: String) -> Bool {
        let name = AppNames.hans(title).replacingOccurrences(of: #"[（(]\d+人?(?:[)）]|$)"#, with: "", options: .regularExpression)
            .filter { !$0.isWhitespace }
        return name.count >= 2 && AppNames.hans(task).filter { !$0.isWhitespace }.contains(name)
    }

    /// A goal message counts as sent when a sent text holds it (a 。 or a space more), or it holds a sent text of 4+.
    /// 133 over the cloud 11-14 (h21): "在验证群发“北京明天最高X度”（X换成你看到的数字）" was sent as 北京明天最高12度, and the
    /// answer got "没有发出“北京明天最高X度”" and 部分失败. A message holding a word the goal says to replace matches
    /// any sent text with something in its place.
    static func wasSent(_ message: String, _ sent: Set<String>, task: String = "") -> Bool {
        if sent.contains(where: { $0 == message || $0.contains(message) || ($0.count >= 4 && message.contains($0)) }) { return true }
        for word in placeholders(task) {
            guard let r = message.range(of: word) else { continue }
            let (head, tail) = (String(message[..<r.lowerBound]), String(message[r.upperBound...]))
            guard head.count + tail.count >= 2 else { continue }
            let filled = sent.contains { s in
                let start: Range<String.Index>? = head.isEmpty ? s.startIndex..<s.startIndex : s.range(of: head)
                guard let h = start else { return false }
                guard !tail.isEmpty else { return h.upperBound < s.endIndex }
                guard let t = s.range(of: tail, range: h.upperBound..<s.endIndex) else { return false }
                return t.lowerBound > h.upperBound
            }
            if filled { return true }
        }
        return false
    }

    /// The words a goal says to replace: "（X换成你看到的数字）" → X, "（城市名换成你看到的）" → 城市名.
    static func placeholders(_ task: String) -> [String] {
        let t = AppNames.hans(task)
        guard let re = try? NSRegularExpression(pattern: #"[（(]\s*([^（()）,，。；;\s]{1,6}?)\s*(?:换成|替换成|改成)"#) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// What the answer cannot have from this run, in the owner's words: apps never opened, messages never sent.
    static func unverifiedNote(task: String, steps: [JObject], sent: Set<String>) -> String? {
        let apps = unvisitedApps(task: task, steps: steps)
        let messages = goalMessages(task).filter { !wasSent($0, sent, task: task) && eitherPartnerSent($0, task: task, sent: sent) == nil }
        var parts: [String] = []
        if !apps.isEmpty { parts.append("本次没有打开" + apps.joined(separator: "、") + "，相关项目没有做") }
        if !messages.isEmpty { parts.append("没有发出" + messages.map { "“\($0)”" }.joined(separator: "、")) }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    /// The numbered items of an answer or a note ("2. …", "2、…", "第2项…"), each with where its text starts and ends.
    static func numberedItems(_ text: String) -> [(n: Int, body: Range<String.Index>)] {
        // "12.5元" is not item 12: the mark is not followed by a digit
        guard let re = try? NSRegularExpression(pattern: #"(?:^|[；;。：:，,\n]|\s)\s*(?:第\s*)?(\d{1,2})\s*(?:[.、．](?!\d)|项[：:]?|項[：:]?)\s*"#)
        else { return [] }
        let ns = text as NSString
        let heads = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> (Int, Range<String.Index>)? in
            guard let n = Int(ns.substring(with: m.range(at: 1))), let r = Range(m.range, in: text) else { return nil }
            return (n, r)
        }
        // A list goes up one by one from 1 (a note may be one item of it, any number); a 1 starts another. D67, y4 on 137:
        // item 13 of Codex's whole answer held its own list ("前4篇笔记标题：1. … 2. … 4. …"), the count started again there
        // and stopped at 4, and the answer of 49 lines was thrown away for the raw notes. The longest list is the answer's;
        // an item goes on the latest list it follows (14 after the inner 4 goes on after 13).
        var lists: [[(Int, Range<String.Index>)]] = []
        for h in heads {
            if h.0 != 1, let i = lists.lastIndex(where: { $0[$0.count - 1].0 + 1 == h.0 }) { lists[i].append(h) } else { lists.append([h]) }
        }
        let items = lists.reduce([(Int, Range<String.Index>)]()) { $1.count >= $0.count ? $1 : $0 }
        return items.enumerated().map { (i, h) -> (n: Int, body: Range<String.Index>) in
            let end = i + 1 < items.count ? items[i + 1].1.lowerBound : text.endIndex
            return (n: h.0, body: h.1.upperBound..<end)
        }
    }

    /// A date written 2026年11月14日, 11月14日 or 2026-11-14 (groups: year?, month, day).
    static let datePattern = #"(?:(\d{4})\s*[年\-/.]\s*)?(\d{1,2})\s*[月\-/.]\s*(\d{1,2})\s*[日号號]?"#

    static func date(_ ns: NSString, _ m: NSTextCheckingResult, at first: Int, calendar: Calendar, near: Date) -> Date? {
        guard let month = Int(ns.substring(with: m.range(at: first + 1))), let day = Int(ns.substring(with: m.range(at: first + 2)))
        else { return nil }
        let given = m.range(at: first).location != NSNotFound ? Int(ns.substring(with: m.range(at: first))) : nil
        let year = given ?? calendar.component(.year, from: near)
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: d) == month, calendar.component(.day, from: d) == day else { return nil }
        // No year and over half a year before `near`: the next one.
        if given == nil, d.timeIntervalSince(near) < -183 * 86_400 { return calendar.date(byAdding: .year, value: 1, to: d) }
        return d
    }

    /// 133 over the cloud 11-14 (y6): "从2026-11-14到2027-02-06春节还有99天"; it is 84. A count of days the answer gives
    /// between two dates (从/自 A 到/至 B … N 天) or from today (距/离 B 还有 N 天) is checked with the calendar and put
    /// right. A count that says it holds both ends (含, 包括) is left alone.
    /// The date said last before `location` in the same item (the search stops at an item's number), a datePattern match.
    static func lastDateSaid(in ns: NSString, before location: Int) -> NSTextCheckingResult? {
        guard let dates = try? NSRegularExpression(pattern: datePattern),
              let heads = try? NSRegularExpression(pattern: #"(?:^|[；;。\n])\s*(?:第\s*)?\d{1,2}\s*(?:[.、．](?!\d)|[项項])"#) else { return nil }
        var from = max(0, location - 120)
        if let head = heads.matches(in: ns as String, range: NSRange(location: from, length: location - from)).last {
            from = head.range.location + head.range.length
        }
        return dates.matches(in: ns as String, range: NSRange(location: from, length: max(0, location - from))).last
    }

    /// The date and time facts a text gives, put right: weekdays, counts of days, spans between two times, and the days
    /// of a weekday in a month.
    static func rightFacts(_ text: String, today: Date) -> String {
        rightWeekdayLists(rightSpans(rightDayCounts(rightWeekdays(text, today: today), today: today)), today: today)
    }

    /// D87, z1 on 138 (item 38): "2027年2月共有4个星期一，分别是2日、9日、16日、23日": Doubao read the year view a column
    /// off (1 February 2027 is a Monday). How many of a weekday a month has, and which days they are, are worked out by
    /// the calendar and put right. A month without a year is in today's year, or the next when over half a year back.
    static func rightWeekdayLists(_ text: String, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let pattern = #"(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月[^。；;\n\d]{0,16}?(\d)\s*个\s*(?:星期|周|週|礼拜|禮拜)([一二三四五六日天])[^。；;\n\d]{0,12}((?:\d{1,2}(?![\d月年:：.])\s*[日号號]?\s*[、，,和及与]\s*)+\d{1,2}(?![\d月年:：.])\s*[日号號]?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let names = ["日", "一", "二", "三", "四", "五", "六"]  // Calendar's weekday 1 is Sunday
        let ns = text as NSString
        let out = NSMutableString(string: text)
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let month = Int(ns.substring(with: m.range(at: 2))), (1...12).contains(month),
                  let count = Int(ns.substring(with: m.range(at: 3))) else { continue }
            var year = m.range(at: 1).location != NSNotFound ? Int(ns.substring(with: m.range(at: 1))) : nil
            if year == nil {
                let now = calendar.component(.year, from: today)
                let end = calendar.date(from: DateComponents(year: now, month: month + 1, day: 1))
                year = end.map { $0.timeIntervalSince(today) < -183 * 86_400 } == true ? now + 1 : now
            }
            let said = ns.substring(with: m.range(at: 4))
            guard let y = year, let wanted = names.firstIndex(of: said == "天" ? "日" : said),
                  let first = calendar.date(from: DateComponents(year: y, month: month, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            let days = (1...length).filter { day in
                calendar.date(from: DateComponents(year: y, month: month, day: day))
                    .map { calendar.component(.weekday, from: $0) - 1 == wanted } == true
            }
            if m.range(at: 5).location != NSNotFound {
                let list = ns.substring(with: m.range(at: 5))
                let given = list.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                if given != days {
                    let mark = list.range(of: #"^\d{1,2}\s*([日号號])"#, options: .regularExpression)
                        .map { String(list[$0].last!) }
                    let sep = list.range(of: #"[、，,和及与]"#, options: .regularExpression).map { String(list[$0]) } ?? "、"
                    let end = list.last.map { "日号號".contains($0) ? String($0) : "" } ?? ""
                    let made = days.map { "\($0)" + (mark ?? "") }.joined(separator: sep) + (mark == nil ? end : "")
                    out.replaceCharacters(in: m.range(at: 5), with: made)
                }
            }
            if count != days.count { out.replaceCharacters(in: m.range(at: 3), with: "\(days.count)") }
        }
        return out as String
    }

    /// D86, z1 on 138 (item 21): Calculator showed 97÷5 = 19.4 (the five highs added up and divided), Doubao said so in
    /// its thought, "19.4, which is exactly the five-city average high (87 ÷ 5)", and noted "总和87°C，平均为17.4°C"; the
    /// answer and the 备忘录 kept it. A note made on Calculator that has no number like the one it shows (rounded or cut)
    /// is refused once, with the number; noted again on the same screen, it is kept.
    private func calcResultMissing(_ text: String) -> String? {
        guard let app = Self.appInFront(steps, startedIn: startApp),
              case let name = AppNames.hans(app).lowercased(), ["计算器", "计算机", "calculator"].contains(where: { name.contains($0) }),
              let shown = Self.calculatorResult(readRows), calcNoteRefused != shown,
              !Self.holdsNumber(text, shown) else { return nil }
        calcNoteRefused = shown
        return shown
    }

    static func calcNoteReason(_ shown: String) -> String {
        "Refused: 计算器 shows \(shown), and the note has no such number. Note the result as the calculator shows it "
            + "(rounded as the goal asks). If this note is not about this calculation, note it again and it is kept."
    }

    /// The result Calculator shows: the lowest line that is only a number above its keys (AC, %, mc…); nil when none or 0.
    static func calculatorResult(_ rows: [[CandidatePicker.Piece]]) -> String? {
        let keys: Set<String> = ["AC", "C", "%", "mc", "mr", "m+", "m-", "Rad", "Deg"]
        guard let top = rows.joined().filter({ keys.contains($0.text.trimmingCharacters(in: .whitespaces)) })
            .map(\.box.minY).min() else { return nil }
        let shown = rows.filter { ($0.map(\.box.maxY).max() ?? 1) <= top + 0.005 }.compactMap { row -> (y: CGFloat, text: String)? in
            let t = row.map(\.text).joined().replacingOccurrences(of: #"[,，\s]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "−", with: "-")
            guard t.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
            return (row.map(\.box.minY).min() ?? 0, t)
        }
        guard let last = shown.max(by: { $0.y < $1.y }), let value = Double(last.text), value != 0 else { return nil }
        return last.text
    }

    /// Whether a text gives a number that is the shown one rounded or cut to the places it is written with.
    /// D100, z5 on 139 (item 31): "(12345 × 678 − 9876) ÷ 3.5" was pressed "12345 × 678 = − 9876 ÷ 3.5 =", Calculator
    /// took ÷ before −, showed 8,367,088.2857143, and that was noted (2388581.14 is right; z4 had it). A note on an item
    /// whose sum the goal gives in brackets must hold what the sum comes to, or it is refused once with the order to press.
    private func bracketNoteMissing(_ text: String) -> String? {
        let goal = AppNames.hans(task)
        guard let n = Self.noteItems(text).min(), !bracketRefused.contains(n),
              let item = Self.numberedItems(goal).first(where: { $0.n == n }),
              let sum = Self.bracketSum(String(goal[item.body])), sum.value.isFinite,
              !Self.holdsNumber(text, String(sum.value)) else { return nil }
        bracketRefused.insert(n)
        return "Refused: the note does not hold what " + sum.text + " comes to. Calculator works × and ÷ before + and −, so "
            + "press what is in the brackets first and = after it, then the rest and =, and note what it then shows. "
            + "If this note is not about this sum, note it again and it is kept."
    }

    /// A sum with brackets in a goal's item ("(12345 × 678 − 9876) ÷ 3.5") and what it comes to; nil when there is none.
    static func bracketSum(_ item: String) -> (text: String, value: Double)? {
        guard let r = item.range(of: #"[\d.\s+\-−×*÷/]*[（(][\d.\s+\-−×*÷/]+[)）][\d.\s+\-−×*÷/()（）]*"#, options: .regularExpression)
        else { return nil }
        let text = item[r].trimmingCharacters(in: .whitespaces)
        var tokens: [String] = []
        var number = ""
        for c in text where !c.isWhitespace {
            if c.isNumber || c == "." { number.append(c); continue }
            if !number.isEmpty { tokens.append(number); number = "" }
            switch c {
            case "+": tokens.append("+")
            case "-", "−": tokens.append("-")
            case "×", "*": tokens.append("*")
            case "÷", "/": tokens.append("/")
            case "(", "（": tokens.append("(")
            case ")", "）": tokens.append(")")
            default: return nil
            }
        }
        if !number.isEmpty { tokens.append(number) }
        guard tokens.contains(where: { "+-*/".contains($0) }) else { return nil }
        struct Reader {
            let tokens: [String]
            var at = 0
            mutating func sum() -> Double? {
                guard var v = term() else { return nil }
                while at < tokens.count, tokens[at] == "+" || tokens[at] == "-" {
                    let op = tokens[at]; at += 1
                    guard let w = term() else { return nil }
                    v = op == "+" ? v + w : v - w
                }
                return v
            }
            mutating func term() -> Double? {
                guard var v = factor() else { return nil }
                while at < tokens.count, tokens[at] == "*" || tokens[at] == "/" {
                    let op = tokens[at]; at += 1
                    guard let w = factor() else { return nil }
                    v = op == "*" ? v * w : v / w
                }
                return v
            }
            mutating func factor() -> Double? {
                guard at < tokens.count else { return nil }
                let t = tokens[at]; at += 1
                if t == "(" {
                    guard let v = sum(), at < tokens.count, tokens[at] == ")" else { return nil }
                    at += 1
                    return v
                }
                if t == "-" { return factor().map { -$0 } }
                return Double(t)
            }
        }
        var reader = Reader(tokens: tokens)
        guard let value = reader.sum(), reader.at == tokens.count else { return nil }
        return (text, value)
    }

    static func holdsNumber(_ text: String, _ shown: String) -> Bool {
        guard let value = Double(shown),
              let re = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#) else { return true }
        let plain = text.replacingOccurrences(of: #"(?<=\d)[,，](?=\d{3})"#, with: "", options: .regularExpression)
        let ns = plain as NSString
        return re.matches(in: plain, range: NSRange(location: 0, length: ns.length)).contains { m in
            let s = ns.substring(with: m.range)
            guard let n = Double(s) else { return false }
            let places = s.split(separator: ".").dropFirst().first?.count ?? 0
            return abs(abs(n) - abs(value)) < pow(10, Double(-places))
        }
    }

    /// D85, y6 on 138 (item 22): "日出清晨6:37，日落下午5:39，白昼时长11小时22分钟": Doubao worked the span out wrong (it is
    /// 11小时2分钟), the note and the closing answer kept it, and the answer only said it did not fit. In one item, a span
    /// said after exactly two clock times (共, 时长, 白天, 历时, 用时, 相隔…) is worked out from them and put right. A later
    /// time with no 上午/下午 that would come before the first is taken as afternoon.
    /// D94, z3 on 139 (item 43): Doubao took 17:39 − 6:37 as 17.39 − 6.37 on Calculator, read 11.02 as hours and noted
    /// "日照时长11.02小时，即11小时1分钟"; the check of the finished work went by the note and twice turned back the right
    /// 11小时2分钟, and the answer said "17:39−6:37=11小时1分钟（…11小时2分钟为错误，已更正）". The two times said again are
    /// still two times; a span in decimal hours, or after 即 or =, is worked out too; and every span said within 40
    /// characters of the times, or of a span before it, is put right, not the first only.
    static func rightSpans(_ text: String) -> String {
        guard let clock = try? NSRegularExpression(pattern: #"(上午|下午|中午|晚上|傍晚|凌晨|清晨|早上|夜里|夜间)?\s*(\d{1,2})[:：](\d{2})(?!\d)"#),
              let span = try? NSRegularExpression(pattern: #"(?:共|一共|总共|时长|历时|用时|全程|白天|白昼|日照|相隔|间隔|相差|即|等于|=|＝)[为是约：:\s]{0,3}(\d{1,2})(?:\.(\d{1,2}))?\s*个?\s*小时\s*(?:(\d{1,2})\s*分钟?)?"#),
              let heads = try? NSRegularExpression(pattern: #"(?:^|\n|[；;])\s*(?:第\s*)?\d{1,2}\s*(?:[.、．](?!\d)|[项項])"#)
        else { return text }
        let ns = text as NSString
        func part(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        func minutes(_ m: NSTextCheckingResult) -> (at: Int, marked: Bool)? {
            guard var h = part(m, 2).flatMap(Int.init), let mm = part(m, 3).flatMap(Int.init), h <= 24, mm < 60 else { return nil }
            let word = part(m, 1)
            if let word, ["下午", "晚上", "傍晚", "夜里", "夜间"].contains(word), h < 12 { h += 12 }
            if word == "中午", h < 11 { h += 12 }
            if word == "凌晨", h == 12 { h = 0 }
            return (h * 60 + mm, word != nil)
        }
        var cuts = [0] + heads.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range.location) + [ns.length]
        cuts = Array(Set(cuts)).sorted()
        var fixes: [(NSRange, String)] = []
        for (a, b) in zip(cuts, cuts.dropFirst()) where b > a {
            let item = NSRange(location: a, length: b - a)
            let times = clock.matches(in: text, range: item)
            let values = times.compactMap(minutes)
            guard values.count == times.count else { continue }
            var distinct: [(at: Int, marked: Bool)] = []
            for v in values where !distinct.contains(where: { $0.at == v.at }) { distinct.append(v) }
            guard distinct.count == 2, let i = values.firstIndex(where: { $0.at == distinct[1].at }) else { continue }
            let (first, second) = (distinct[0], distinct[1])
            var end = second.at
            if end <= first.at, !second.marked, end < 12 * 60 { end += 12 * 60 }
            var length = end - first.at
            if length <= 0 { length += 24 * 60 }
            let after = times[i].range.location + times[i].range.length
            var anchors = times[i...].map { $0.range.location + $0.range.length }
            for said in span.matches(in: text, range: NSRange(location: after, length: b - after)) {
                guard anchors.contains(where: { (0...40).contains(said.range.location - $0) }),
                      let h = part(said, 1).flatMap(Int.init) else { continue }
                anchors.append(said.range.location + said.range.length)
                let tenths = part(said, 2).flatMap { Double("0." + $0) }.map { Int(($0 * 60).rounded()) } ?? 0
                if h * 60 + tenths + (part(said, 3).flatMap(Int.init) ?? 0) == length { continue }
                let from = said.range(at: 1).location
                fixes.append((NSRange(location: from, length: said.range.location + said.range.length - from),
                              "\(length / 60)小时" + (length % 60 > 0 ? "\(length % 60)分钟" : "")))
            }
        }
        let out = NSMutableString(string: text)
        for (range, with) in fixes.reversed() { out.replaceCharacters(in: range, with: with) }
        return out as String
    }

    static func rightDayCounts(_ text: String, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let d = datePattern
        let between = #"(?:从|自|從)\s*"# + d + #"\s*(?:到|至)\s*"# + d + #"[^，。；;\d]{0,12}?(?:共|有|是|相差|差|还有|還有|还剩)?\s*(\d{1,4})\s*天"#
        let fromToday = #"(?:距离|距離|距|离|離)\s*"# + d + #"[^，。；;\d]{0,12}?(?:还有|還有|还剩|有|共)\s*(\d{1,4})\s*天"#
        var out = text as NSString
        for (pattern, two) in [(between, true), (fromToday, false)] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out
            for m in re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).reversed() {
                let whole = ns.substring(with: m.range)
                if whole.contains("含") || whole.contains("包括") { continue }
                let start = startOfDay(two ? date(ns, m, at: 1, calendar: calendar, near: today) : Optional(today), calendar)
                guard let a = start, let b = startOfDay(date(ns, m, at: two ? 4 : 1, calendar: calendar, near: a), calendar),
                      var days = calendar.dateComponents([.day], from: a, to: b).day else { continue }
                // D79, y3 on 138 (item 1): "2027年春节是2027年2月6日，星期六；距2026年11月17日还有81天" (today the 17th) was "put
                // right" to 0 days; the check refused it three times, each new answer was put "right" again, and the owner
                // got 0. A day 距 names that is today or gone is where the count starts: it runs to the date said last before
                // it in the same item, or the count is left alone.
                if !two, days <= 0 {
                    guard let said = lastDateSaid(in: ns, before: m.range.location),
                          let to = startOfDay(date(ns, said, at: 1, calendar: calendar, near: b), calendar),
                          let fromIt = calendar.dateComponents([.day], from: b, to: to).day, fromIt > 0 else { continue }
                    days = fromIt
                }
                let n = m.range(at: two ? 7 : 4)
                if Int(ns.substring(with: n)) != days { out = out.replacingCharacters(in: n, with: String(days)) as NSString }
            }
        }
        // D31, 135 over the cloud 11-15 (y4): "2027年春节为2027年2月6日；从今天2026年11月15日到那天还有225天" (83): "那天" is the
        // date said last before it in the same item (never one of the item before: the search stops at an item's number).
        // D89, z2 on 138 (item 35): "2027年春节是2027年2月6日，星期六；从2026年11月17日到春节间隔80天" (81): a feast day the item
        // gave a date for ("春节是…", "除夕为…") is that date, as 那天 is the date said last.
        let feasts = "春节|春節|除夕|元旦|元宵节|元宵|清明节|清明|端午节|端午|中秋节|中秋|国庆节|国庆|國慶|七夕|重阳节|重阳|冬至|圣诞节|圣诞|聖誕"
        // D96, z4 on 139 (item 41): "2027年春节为2027年2月6日，从今天（2026年11月17日）到那天还有0天": today's date in brackets
        // was taken for 那天. A date in brackets after 今天 is where the count starts.
        let thatDay = #"(?:从|自|從)?\s*(?:今天)?\s*[（(]?\s*(?:"# + d + #")?\s*[)）]?\s*(?:到|至|距离|距離|距|离|離)\s*(那天|那一天|当天|當天|"# + feasts
            + #")[^，。；;\d]{0,12}?(?:还有|還有|还剩|有|共|是)?\s*(\d{1,4})\s*天"#
        if let re = try? NSRegularExpression(pattern: thatDay), let dates = try? NSRegularExpression(pattern: d),
           let heads = try? NSRegularExpression(pattern: #"(?:^|[；;。\n])\s*(?:第\s*)?\d{1,2}\s*(?:[.、．](?!\d)|[项項])"#) {
            let ns = out
            for m in re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).reversed() {
                if ns.substring(with: m.range).contains("含") || ns.substring(with: m.range).contains("包括") { continue }
                var from = max(0, m.range.location - 120)
                if let head = heads.matches(in: ns as String, range: NSRange(location: from, length: m.range.location - from)).last {
                    from = head.range.location + head.range.length
                }
                let before = NSRange(location: from, length: max(0, m.range.location - from))
                let start: Date? = m.range(at: 2).location != NSNotFound ? date(ns, m, at: 1, calendar: calendar, near: today) : today
                let target = ns.substring(with: m.range(at: 4))
                let named = ["那天", "那一天", "当天", "當天"].contains(target) ? Optional(dates)
                    : (try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: target) + #"[^，。；;\d]{0,6}"# + d))
                guard let said = named?.matches(in: ns as String, range: before).last, let a = startOfDay(start, calendar),
                      let b = startOfDay(date(ns, said, at: 1, calendar: calendar, near: a), calendar),
                      let days = calendar.dateComponents([.day], from: a, to: b).day, days >= 0 else { continue }
                let n = m.range(at: 5)
                if Int(ns.substring(with: n)) != days { out = out.replacingCharacters(in: n, with: String(days)) as NSString }
            }
        }
        return out as String
    }

    private static func startOfDay(_ d: Date?, _ calendar: Calendar) -> Date? { d.map { calendar.startOfDay(for: $0) } }

    /// The text with each weekday it gives for a date ("12月1日是星期日", "2026年12月1日（周二）") made right by the calendar.
    /// A date without a year is in today's year, or the next when it would be over half a year back.
    static func rightWeekdays(_ text: String, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let pattern = #"(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号號]\s*[（(]?\s*(?:是|为|為)?\s*(?:星期|周|週|礼拜|禮拜)([一二三四五六日天])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let names = ["日", "一", "二", "三", "四", "五", "六"]  // Calendar's weekday 1 is Sunday
        let ns = text as NSString
        var out = ns
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let month = Int(ns.substring(with: m.range(at: 2))), let day = Int(ns.substring(with: m.range(at: 3))) else { continue }
            var year = m.range(at: 1).location != NSNotFound ? Int(ns.substring(with: m.range(at: 1))) : nil
            if year == nil {
                let now = calendar.component(.year, from: today)
                let thisYear = calendar.date(from: DateComponents(year: now, month: month, day: day))
                year = thisYear.map { $0.timeIntervalSince(today) < -183 * 86_400 } == true ? now + 1 : now
            }
            guard let y = year, let date = calendar.date(from: DateComponents(year: y, month: month, day: day)),
                  calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { continue }
            let right = names[calendar.component(.weekday, from: date) - 1]
            let said = ns.substring(with: m.range(at: 4))
            if said == right || (said == "天" && right == "日") { continue }
            out = out.replacingCharacters(in: m.range(at: 4), with: right) as NSString  // one character for one: ranges hold
        }
        return out as String
    }

    /// The answer with this run's notes added after it, when it covers under half of a goal of 3+ numbered things; nil
    /// otherwise. Notes the run itself wrote (the cart's count, a listen's transcript) and ones the answer holds are left out.
    static func completedAnswer(_ answer: String, notes: [String], task: String) -> String? {
        let wanted = goalParts(task)
        let toldItems = Set(numberedItems(answer).map { $0.n }), told = toldItems.count
        guard fewThingsTold(answer, task: task) else { return nil }
        let said = typedKey(answer)
        var added: [String] = [], keys: Set<String> = []
        // D42, y1 on 136: the answer gave 44 of 49 things and 7300 characters of notes went after it, nearly all of them
        // things it had already given in other words, and the ways learned on the way. Past half, only the notes of things
        // the answer lacks go after it; a learned way never does (it is for the next run, not the owner).
        // D67, y4 on 137: 40 screens of 测试群 read back went to the owner as they were. What a readup read is for the run.
        for note in notes where !note.hasPrefix("购物车：") && !note.hasPrefix("听到和字幕") && !note.hasPrefix("新学到的做法")
            && !note.hasPrefix("往上读到的聊天记录") {
            if told * 2 >= wanted {
                let items = noteItems(note)
                guard !items.isEmpty, !items.isSubset(of: toldItems) else { continue }
            }
            let k = typedKey(note)
            guard !k.isEmpty, !said.contains(k), !keys.contains(k) else { continue }
            keys.insert(k)
            added.append(note)
        }
        guard !added.isEmpty else { return nil }
        return answer + "\n本次记录的全部结果：\n" + added.joined(separator: "\n")
    }

    /// Whether an answer leaves out many of a goal's numbered things: under half of them, or (D25, 135 y1: it stopped at
    /// item 28 of 49) three or more of a goal of 10+.
    static func fewThingsTold(_ answer: String, task: String) -> Bool {
        let wanted = goalParts(task), told = Set(numberedItems(answer).map { $0.n }).count
        return wanted >= 3 && (told * 2 < wanted || (wanted >= 10 && told <= wanted - 3))
    }

    // D88, z2 on 138: "in Simplified Chinese only (no English)" was taken to the letter: items 30, 41, 43 and 47 said a
    // title or a message "含英文，无法在仅用中文的报告中原样列出" (Z2验证9:29 was one), and "iPhone 13 mini" became
    // "苹果手机13迷你款". The report is in Simplified Chinese; what it copies keeps its letters.
    static let wholeAnswerPrompt = """
    You write the final report of a phone task for the phone's owner, in Simplified Chinese. Names, titles, messages, \
    model names and other words read on the phone are copied as they are written in the notes, English letters and all: \
    never translate, shorten or leave one out because of its letters. The goal \
    lists numbered things. From the run's notes (in the order they were written; a later note on the same thing is newer \
    and fuller) and its answer so far, write one line per thing of the goal, numbered as in the goal ("1. …"): its result, \
    or "未完成：" and why. Use only what the notes and the answer say, and copy every value (number, price, time, name) \
    exactly as written there; never guess one. Write nothing before line 1 and nothing after the last line.
    """

    /// D44: the whole answer written by Codex from the notes; nil without a planner, on an error, or when it still leaves
    /// many things out.
    private func wholeAnswer(_ answer: String) async -> String? {
        guard let planner, !notes.isEmpty else { return nil }
        let text = "Goal: \(task)\n\nNotes:\n" + notes.joined(separator: "\n") + "\n\nAnswer so far:\n" + answer
        guard let reply = try? await planner.chat(system: Self.wholeAnswerPrompt, text: text, image: nil,
                                                 maxTokens: Self.bigGoalTokens, temperature: 0) else { return nil }
        var whole = AppNames.hans(reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
        // D98, z4 on 139: Codex's whole answer stopped at item 29 of 48 (2402 characters), twice, and the owner got
        // items 1-29 with the run's notes after them, English and all. A report cut off is asked to go on from the
        // item after its last, at most twice, and the rest is added to it.
        for _ in 0..<2 where !whole.isEmpty && Self.fewThingsTold(whole, task: task) {
            let wanted = Self.goalParts(task)
            guard let last = Self.numberedItems(whole).map(\.n).max(), last < wanted else { break }
            let more = text + "\n\nThe report written so far stops after item \(last):\n" + whole
                + "\n\nWrite items \(last + 1) to \(wanted) only, the same way, beginning with \"\(last + 1).\""
            guard let next = try? await planner.chat(system: Self.wholeAnswerPrompt, text: more, image: nil,
                                                      maxTokens: Self.bigGoalTokens, temperature: 0) else { break }
            let rest = AppNames.hans(next.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let first = Self.numberedItems(rest).first?.n, first > last else { break }
            DebugLog.write("done: Codex's whole answer stopped at item \(last); it went on from item \(first)")
            whole += "\n" + rest
        }
        if whole.isEmpty || Self.fewThingsTold(whole, task: task) {
            DebugLog.write("done: Codex's whole answer not used: \(whole.count) characters, items \(Self.numberedItems(whole).map { $0.n }.prefix(60))")
            return nil
        }
        return whole
    }

    /// The goal's things a note is about: its "第N项".
    static func noteItems(_ note: String) -> Set<Int> {
        guard let re = try? NSRegularExpression(pattern: #"第\s*(\d{1,3})\s*[项項]"#) else { return [] }
        let ns = note as NSString
        return Set(re.matches(in: note, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range(at: 1))) })
    }

    /// D51: the note is about a thing of the goal no earlier note was about (not a 未能完成 line).
    static func newThingNoted(_ note: String, before: Set<Int>) -> Bool {
        !note.hasPrefix("未能完成") && !noteItems(note).subtracting(before).isEmpty
    }

    /// D41, y1 on 136: "未能完成：1. 第21项：The first data cable’s name and price are recorded - open 淘宝, …（stuck: 1 new
    /// plans in a row and nothing got on）" went into the owner's answer: the plan's own words, in English. The note keeps
    /// the thing's number and says why in Chinese; a part with no number keeps its words.
    static func failedPartNote(_ part: String, why: String) -> String {
        let reason = CloudBridge.failureWords(why)
        guard let head = part.range(of: #"第\s*\d{1,3}\s*[项項]"#, options: .regularExpression) else { return part + "（" + reason + "）" }
        return part[head].replacingOccurrences(of: " ", with: "") + "（" + reason + "）"
    }

    /// The answer, with any item that now tells of this run's own sent messages (keys from typedKey, 4+ characters) while
    /// its first note did not, put back as that note tells it.
    static func keepReadNotes(_ answer: String, notes: [String], sent: Set<String>) -> String {
        let keys = sent.filter { $0.count >= 4 && !$0.hasPrefix("tap:") }
        guard !keys.isEmpty else { return answer }
        var noted: [Int: String] = [:]
        for note in notes {
            // D147, x4 on 145 (rerun): "第20项：测试群最新三条消息（最新在前）：1. 我发的“X3全部做完”…；2. …；3. …" was read
            // by numberedItems as items 1–3 (the list inside), item 20 was never kept, and the answer's 20 told the screen
            // after the run's own later sends ("X4全部做完" first). A note that starts 第N项 is item N's.
            if let head = note.range(of: #"^\s*第\s*\d{1,3}\s*[项項]\s*[：:]?"#, options: .regularExpression),
               let n = noteItems(String(note[head])).first {
                if noted[n] == nil { noted[n] = String(note[head.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
                continue
            }
            guard let first = numberedItems(note).first, noted[first.n] == nil else { continue }
            noted[first.n] = String(note[first.body]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !noted.isEmpty else { return answer }
        var out = "", cursor = answer.startIndex
        for item in numberedItems(answer) {
            out += answer[cursor..<item.body.lowerBound]
            let body = String(answer[item.body])
            if let note = noted[item.n], !note.isEmpty,
               keys.contains(where: { typedKey(body).contains($0) && !typedKey(note).contains($0) }) {
                out += note
            } else {
                out += body
            }
            cursor = item.body.upperBound
        }
        out += answer[cursor...]
        return out
    }

    /// A done check's objection without the parts (split at ；; and line ends) that are the run's own sent messages or a
    /// cart count the cart had before; nil when nothing else is left.
    static func standingObjection(_ objection: String, sent: Set<String>, adds: Int, wanted: Int, each: Int? = nil) -> String? {
        // 131 over the cloud 11-13 (r131b g6): "任务2最新三条消息与屏幕不符，任务4商品价格前后矛盾，…" came as one sentence, and
        // the part about item 2 (this run's messages) set aside item 4's price too (18.24 in item 4, 13.18 in item 6). A
        // comma before the next item's number parts it as well.
        let marked = objection.replacingOccurrences(of: #"[，,]\s*(?=(?:任务|任務|第|item\s*)\d{1,2})"#, with: "\n",
                                                    options: [.regularExpression, .caseInsensitive])
        let parts = marked.components(separatedBy: CharacterSet(charactersIn: "；;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func setAside(_ s: String) -> Bool {
            blamesOwnSend(s, sent: sent) || blamesOldCart(s, adds: adds, wanted: wanted, each: each)
        }
        guard parts.count > 1 else { return setAside(objection) ? nil : objection }
        let left = parts.filter { !setAside($0) }
        if left.isEmpty { return nil }
        return left.count == parts.count ? objection : left.joined(separator: "；")
    }

    /// Whether a spot has 发送 / 發送 / Send written on it (OCR rows of the frame around it, screen fractions).
    static func labelsSend(_ rows: [[CandidatePicker.Piece]], at p: CGPoint) -> Bool {
        rows.joined().contains { piece in
            let t = AppNames.hans(piece.text).lowercased().replacingOccurrences(of: " ", with: "")
            return (t.contains("发送") || t == "send")
                && abs(piece.box.midX - p.x) <= 0.08 && abs(piece.box.midY - p.y) <= 0.05
        }
    }

    /// Whether a done check objects to a cart count higher than the goal asked, while this run added no more than asked
    /// (1...wanted "added" toasts): the extra was in the cart before. An objection with no count above `wanted` (nothing
    /// in the cart, the wrong item) still stands. `each`: the most the goal asks of one thing (130 g4: 淘宝 一件 and 美团 一份
    /// made `wanted` 2, and "淘宝 ×2, 1 asked" was not seen as too many); `wanted` when not given.
    static func blamesOldCart(_ objection: String, adds: Int, wanted: Int, each: Int? = nil) -> Bool {
        guard adds >= 1, adds <= wanted else { return false }
        let limit = each ?? wanted
        let t = AppNames.hans(objection).lowercased()
        guard t.contains("购物车") || t.contains("cart") else { return false }
        let ns = t as NSString
        let re = try? NSRegularExpression(pattern: #"(?:(?<![a-z])[×x]\s?|(?:数量|quantity|count)\D{0,4})(\d{1,3})(?!\d)"#)
        let counts = (re?.matches(in: t, range: NSRange(location: 0, length: ns.length)) ?? [])
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        return counts.contains { $0 > limit }
    }

    /// Whether a done check's objection comes from what this run sent: it quotes a sent text (keys from typedKey, at least
    /// 4 characters: a short 你好 or 好的 may be named for another reason), or, once the run has sent something, it is
    /// about a chat's latest messages. 128 second round (g4): the check named the run's own "G4全部做完" only as "10:17
    /// 的G4消息"; the latest messages a run reads before it sends are never the ones on the screen at the end.
    /// 130 over the cloud 11-13 (g2): "G2买东西做完 was not sent on its own, the screen shows a garbled joined message" was
    /// set aside as the run's own message, and the answer said both were sent. That a message did not go out, or went
    /// out wrong, is an objection to the run's own sending: it always stands.
    static func blamesOwnSend(_ objection: String, sent: Set<String>) -> Bool {
        let keys = sent.filter { $0.count >= 4 && !$0.hasPrefix("tap:") }
        guard !keys.isEmpty else { return false }
        let low = AppNames.hans(objection).lowercased()
        let notSent = ["未发出", "没发出", "没有发出", "未发送", "没发送", "没有发送", "未单独发出", "未成功发送", "发送失败", "乱码", "拼接",
                       "不完整", "错字", "garbl", "not sent", "wasn't sent", "was not sent", "never sent", "unsent", "not been sent",
                       "jumbled", "mixed up", "merged"]
        if notSent.contains(where: { low.contains($0) }) { return false }
        let said = typedKey(objection)
        if keys.contains(where: { said.contains($0) }) { return true }
        let t = AppNames.hans(objection).lowercased()
        return ["最新", "latest", "newest", "most recent"].contains { t.contains($0) }
            && ["消息", "message", "条"].contains { t.contains($0) }
    }

    /// A tap on the keyboard's bottom-right key, while a keyboard is up (0-1000): 发送 / 换行 below the backspace key
    /// (0.80–0.83) and above the globe and microphone (0.93–).
    static func onReturnKey(_ act: JObject) -> Bool {
        guard act["action"]?.str == "tap", let x = act["x"]?.double, let y = act["y"]?.double else { return false }
        return x >= 760 && (845...925).contains(y)
    }

    /// A tap on Lan Agent keyboard's Return key: the last of its one row of keys, lower right.
    static func onOurReturnKey(_ act: JObject) -> Bool {
        guard act["action"]?.str == "tap", let x = act["x"]?.double, let y = act["y"]?.double else { return false }
        return x >= 760 && y >= 700
    }

    /// Return, or a tap where 发送 sits (next to the box, or the keyboard's bottom-right key).
    /// cmd+v and the like: something goes into the box that was not typed.
    static func pastes(_ act: JObject) -> Bool {
        guard act["action"]?.str == "key" else { return false }
        return ["cmd+v", "command+v", "ctrl+v", "control+v"].contains((act["combo"]?.str ?? "").lowercased().filter { !$0.isWhitespace })
    }

    /// What a paste puts in, as approval is asked for it (unreadable: said so, and still asked).
    static func pastedText(_ board: String?) -> String {
        let text = (board ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? pastePlaceholder : String(text.prefix(300))
    }

    static let pastePlaceholder = "（粘贴的内容）"

    /// The app in front by what this run did: the last one it opened, unless it went Home or opened one by its icon
    /// since; with no open at all, the one it started in. nil: not known.
    /// Apps that send nothing to anyone: what is typed there stays on the phone.
    /// 127 over the cloud 11-12 (g2): 深圳宝安国际机场 typed in 高德 for "开车到深圳宝安机场" was held as a message (the
    /// goal also posted to 测试群), then a search in 淘宝, and the run failed. Where one only searches, Return searches:
    /// maps, browsers and shops. Apps with comments (抖音, 小红书) are not here: a comment goes out.
    static let localApps = ["备忘录", "notes", "提醒事项", "reminders", "日历", "行事历", "calendar", "计算器", "calculator",
                            "时钟", "clock", "天气", "weather", "设置", "设定", "settings", "文件", "档案", "files", "股市", "stocks",
                            "计算机", "高德", "百度地图", "地图", "maps", "safari", "浏览器", "chrome", "淘宝", "拼多多", "京东",
                            "美团", "饿了么", "大众点评", "百度"]

    static func inLocalApp(_ steps: [JObject]) -> Bool {
        guard let app = appInFront(steps, startedIn: nil) else { return false }
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return localApps.contains { name == $0 || name.hasPrefix($0) }
    }

    static func appInFront(_ steps: [JObject], startedIn: String?) -> String? {
        for s in steps.reversed() {
            switch s["action"]?.str {
            case "open": return s["app"]?.str
            case "home": return nil
            case "tap" where opensByIcon(s): return nil
            default: continue
            }
        }
        return startedIn
    }

    /// D181, x2 (Calendar) and n16 (微信, 00:06) over the cloud 11-19/20 (148): the phone left the app without the run
    /// going Home (a swipe from the home bar; the lock screen), the model said so ("上次滑动回到了主屏幕", "屏幕回到了锁屏
    /// 界面") and asked to open the app again; it was refused as still in it, and the next open became a drag down "to
    /// close a picture" (Spotlight, the lock screen). A thought that names the Home Screen, the lock screen, the app
    /// switcher or the system's search is taken at its word.
    static func saysAppLeft(_ thought: String) -> Bool {
        AppNames.hans(thought).range(of: #"主屏幕|主画面|主屏|桌面|锁屏|锁定画面|锁定屏幕|应用切换器|多任务|系统搜索|通知中心|控制中心|home screen|lock screen|app switcher|spotlight|system search|notification center|control center"#,
                                     options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func stillInAppReason(_ app: String) -> String {
        // 125 in 测试群 11-12: the model sees a step's first 300 characters (recentActions), and how to close the picture
        // came after them. Short, the way out first.
        "Refused: still in \(app), never left it: nothing to open. This is a picture or video \(app) shows full screen "
            + "(a screenshot of another app is only a picture). Note what you need, then drag it down (y 350 to 800) to close it."
    }

    /// Whether a text sent before would go where it went already: the title read now among those it was sent to. No
    /// title now, or none read at those sends: taken as the same chat (refused rather than sent twice).
    static func samePlace(_ places: Set<String>, _ title: String?) -> Bool {
        guard let title, !places.isEmpty else { return true }
        return places.contains { WatchReport.sameChatTitle($0, title) }
    }

    /// A "done" of a goal in numbered parts that answers it all: numbered as far as the goal's last part or the one
    /// before it (the last is often "整理成一段话告诉我"), or "全部" with at least half of them numbered.
    static func answersWholeGoal(_ answer: String, task: String) -> Bool {
        let want = goalParts(task)
        guard want >= 2 else { return false }
        let text = AppNames.hans(answer)
        let got = goalParts(text)
        return got >= want - 1 || (text.contains("全部") && got * 2 >= want)
    }

    /// How many numbered parts a goal written on one line has ("1. …；2. …；3. …"), counted 1, 2, 3… in order (a price
    /// "13.5" or a time is not a part). 123 over the cloud 11-12: a goal of nine parts started on its remembered way, a
    /// plan with no numbered lines, and had the base 55 steps instead of 180.
    static func goalParts(_ goal: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: #"(?:^|[：:；;，,。\n])\s*(\d{1,2})\s*[.)、．]"#) else { return 0 }
        let ns = goal as NSString
        let numbers = re.matches(in: goal, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        var n = 0
        for k in numbers where k == n + 1 { n = k }
        return n
    }

    /// D16 (134 over the cloud 11-15, y3 and y4): Codex was out and Doubao planned; a new plan after a stuck part held
    /// the next 4–5 things only. Its last part done, the run took that for the end of the goal: "done" was refused three
    /// times ("never went into 抖音…") and the run went out with 16 of 50 things (y3) and 36 (y4), the messages and the
    /// closing note never made. The goal's numbered things nothing tells of yet: no note, finished or given-up part, or
    /// answer heads one with 第N项, and no message it asks to send (发“…”) went out. Things that only ask to be told
    /// (告诉我, 检查一遍) come with the final answer and are left out. Empty for a goal under 10 things.
    static func itemsLeft(task: String, told: [String], sent: Set<String>) -> [Int] {
        let goal = AppNames.hans(task)
        let items = numberedItems(goal)
        guard items.count >= 10,
              let head = try? NSRegularExpression(pattern: #"(?:^\s*(?:\d{1,2}\s*[.、．]\s*)?|[；;。\n]\s*|->\s*|未能完成[：:]\s*(?:\d{1,2}\s*[.、．]\s*)?)第\s*(\d{1,2})\s*[项項]"#),
              let send = try? NSRegularExpression(pattern: #"发\s*[“"「]([^”"」]{2,20})[”"」]"#) else { return [] }
        var said = Set<Int>()
        var saidOf: [Int: String] = [:]
        for text in told {
            let ns = AppNames.hans(text) as NSString
            let heads = head.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            for (i, m) in heads.enumerated() {
                guard let n = Int(ns.substring(with: m.range(at: 1))) else { continue }
                // D80: "第24项待后续记录" is an item put off, not a result.
                let clause = ns.substring(from: m.range.location + m.range.length).prefix(while: { !"；;。\n".contains($0) })
                if clause.range(of: #"待后续|后续再|后续记录|后续补|待补|稍后|之后再|待记录"#, options: .regularExpression) != nil { continue }
                // D99, z5 on 139: a part was let through on "第22项：…已在之前记下；第24项：…已在之前记下；第25项：…已在之前查看
                // 记下", and nothing had been noted for any of them: the answer said "记录称已记下…但未提供具体内容". A
                // claim of an earlier record is no record; an earlier note that holds one counts on its own.
                if clause.range(of: #"(?:已在|已于)?(?:之前|前面|此前|早先)(?:已经?|已)?(?:查看)?(?:记下|记录|记好|查到|看过|查看)"#,
                                options: .regularExpression) != nil { continue }
                said.insert(n)
                let from = m.range.location + m.range.length
                let to = i + 1 < heads.count ? heads[i + 1].range.location : ns.length
                saidOf[n, default: ""] += ns.substring(with: NSRange(location: from, length: max(0, to - from))) + "\n"
            }
        }
        return items.compactMap { item -> Int? in
            let body = String(goal[item.body]).trimmingCharacters(in: .whitespaces)
            if body.contains("告诉我") || body.hasPrefix("检查") { return nil }
            let ns = body as NSString
            let asked = send.matches(in: body, range: NSRange(location: 0, length: ns.length))
                .map { typedKey(ns.substring(with: $0.range(at: 1))) }
            if asked.contains(where: { key in sent.contains { $0.contains(key) } }) { return nil }
            // D81, y4 on 138 (item 40): "如果深圳今天最高温比首尔高10度以上，就在微信测试群发“Y4温差大”，否则发“Y4温差小”" had
            // the note "第40项：首尔今日最高温14°，最低温10°" on the way; a stuck plan took 40 for done and left it out,
            // "Y4全部做完" went out first, and 温差大 was sent only after it. A thing that asks for a message is done when
            // the message went out, or a note says it is not to go or could not.
            // D106, z6 on 140 (item 14): "用计算器把深圳、上海、北京、首尔、广州今天的最高温加起来再除以5" counted as
            // noted on "第14项深圳今日最高28°C" alone; the part closed and the other four were never looked up. An item
            // that names three things or more in a list is noted once each is (or once it says why it could not be).
            if said.contains(item.n), asked.isEmpty, !notSending(saidOf[item.n] ?? ""),
               !namesAllTold(body, in: saidOf[item.n] ?? "") { return item.n }
            if said.contains(item.n), asked.isEmpty || notSending(saidOf[item.n] ?? "") { return nil }
            return item.n
        }
    }

    /// D106: the things an item names in a list ("深圳、上海、北京、首尔、广州"); fewer than three: none. CJK ideographs by
    /// their range: ICU's \p{Han} takes the list's own 、 too (build 141's unit test: "北京、首" came back as one name).
    static func listedNames(_ item: String) -> [String] {
        guard let r = item.range(of: #"[\u4E00-\u9FFF]{2,4}(?:、[\u4E00-\u9FFF]{2,4}){2,}"#, options: .regularExpression)
        else { return [] }
        return item[r].components(separatedBy: "、")
    }

    /// Whether what was noted for an item names each thing its list names. The list's first and last words may carry a
    /// word of the sentence ("把深圳", "广州今天"): their first or last two characters do.
    static func namesAllTold(_ item: String, in told: String) -> Bool {
        let names = listedNames(AppNames.hans(item))
        guard names.count >= 3 else { return true }
        let t = AppNames.hans(told)
        return names.allSatisfy { t.contains($0) || t.contains(String($0.prefix(2))) || t.contains(String($0.suffix(2))) }
    }

    /// D107, z6 on 140: "开发商Alipay (Hangzhou) Te...（被截断）" (item 27) and a note's title "…还值得入手吗？Pho...（被截断）"
    /// read off the search list (item 43 said to open the note, and its second comment was never read) went into the
    /// answer cut. A note holding text cut short on the screen is refused once for its item, with the order to open it.
    private func cutNoteMissing(_ text: String) -> String? {
        guard Self.holdsCutText(text) else { return nil }
        let n = Self.noteItems(text).min() ?? 0
        guard !cutRefused.contains(n) else { return nil }
        cutRefused.insert(n)
        cutPending[n] = (text, notes.count)
        return "Refused: this note holds text cut short on the screen (… or ... where it was cut, or 被截断). Open the thing "
            + "it is about (the note, the product, the app's page, the developer's name) and read it whole, then note it. If "
            + "it is cut there too, note it again as it is and it is kept."
    }

    /// D177, x4 over the cloud 11-19 (148), item 17: on 电池 the model said "电池页面已显示电量100%已充满" and swiped up to
    /// 低耗电模式; its note then said "当前页面未显示具体电量数值", and the owner got 未完成 for a level it had read. A note
    /// saying a thing is not shown, right after the swipes on this page said a number the note lacks, is refused once
    /// with those words quoted.
    private var unshownRefused: Set<Int> = []
    private func unshownNoteMissing(_ text: String) -> String? {
        guard let said = Self.saidBeforeUnshown(text, steps: steps) else { return nil }
        let n = Self.noteItems(text).min() ?? 0
        guard !unshownRefused.contains(n) else { return nil }
        unshownRefused.insert(n)
        return "Refused: this note says a thing is not shown, but on this page you said: " + said.map { "“\($0)”" }.joined(separator: " ")
            + " If a number there is the value the note says is not shown, note it as you saw it (your thoughts are not kept). "
            + "If it was something else, note it again as it is and it is kept."
    }

    static func saidBeforeUnshown(_ note: String, steps: [JObject]) -> [String]? {
        let pattern = #"未显示|没有显示|没显示|不显示|看不到|未看到|没看到|未能读取|无法读取|not (?:visible|shown)"#
        guard AppNames.hans(note).range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        var said: [String] = []
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            if a == "swipe" || a == "hold" {
                if let t = s["thought"]?.str, !t.isEmpty { said.insert(String(t.prefix(160)), at: 0) }
            } else if ["stale plan", "refused"].contains(a) {
                continue
            } else { break }
            if said.count >= 3 { break }
        }
        let value = #"\d+(?:\.\d+)?\s*(?:%|％|元|°|度|万|件|人|个|GB|小时|分钟)"#
        let numbers = { (t: String) -> [String] in
            guard let re = try? NSRegularExpression(pattern: value) else { return [] }
            return re.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { Range($0.range, in: t).map { String(t[$0]) } }
        }
        let had = Set(numbers(note).map { $0.filter { !$0.isWhitespace } })
        let fresh = said.filter { t in numbers(t).contains { !had.contains($0.filter { !$0.isWhitespace }) } }
        return fresh.isEmpty ? nil : fresh
    }

    static func holdsCutText(_ text: String) -> Bool {
        AppNames.hans(text).range(of: #"被截断|显示不全|[\p{Han}A-Za-z0-9](?:\.\.\.|…)"#, options: .regularExpression) != nil
    }

    /// D81: a note on a thing that asks for a message, saying it is not sent: given up, or not to be sent.
    static func notSending(_ said: String) -> Bool {
        said.range(of: #"未能|未完成|没完成|没做成|做不成|无法|失败|跳过|不发|无需发|不用发|不需要发|不必发|未发|没发|没有发|不满足|拒绝|被拒|没装|未安装"#,
                   options: .regularExpression) != nil
    }

    /// The goal's items a part of a plan is over: its run (partItemRange), or the one it starts with ("3. 第43项：…").
    static func partItems(_ part: String) -> [Int]? {
        if let run = partItemRange(part) { return Array(run) }
        guard let re = try? NSRegularExpression(pattern: #"^\s*(?:\d{1,2}\s*[.)、．]\s*)?第\s*(\d{1,3})\s*[项項]"#),
              let m = re.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)),
              let n = Range(m.range(at: 1), in: part).flatMap({ Int(part[$0]) }) else { return nil }
        return [n]
    }

    /// D82, y4 on 138: the executor did items 42, 43 and 44 inside part 2 (第42项) and finished it; part 3 (第43项) was
    /// already noted, so nothing it did there was new, the part "was not getting on" at 20 steps, 43 was put down as
    /// 未能完成, and a stuck plan and 15 minutes went on the closing note. How many parts from `from` on are over items
    /// that all have their result already; the plan's last part is never among them (its done ends the plan as before).
    static func partsNoted(_ parts: [String], from: Int, task: String, told: [String], sent: Set<String>) -> Int {
        let goal = AppNames.hans(task)
        let items = numberedItems(goal)
        guard items.count >= 10 else { return 0 }
        let left = Set(itemsLeft(task: task, told: told, sent: sent))
        let results = Set(items.filter { item in
            let body = String(goal[item.body]).trimmingCharacters(in: .whitespaces)
            return !body.contains("告诉我") && !body.hasPrefix("检查")
        }.map(\.n))
        var k = 0
        while from + k < parts.count - 1, let mine = partItems(parts[from + k]),
              mine.allSatisfy({ results.contains($0) && !left.contains($0) }) {
            k += 1
        }
        return k
    }

    /// D186, x1 and x4 over the cloud 11-20 (150): "fail 第19项：…" came with item 19 already looking noted (the scroll note
    /// "第19项（滚动页面时看到，原话）…" and the fail's own "未能完成：第19项…"); D130's pass over noted parts closed 19 as noted
    /// and failed part 20 in its place, and 20 (测试群最新三条) was never looked at. In x1 "fail 第13项" failed part 14 the
    /// same way. Of the k parts passed as noted, the passing stops at the first holding an item the fail names.
    static func partsNotedBefore(_ k: Int, parts: [String], from: Int, named: Set<Int>) -> Int {
        guard !named.isEmpty else { return k }
        return (0..<k).first(where: { from + $0 < parts.count && !named.isDisjoint(with: partItems(parts[from + $0]) ?? []) }) ?? k
    }

    /// D186: the items a text names (第N项).
    static func itemsNamed(_ text: String) -> Set<Int> {
        guard let re = try? NSRegularExpression(pattern: #"第\s*(\d{1,3})\s*[项項]"#) else { return [] }
        let ns = text as NSString
        return Set(re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range(at: 1))) })
    }

    /// Numbers as runs: [7, 8, 9, 11, 17, 18, 19] → "7–9, 11, 17–19".
    static func itemRanges(_ numbers: [Int]) -> String {
        var out: [String] = [], i = 0
        while i < numbers.count {
            var j = i
            while j + 1 < numbers.count, numbers[j + 1] == numbers[j] + 1 { j += 1 }
            out.append(j - i >= 2 ? "\(numbers[i])–\(numbers[j])" : (i...j).map { String(numbers[$0]) }.joined(separator: ", "))
            i = j + 1
        }
        return out.joined(separator: ", ")
    }

    /// For the planner: the goal's things left (itemsLeft), every one to be planned.
    /// D141, q133x on 145 (x4, a goal of 28): at step 87 the memo of items 1–23 (item 24) was typed with results made
    /// up for 3 and 4 (视频号 "@小透明，点赞数10"; looked up later: "深圳游玩•", 5977), and at 112 "X4全部做完" (item 26)
    /// went out to 测试群 with items 3–19 not done. Results typed for items that have none yet, or a goal's 全部做完
    /// message typed before the items ahead of it: those items (empty: go ahead).
    static func typedAheadOfResults(_ typed: String, task: String, told: [String], sent: Set<String>) -> [Int] {
        let t = AppNames.hans(typed).trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return [] }
        let left = itemsLeft(task: task, told: told, sent: sent)
        guard !left.isEmpty else { return [] }
        if t.count <= 20, t.range(of: #"(全部|都|全)(做完|完成|办完|搞定)"#, options: .regularExpression) != nil {
            let goal = AppNames.hans(task)
            guard let own = numberedItems(goal).first(where: { goal[$0.body].contains(t) }) else { return [] }
            return left.filter { $0 < own.n }
        }
        guard let re = try? NSRegularExpression(pattern: #"(?:^|[；;。，,\n]|\s)\s*(?:第\s*)?(\d{1,2})\s*(?:[.、．](?!\d)|[项項][：:])"#)
        else { return [] }
        let ns = t as NSString
        let typedItems = Set(re.matches(in: t, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) })
        guard typedItems.count >= 2 else { return [] }
        return left.filter { typedItems.contains($0) }
    }

    static func aheadReason(_ ahead: [Int]) -> String {
        "Refused: 第" + itemRanges(ahead) + "项 have no result noted in this run yet, so this cannot be typed or sent now. "
            + "Do them first in the goal's order: look each one up and note its result (or note 未能完成 with the reason for "
            + "one that cannot be done). Never write a result that was not seen on the screen."
    }

    static func itemsLeftLine(_ left: [Int]) -> String {
        "The goal's things with no result yet: " + itemRanges(left) + ". Plan EVERY one of them, one part per thing, in the "
            + "goal's order, each part starting with 第N项： (N = its number in the goal). Leave out only ones already given "
            + "up above (未能完成): those stay not done. The run ends only when all the goal's things have a result."
    }

    /// At most this many new plans for things left when a plan runs out (D16).
    static let continuationLimit = 8

    /// D27: screens readup goes up at most (a chat's day or two).
    static let readUpScreens = 40
    static let readUpStillTries = 2  // D143: swipes more, a wait apart, before an unmoved screen is the top
    /// D164, s6 over the cloud 11-19 (148): "一直读到11月14日" stopped at 11月17日 as "the top" (145's s6 did too), and on
    /// 147 a read-up's swipe opened a picture full screen: the swipes started at the middle, on the bubbles. A chat is
    /// read up from the margin, as every list is scrolled (marginX); a screen that did not move gets one swipe from the
    /// middle before it is the top.
    static let readUpX = Double(marginX) / 1000

    /// D27: a read up a chat, oldest first: each screen's rows not seen on the screens below it go before what came
    /// before (a screen further up shows older messages). `screens` are in the order read, newest first.
    static func readUpMerge(_ screens: [[String]]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for rows in screens {
            let fresh = rows.filter { !$0.isEmpty && seen.insert(AppPlaces.normalized($0)).inserted }
            out = fresh + out
        }
        return out
    }

    /// D27: the note a readup leaves; a long read keeps its first and last 2500 characters.
    /// D123, q143n on 144 (n16): the header said "读到“143夜测一”为止" whether or not those words were read, and the model
    /// took it that the read-up had found them. It says which: found, the top reached without them, or not yet.
    static func readUpNote(_ lines: [String], screens: Int, until: String, top: Bool = false, now: Date = Date()) -> String {
        let text = lines.map { datedTimeLine($0, now: now) }.joined(separator: "\n")  // D139
        let bare = { (s: String) in AppNames.hans(s).filter { !$0.isWhitespace } }
        let targets = readUpTargets(until, now: now)
        let hit = targets.first { t in lines.contains { bare($0).contains(t) } }
        let found = hit != nil
        let shownAs = hit.map { $0 == targets.first ? "" : "（微信里显示为“\($0)”）" } ?? ""
        let reach = until.isEmpty ? "" : found ? "，读到“\(until)”\(shownAs)为止"
            : top ? "，一直读到最上面，没有读到“\(until)”" : "，还没读到“\(until)”，更早的没有读"
        let kept = text.count <= 6000 ? text
            : String(text.prefix(2500)) + "\n…（中间省略\(text.count - 5000)字）…\n" + String(text.suffix(2500))
        return "往上读到的聊天记录（\(screens) 屏，从旧到新" + reach
            + "；行首“（我）”是机主自己发的，靠右、没有名字；别人的消息上方一行是发送人名字"
            // D46, y5 on 136: the run found 133真人测试一 under 昨天下午1:20, then "corrected" it to the time line below
            // it (2:34): in WeChat a time line heads the messages under it.
            + "；单独一行的时间是它下面那些消息的发送时间，不是上面消息的；时间行后括号里是程序算出的日期，整理时照这个从旧到新的"
            + "顺序写，不要按钟点重排）：\n" + kept + sentTimesLine(of: until, in: lines)
    }

    /// D139, s6 on 144: the read-up was given oldest first, and the answer put today's 凌晨12:42 … 下午3:13 before
    /// 昨天晚上9:47, sorted by the clock. A chat time line without a date gets the date it stands for: 昨天 晚上9:47（11月17日）.
    static func datedTimeLine(_ line: String, now: Date = Date()) -> String {
        let bare = line.trimmingCharacters(in: .whitespaces)
        guard isChatTimeLine(bare), bare.range(of: #"\d{1,2}月\d{1,2}日"#, options: .regularExpression) == nil else { return line }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        var back = 0
        if bare.contains("昨天") { back = 1 } else if bare.contains("前天") { back = 2 }
        let days = ["日", "一", "二", "三", "四", "五", "六"]
        if let r = bare.range(of: #"(星期|周)[一二三四五六日天]"#, options: .regularExpression) {
            let name = String(bare[r].last!) == "天" ? "日" : String(bare[r].last!)
            if let want = days.firstIndex(of: name) {
                let todayIndex = cal.component(.weekday, from: today) - 1
                back = (todayIndex - want + 7) % 7
                if back == 0 { back = 7 }
            }
        }
        guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return line }
        return line + "（\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日）"
    }

    /// D172, s6 over the cloud 11-19 (148, second run): the read up went on swiping after the chat was gone (WeChat's chat
    /// list and its mini-program drawer, then the system search): 144 s, and its notes held 短信, 丰巢 and search results as
    /// 测试群's messages; the check of the answer found them. A read stops when the title it began under is gone: another
    /// title, or none on two screens in a row (a picture opened full screen has none for one). A title read with a bit
    /// more or less (a grey line joined to it) is the same chat.
    static func leftChat(_ chat: String?, _ now: String?, untitled: Int) -> Bool {
        guard let chat else { return false }
        guard let now else { return untitled >= 1 }
        let a = AppNames.hans(chat).filter { !$0.isWhitespace }, b = AppNames.hans(now).filter { !$0.isWhitespace }
        return !a.contains(b) && !b.contains(a)
    }

    /// D133, s6 on 144 (11-18): "一直读到11月14日为止" was read up for 11月14日, but WeChat heads the last week's messages
    /// 昨天 and 星期X (11-14 was 星期六); the date never shows there. A date one to six days back is also looked for as WeChat
    /// shows it. The words themselves come first.
    static func readUpTargets(_ until: String, now: Date = Date()) -> [String] {
        let bare = AppNames.hans(until).filter { !$0.isWhitespace }
        guard !bare.isEmpty else { return [] }
        var out = [bare]
        guard let re = try? NSRegularExpression(pattern: #"^(\d{1,2})月(\d{1,2})[日号]$"#),
              let m = re.firstMatch(in: bare, range: NSRange(bare.startIndex..., in: bare)),
              let mr = Range(m.range(at: 1), in: bare), let dr = Range(m.range(at: 2), in: bare),
              let month = Int(bare[mr]), let day = Int(bare[dr]) else { return out }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        var parts = cal.dateComponents([.year], from: today)
        parts.month = month
        parts.day = day
        guard var date = cal.date(from: parts) else { return out }
        if date > today, let back = cal.date(byAdding: .year, value: -1, to: date) { date = back }
        guard let days = cal.dateComponents([.day], from: date, to: today).day else { return out }
        if days == 1 {
            out.append("昨天")
        } else if (2...6).contains(days) {
            out.append(["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][cal.component(.weekday, from: date) - 1])
        }
        return out
    }

    /// D134, s4 on 144 (11-18): 137测试备注 was changed to 144测试备注; a new plan took the saved page for another friend's,
    /// and 主人蓝海乐 was changed to 144测试备注 as well. A name or remark the goal sets, typed and then saved (a tap after
    /// it), is not typed again unasked: refused once.
    static func setsNameAgain(_ steps: [JObject], typed: String, task: String) -> Bool {
        let goal = AppNames.hans(task)
        guard goal.range(of: #"(备注|群名|名称|名字|昵称)[^，。；“”"]{0,4}(改成|改为|设为|设成|写成)"#, options: .regularExpression) != nil,
              let re = try? NSRegularExpression(pattern: #"[「“"]([^」”"]+)[」”"]"#) else { return false }
        let key = typedKey(typed)
        let ns = task as NSString
        let quoted = re.matches(in: task, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        guard key.count >= 2, quoted.contains(where: { typedKey($0) == key }),
              let i = steps.lastIndex(where: { $0["action"]?.str == "type" && typedKey($0["text"]?.str ?? "") == key }) else { return false }
        return steps[(i + 1)...].contains { $0["action"]?.str == "tap" }
    }

    static func setAgainReason(_ typed: String) -> String {
        "Refused: “\(typed)” was already typed and saved once in this run, and the goal sets it for one person or thing. "
            + "A page that still shows the old name belongs to someone else (or is the page from before the save): go back "
            + "and check whose page it was saved on; never set it on a second one. If the text in this field came out wrong, "
            + "clear the field and type it again: that is let through."
    }

    /// D54, 136 (user 11-16: "这个可以让codex来判断啊，咋会犯这样的低级错误"): when 133真人测试一 was sent was answered 昨天下午1:20
    /// (y3, y4), "corrected" by the check to the time line under it (y5), and 11:26 PM off a search (y6). Which time line heads
    /// a message is not left to a model: the nearest time line above each line holding the text, worked out here.
    static func sentTimes(of target: String, in lines: [String]) -> [String] {
        let wanted = target.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return [] }
        var heading: String?, found: [String] = []
        for line in lines {
            let bare = line.trimmingCharacters(in: .whitespaces)
            if isChatTimeLine(bare) { heading = bare } else if bare.contains(wanted) { found.append(heading ?? "") }
        }
        return found
    }

    /// A line that is only a chat's time label: 昨天下午1:20, 凌晨12:20, 11月14日 下午3:30, 星期六 晚上7:03, 2025年12月8日 9:05.
    static func isChatTimeLine(_ line: String) -> Bool {
        line.range(of: #"^(\d{4}年)?(\d{1,2}月\d{1,2}日)?\s*(昨天|前天|今天|星期[一二三四五六日天]|周[一二三四五六日天])?\s*"#
                   + #"(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上|半夜)?\s*\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    /// The read's last line: the send times worked out for the text it read up to ("" when the text was not read).
    static func sentTimesLine(of target: String, in lines: [String]) -> String {
        let times = sentTimes(of: target, in: lines)
        guard !times.isEmpty else { return "" }
        let shown = times.map { $0.isEmpty ? "（上方没有读到时间行）" : "“\($0)”" }
        let what = times.count == 1 ? "“\(target)”的发送时间是" + shown[0]
            : "共读到\(times.count)条“\(target)”，发送时间从旧到新依次是" + shown.joined(separator: "、") + "（最下面一条最新）"
        return "\n程序按时间行算出：" + what + "。照抄这个时间，不要自己再推算。"
    }

    /// D38, s6 on 136: a read up 测试群 named only 学威 as a sender ("其余无法逐条归属"): the owner's own messages carry no
    /// name in WeChat, only their side. A row on the right (starting past a quarter of the width, ending near the right
    /// edge) is marked as the owner's; a long one of the owner's that starts further left is left unmarked, never a
    /// wrong mark.
    static func readUpLine(_ row: [CandidatePicker.Piece]) -> String {
        let text = row.map { $0.text }.joined(separator: " ")
        guard let minX = row.map({ $0.box.minX }).min(), let maxX = row.map({ $0.box.maxX }).max() else { return text }
        return minX >= 0.25 && maxX >= 0.78 ? "（我）" + text : text
    }

    /// D18: the words read while a finger was held that are gone once it let go (a chart's value under the finger,
    /// "下午3:00 25°"), in reading order, at most 16 pieces.
    static func shownOnlyWhileHeld(_ held: [[CandidatePicker.Piece]], now: [[CandidatePicker.Piece]]) -> String {
        let after = Set(now.joined().map { AppPlaces.normalized($0.text) })
        return held.joined().filter { !after.contains(AppPlaces.normalized($0.text)) }.prefix(16).map { $0.text }
            .joined(separator: " ")
    }

    /// B4 (122 over the cloud 11-11): the clipboard cannot be read from the background, and the approval showed only
    /// "（粘贴的内容）". What the paste put in is read off the screen: the words after it that were nowhere before it
    /// (the input box grows and the chat moves up, but its words stay the same), keys and short marks left out.
    static func newWords(before: [[CandidatePicker.Piece]], after: [[CandidatePicker.Piece]]) -> String {
        let key = { (s: String) in AppPlaces.normalized(s) }
        let old = Set(before.joined().map { key($0.text) })
        let fresh = after.joined().filter { piece in
            let k = key(piece.text)
            return piece.box.midY > 0.12 && k.count >= 2 && !old.contains(k) && !CandidatePicker.keyLabels.contains(piece.text)
                && !["發送", "send", "return", "換行"].contains(k)
        }.sorted { abs($0.box.midY - $1.box.midY) > 0.01 ? $0.box.midY < $1.box.midY : $0.box.minX < $1.box.minX }
        return String(fresh.map(\.text).joined(separator: " ").prefix(300))
    }

    static func sends(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "key": return ["enter", "return"].contains(act["combo"]?.str?.lowercased() ?? "")
        case "tap": return (act["x"]?.double ?? 0) >= 800 && (act["y"]?.double ?? 0) >= 400  // 发送 by the box: ~0.49
        default: return false
        }
    }

    static let noKeyboardReason = "Not typed: no keyboard is on screen, so the input box is not focused (the last tap "
        + "missed it). Tap the input box again (this tap is aimed) and type only once the keyboard shows."
    static let waitLimit = 3        // waits in a row that changed nothing
    static let blindLookLimit = 10  // looks of about 6 s each with sharing on before the user is asked
    static let blindLooksBeforeCancel = 2
    static let refusalsInARow = 3
    static let offlineWaitLimit = 24  // waits of 5 s for the network before the user is asked
    private var offlineWaits = 0
    private var sendBlocks = 0
    /// Looks at where a message would go before it is sent (the fast model; nil: no look).
    var sendChecker: ChatModel?
    /// Checks a finished run's answer (the fast model; nil: the planner). Over the proxy Codex took ~12 s to its first
    /// word for a one-line OK (11-10); Doubao 1.3 s.
    var doneChecker: ChatModel?
    /// Set for a task the cloud gave: asked before each message is sent; false stops the run with nothing sent.
    var approveSend: ((String) async -> Bool)?
    /// The chat title read at the top when approval was asked (shown with it: 121 r05's message was approved for 测试群
    /// while it sat in 验证群).
    private(set) var approvalPlace: String?
    private var approvedTexts: Set<String> = []
    static let notApprovedAnswer = "没有发送：这条消息未获批准。"

    /// D37: a page title that is a picker or a settings page, where nothing typed reaches anyone (WeChat's own words).
    static func notAChat(_ title: String) -> Bool {
        let t = AppNames.hans(title).trimmingCharacters(in: .whitespacesAndNewlines)
        let pages = ["新聊天", "发起群聊", "选择联系人", "选择成员", "选择群成员", "添加成员", "删除成员", "群成员", "聊天成员",
                     "聊天信息", "设置备注和标签", "备注", "群聊名称", "修改群聊名称", "我在本群的昵称", "通讯录", "添加朋友",
                     "朋友资料", "资料设置", "新消息通知", "设置"]
        return pages.contains { t == $0 || (t.hasPrefix($0) && t.dropFirst($0.count).allSatisfy { "()（）0123456789 ".contains($0) }) }
    }

    /// D163, s4 over the cloud 11-19 (148): to see the new remark in 通讯录 the run searched for it there; the remark,
    /// typed into the search box, was refused as set a second time, and the friend's 微信号 typed there next was held as
    /// a message ("about to send: LHY8768Z"), turned down, and the run stopped unfinished. A box at the top with 取消 at
    /// its right end is a search (WeChat's, Contacts', Settings'…): what is typed there reaches no one and sets nothing.
    static func searchBarUp(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        rows.joined().contains { piece in
            ["取消", "cancel"].contains(AppNames.hans(piece.text).lowercased().trimmingCharacters(in: .whitespaces))
                && piece.box.midY <= 0.14 && piece.box.minX >= 0.75
        }
    }

    static func searchBarUp(in frame: Data?) async -> Bool {
        guard let frame else { return false }
        return searchBarUp(await CandidatePicker.rowsOffMain(in: frame, top: 0.03, bottom: 0.15))
    }

    static let wrongPlaceReason = "Not sent: this is not where the goal says to send. Go to the conversation the goal names "
        + "(back to the list, or search for it), then type and send there. Seen: "

    static let sendCheck = """
    An agent on an iPhone is about to send a message. You get the goal and the screen now.
    Reply with exactly one line: OK, or NO: where it is instead, in a few words.
    Say NO only when the conversation open on the screen (its name is at the top) is clearly not the one the goal says to send to.
    Never judge the message itself.
    """

    /// The goal sends a message somewhere: a check before each send is worth its seconds.
    static func asksToSend(_ task: String) -> Bool {
        let t = task.lowercased()
        let verbs = ["發", "发", "傳給", "传给", "回覆", "回复", "send", "reply"]
        let places = ["群", "給", "给", "聊天", "訊息", "消息", "message", "chat"]
        return verbs.contains { t.contains($0) } && places.contains { t.contains($0) }
    }

    static let untypedSearchReason = "Not searched: nothing was typed in this app yet. Words already in a search box (often grey) "
        + "are the app's own suggestion, not your search. Tap the box, type the words the goal asks for, then search."

    /// A search started (Return, or a tap the model says is the search button) in a goal that searches, with nothing
    /// typed or pressed since the app was opened (by open, or by its icon).
    static func searchesUntyped(_ act: JObject, after steps: [JObject], task: String) -> Bool {
        let goal = task.lowercased()
        guard ["搜尋", "搜索", "搜寻", "search"].contains(where: { goal.contains($0) }) else { return false }
        let submits: Bool
        switch act["action"]?.str {
        case "key": submits = sends(act)
        case "tap":
            let t = (act["thought"]?.str ?? "").lowercased()
            submits = ["搜尋", "搜索", "搜寻", "search"].contains { t.contains($0) }
                && ["按鈕", "按钮", "button", "執行", "执行"].contains { t.contains($0) }
        default: submits = false
        }
        guard submits else { return false }
        for step in steps.reversed() {
            switch step["action"]?.str {
            case "type", "press", "compose": return false
            case "open": return true
            default: if opensByIcon(step) { return true }
            }
        }
        return true
    }

    /// The goal posts something others see (a message, a reply, a comment, a post). What it says not to do is not counted:
    /// "不要留言" asks for no comment.
    static func publishes(_ task: String) -> Bool {
        let t = task.lowercased().replacingOccurrences(
            of: #"(不要|不用|不必|別|别|勿|禁止|don't|do not|never)[^，,。.；;！!？?\n]*"#, with: " ", options: .regularExpression)
        // Build 120 on the phone, 11-11: "影片是誰發的", "評論、收藏、轉發各是多少" were read as sending, and a news
        // site typed in Safari and a search on 小紅書 were held for approval (one task cancelled). But "在测试群发你好"
        // sends: a 发 still counts, except inside words that only read or name something.
        let said = ["發一", "发一", "發個", "发个", "發條", "发条", "發訊息", "发讯息", "發消息", "发消息", "發信息", "发信息",
                    "發到", "发到", "發給", "发给", "發送", "发送", "傳給", "传给", "轉發給", "转发给", "轉發到", "转发到",
                    "回覆", "回复", "留言", "發評論", "发评论", "寫評論", "写评论", "評論一", "评论一", "發表評論", "发表评论",
                    "發帖", "发帖", "發文", "发文", "發布到", "发布到", "發朋友圈", "发朋友圈", "說一聲", "说一声",
                    "說一句", "说一句", "傳送", "传送",
                    "send ", "reply ", "post a", "comment on", "leave a comment"]
        if said.contains(where: { t.contains($0) }) { return true }
        // "跟我說一下天氣" and "告訴我" ask this phone, they send nothing; "跟他說", "告訴大家", "評論：好看" send.
        if t.range(of: #"(跟|对|對|和|向)(?!我)[^，,。.；;！!？?\n]{1,12}[说說]|告[訴诉](?!我)|(評論|评论|(?<!我)[說说])[：:「“"]"#,
                   options: .regularExpression) != nil { return true }
        var rest = t
        for word in [#"[誰谁]?[發发]的"#,  // who posted it, what they posted
                     #"[轉转][發发](?![給给到這这一那該该])"#,  // the share count, not "转发给/转发这条"
                     #"[發发][布佈表](?![到一這这])"#,  // 发布时间, 发表于
                     #"(開|开|出|批|沙|爆|自|激|研|散|揮|挥|蒸|奮|奋|頒|颁|引|啟|启|收|头)[發发]"#,
                     #"[發发](現|现|生|票|貨|货|展|音|燒|烧|型|揮|挥|明|光|行|起|射|電|电|財|财|胖|呆|愁|抖|麻|熱|热|炎|病|作|育|芽|酵|達|达|覺|觉|放|售|件)"#] {
            rest = rest.replacingOccurrences(of: word, with: " ", options: .regularExpression)
        }
        return rest.contains("發") || rest.contains("发")
    }

    /// Every message a goal gives: each part in quotes, or else the words after a colon. 121 over the cloud 11-11:
    /// "先發「k02第一句」，再發「k02第二句」" asked approval for the first only; the second, read as words the goal names
    /// that are not its message (like a chat's name), went out unasked.
    static func messageParts(_ task: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[「“"]([^」”"]+)[」”"]"#) else { return [] }
        let ns = task as NSString
        let matches = re.matches(in: task, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return messagePart(task).map { [$0] } ?? [] }
        // 125 stress test 11-12 (t06): every quoted part was a message, so “蓝牙耳机” searched in 淘宝 asked for approval
        // as one, and then could not be typed into 拼多多's search, 110 times. A quoted part is a message only when a way
        // of saying "send" comes right before it (发“…”, 内容是“…”, 回复“…”), not 搜索“…”.
        return matches.filter { m in
            let start = max(0, m.range.location - 6)
            let before = ns.substring(with: NSRange(location: start, length: m.range.location - start))
            return sayWords.contains { before.contains($0) }
        }.map { ns.substring(with: $0.range(at: 1)) }
    }

    static let sayWords = ["发", "發", "说", "說", "回复", "回覆", "留言", "评论", "評論", "写", "寫", "讯息", "訊息", "消息",
                           "内容", "內容", "话", "話"]

    /// The words a goal gives as the message: after a colon, or in quotes (nil: none given).
    static func messagePart(_ task: String) -> String? {
        if let r = task.range(of: #"[「“"]([^」”"]+)[」”"]"#, options: .regularExpression) {
            return String(task[r].dropFirst().dropLast())
        }
        // Only a colon after a way of saying "send" gives the message (發一則訊息：…, 留言：…): 121 over the cloud 11-11,
        // "幫我做這六件事：1. 查深圳明天的最高溫；…" made the list's first item the message, and 深圳 typed in Weather's search
        // was held for approval.
        let said = ["发", "發", "说", "說", "回复", "回覆", "留言", "评论", "評論", "写", "寫", "讯息", "訊息", "消息", "内容", "內容", "话", "話"]
        for colon in task.indices where task[colon] == "：" || task[colon] == ":" {
            let before = String(task[..<colon].suffix(8))
            guard said.contains(where: { before.contains($0) }) else { continue }
            let rest = task[task.index(after: colon)...].prefix { !"。；;\n".contains($0) }
            let message = rest.trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? nil : message
        }
        return nil
    }

    /// Whether text about to go out with Return waits for the cloud's approval: a message, a reply, a post. Words the
    /// goal itself names, searched or opened in a goal that posts nothing, are not one; nor, in a goal that gives its
    /// message, words it names that are not that message (the chat's name searched for).
    /// chatApp: the app in front is one that sends messages (see inChatApp). Build 118, 11-10: 高德 searched 下水徑地鐵站, a
    /// station it knew from before, in a goal that posts nothing; it was held as a message and the task was cancelled.
    static func needsApproval(_ text: String, task: String, chatApp: Bool = true) -> Bool {
        func key(_ s: String) -> String { AppNames.hans(typedKey(s)).lowercased() }
        // Build 121 over the cloud 11-11: the goal said www.sina.com.cn, Codex typed https://www.sina.com.cn in Safari
        // (opened by its icon, so the app was unknown), and the address was held as a message. An address is compared
        // without its scheme, www. and closing slash.
        let typed = key(text).replacingOccurrences(of: #"^(https?://)?(www\.)?|/$"#, with: "", options: .regularExpression)
        let goal = key(task)
        // The same day: "進新浪網" without an address; a learned route opened Safari by its icon again. A web address
        // typed for a goal that names a browser and posts nothing goes to the address bar, not to a chat.
        let address = key(text).range(of: #"^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(/\S*)?$"#, options: .regularExpression) != nil
        if address,
           goal.range(of: #"safari|chrome|浏览器|瀏覽器|网址|網址|网站|網站|网页|網頁"#, options: .regularExpression) != nil,
           !publishes(task) { return false }
        // 126 over the cloud 11-12 (g3): Safari could not reach the search site, so the model typed cn.bing.com in the
        // address bar; the goal also posted to 测试群, and the address was held as a message "about to send into the
        // wrong place" until the run ended. An address typed outside a chat app is not a message unless the goal's
        // message is that address.
        if address, !chatApp, !messageParts(task).map(key).contains(where: { !$0.isEmpty && $0.contains(typed) }) { return false }
        // D127, q134h on 144 (h21): "北京明天最高X度（X换成你看到的数字）" typed as 北京明天最高8度 passed as the goal's words with
        // one stray letter and went out unasked, like a search; typed as 北京明天最高13度 (two strays) it was held as some other
        // message, and the owner's runner turned it down. The goal's message with its placeholder filled is that message.
        if fillsPlaceholder(typed, task: task) { return publishes(task) }
        guard !typed.isEmpty, goal.contains(typed) || takenFrom(typed, goal) else { return chatApp || publishes(task) }
        guard publishes(task) else { return false }
        let messages = messageParts(task).map(key).filter { !$0.isEmpty }
        // A goal that posts but gives no message ("整理成一段話發到测试群"): its own words typed in a chat app may be the
        // message; typed in 天气 or 淘宝 they are searches.
        guard !messages.isEmpty else { return chatApp }
        // 133 over the cloud 11-14 (x1): "咖啡" typed in 美团's search box, in a goal that sends “X1咖啡便宜”, was held as
        // the message; its search was refused twice as "the wrong place" and the run failed at 515 s. Outside a chat app
        // only the whole message, or nearly, is it: one word of it is a search.
        return messages.contains { typed.contains($0) || ($0.contains(typed) && (chatApp || typed.count * 10 >= $0.count * 7)) }
    }

    static let chatApps = ["微信", "wechat", "qq", "企业微信", "钉钉", "飞书", "信息", "messages", "短信", "telegram", "whatsapp", "line"]

    /// Apps a goal names that send no messages (Simplified, as AppNames.hans writes them).
    static let namedApps = ["高德", "地图", "天气", "计算器", "计算机", "股市", "safari", "浏览器", "淘宝", "拼多多", "美团",
                            "抖音", "小红书", "快手", "备忘录", "日历", "行事历", "时钟", "设置", "设定", "京东", "百度"]

    /// Whether the app opened last in this run sends messages. No app opened by name: the goal's own apps decide (build
    /// 121 over the cloud 11-11: a learned route opens its app by the icon, and 下水径 typed in 高德 and an address
    /// typed in Safari were held as messages); a goal that names none, or names a chat app, may be in one.
    /// Whether this app sends messages (微信, 企业微信, 钉钉…).
    /// D109: apps whose feed turns one video a screen, and a swipe there that turns it (up or down, long).
    /// D121, z3 on 143 (items 24 and 37): Calendar's month view stayed on November through seven held swipes: a held
    /// stroke ends with no speed, and the months snap back. A month turns with a quick stroke there too.
    /// D121b, 144: on this phone (zh-TW) Calendar is 行事曆, and its months still turned with four slow strokes.
    static let flickApps = ["抖音", "抖音极速版", "快手", "快手极速版", "tiktok", "日历", "calendar", "行事历", "行事曆"]

    /// D165, s7 over the cloud 11-19 (148): a 小红书 note's pictures never turned: five sideways swipes, each walked slowly
    /// and held (D109), and each snapped back; the steps were then taken from an older note. A sideways swipe after one
    /// the same way that changed nothing (or that the model says did not turn) is one quick stroke, as a finger turns a
    /// picture, a banner or a page. Coordinates 0-1.
    static func turnsSideways(after steps: [JObject], thought: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Bool {
        guard abs(x2 - x1) >= 0.25, abs(y2 - y1) <= 0.15,
              let last = steps.last(where: { !["stale plan", "note", "refused"].contains($0["action"]?.str ?? "") }),
              last["action"]?.str == "swipe", let a1 = last["x1"]?.double, let a2 = last["x2"]?.double,
              let b1 = last["y1"]?.double, let b2 = last["y2"]?.double,
              abs(a2 - a1) >= 250, abs(b2 - b1) <= 150, (a2 - a1) * (x2 - x1) > 0 else { return false }
        let said = AppNames.hans(thought).lowercased().range(of: #"(未|没|没有|还没)(翻页|翻过去|切换|滑过去|翻到)|did(n't| not) (turn|page|flip|move|change)"#,
                                                                options: .regularExpression) != nil
        return last["changed"] == .bool(false) || said
    }

    static func flicks(app: String?, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Bool {
        guard let app else { return false }
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return flickApps.contains(name) && abs(y2 - y1) >= 0.25 && abs(x2 - x1) <= 0.15
    }

    static func isChatApp(_ app: String) -> Bool {
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return chatApps.contains { name == $0 || name.contains($0) && $0.count >= 2 }
    }

    static func inChatApp(_ steps: [JObject], task: String = "") -> Bool {
        guard let app = steps.last(where: { $0["action"]?.str == "open" })?["app"]?.str else {
            let goal = AppNames.hans(task).lowercased()
            if ["微信", "wechat", "企业微信", "钉钉", "飞书", "短信", "imessage", "telegram", "whatsapp"].contains(where: { goal.contains($0) }) {
                return true
            }
            return !namedApps.contains { goal.contains($0) }
        }
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return chatApps.contains { name == $0 || name.contains($0) && $0.count >= 2 }
    }

    /// D127: a goal message holding a word the goal says to replace ("北京明天最高X度", X换成…), typed with 1–12 characters
    /// in that word's place. `typed` is a typedKey, lowercased.
    static func fillsPlaceholder(_ typed: String, task: String) -> Bool {
        func key(_ s: String) -> String { AppNames.hans(typedKey(s)).lowercased() }
        let words = placeholders(task).map(key).filter { !$0.isEmpty }
        return messageParts(task).map(key).contains { message in
            words.contains { word in
                guard let r = message.range(of: word) else { return false }
                let (head, tail) = (String(message[..<r.lowerBound]), String(message[r.upperBound...]))
                guard head.count + tail.count >= 2, typed.hasPrefix(head), typed.hasSuffix(tail) else { return false }
                return (1...12).contains(typed.count - head.count - tail.count)
            }
        }
    }

    /// The goal's own words, a little shortened or reworded: its characters in the goal's order, with one in ten (at least
    /// one, none in a word under four) left out or added. Build 116 over the cloud 11-10: 深圳灣公園附近停車場, the goal's 深圳灣公園附近的停車場 without
    /// its 的, was held as a message, refused, and the search task ended "not approved".
    static func takenFrom(_ typed: String, _ goal: String) -> Bool {
        let t = Array(typed), g = Array(goal)
        guard t.count >= 2 else { return false }
        var at = 0, strays = 0
        for c in t {
            if let i = g[at...].firstIndex(of: c) { at = i + 1 } else { strays += 1 }
        }
        return strays <= (t.count >= 4 ? max(1, t.count / 10) : 0)
    }

    /// Where a message would go now, if that is not where the goal says (nil: fine, or the check could not be made).
    /// Where a message would go, as far as the screen says it without a model.
    enum ChatCheck: Equatable { case right, wrong(String), unknown }

    /// The groups a goal names, each with the words before it (测试群 in "在微信打開测试群", "發到测试群"): the title at
    /// the top must end one of them.
    static func namedGroups(_ task: String) -> [String] {
        let pattern = #"[\p{Han}A-Za-z0-9]{1,10}群"#
        let all = (try? NSRegularExpression(pattern: pattern))?
            .matches(in: task, range: NSRange(task.startIndex..., in: task))
            .compactMap { Range($0.range, in: task).map { String(task[$0]) } } ?? []
        let generic = ["微信群", "这个群", "這個群", "那个群", "那個群", "一个群", "一個群", "两个群", "兩個群", "各个群", "各個群"]
        return all.filter { name in !generic.contains { name.hasSuffix($0) } }
    }

    /// D114: the one group a short goal only reads in ("在微信验证群看最新一条消息是谁发的"): at most two numbered parts,
    /// one group named, nothing quoted (to send or to find). nil for any other goal.
    static func readsOneGroup(_ task: String) -> String? {
        let groups = namedGroups(task)
        guard goalParts(task) < 3, groups.count == 1,
              task.range(of: #"[“"「『]"#, options: .regularExpression) == nil else { return nil }
        return groupName(groups[0])
    }

    /// A group as the goal names it, without the words before it ("在微信验证群" → 验证群, "如果群" → 群).
    static func groupName(_ said: String) -> String {
        said.replacingOccurrences(of: #"(?i)^.*(?:微信|wechat|如果|若是|要是|打开|打開|进入|進入|点进|點進|发到|發到|到|在|的)"#, with: "",
                                  options: .regularExpression)
    }

    /// A chat title that is a group's: it ends in 群 once a member count "(4)" is taken off.
    static func looksLikeGroup(_ title: String) -> Bool {
        AppNames.hans(title).replacingOccurrences(of: #"\s*[（(][^)）]*(?:[)）]|$)\s*$"#, with: "", options: .regularExpression)
            .hasSuffix("群")
    }

    /// D115, s4 on 143: for 测试群's members Doubao opened 137测试群 (left by earlier rounds) and went on there; after
    /// the done check stopped it, Codex in the right 测试群（4人） kept taking the members for the wrong group's, back and
    /// forth 20 times until the steps ran out. Each step in a chat app now says where it is against the goal's group.
    static func chatPlaceLine(_ title: String?, after last: String?, task: String, steps: [JObject]) -> String? {
        guard let title else { return nil }
        let named = namedGroups(task).map(groupName).filter { $0.count >= 2 }
        guard !named.isEmpty else { return nil }
        let names = named.joined(separator: "、")
        if looksLikeGroup(title) {
            if chatCheck(seen: title, task: task, steps: steps) == .right {
                return "Chat place: the chat open now, “\(title)”, is \(names), the group the goal names. Work here: what you "
                    + "read in it, and on its 聊天信息 page (its members), is that group's."
            }
            return "Chat place: the chat open now, “\(title)”, is not \(names), the group the goal names: a name that only "
                + "holds it with more around it (137测试群 for 测试群) is another group. Do nothing for the goal here: go back "
                + "and open \(names) itself."
        }
        let infoPage = AppNames.hans(title).range(of: #"^(聊天信息|群成员|聊天成员|群聊成员)"#, options: .regularExpression) != nil
        guard infoPage, let last else { return nil }
        if chatCheck(seen: last, task: task, steps: steps) == .right {
            return "Chat place: this page belongs to “\(last)”, the group the goal names: its members are that group's members."
        }
        return "Chat place: this page belongs to “\(last)”, not \(names), the group the goal names: go back and open \(names) itself."
    }

    static func chatCheck(seen: String?, task: String, steps: [JObject]) -> ChatCheck {
        let groups = namedGroups(task)
        guard !groups.isEmpty else { return .unknown }
        func key(_ s: String) -> String {
            // 133 over the cloud 11-14 (g7): the title read "测试群（4人", its ）cut off, and two sends were refused as
            // "not the group the goal names": the run failed at 566 s. A bracket left open at the end goes too.
            AppNames.hans(s.replacingOccurrences(of: #"[（(][^)）]*(?:[)）]|$)"#, with: "", options: .regularExpression))
                .lowercased().filter { $0.isLetter || $0.isNumber }
        }
        if let seen {
            let t = key(seen)
            if t.count >= 2, groups.contains(where: { key($0).hasSuffix(t) }) { return .right }
            return .wrong("the chat at the top is “\(seen)”, not the group the goal names")
        }
        if let app = steps.last(where: { $0["action"]?.str == "open" })?["app"]?.str,
           !inChatApp([["action": .str("open"), "app": .str(app)]]) {
            return .wrong("this is \(app), not a chat: no chat title at the top")
        }
        return .unknown
    }

    private func wrongPlace(frame: Data?) async -> String? {
        guard let model = sendChecker else { return nil }
        do {
            let reply = try await model.chat(system: Self.sendCheck, text: "Goal: \(task)\n\nThe image is the screen now.",
                                             image: frame, maxTokens: 80, temperature: 0).text
            trace?.write(kind: "send check", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("send check: \(reply.prefix(160))")
            return Self.wrongness(reply)
        } catch {
            DebugLog.write("send check failed: \(error.localizedDescription)")
            return nil
        }
    }
    static let leaveLimit = 2       // times the same way off the same screen is taken; the next is refused

    static let waitReason = "Refused: you waited several times and nothing changed, so more waiting will not help. Change "
        + "the method now: reload, go back, or another way to the same result. A website that stays blank is not reachable "
        + "from here: type another search site in the address bar (www.baidu.com, cn.bing.com)."
    static let circleReason = "Refused: you already left this same screen this way twice and came back to it. Leaving does "
        + "not make it go away. Deal with what is on it: a sheet or permission prompt belongs to the app, answer it with the "
        + "smallest choice (不允許, 不分享, 稍後, 關閉, Not Now), then go on. If what the goal asks for is already done or on "
        + "this screen, finish: answer done."
    /// The app a name for a part of it stands for (美团外卖 → 美团, 视频号 → 微信); nil when it is no such part.
    static func hostApp(_ name: String) -> String? {
        let n = AppNames.hans(name).filter { !$0.isWhitespace }
        let parts = ["美团外卖": "美团", "淘宝闪购": "淘宝", "饿了么外卖": "饿了么", "京东外卖": "京东", "高德打车": "高德地图",
                     "抖音商城": "抖音", "视频号": "微信", "朋友圈": "微信", "微信支付": "微信"]
        if let host = parts[n] { return host }
        if n.hasSuffix("外卖"), n.count > 2 { return String(n.dropLast(2)) }
        return nil
    }

    /// Asks the owner whether to install an app the task needs and the phone does not have: true install, false end the
    /// task, nil nobody to ask (the thing is noted as not installed, as before). Set per run by RunSession.
    var askInstall: ((String) async -> Bool?)?
    /// Apps asked about in this run (once each), and apps looked for a second time before "not on this phone".
    private var installAsked: Set<String> = []
    /// D194, the X install over the cloud 11-20 (151): the owner said yes, 安裝 went through with no password, and the
    /// run of one thing (45 steps) spent 30 of them on wait while App Store's ring turned; it ended "步骤用完了还没做完"
    /// before X was on the phone. Each install the owner allows adds steps for the download.
    private var installSteps = 0
    static let installStepAllowance = 60
    /// D28, user 11-15: before 发布 in a video or post app the owner is asked (the cloud's approval, or a panel here);
    /// nil: nobody to ask (a WeChat watch run), and nothing is published. Apps this run may publish in, or was told not to.
    var askPublish: ((String) async -> Bool?)?
    private var publishAllowed: Set<String> = [], publishDeclined: Set<String> = []
    /// D59, user 11-16: a security check (滑块, 拼图) is done by the owner by hand: true done, false not done, nil nobody to
    /// ask (a WeChat watch run). Set per run by RunSession; asked at most verifyLimit times a run.
    var askVerify: ((String) async -> Bool?)?
    private var verifyAsked = 0
    static let verifyLimit = 3

    static func verifyQuestion(_ app: String) -> String {
        "“\(app)”要人工安全验证（滑块或拼图），请到手机上亲手完成，完成后点“已完成”；不处理的话这一项记为未完成，其他的照做。"
    }

    static func verifyFailReason(_ app: String, asked: Bool) -> String {
        app + "要求人工安全验证（滑块或拼图），" + (asked ? "机主没有完成" : "没有人能处理") + "，按规则不自动处理"
    }
    private var lookedAgain: Set<String> = []
    /// What the run is told once the owner said yes. Never a password: Apple asks the owner for that on the phone.
    static func installNote(_ app: String) -> String {
        "机主同意下载安装“\(app)”：这一次下载是机主刚刚亲自同意的，目标里的“不要下载或更新任何App”这一次不适用于“\(app)”，先装好再做别的项目。"
            + "打开 App Store，搜索“\(app)”，在结果里找名字和开发者都对的那个 App，点“获取”（或云朵图标）。"
            + "如果要输入 Apple ID 密码、要按两下侧边按钮或刷脸确认，就停在那里用 wait 等机主在手机上确认，绝对不要输入密码。"
            + "按钮变成“打开”就是装好了：打开它，首次打开的条款点同意、权限只给要用到的，然后接着做原来的事。不要买 App 内的东西。"
    }
    static func installDeclined(_ app: String) -> String { "手机上没有“\(app)”，机主选择不下载，任务结束" }
    /// D23, 135 over the cloud 11-15 (y1 16:31): the owner said yes to 京东, and the new plan went on to WeChat and the
    /// calculator: the goal's "不要下载或更新任何App" won over the note. The install is the new plan's first part.
    static func installFirst(_ app: String) -> String {
        "安装“\(app)”：机主刚刚同意下载，目标里“不要下载或更新任何App”这一次不适用于“\(app)”。打开 App Store，搜索“\(app)”，点“获取”，"
            + "等按钮变成“打开”后打开它；装好以后再接着做目标里用到“\(app)”的那一项和其余各项。"
    }

    /// Apple's own apps: a failed open of one is Search failing, never something to download (134 y1: 行事曆).
    static func builtInApp(_ app: String) -> Bool {
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return ["日历", "行事历", "时钟", "天气", "计算器", "计算机", "备忘录", "设置", "设定", "safari", "appstore", "照片", "相机",
                "地图", "提醒事项", "信息", "电话", "邮件", "音乐", "钱包", "文件", "健康", "股市", "翻译", "指南针", "播客", "图书",
                "家庭", "快捷指令", "通讯录", "facetime", "语音备忘录", "测距仪", "放大器", "查找", "手表", "视频", "游戏中心"]
            .contains(name)
    }

    static let openFailedReason = " is not on this phone: it is not on the Home Screen and Search does not list it as an app. "
        + "Do not search the web for it and do not try again; if the goal needs it, stop with fail and say so."

    /// True when this is the third time the same way off this screen is taken: it comes back each time (a contacts sheet
    /// left and reopened for 300 s, over USB 11-09). Counts this one. Another way off, or another app, is another move.
    func circling(_ act: JObject, on look: [UInt8]) -> Bool {
        guard ["home", "back", "open"].contains(act["action"]?.str ?? "") || Self.leaves(act) else { return false }
        let move = Actions.key(act)
        if let i = departures.firstIndex(where: { Actions.key($0.move) == move && Vision.sameScreen($0.look, look) }) {
            departures[i].times += 1
            return departures[i].times > Self.leaveLimit
        }
        departures.append((look, act, 1))
        return false
    }

    /// True when this many waits in a row changed nothing.
    static func waitedEnough(_ steps: [JObject]) -> Bool {
        let recent = steps.filter { !["refused", "stale plan"].contains($0["action"]?.str ?? "") }.suffix(waitLimit)
        return recent.count == waitLimit && recent.allSatisfy { $0["action"]?.str == "wait" && $0["changed"] == .bool(false) }
    }

    /// Build 118 without Codex, 11-10: Weather opened at the bottom of the page, the forecast was above, and the models
    /// swiped "up to bring the forecast in" 25 times: at the end of a page that way nothing moves.
    static let endReachedReason = "Refused: the last two swipes this way moved nothing: the page is at its end that way. "
        + "What you look for is the other way. To see what is above (the top of the page, earlier rows) move the finger down: "
        + "swipe 500 300 500 750. To see what is below, move it up: swipe 500 750 500 300. Or it is on another tab or page."

    static func swipedToTheEnd(_ act: JObject, after steps: [JObject]) -> Bool {
        guard let y1 = act["y1"]?.double, let y2 = act["y2"]?.double, abs(y2 - y1) > 100 else { return false }
        let last = steps.filter { !["refused", "stale plan", "loop"].contains($0["action"]?.str ?? "") }.suffix(2)
        return last.count == 2 && last.allSatisfy { s in
            guard s["action"]?.str == "swipe", let a = s["y1"]?.double, let b = s["y2"]?.double else { return false }
            return (b - a) * (y2 - y1) > 0 && (s["changed"] == .bool(false) || s["scrolled"] == .bool(false))
        }
    }

    static let deadTapReason = "Refused: tapping this spot already did nothing twice (the screen did not change, or the next "
        + "stroke still left no line). It is not the control you want: look at what else is on screen and try a different one. "
        + "Text you just typed is submitted with: key enter."

    static let tabPageHint = " Here the top left is no back button: this is one of the app's tab pages (购物车, 我的, 消息). "
        + "Tap a tab in the bar at the bottom (首页, 我的淘宝, 我的) to go elsewhere; reopening the app comes back here."

    /// The tap since the previous stroke (the try at picking a tool), if there was one.
    static func tapBeforeStroke(_ steps: [JObject]) -> JObject? {
        for s in steps.reversed() {
            switch s["action"]?.str ?? "" {
            case "tap": return s
            case "no ink": return nil  // two strokes with no tap between: no tool was tried
            default: continue
            }
        }
        return nil
    }

    /// The points a stroke goes through, 0-1 of the screen, for checking it left a line.
    private func strokePoints(_ act: JObject) -> [CGPoint] {
        func p(_ k: String) -> Double { (act[k]?.double ?? 0) / 1000 }
        switch act["action"]?.str {
        case "circle": return circle(p("x"), p("y"), p("r"), aspect: screen?.aspect ?? 9 / 19.5, n: 36)
        case "path": return points(act).map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }
        default: return []
        }
    }

    /// The share of a stroke's points where a line newly shows: clearly darker than before (a pen, black or in colour;
    /// the canvas's grey dots moving do not count). A stroke without a pen selected only pans the canvas and leaves
    /// none (logs(14): two smileys "drawn" on an empty board, both taken as done). nil when it cannot be told.
    static func inkShare(before: Data?, after: Data?, stroke: [CGPoint]) -> Double? {
        guard let before, let after, let a = Vision.image(before), let b = Vision.image(after),
              a.width == b.width, a.height == b.height, stroke.count >= 2 else { return nil }
        let w = a.width / 2, h = a.height / 2, reach = 4  // a line within 8 px of where it was aimed
        let ga = Vision.gray(a, w, h), gb = Vision.gray(b, w, h)
        var samples = 0, inked = 0
        for pt in stroke {
            let x = Int(Double(pt.x) * Double(w)), y = Int(Double(pt.y) * Double(h))
            guard x >= reach, y >= reach, x < w - reach, y < h - reach else { continue }
            samples += 1
            var darkBefore = 255, darkAfter = 255
            for dy in -reach...reach { for dx in -reach...reach {
                let i = (y + dy) * w + x + dx
                darkBefore = min(darkBefore, Int(ga.px[i]))
                darkAfter = min(darkAfter, Int(gb.px[i]))
            } }
            if darkAfter < 150 && darkAfter < darkBefore - 80 { inked += 1 }
        }
        return samples == 0 ? nil : Double(inked) / Double(samples)
    }

    /// D50, y3 on 136 (item 7): on 淘宝's search results a tap at the bottom right (taken for 我的淘宝) opened a 满意度调研
    /// page; back, the tap again, and every back after that was refused (the actor's twice, then Codex's, driving after a
    /// new plan): the run was held on the survey and the thing skipped. When Codex, looking afresh, also leaves a screen
    /// the run keeps coming back to, it leaves, and the tap that opened it is refused instead. A leave the executor asks
    /// for alone is still refused (traces(33): the chat it left was the right one).
    static func codexLeaves(_ act: JObject, opener: JObject) -> Bool {
        act["by"]?.str == "planner" && leaves(act) && !leaves(opener)
    }

    /// D50: the tap that opened a screen the run left twice over.
    static let openerReason = "Refused: this tap opened a screen you then left, twice over: here it does not do what you "
        + "think (it is not the control you want, or it opens something else, such as an ad or a survey). Do not tap it "
        + "again on this page: read the labels for the right control, or go back further first (to the app's home, where "
        + "its tabs are)."

    /// D169, n07 over the cloud 11-19 (148): a 小红书 video note showed its likes (2.6万) on the video and its whole title
    /// only on the comments sheet; the run opened and closed the sheet ten times to see both at once, never noted either,
    /// and ran out of steps. What is asked for may be split over the two screens of a back-and-forth.
    static let loopReason = "this move starts again a back-and-forth this run already went through twice; the move that "
        + "left was the mistake. Stay on this screen and do the task here. If what the goal asks for is already done, answer done. "
        + "If it shows partly here and partly on the other screen, note what this screen shows now (note …) and take the "
        + "rest from your notes or the other screen: a thing noted need not be seen again."

    /// A move that leaves the current screen: back, home, or a tap on the back arrow at the top left.
    static func leaves(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "back", "home": return true
        case "tap": return (act["x"]?.double ?? 1000) <= 150 && (act["y"]?.double ?? 1000) <= 130
        default: return false
        }
    }

    /// Two plans aim at the same place: the same action landing within 3% of the screen of each other (a model
    /// rarely names the exact same pixel twice), or the same text or key for actions without a place.
    /// The taps since the last other move, with `next`, close a round already gone through: the same spots in the same
    /// order, twice over (three times for a round of two, which can be a real back and forth). 127 over the cloud 11-12
    /// (g8): 购物车 → ×2 → "−" (which opened the item again), ten times over, 30 steps; each tap changed the screen, so no
    /// dead tap was seen.
    static func repeatsRound(_ steps: [JObject], next: JObject) -> Bool {
        var taps: [JObject] = []
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            // D17, 134 over the cloud 11-15 (y4): 高德's 驾车 tab, the mode panel, 公车捷运, and round again; then the drive
            // time was noted and 公车捷运 was refused 25 times as the same round. A round that noted something got on.
            // D129, q133x on 144 (x4): the taps of a part skipped as a round counted again in the next part, whose first tap
            // was refused as the old round; three parts were skipped after one refusal each and the run failed at item 14.
            if a == "tap" { taps.insert(s, at: 0) } else if observedActions.contains(a) || a == "note" || partEnds.contains(a) { break }
            if taps.count >= 12 { break }
        }
        taps.append(next)
        for k in 2...4 {
            let rounds = k == 2 ? 3 : 2
            guard taps.count >= k * rounds else { continue }
            let last = Array(taps.suffix(k * rounds))
            let first = Array(last.prefix(k))
            if (1..<rounds).allSatisfy({ r in (0..<k).allSatisfy { sameSpot(first[$0], last[r * k + $0]) } }),
               Set(first.map { "\(Int(($0["x"]?.double ?? 0) / 30)),\(Int(($0["y"]?.double ?? 0) / 30))" }).count == k {
                return true
            }
        }
        return false
    }

    /// Records that end a part: what came before belongs to another part (D129).
    static let partEnds: Set<String> = ["part done", "part failed", "thing skipped"]

    static let roundReason = "Refused: these taps, the same spots in the same order, already came back to where they began "
        + "twice. One of them does not do what you think (a − or ✕ that opens the item instead). Do not go round again: "
        + "look closely for the right control (read its label), try another way, or leave it and say in the answer what "
        + "could not be done."

    /// 128 over the cloud 11-13 (second round, g1): with the note written, the executor and then Codex scrolled it up and
    /// down to "check" it, 15 swipes in pairs (about 4 minutes); a list or a menu gets the same. A page scrolled one way,
    /// back, and the first way again has been seen whole: the next turn back is refused.
    static func scrollsBackAgain(_ steps: [JObject], next: JObject) -> Bool {
        guard let d = swipeDirection(next) else { return false }
        var dirs = [d]
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            if a == "swipe" {
                guard let e = swipeDirection(s) else { break }
                dirs.insert(e, at: 0)
            } else if observedActions.contains(a) || partEnds.contains(a) { break }
            if dirs.count >= 16 { break }
        }
        let turns = zip(dirs, dirs.dropFirst()).filter { $0 != $1 }.count
        return turns >= scrollTurnsLimit
    }

    /// Up (-1) or down (+1) for a swipe that is mostly vertical and long enough to scroll (0-1000 coordinates).
    static func swipeDirection(_ s: JObject) -> Int? {
        guard s["action"]?.str == "swipe", let x1 = s["x1"]?.double, let y1 = s["y1"]?.double,
              let x2 = s["x2"]?.double, let y2 = s["y2"]?.double else { return nil }
        let (dx, dy) = (x2 - x1, y2 - y1)
        guard abs(dy) >= 150, abs(dy) > 2 * abs(dx) else { return nil }
        return dy > 0 ? 1 : -1
    }

    /// D22, 134 真人单句 11-15 (h08): 行事曆's month view scrolls up and down; it was swiped left 40 times ("still November
    /// 2026") and the run ran out of steps. Three swipes the same way in a row that changed nothing: a fourth is refused.
    static func swipesGoNowhere(_ steps: [JObject], next: JObject) -> Bool {
        guard let way = swipeWay(next) else { return false }
        var dead = 0
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            if a == "swipe" {
                guard swipeWay(s) == way, s["changed"] == .bool(false) else { return false }
                dead += 1
                if dead >= 3 { return true }
            } else if observedActions.contains(a) {
                return false
            }
        }
        return false
    }

    /// The way a swipe goes along its longer axis (150+ of 1000): "up", "down", "left" or "right"; nil for a short one.
    static func swipeWay(_ s: JObject) -> String? {
        guard s["action"]?.str == "swipe", let x1 = s["x1"]?.double, let y1 = s["y1"]?.double,
              let x2 = s["x2"]?.double, let y2 = s["y2"]?.double else { return nil }
        let (dx, dy) = (x2 - x1, y2 - y1)
        guard max(abs(dx), abs(dy)) >= 150 else { return nil }
        return abs(dx) > abs(dy) ? (dx < 0 ? "left" : "right") : (dy < 0 ? "up" : "down")
    }

    static let deadSwipeReason = "Refused: three swipes this way in a row changed nothing on the screen: this view does not "
        + "move that way. Try the other direction or axis (a calendar's months scroll up and down), a control on the screen "
        + "(an arrow, a tab, a date, 今天), or another way to the goal."

    /// D48, y3 on 136 (item 24): on 關於本機 Doubao said "shows 機型名稱 iPhone 13 mini", scrolled, said "shows 容量 256GB, the
    /// model name is above", and scrolled back, three times, never writing either down; the turn back was refused and the
    /// thing skipped. Its thoughts are not shown to it again: the refusal quotes what it said it saw, to be noted now.
    static func scrollBackRefusal(_ steps: [JObject]) -> String {
        var said: [String] = []
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            if a == "swipe" {
                if let t = s["thought"]?.str, !t.isEmpty { said.insert(String(t.prefix(160)), at: 0) }
            } else if observedActions.contains(a) { break }
            if said.count >= 4 { break }
        }
        guard !said.isEmpty else { return scrollBackReason }
        return scrollBackReason + " What you said you saw while scrolling it: " + said.map { "“\($0)”" }.joined(separator: " ")
            + " Write down now, with note, each value the goal asks for that you saw there (your thoughts are not kept); "
            + "then go on."
    }

    /// D53, y4 on 136 (item 27): on 關於本機 seven swipes in a row with nothing noted, and the thing was skipped as swiping;
    /// y3 the same page, three turns. What the model said while scrolling is shown to it again after two swipes with no
    /// note, so a value it saw on an earlier screen is written down instead of scrolled back to.
    static func scrollingHint(_ steps: [JObject]) -> String? {
        var said: [String] = [], swipes = 0
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            // y2 on 137 (item 24): 天氣's chart was held six times ("tomorrow 3 p.m. is 26°") with nothing noted, and the
            // thing was skipped: a hold that reads a value counts as looking, like a swipe.
            if a == "swipe" || a == "hold" {
                swipes += 1
                if let t = s["thought"]?.str, !t.isEmpty, said.count < 4 { said.insert(String(t.prefix(160)), at: 0) }
            } else if a == "note" || observedActions.contains(a) { break }
            if swipes >= 12 { break }
        }
        // D192, x4 on 151 (item 6): "前4个商品价格分别为12.86、26.7、43.8、32.68元，需要向下滑动查看第5个" and, one swipe on,
        // the cheapest of the first five was taken from the screen alone (16.8, the sixth); 12.86, the first, had scrolled
        // off. One swipe is enough when what was said holds two values or more.
        guard swipes >= 2 || said.contains(where: { Self.valuesIn($0) >= 2 }), !said.isEmpty else { return nil }
        return "What you said while scrolling or holding on this page: " + said.map { "“\($0)”" }.joined(separator: " ")
            + " If any of it is a value the goal asks for, write it down now with note TEXT together with your next action "
            + "(your thoughts are not kept; a value seen on an earlier screen is not scrolled back to)."
    }

    /// D192: prices, temperatures and counts in a text ("12.86、26.7元", "¥16.8", "18°", "3个").
    static func valuesIn(_ text: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: #"[¥￥]\s*\d+(?:\.\d+)?|\d+\.\d+|\d+\s*(?:元|°|℃|万|%|个|件|人)"#) else { return 0 }
        return re.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// D83, y4 on 138 (item 27), the fourth time on 關於本機 (D19, D48, D53): Doubao said "shows 機型名稱 iPhone 13 mini"
    /// twice while scrolling, noted only "第27项：总容量为256GB", was refused the turn back twice with its words quoted and
    /// still wrote nothing; a stuck plan took 27 for done and the owner got "型号名称未能可靠记录". When the turn back is
    /// refused, the run notes what was said while scrolling, word for word, under the part's item.
    static func seenWhileScrollingNote(_ steps: [JObject], part: String?) -> String? {
        var seen: [String] = []
        for s in steps.reversed() {
            let a = s["action"]?.str ?? ""
            if a == "swipe" || a == "hold" {
                let t = (s["thought"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { seen.append(String(t.prefix(160))) }
            } else if observedActions.contains(a) { break }
            if seen.count >= 4 { break }
        }
        var said: [String] = []
        for t in seen.reversed() where !said.contains(t) { said.append(t) }
        guard !said.isEmpty else { return nil }
        let item = part.flatMap(partItems).flatMap { $0.count == 1 ? $0[0] : nil }
        // D138, x3 on 144: the executor was in 天气 for item 9 while the plan's part was still item 1 (美团): what it saw
        // was noted as "第1项（滚动页面时看到）…", then again as 第2项 and 第3项. A part naming another app gets no label.
        let label = item.flatMap { n -> String? in
            guard let part, let front = appInFront(steps, startedIn: nil) else { return "第\(n)项" }
            let (p, f) = (AppNames.hans(part).lowercased(), AppNames.hans(front).lowercased())
            let named = goalApps.filter { app in ([app.name] + app.also).contains { !$0.isEmpty && p.contains($0) } }
            guard !named.isEmpty, !f.isEmpty else { return "第\(n)项" }
            let inFront = named.contains { app in
                ([app.name] + app.also + AppNames.variants(app.name).map { AppNames.hans($0).lowercased() })
                    .contains { !$0.isEmpty && (f.contains($0) || $0.contains(f)) }
            }
            return inFront ? "第\(n)项" : nil
        }
        return (label ?? "") + seenWhileScrollingMark + said.joined(separator: " ")
    }

    static let seenWhileScrollingMark = "（滚动页面时看到，原话）："

    static let scrollTurnsLimit = 3
    static let scrollBackReason = "Refused: this page was already scrolled one way, back, and that way again: all of it has "
        + "been seen. Do not scroll it again. Go on with what the goal needs next, or answer from what you saw."

    /// D153, s4 over the cloud 11-19 (147): taps at the middle of WeChat's new-chat picker had done nothing there; later
    /// the middle of a profile photo opened full screen, the tap that closes it, was refused as that dead spot, and the
    /// run spent its last 60 steps in the photo viewer. A spot is dead on the screen it did nothing on, not on another.
    static func deadTwiceHere(_ dead: [(tap: JObject, scene: [UInt8]?)], _ act: JObject, scene: [UInt8]?) -> Bool {
        dead.filter { d in
            guard sameSpot(d.tap, act) else { return false }
            guard let was = d.scene, let now = scene else { return true }
            return RouteBook.sceneDistance(was, now) <= 1
        }.count >= 2
    }

    static func sameSpot(_ a: JObject, _ b: JObject) -> Bool {
        guard a["action"] == b["action"] else { return false }
        let (pa, pb) = (pointerPath(a), pointerPath(b))
        guard pa.count == pb.count else { return false }
        if pa.isEmpty { return Actions.sameTarget(a, b) }
        return zip(pa, pb).allSatisfy { abs($0.x - $1.x) <= 0.03 && abs($0.y - $1.y) <= 0.03 }
    }

    /// A 3-point path with one wide, roughly even bend (a smile, an arc) is drawn as a smooth curve: models keep
    /// sending three points for a curve, and the straight joins came out as a V. Sharp or lopsided bends stay.
    static func isGentleBend(_ pts: [CGPoint], aspect: Double) -> Bool {
        guard pts.count == 3, aspect.isFinite, aspect > 0 else { return false }
        let sy = 1 / aspect  // a y unit is this many x units tall
        let (ax, ay) = (Double(pts[0].x - pts[1].x), Double(pts[0].y - pts[1].y) * sy)
        let (bx, by) = (Double(pts[2].x - pts[1].x), Double(pts[2].y - pts[1].y) * sy)
        let (la, lb) = (hypot(ax, ay), hypot(bx, by))
        guard la > 0, lb > 0, max(la, lb) / min(la, lb) <= 2 else { return false }
        return (ax * bx + ay * by) / (la * lb) <= 0  // the bend is 90° or wider
    }

    func run() async {
        var failures = 0
        (pasteHopOff, lastTap, typedInto, inkSeen, deadTaps, returnSent) = (false, nil, nil, nil, [], false)
        actorClosed = false
        verifyAsked = 0
        (noKeyboard, aimNext, sentTexts, unsent, boxCleared, typedBase) = (0, false, [], nil, false, [:])
        sendCorrections = 0
        quietSinceSend = 0
        pendingInput = inputToInspect
        pendingRefused = 0
        untypedSearches = 0
        if let inputToInspect { unsent = inputToInspect }
        homeRecoveryTried = false
        // What this run was taught, in the exported trace: the system prompts themselves are not recorded.
        let applied = lessons?.relevant(to: task) ?? []
        lessonRun = UUID().uuidString
        if !applied.isEmpty || !Prompts.userRules.isEmpty {
            trace?.write(kind: "lessons", ["lessons": .arr(applied.map { .str($0.text) }), "rules_md": .bool(!Prompts.userRules.isEmpty)])
            DebugLog.write("lessons: \(applied.count) applied, rules.md \(Prompts.userRules.isEmpty ? "absent" : "used")")
        }
        replayedRoute = nil
        (parts, partIndex, doneParts, takeover, stepsInPart, rescued, troubles) = ([], 0, [], 0, 0, false, 0)
        (stallsNoProgress, messageSent, sendIsMessage, refusalsNoProgress) = (0, [], false, 0)
        itemFailsLeft = Self.itemFailsAllowed(task)
        (skipOwed, earlierRunRefused) = (false, -1)
        (cartAdds, cartToastShown, cartAddsIn, skipAsked) = (0, false, [:], false)
        (failRefusedAt, freeFailRefusals, cartTapsChecked, appErrorLooks, pressRuns, stepsSinceProgress) = (-1, 0, 0, 0, [:], 0)
        (notes, departures, circleRefused, blindLooks, deadRefused, offlineWaits, sendBlocks) = ([], [], 0, 0, 0, 0, 0)
        (installAsked, lookedAgain, installSteps) = ([], [], 0)
        (publishAllowed, publishDeclined) = ([], [])
        (coached, tryingTip) = ([], nil)
        (notesAtPart, emptyPartRefused, pasteFrame, sameAppRefused, pictureIn, listenedAll) = (0, -1, nil, 0, nil, false)
        sentPlaces = [:]
        rangeRefused = (-1, 0)
        approvedTexts = []
        checksLeft = 2
        rejectedAnswer = nil
        // 128 over the cloud 11-13 (g1): a goal of twenty things followed "the way it was done before", which was the
        // end of the last such run (scrolling a note, deleting a line, closing menus): 44 steps before Codex replanned.
        // A goal of several numbered things is planned afresh; a remembered way is for one thing done again.
        // Who leads stays as it was: a goal done before is not "not done before" because its way is not followed (the
        // second round of 128, g8: Codex led all twenty things, 70 of 95 calls, about 4.5 s each against 2.5).
        let remembered = presetPlan.isEmpty && learnedRoutes ? routes?.recipe(for: task) : nil
        recipe = Self.goalParts(task) < 3 ? remembered : nil
        plannerLeads = plannerLeadsUnknown && presetPlan.isEmpty && learnedRoutes && remembered == nil && planner != nil
        if plannerLeads { DebugLog.write("run: not done before; the planner does it and it is remembered") }
        (sendTap, backMissed, actFrame) = (nil, false, nil)
        do {
            do { try await replay() }
            catch let e where e is CancellationError || Task.isCancelled { throw e }
            catch { DebugLog.write("route: replay stopped by \(error.localizedDescription); the model takes over") }
            if presetPlan.isEmpty, !directStart, let recipe {
                plan = Self.rememberedPlan(recipe)
                record(nil, ["action": .str("plan"), "plan": .str(plan), "plan_zh": .str(""), "think_s": .num(0),
                             "source": .str("remembered")])
                DebugLog.write("plan: remembered from a run that finished (\(recipe.lines.count) steps); the planner is not asked")
            } else if !presetPlan.isEmpty || directStart {
                plan = presetPlan.isEmpty ? """
                Work from the CURRENT screen and the original Goal; keep completed work.
                Choose the next action from what is visible, then inspect its result before continuing.
                If the route is unclear or progress stops, request replan rather than guessing or repeating moves.
                Finish only after checking the visible result against the Goal, using its required answer format.
                """ + (recipe.map { "\n\n" + Self.rememberedPlan($0) } ?? "") : presetPlan
                record(nil, ["action": .str("plan"), "plan": .str(plan), "plan_zh": .str(""), "think_s": .num(0),
                             "source": .str(presetPlan.isEmpty ? "direct start" : "fixed plan")])
            } else {
                try await replan()
            }
            let budget = Self.stepBudget(plan: plan, base: stepLimit ?? maxSteps, goal: presetPlan.isEmpty ? task : "")
            if budget > (stepLimit ?? maxSteps) { DebugLog.write("run: \(budget) steps for a plan of several parts") }
            var stepsRun = 0
            while stepsRun < budget + installSteps {  // D194: an allowed install adds steps for its download
                stepsRun += 1
                do {
                    let recordsBefore = steps.count
                    if try await step() {
                        if try await rescue() { continue }
                        guard steps.last?["action"]?.str == "fail", try await askForHelp() else { return finish() }
                        continue
                    }
                    failures = 0
                    blindLooks = 0
                    offlineWaits = 0
                    // D19: in a goal of 10 things or more, 12 refusals with nothing got on skip the thing (25 took about
                    // two minutes each time, six times in 134's y3–y5).
                    if refusalsNoProgress >= (presetPlan.isEmpty && Self.goalParts(task) >= 10 ? Self.bigGoalRefusalLimit : Self.refusalLimit) {
                        let why = "stuck: refused \(refusalsNoProgress) times and nothing got on"
                        if try await skipStuckThing(nil, why) { continue }
                        record(nil, ["action": .str("fail"), "reason": .str(why)])
                        return finish()
                    }
                    if let between = betweenSteps { await between() }  // a stop meanwhile ends the next step as usual
                    // 134 over the cloud 11-15 (y2): of 63 minutes, 38 made 50 results (46 s each) and 25 went on things
                    // skipped in the end, one of them 9 minutes: a part may take up to 80 steps before it counts as
                    // stalled, then three new plans. In a goal of 10 things or more, 30 steps with nothing found, sent
                    // or finished skip the thing (~4 minutes).
                    stepsSinceProgress += 1
                    if steps.dropFirst(recordsBefore).contains(where: { Self.typedNewText($0, earlier: steps.prefix(recordsBefore)) }) {
                        stepsSinceProgress = 0
                    }
                    if presetPlan.isEmpty, Self.goalParts(task) >= 10, stepsSinceProgress >= Self.bigGoalPatience,
                       try await skipStuckThing(nil, "no result in \(stepsSinceProgress) steps") {
                        continue
                    }
                    // build104 live 11-08: a one-part task (a smiley) spent all 50 steps with 9 strokes that left no ink and
                    // Codex never came, because only plans of several parts had this budget. Every task the planner or the
                    // user gave gets it (fixed flows such as watching WeChat keep their own); steps Codex drives don't count.
                    if presetPlan.isEmpty, planner != nil, takeover == 0, !plannerLeads {
                        stepsInPart += 1
                        troubles += steps.dropFirst(recordsBefore).filter(Self.isTrouble).count
                        let gestures = steps.suffix(Self.swipesInARow + 2).filter { $0["action"]?.str != "stale plan" }
                        let swiping = gestures.count >= Self.swipesInARow
                            && gestures.suffix(Self.swipesInARow).allSatisfy { $0["action"]?.str == "swipe" }
                        let partLimit = Self.partSteps(for: parts.count >= 2 && partIndex < parts.count ? parts[partIndex] : task)
                        if stepsInPart >= partLimit || troubles >= Self.troubleLimit || swiping {
                            record(nil, ["action": .str("part stalled"),
                                         "reason": .str((parts.count >= 2 ? "part \(partIndex + 1)" : "the task")
                                                        + " not getting on: \(stepsInPart) steps, \(troubles) failed, swiping \(swiping)")])
                            troubles = 0
                            stallsNoProgress += 1
                            // A goal of 10 things or more skips the thing at its first stall (134 y2, above); D62: one of
                            // swipes gets a new plan first.
                            if stallsNoProgress >= Self.stallsToSkip(bigGoal: Self.goalParts(task) >= 10, swiping: swiping) {
                                let why = "stuck: \(stallsNoProgress) new plans in a row and nothing got on"
                                if try await skipStuckThing(nil, why) { continue }
                                record(nil, ["action": .str("fail"), "reason": .str(why)])
                                return finish()
                            }
                            try await replan(stuck: true)
                        }
                    }
                    if let n = endAfterSend, !sentTexts.isEmpty, unsent == nil {
                        quietSinceSend += 1
                        if quietSinceSend > n {
                            record(nil, ["action": .str("fail"),
                                         "reason": .str("could not verify the sent message; not sending again to avoid duplicates")])
                            return finish()
                        }
                    }
                } catch let e as BlindError {
                    // Over USB 11-09: a run stopped to ask the user to share the screen, while it was being shared.
                    if e.sharingOn, blindLooks < Self.blindLookLimit {
                        blindLooks += 1
                        DebugLog.write("run: no new frame yet with sharing on (\(blindLooks)); looking again")
                        // The pointer answers this right after a click near the clock. Whatever else brought the question
                        // up (Pointer.cancelSharing), it stays until answered, and frames also stop by themselves for up to 10 s.
                        if blindLooks == Self.blindLooksBeforeCancel, (try? await phone?.answerSharingQuestion()) == true {
                            record(nil, ["action": .str("sharing question"),
                                         "reason": .str("frames came back after tapping Cancel on whether to stop sharing the screen")])
                        }
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    record(nil, ["action": .str("paused"), "reason": .str(e.reason)])
                    guard try await askForHelp() else { return finish() }
                    continue
                } catch let e where e is CancellationError || Task.isCancelled {
                    throw e
                } catch {  // a bad reply or a dropped link: recover, don't crash
                    record(nil, ["action": .str("hiccup"), "reason": .str(String(error.localizedDescription.prefix(300)))])
                    let linkLost = Self.isLinkLoss(error, screenLive: screen?.live)  // the next look waits for it (waitForScreen)
                    let offline = ModelRequestFailure.isNetworkDown(error)
                    failures += linkLost || offline ? 0 : 1  // a lost link is not the agent's fault
                    if offline {
                        offlineWaits += 1
                        if offlineWaits > Self.offlineWaitLimit {
                            let why = ModelRequestFailure.localProxy().map(ModelRequestFailure.proxyDown)  // D92
                                ?? "the phone has had no network for \(Self.offlineWaitLimit * 5) s"
                            record(nil, ["action": .str("fail"), "reason": .str(why)])
                            guard try await askForHelp() else { return finish() }
                            offlineWaits = 0
                            continue
                        }
                        let proxy = ModelRequestFailure.localProxy().map { ", through the proxy on the phone at \($0)" } ?? ""
                        DebugLog.write("run: no network (\(error.localizedDescription)\(proxy)); waiting 5 s, then the same step again (\(offlineWaits))")
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    }
                    if failures >= maxFailures {
                        // D20, 134 over the cloud 11-15 (y5, y6): Search stopped listing Safari; three tries to open it were
                        // three errors in a row and two runs of 50 things failed (y6 at 102 s, one thing done). In a goal
                        // of several things the thing is left 未能完成 and the run goes on (a few times at most).
                        let what = error.localizedDescription.components(separatedBy: " did not open this time").first ?? ""
                        let why = error.localizedDescription.contains(" did not open this time")
                            ? what + (error.localizedDescription.contains("Home Screen did not come up") ? " 这次打不开（回不到主屏幕）"
                                                                                                      : " 这次打不开（系统搜索里找不到它）")
                            : "连续出错：" + String(error.localizedDescription.prefix(80))
                        if (try? await skipStuckThing(nil, why)) == true {
                            failures = 0
                            continue
                        }
                        record(nil, ["action": .str("fail"), "reason": .str("\(failures) errors in a row")])
                        guard try await askForHelp() else { return finish() }
                        failures = 0
                        continue
                    }
                    await screen?.settled()
                    if error is BoardTimeout || error is DeviceError {
                        // An unacknowledged action may have completed. Observe its result before replanning;
                        // reset tracking, but never replay the original relative move/click/text.
                        do {
                            if phone?.device.connected == true { try await phone?.device.abort() }
                            try await screen?.requireFrame(after: nil)
                            try await phone?.reset()
                        } catch let e where Self.isLinkLoss(e, screenLive: screen?.live) {
                            // D34, y6 on 135: the board's BLE dropped for 3 s mid-swipe; this look threw "开发板已断开"
                            // past the run's own wait, and a run of 50 things ended at 47 minutes. The next look waits.
                            DebugLog.write("run: the board or mirror dropped (\(e.localizedDescription)); the next look waits for it")
                            continue
                        }
                    }
                    do { try await replan(stuck: true) }
                    catch let e where ModelRequestFailure.isNetworkDown(e) {
                        DebugLog.write("run: no network for the new plan (\(e.localizedDescription)); the next step tries again")
                    }
                }
            }
            record(nil, ["action": .str("fail"), "reason": .str("step limit reached")])
        } catch let e where e is CancellationError || Task.isCancelled {
            record(nil, ["action": .str("stopped")])
        } catch let e as BlindError {
            record(nil, ["action": .str("fail"), "reason": .str(e.reason)])
        } catch {  // e.g. the planner itself is unreachable
            record(nil, ["action": .str("error"), "reason": .str(ModelRequestFailure.message(error))])
        }
        finish()
    }

    /// Pauses for the user (at most twice a run). True = go on from the current screen with a new plan.
    private func askForHelp() async throws -> Bool {
        guard let onHelp, helpAsked < 2, stepLimit == nil, !noHelp else { return false }
        helpAsked += 1
        let reason = steps.last?["reason"]?.str ?? ""
        record(nil, ["action": .str("help"), "reason": .str(reason)])
        let choice = await onHelp(reason)
        try Task.checkCancellation()
        switch choice {
        case .stop:
            record(nil, ["action": .str("stopped")])
            return false
        case .resume:
            record(nil, ["action": .str("takeover"), "reason": .str("the user did this part by hand: \(reason)")])
        case .skip:
            record(nil, ["action": .str("skipped"), "reason": .str("the user asked to skip this step: \(reason)")])
        }
        // build104 live 11-08: after the user's answer the next refused done stopped the run again at once (the count
        // of refusals went on from 3). The user's answer starts the count again.
        doneRejected = 0
        await screen?.settled()
        try await replan(stuck: true)
        return true
    }

    /// The actor's system prompt: the original, plus this task's hints, the user's lessons and rules.md.
    var actorPrompt: String { Prompts.actor + "\n" + AssistiveTouchSpots.rule + AppNames.languageNote + taught }

    /// The planner gets the same: a plan that ignores them makes the actor ignore them too.
    var plannerPrompt: String { Prompts.plannerApp + "\n" + AssistiveTouchSpots.rule + AppNames.languageNote + taught }

    private var taught: String {
        (hints.isEmpty ? "" : "\n\nHints for this task:\n" + hints.map { "- " + $0 }.joined(separator: "\n"))
            + (lessons?.context(task: task) ?? "") + Prompts.userRules
            + (reference.isEmpty ? "" : "\n\nKnowledge base chosen by the user. Base every reply on it; when it does not "
               + "cover the question, use the user's fallback reply instead of guessing. Never send anything from "
               + "outside it about the user, and never copy one chat's content into another chat:\n" + reference)
    }

    private func finish() {
        if let metrics { trace?.writeMetrics(metrics.snapshot()) }
        if let routes, learnedRoutes, steps.last?["action"]?.str == "done" {
            let run = (task: self.task, steps: self.steps, shots: self.shots, aspect: screen?.aspect ?? 0, used: replayedRoute,
                       recipe: presetPlan.isEmpty)
            Task { await routes.learn(task: run.task, steps: run.steps, shots: run.shots, aspect: run.aspect, replayed: run.used,
                                      recipe: run.recipe) }
        }
        // A run that sent by tapping and ended done: that spot is this screen's send button, by its look.
        // 130 over the cloud 11-13 (g2): WeChat's + by the input box had been learned so, and sends went there. Only a spot
        // with 发送 / Send written on it is learned.
        if let controls, steps.last?["action"]?.str == "done", !sentTexts.isEmpty, let tap = sendTap {
            Task { @MainActor in
                let y = Double(tap.point.y)
                let rows = await CandidatePicker.rowsOffMain(in: tap.frame, top: max(0, y - 0.06), bottom: min(1, y + 0.06))
                if Self.labelsSend(rows, at: tap.point) {
                    controls.learn("send", at: tap.point, on: tap.frame)
                } else {
                    DebugLog.write(String(format: "send: (%.3f, %.3f) not learned: no 发送 written there", tap.point.x, tap.point.y))
                }
            }
        }
        sendTap = nil
    }

    /// Walk a learned route (RouteBook) without the model while each screen is the one it was learned on, tapping
    /// each step's label where it is now. The first screen that differs, a missing label or a step that changes
    /// nothing hands the run to the model from there; the replayed steps are in its recent actions.
    func replay() async throws {
        guard let routes, learnedRoutes, phone != nil, let first = screen?.frame, let scene = Vision.experienceScene(first),
              let entry = routes.entry(task: task, scene: scene, aspect: screen?.aspect ?? 0) else { return }
        let route = entry.route, from = entry.from
        replayedRoute = route.id
        if from > 0 { DebugLog.write("route: joined at step \(from + 1) of \(route.steps.count), the screen this run starts on") }
        var walked = 0, stop = ""
        walk: for step in route.steps[from...] {
            try Task.checkCancellation()
            try await gate?()
            guard let shown = screen?.frame, let here = Vision.experienceScene(shown),
                  RouteBook.sceneDistance(here, step.scene) <= 1 else { stop = "the screen differs"; break }
            var act: JObject = ["action": .str(step.action), "source": .str("route")]
            switch step.action {
            case "tap":
                var x = Double(step.values[0]), y = Double(step.values[1])
                if let anchor = step.anchor {
                    let was = CGPoint(x: (x - Double(step.offsetX ?? 0)) / 1000, y: (y - Double(step.offsetY ?? 0)) / 1000)
                    guard let spot = RouteBook.find(anchor, near: was, in: shown) else { stop = "“\(anchor)” is not on screen"; break walk }
                    x = min(1000, max(0, spot.x * 1000 + Double(step.offsetX ?? 0)))
                    y = min(1000, max(0, spot.y * 1000 + Double(step.offsetY ?? 0)))
                }
                act["x"] = .num(x.rounded())
                act["y"] = .num(y.rounded())
                // D122, q143n on 144 (n08): a remembered way opened 高德 by its icon; no thought named it, and "this run
                // never went into 高德" refused a right answer three times. The label tapped goes with the step.
                if let anchor = step.anchor { act["text"] = .str(anchor) }
            case "swipe":
                for (k, v) in zip(["x1", "y1", "x2", "y2"], step.values) { act[k] = .num(Double(v)) }
            default: break
            }
            onDoing?(.acting(act))
            let started = now()
            try await perform(act)
            lastActed = now()
            act["act_s"] = .num(((lastActed - started) * 100).rounded() / 100)
            record(shown, act)
            _ = try await settle()
            let changed = Vision.changed(shown, screen?.frame, ignore: pointerPath(act))
            steps[steps.count - 1]["changed"] = .bool(changed)
            guard changed else { stop = "a step changed nothing"; break }
            walked += 1
        }
        if walked < route.steps.count - from { routes.missed(route.id) }
        DebugLog.write("route: replayed \(walked)/\(route.steps.count - from) learned steps without the model"
                       + (stop.isEmpty ? "" : "; stopped: \(stop)"))
    }

    /// One see-think-act round (one or more actions). Returns true when the task is over.
    func step() async throws -> Bool {
        var timing = Metrics.Step()
        let replied = try await nextActions()
        timing.llmMs = (replied[0].act["think_s"]?.double ?? 0) * 1000
        for var planned in replied where planned.act["action"]?.str == "note" {  // nothing on the phone moves: kept, and shown from here on
            if let said = planned.act["text"]?.str, !said.isEmpty {
                // D87: a date fact in a note is put right as in the answer, so what is typed from the notes (a 备忘录 of
                // the results) holds it right too.
                let text = Self.rightFacts(said, today: Date())
                if text != said {
                    planned.act["text"] = .str(text)
                    DebugLog.write("note: a weekday, a count of days or a span was wrong; put right")
                }
                if !notes.contains(text), let why = cutNoteMissing(said) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(why)])
                    DebugLog.write("note: refused once; it holds text cut short on the screen")
                    continue
                }
                if !notes.contains(text), let why = unshownNoteMissing(said) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(why)])
                    DebugLog.write("note: refused once; it says not shown what was said just before")
                    continue
                }
                if !notes.contains(text), let why = bracketNoteMissing(said) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(why)])
                    DebugLog.write("note: refused; a sum in brackets the goal gives does not come out as noted")
                    continue
                }
                // D94: what was said holds the Calculator's number, even when a span in it was put right.
                if !notes.contains(text), let shown = calcResultMissing(said) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.calcNoteReason(shown))])
                    DebugLog.write("note: refused; Calculator shows \(shown) and the note has no such number")
                    continue
                }
            }
            if let text = planned.act["text"]?.str, !text.isEmpty, !notes.contains(text) {
                let before = notes.reduce(into: Set<Int>()) { $0.formUnion(Self.noteItems($1)) }
                notes.append(text)
                (stallsNoProgress, refusalsNoProgress) = (0, 0)
                // D51, y5 on 136: the plan's part 1 was item 23; items 23, 24 and 25 were noted in 20 steps without a
                // "part done", the part counted as stalled and a thing was skipped (four times in y5; 29, 32 and 37 were
                // noted and still reported 未能完成). A note of a thing not noted before is the part getting on.
                if Self.newThingNoted(text, before: before) {
                    (stepsInPart, troubles) = (0, 0)
                    if skipOwed { (itemFailsLeft, skipOwed) = (itemFailsLeft + 1, false) }  // D141b
                }
                gotOn()
            }
            record(planned.shot, planned.act)
        }
        let acts = replied.filter { $0.act["action"]?.str != "note" }
        guard !acts.isEmpty else { return false }
        let seen = acts[0].shot
        var spots = [pointerAt]  // where the pointer was and goes: pointer moves are not screen changes
        let stuck = repeating(acts[0].act)
        let drawing = Set(["circle", "path"])
        let startsDrawing = drawing.contains(acts[0].act["action"]?.str ?? "")
            && !drawing.contains(steps.last?["action"]?.str ?? "")
        defer { metrics?.step(timing) }
        for (i, planned) in acts.enumerated() {
            var act = planned.act
            if act["action"]?.str == "swipe" {
                act = Self.safeSwipe(act, after: steps, browser: Self.inBrowser(steps, startedIn: startApp, thought: act["thought"]?.str ?? ""))
            }
            // Over USB 11-10 one reply opened WeChat twice, 18 s each.
            if i > 0, act["action"]?.str == "open", acts[i - 1].act["action"]?.str == "open", acts[i - 1].act["app"] == act["app"] { continue }
            // 123 on the phone 11-12 (W2 again): a Weather screenshot opened full screen from 测试群 was taken for the
            // Weather app, and WeChat was "opened" twice through Search (13 s, 19 s), then the run went round in circles.
            // A run that has not left the app it is in has nothing to open: refused once, saying what it looks at.
            if act["action"]?.str == "listen", listenedAll {
                record(planned.shot, ["action": .str("refused"), "reason": .str("Refused: the video has started over and "
                    + "all it says is in the notes. Answer now with done.")])
                return false
            }
            if let pic = pictureIn {
                pictureIn = nil
                let what = act["action"]?.str ?? ""
                let reopens = what == "open"
                    && AppNames.variants(pic).map(AppNames.hans).contains(AppNames.hans(act["app"]?.str ?? ""))
                if what == "home" || reopens {
                    // 125 in 测试群 11-12: a tap in the middle came after the model had closed the picture itself, landed
                    // on another screenshot in the chat and opened it. A drag down closes a picture and only scrolls a chat.
                    DebugLog.write("picture: \(what) right after the still-in-\(pic) refusal; dragging the picture down instead")
                    act = ["action": .str("swipe"), "x1": .num(500), "y1": .num(350), "x2": .num(500), "y2": .num(800),
                           "picture_close": .bool(true),
                           "thought": .str("A picture shown full screen in \(pic): dragging it down closes it.")]
                }
            }
            // 126 in 测试群 11-12: "看完图片后把它往下拖一下关闭" came with a swipe from y 800 to y 300, up: the picture
            // stayed open and the reply took 35 s more. A drag the thought calls down, to close a picture, goes down.
            if act["action"]?.str == "swipe", let y1 = act["y1"]?.double, let y2 = act["y2"]?.double, y2 < y1,
               Self.saysDragDown(act["thought"]?.str ?? "") {
                DebugLog.write("swipe: the thought drags down to close a picture and the swipe went up; turned down")
                act["y1"] = .num(min(y2, 350))
                act["y2"] = .num(max(y1, 800))
            }
            // 126 over the cloud 11-12 (g6): "已加购5次" in the model's own words, and 加入购物车 tapped again each time the
            // spec sheet came up. Once the "added" toast has come as often as the goal asks for, adding is refused.
            // 131 over the cloud 11-13 (r131b g5): counted over the whole goal, 淘宝 一件 and 美团外卖 一份 made 2 for both:
            // 淘宝 got a second bottle, and 美团's one add was refused. Each app is held to what the goal asks of it.
            if act["action"]?.str == "tap", case let shop = Self.appInFront(steps, startedIn: startApp),
               Self.addsDish(act["thought"]?.str ?? "", in: shop) {
                let added = shop.map { cartAddsIn[AppNames.hans($0).lowercased(), default: 0] } ?? cartAdds
                if added >= Self.cartWanted(task, in: shop) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.cartFullReason(added))])
                    return false
                }
            }
            // 133 over the cloud 11-14 (y4): "12345*678-9876/3.5=" went in right each time, but Calculator showed only the
            // end of the long expression ("345×678−9,876"); the run cleared and typed it again 42 times, 25 minutes and
            // most of its steps. The same keys (3 or more) a fourth time without anything found between are refused.
            // A Screen Time passcode is never typed (user 11-15: everything but typing a password for them).
            if act["action"]?.str == "type", Self.screenTimePasscodeShown(readRows) {
                record(planned.shot, ["action": .str("refused"), "reason": .str(Self.screenTimePasscodeNote)])
                return false
            }
            if act["action"]?.str == "press" {
                let keys = Self.typedKey(act["text"]?.str ?? "")
                if keys.count >= 3 {
                    pressRuns[keys, default: 0] += 1
                    if pressRuns[keys, default: 0] > 3 {
                        record(planned.shot, ["action": .str("refused"), "reason": .str(Self.samePressReason)])
                        return false
                    }
                }
            }
            // 126 over the cloud 11-12 (g7): "备忘录已完整写入第1至17项结果，第18项完成" and then "open 微信" for the next
            // part, with no done: the part stayed open, and the run went back and forth between 备忘录 and 微信 for 56
            // steps checking the note. A part the thought calls finished, as the run moves on to another app, is done.
            if act["action"]?.str == "open", parts.count >= 2, partIndex < parts.count,
               Self.saysPartDone(act["thought"]?.str ?? "", part: partIndex + 1, text: parts[partIndex]) {
                DebugLog.write("part \(partIndex + 1): the thought says it is finished; the next part begins")
                _ = partFinished(["answer": .str(String((act["thought"]?.str ?? "").prefix(300))), "by": .str("actor")],
                                 shot: planned.shot)
            }
            if act["action"]?.str == "open", sameAppRefused == 0, let inApp = Self.appInFront(steps, startedIn: startApp),
               AppNames.variants(inApp).map(AppNames.hans).contains(AppNames.hans(act["app"]?.str ?? "")),
               !Self.saysAppLeft(act["thought"]?.str ?? "") {
                sameAppRefused += 1
                pictureIn = inApp
                record(planned.shot, ["action": .str("refused"), "reason": .str(Self.stillInAppReason(inApp))])
                return false
            }
            let ourKeyboard = ourKeyboardOnScreen?() == true
            if ourKeyboard ? Self.onOurReturnKey(act) : (Self.onReturnKey(act) && screen?.frame.map({ CandidatePicker.keyboardUp(in: $0) }) == true) {
                // The keyboard's bottom-right key (发送 / 换行 / 前往) is Return, which the board's keyboard presses
                // without the pointer. As a tap it waited for a seen pointer, which the dark keyboard hides: every
                // send was withheld until "3 errors in a row" (logs 11-06: 76 s, 16 model calls, nothing sent).
                DebugLog.write("tap on the keyboard's Return key: pressing Return instead")
                act["action"] = .str("key")
                act["combo"] = .str("enter")
                for k in ["x", "y", "precise"] { act[k] = nil }
            }
            if act["action"]?.str == "tap", let rowTarget, let shown = screen?.frame, let row = rowTarget(shown),
               let y = act["y"]?.double, (140...880).contains(y), abs(y / 1000 - row.y) > 0.025 {
                // A tap into the chat list body while this run's chat is listed once, read on this phone: its row.
                // logs 11-06: "the 主人蓝海乐 row is visible", tapped 小柳 and then another group, back twice.
                DebugLog.write(String(format: "tap on the chat list moved to the target chat's row (y %.3f → %.3f)", y / 1000, row.y))
                act["x"] = .int(Int((row.x * 1000).rounded()))
                act["y"] = .int(Int((row.y * 1000).rounded()))
            }
            if let controls, let shown = screen?.frame {
                func use(_ hit: ControlBook.Hit, _ role: String) {
                    act["action"] = .str("tap")
                    act["x"] = .int(Int((Double(hit.point.x) * 1000).rounded()))
                    act["y"] = .int(Int((Double(hit.point.y) * 1000).rounded()))
                    act["learned"] = .str(role)
                    act["control"] = .str(hit.id)
                }
                if act["action"]?.str == "back", let hit = controls.find("back", in: shown) {
                    // Here the back swipe did nothing before and this button worked: tap it, no swipe first.
                    DebugLog.write(String(format: "back: tapping the learned back button at (%.3f, %.3f)", hit.point.x, hit.point.y))
                    use(hit, "back")
                } else if act["action"]?.str == "tap", unsent != nil, let x = act["x"]?.double, let y = act["y"]?.double,
                          !Self.onReturnKey(act), let hit = controls.find("send", in: shown),
                          hypot(x / 1000 - Double(hit.point.x), y / 1000 - Double(hit.point.y)) <= 0.12 {
                    // 130 over the cloud 11-13 (g2): the model tapped the keyboard's 發送; any tap at the bottom right
                    // was taken to the learned "send" (0.933, 0.607), which was WeChat's + by the input box. Nothing was
                    // sent, the run went on as if it had, and the next message was typed into the old one and sent as
                    // "G2买东 G2G2全部做完部做完西做完". The learned spot is used only for a tap aimed near it.
                    // The send button found by how it looked when a send went out, not the model's guess of it.
                    DebugLog.write(String(format: "send: the learned send button at (%.3f, %.3f), score %.2f", hit.point.x, hit.point.y, hit.score))
                    use(hit, "send")
                }
            }
            // Out of checks, it gave up instead of answering again: over the cloud 11-10 the check twice took a note's first
            // line, its title in Notes, for "only its body", and the run waited for help until it timed out. What it read
            // goes out marked as not checked, as a third done would.
            if act["action"]?.str == "fail", checksLeft == 0, let answer = rejectedAnswer, endAfterSend == nil, presetPlan.isEmpty,
               parts.count < 2 || partIndex >= parts.count - 1 {
                DebugLog.write("done check: it gave up after two refusals; its answer goes out as not checked")
                act["action"] = .str("done")
                act["answer"] = .str(answer)
                act["reason"] = nil
            }
            // D59, user 11-16: 淘宝 showed a slider puzzle in y1 on 137 and the thing was skipped. A security check is never
            // solved by the run: the owner is asked to do it by hand on the phone (the cloud's approval, or a panel here),
            // and the run goes on from the screen it leaves. No answer, a no, or nobody to ask: the thing is not done.
            if act["action"]?.str == "verify" {
                let named = AppNames.hans(act["app"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let app = named.isEmpty ? (Self.appInFront(steps, startedIn: startApp) ?? "这个应用") : named
                record(planned.shot, ["action": .str("needs verification"), "app": .str(app)])
                var done: Bool?
                if verifyAsked < Self.verifyLimit { done = await askVerify?(Self.verifyQuestion(app)) }
                verifyAsked += 1
                try Task.checkCancellation()
                if done == true {
                    record(nil, ["action": .str("verified by owner"), "app": .str(app)])
                    await screen?.settled()
                    gotOn()
                    (stallsNoProgress, refusalsNoProgress, troubles, stepsInPart) = (0, 0, 0, 0)
                    return false
                }
                act = ["action": .str("fail"), "reason": .str(Self.verifyFailReason(app, asked: done != nil))]
            }
            let name = act["action"]?.str ?? ""
            var justSent: String?
            if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil, !["wait", "done", "fail"].contains(name) {
                record(planned.shot, ["action": .str("send verification"), "reason": .str(Self.sendVerificationReason)])
                return false
            }
            if i > 0, ["done", "fail"].contains(name) || (name == "tap" && acts[i - 1].act["action"]?.str != "tap") {
                // Inspect drawing/typing before a later UI tap or a terminal claim about its result.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                return false
            }
            if name == "replan" || stuck {
                if stuck { act["performed"] = .bool(false) }
                record(planned.shot, act)
                try await replan(stuck: true) // preserve recovery reason and completed work in the planner context
                return false
            }
            if i == 0 {
                if name == "wait", endAfterSend == nil, Self.waitedEnough(steps) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.waitReason)])
                    return false
                }
                if endAfterSend == nil, let shot = planned.shot, let look = Vision.look(shot), circling(act, on: look) {
                    circleRefused += 1
                    if circleRefused >= 3 { return try await changeOfPlan(planned.shot, "kept leaving the same screen and coming back to it") }
                    record(planned.shot, ["action": .str("loop"), "reason": .str(Self.circleReason)])
                    return false
                }
                // traces(33): enter the chat, decide the avatar is wrong, go back, enter, go back... twice is enough.
                // The leaving move (back) is the one refused, so the run stays where it can do the task.
                if let guarded = bounceGuard, Self.sameSpot(guarded.stop, act), !bounceOpener, Self.codexLeaves(act, opener: guarded.other) {
                    (bounceGuard, bounceRefused, bounceOpener) = ((stop: guarded.other, other: act), 0, true)
                    DebugLog.write("loop: Codex, looking afresh, leaves too; the tap that opened this screen is refused from now on")
                } else if let guarded = bounceGuard, Self.sameSpot(guarded.stop, act) {
                    bounceRefused += 1
                    if bounceRefused >= 3 {
                        (bounceGuard, bounceRefused, bounceOpener) = (nil, 0, false)
                        return try await changeOfPlan(planned.shot, "kept going back and forth between two screens")
                    }
                    record(planned.shot, ["action": .str("loop"), "reason": .str(bounceOpener ? Self.openerReason : Self.loopReason)])
                    return false
                }
                if bounceGuard == nil, let first = Self.bounce(act, after: steps) {
                    if Self.leaves(act), !Self.codexLeaves(act, opener: first) {  // this move restarts the circle: refuse it now
                        bounceGuard = (stop: act, other: first)
                        bounceRefused = 1
                        record(planned.shot, ["action": .str("loop"), "reason": .str(Self.loopReason)])
                        return false
                    }
                    bounceGuard = (stop: first, other: act)  // go ahead, but not back again (D50: Codex leaving: not in again)
                    bounceOpener = Self.leaves(act)
                    DebugLog.write("loop: back and forth twice; going on, the move back is refused from now on")
                }
            }
            let unsentReason: String? = endAfterSend != nil && unsent != nil
                ? "The requested message still awaits sending. Inspect the current draft, correct any visible mistake, send once, then verify a NEW matching message before claiming done."
                : nil
            // The task's own checks (drawn, sent) are for the done that ends it: build104 live 11-08, part 1 (the alarm)
            // was done three times and refused each time as "nothing has been drawn" (that was part 2), and the run stopped.
            // 124 over the cloud 11-12 (e03): Codex drove through parts 2-4 and answered all nine things in its "done";
            // it was taken as part 2 only, part 3 (send to 验证群, already sent) began, and the run went round in circles
            // and failed with the answer lost. A done that answers the whole goal is checked as the end of the task.
            let coversGoal = name == "done" && parts.count >= 2 && partIndex < parts.count - 1
                && Self.answersWholeGoal(act["answer"]?.str ?? "", task: task)
            let endsTask = parts.count < 2 || partIndex >= parts.count - 1 || coversGoal
            var unvisited: String?  // only for a task given in words (not the watch's fixed ways)
            if name == "done", endsTask, presetPlan.isEmpty, !keyboardGuard {
                let answer = act["answer"]?.str ?? ""
                unvisited = Self.unvisitedReason(task: task, steps: steps, answer: answer, startedIn: startApp)
                if unvisited == nil, endAfterSend == nil {
                    // D145, x3 on 145 (rerun): "第6项：因缺少第5项的计算结果，无法在微信测试群发送“X3外卖合计N元”" was the part's
                    // result, and the answer did not say it again: refused twice as never sent, the model made a message
                    // up. What was noted on the way counts as said.
                    unvisited = Self.unsentGoalReason(task: task, sent: sentTexts,  // sent, not only approved
                                                      answer: ([answer] + notes + doneParts).joined(separator: "\n"))
                }
                let absent = steps.filter { $0["action"]?.str == "open failed" }.compactMap { $0["app"]?.str }
                if unvisited == nil, !skipAsked, let skipped = Self.skippedWithoutReason(answer, task: task, absent: absent) {
                    skipAsked = true  // once a run: an item it then cannot do goes out as said
                    unvisited = skipped
                }
            }
            // D16: a plan that ran out is not the end of a goal of 10+ things (see itemsLeft): the things left get a new
            // plan, once something more got done since the last one, at most continuationLimit times a run.
            if name == "done", endsTask, presetPlan.isEmpty, endAfterSend == nil, planner != nil,
               continuations < Self.continuationLimit {
                let left = Self.itemsLeft(task: task, told: notes + doneParts + [act["answer"]?.str ?? ""], sent: messageSent)
                let now = (notes: notes.count, sent: messageSent.count)
                if !left.isEmpty, continuedAt.map({ now.notes > $0.notes || now.sent > $0.sent }) ?? true {
                    continuations += 1
                    continuedAt = now
                    doneRejected = 0
                    record(planned.shot, ["action": .str("plan continues"),
                                          "reason": .str("the plan ran out with the goal's things \(Self.itemRanges(left)) not done")])
                    DebugLog.write("plan: ran out with \(left.count) of the goal's things not done; new plan \(continuations)")
                    try await replan(rest: left)
                    return false
                }
            }
            if name == "done", endsTask, let missing = unsentReason ?? (inkSeen == false ? Self.noInkReason : Self.unmadeResult(task: task, steps: steps)) ?? unvisited {
                doneRejected += 1
                if doneRejected >= 3 {  // it keeps claiming a result it did not make
                    // 130 (q130b g5): a goal of many things is not thrown away for the few made up: they are named as
                    // not done, and the rest goes out as a partial failure. Anything else stops as before.
                    if Self.goalParts(task) >= 3, let answer = act["answer"]?.str,
                       let note = Self.unverifiedNote(task: task, steps: steps, sent: sentTexts) {
                        act["answer"] = .str((answer.hasPrefix("部分失败") ? "" : "部分失败：") + answer + "（" + note + "）")
                        DebugLog.write("done: refused 3 times; it goes out with the parts not done named")
                    } else {
                        record(planned.shot, ["action": .str("fail"), "reason": .str("claimed done 3 times without doing it: " + missing)])
                        return true
                    }
                } else {
                    record(planned.shot, ["action": .str("done rejected"), "reason": .str(missing)])
                    return false
                }
            }
            // 129 over the cloud 11-13 (g4): item 2 was noted right at 56 s (G1全部做完, G2买东西做完, G2全部做完);
            // the final answer, written after the run had sent G4买东西做完 there, gave the chat as it was then, and the
            // check passed it. An item the answer now tells with this run's own messages, which its note did not, is
            // put back as it was noted when read.
            if name == "done", endsTask, let answer = act["answer"]?.str {
                // Messages only (131 r131c c2: sentTexts holds a note's typed "C2组记录" and searches' Return too).
                let kept = Self.keepReadNotes(answer, notes: notes, sent: messageSent.union(approvedTexts))
                if kept != answer {
                    DebugLog.write("done: an item retold with this run's own messages is put back as it was noted")
                    act["answer"] = .str(kept)
                }
            }
            // 131 over the cloud 11-13 (g1): both Codex accounts down (one "model not supported", one at its limit), the
            // executor planned, and the run ended with the last part's answer only ("第11项完成…"): the other nineteen
            // results were in its notes but not in the answer. An answer that covers under half of a goal's things gets
            // what this run noted added after it.
            // D44, y2 on 136: the last part's answer told item 47 of 49 only, and 7000 characters of notes went after it as
            // they were (one thing three times over, a failed part in English). Codex first writes the whole answer from
            // the notes; they are added as they are only when it cannot.
            if name == "done", endsTask, let answer = act["answer"]?.str, Self.fewThingsTold(answer, task: task),
               let whole = await wholeAnswer(answer) {
                DebugLog.write("done: the answer covers few of the goal's things; Codex wrote the whole answer from the notes")
                act["answer"] = .str(whole)
            }
            if name == "done", endsTask, let answer = act["answer"]?.str,
               let full = Self.completedAnswer(answer, notes: notes, task: task) {
                DebugLog.write("done: the answer covers few of the goal's things; what this run noted is added")
                act["answer"] = .str(full)
            }
            // 132 over the cloud 11-14 (c3): "2026年12月1日是星期日"; it is a Tuesday. A weekday the answer gives for a
            // date is checked with the calendar and put right.
            if name == "done", endsTask, let answer = act["answer"]?.str {
                let fixed = Self.rightFacts(answer, today: Date())
                if fixed != answer {
                    DebugLog.write("done: a weekday, a count of days or a span between two times was wrong; put right")
                    act["answer"] = .str(fixed)
                }
            }
            // D113, q143n on 143 (n07, n15): a note title "…来首尔不知道去哪…" and an author "Linlin的奇妙…" went out cut, as
            // read off the list: D107 looks at notes, and a short goal is answered in done. Refused once, to open it.
            if name == "done", endsTask, Self.goalParts(task) < 3, let answer = act["answer"]?.str,
               let why = cutNoteMissing(answer) {
                record(planned.shot, ["action": .str("done rejected"),
                                      "reason": .str(why.replacingOccurrences(of: "this note holds", with: "this answer holds"))])
                DebugLog.write("done: refused once; the answer holds text cut short on the screen")
                return false
            }
            // D185, n16 on 150: the answer gave the time line under the message as its time; read off the screen.
            if name == "done", endsTask, !timeLineRefused, let answer = act["answer"]?.str,
               let shown = screen?.frame ?? planned.shot,
               let why = Self.timeLineMismatch(answer, rows: await CandidatePicker.rowsOffMain(in: shown, top: 0.08, bottom: 0.92)) {
                timeLineRefused = true
                record(planned.shot, ["action": .str("done rejected"), "reason": .str(why)])
                DebugLog.write("done: refused once; the answer took the time line below the message for its time")
                return false
            }
            // D114, q143n on 143 (n12): to read 验证群's last message WeChat opened on 测试群 with a 10001 SMS banner over its
            // title; the taps meant for the back arrow hit the status bar, Doubao said it was "already inside the target
            // chat" and told 测试群's last message, and the done check passed it. A short goal that reads one group ends
            // only under that group's title: refused once, with the way there.
            if name == "done", endsTask, !groupTitleRefused, messageSent.isEmpty, let group = Self.readsOneGroup(task),
               Self.inChatApp(steps, task: task) {
                let title = (screen?.frame ?? planned.shot).flatMap { WatchReport.navigationTitle(in: $0) }
                if Self.chatCheck(seen: title, task: task, steps: steps) != .right {
                    groupTitleRefused = true
                    let seen = title.map { "the title there is “\($0)”" } ?? "no chat title can be read there; a banner may cover it"
                    record(planned.shot, ["action": .str("done rejected"), "reason": .str(
                        "Refused: “\(group)” is not shown at the top of this screen (\(seen)). Read it only under its own "
                        + "title: swipe a banner at the top up to clear it, go back to the chat list, open \(group) and read it there.")])
                    DebugLog.write("done: refused once; the group the goal reads is not the chat on the screen")
                    return false
                }
            }
            // D125, q134h on 144 (h03): the run before had read 测试群 back to Sunday; WeChat opened on it there, "the last
            // message" was told from the bottom of that screen (Y4全部做完, 星期日), and the check passed it. A goal asking
            // for a chat's latest message, in a chat opened as it was left, is refused once to go to the bottom first.
            if name == "done", endsTask, !bottomRefused, Self.asksLatestMessage(task), Self.inChatApp(steps, task: task),
               Self.mayBeScrolledUp(steps) {
                bottomRefused = true
                record(planned.shot, ["action": .str("done rejected"), "reason": .str(Self.scrolledUpReason)])
                DebugLog.write("done: refused once; the chat may be scrolled up, not at its latest message")
                return false
            }
            if name == "done", endsTask, verifiesDone, presetPlan.isEmpty, endAfterSend == nil {
                if checksLeft > 0 {
                    let answer = act["answer"]?.str ?? "", frame = screen?.frame ?? planned.shot
                    var wrong = await wrongClaim(answer, frame: frame)
                    // 128 over the cloud 11-13 (g2): item 2 read 测试群's latest three right (G1全部做完, G1买东西做完,
                    // G8全部做完); the check, seeing the chat at the end, said G2全部做完 and G2买东西做完 were missing,
                    // twice, and the answer was "corrected" to messages the run had sent itself. The checker's prompt
                    // says so (128) and was not followed: a contradiction that quotes the run's own sent text is the
                    // run's own change, not a wrong answer.
                    // 128 over the cloud 11-13 (g8): the lamp was in the cart twice from earlier days; this run added one
                    // (×3). The check said "×3, more than the 1 asked", twice, and the run spent 2 minutes trying to take
                    // two off (four rounds of taps refused). What this run added is counted; the rest was there before.
                    // 130 (g4): both came in one sentence ("item 2 …; item 4 cart ×2"): each part is weighed on its own,
                    // and only the parts that are the run's own messages or the cart's earlier count are set aside.
                    if let w = wrong {
                        // 131 over the cloud 11-13 (r131c c2): "备忘录第一行是“美元≈6.67人民币”，不是“C2组记录”" was set aside
                        // as this run's own message: sentTexts holds what was typed into the note too. Messages only.
                        let kept = Self.standingObjection(w, sent: messageSent.union(approvedTexts), adds: cartAdds,
                                                          wanted: Self.cartWanted(task), each: Self.cartEach(task))
                        if kept != w {
                            DebugLog.write(kept == nil
                                ? "done check: its objection is to this run's own messages or the cart's earlier count; the answer stands as read"
                                : "done check: the parts about this run's own messages or the cart's earlier count set aside")
                        }
                        wrong = kept
                    }
                    var stands = false  // no await inside && (the build 116 CI error was one inside ??)
                    if wrong != nil, answer == rejectedAnswer { stands = await confirmedBySecondModel(answer, frame: frame) }
                    if let wrong, !stands {
                        checksLeft -= 1
                        rejectedAnswer = act["answer"]?.str
                        let line = Self.objectionNote(wrong)
                        if !notes.contains(line) { notes.append(line) }
                        record(planned.shot, ["action": .str("done rejected"), "reason": .str(wrong)])
                        return false
                    }
                } else if let answer = act["answer"]?.str {  // told twice and it stands by it: reported, but not as checked
                    act["answer"] = .str("（未能核實）" + answer)
                }
            }
            if name == "done", !coversGoal, partFinished(act, shot: planned.shot) { return false }
            let failAgain = Self.failIsRepeat(refusedAt: failRefusedAt, lastActed: lastActed, free: freeFailRefusals)
            if name == "fail", itemFailsLeft > 0 || failAgain, presetPlan.isEmpty, Self.goalParts(task) >= 3 {
                let why = act["reason"]?.str ?? ""
                if failAgain {
                    freeFailRefusals += 1
                } else {
                    itemFailsLeft -= 1
                    skipOwed = true
                    freeFailRefusals = 0
                    let line = "未能完成：" + String(why.prefix(120))
                    if !notes.contains(line) { notes.append(line) }
                }
                // The repeat is about the part already closed: the one now open is not closed with it.
                let next = failAgain ? Self.alreadyNotedReason + nextPartText : closeFailedPart(why, by: act["by"]?.str)
                failRefusedAt = now()
                record(planned.shot, ["action": .str("fail refused"), "reason": .str(Self.oneThingFailedReason + next)])
                return false
            }
            if name != "done" && name != "fail" {
                try await gate?()
                try await screen?.requireFrame(after: nil)
                // Home and wait do not use coordinates or the current focus. Animation cannot make their target stale.
                if i == 0, !["home", "wait", "listen", "readup"].contains(name), !Self.staleProof(act),
                   act["home_recovery"] != .bool(true), seen != screen?.frame,
                   Vision.changed(seen, screen?.frame, ignore: spots, caret: true) {
                    staleRun += 1
                    // Coordinates read off a screen that moved under them are never sent. But some screens never hold
                    // still (a live clock icon, a video, an animated background): when the model, looking again at a
                    // newer screen, picks the same spot, the change did not move the target. An action with a target
                    // goes ahead at once when nothing changed where it lands (a new bubble, the keyboard rising elsewhere):
                    // each drop is another model call, 7–15 s each when the model was slow (logs 11-08: 4 drops in one
                    // report). Without a target (typing, keys) that waits for two drops as before.
                    let again = lastStale.map { Self.sameSpot($0, act) } ?? false
                    let target = pointerPath(act)
                    // A video behind the controls changes everything and every word stays: ~29 s a step (over USB 11-09).
                    var safe = again || ((staleRun > 2 || !target.isEmpty)
                        && !Vision.changedNear(seen, screen?.frame, around: target))
                    if !safe {
                        let (was, now) = (seen ?? Data(), screen?.frame ?? Data())
                        let wasRows = await CandidatePicker.rowsOffMain(in: was, top: 0.055, bottom: 1)
                        let nowRows = await CandidatePicker.rowsOffMain(in: now, top: 0.055, bottom: 1)
                        safe = Self.sameWords(wasRows, nowRows)
                        // 130 over the cloud 11-13: about 15 answers a run (3 s each) were dropped this way, most after a
                        // tap while a page went on loading or a banner turned. Where the words around the tap's target
                        // are the same, in the same places, and nothing new came there, the target did not move.
                        if !safe, name == "tap", target.count == 1, Self.sameWordsNear(wasRows, nowRows, around: target[0]) {
                            safe = true
                            DebugLog.write("stale plan: the words around the target are as they were; acting")
                        }
                    }
                    if !safe {
                        // 131 over the cloud 11-13: ~110 answers dropped in four runs and the words-around check above
                        // let none through; the log did not say what was dropped (a tap, typing, a swipe).
                        DebugLog.write("stale plan: dropping \(name), \(target.count) target point(s), \(staleRun) in a row")
                        lastStale = act
                        if staleRun >= 5 {  // it keeps moving right there: let the planner look afresh
                            staleRun = 0
                            lastStale = nil
                            record(screen?.frame, ["action": .str("stale plan"),
                                                   "reason": .str("the screen keeps changing where the action would land; planning again")])
                            try await replan(stuck: true)
                            return false
                        }
                        record(screen?.frame, ["action": .str("stale plan"), "reason": .str("screen changed while the model was responding; inspect again")])
                        if staleRun > 2 { await screen?.settled() }
                        return false
                    }
                    DebugLog.write(again ? "stale plan \(staleRun) in a row: the newer look chose the same spot; acting"
                                         : "stale plan \(staleRun) in a row: nothing changed where this action lands; acting")
                }
                staleRun = 0
                lastStale = nil
                if name == "type", let refused = outgoingGuard?(act["text"]?.str ?? "") {
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(refused)])  // never typed
                    return false
                }
                if name == "type", !notesTypedRefused,
                   Self.typedIntoNotesBefore(act["text"]?.str ?? "", steps: steps, startedIn: startApp) {
                    notesTypedRefused = true
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.notesTypedAgainReason)])
                    return false
                }
                if name == "type", let pendingInput {
                    // build105 live 11-08: a search for 无边记 (the phone says 無邊記) found nothing, and every new word
                    // was refused as "already entered", 30 times, until the steps ran out. Only the same words are
                    // refused, twice; other words replace what is in the field.
                    if Self.typedKey(act["text"]?.str ?? "") == Self.typedKey(pendingInput), pendingRefused < 2 {
                        pendingRefused += 1
                        record(planned.shot, ["action": .str("blocked"),
                            // 131 over the cloud 11-13 (r131c c3): 抖音's search for 猫 — one character OCR could not
                            // confirm — went type, refused, tap the field and type again, four rounds and 16 minutes.
                            "reason": .str("Text was already entered: \(pendingInput). Inspect the current field. "
                                + "If it shows these words, search or send now with the Return / 搜索 key (key: return); "
                                + "do not tap the field and type them again. "
                                + "Do not clear, retype, or paste over correct text; send it once if correct. "
                                + "Only use explicit correction keys if a visible mistake needs fixing.")])
                        return false
                    }
                    try await phone?.key("cmd+a")
                    try await phone?.key("backspace")
                    self.pendingInput = nil
                    pendingRefused = 0
                }
                // Lan Agent's keyboard has no letter keys to see, but it reports itself: a field it is up for is focused.
                if name == "type", keyboardGuard, noKeyboard < 2, let shown = screen?.frame, Vision.image(shown) != nil,
                   !CandidatePicker.keyboardUp(in: shown), ourKeyboardOnScreen?() != true {
                    noKeyboard += 1
                    aimNext = true
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.noKeyboardReason)])  // never typed
                    return false
                }
                // 123 over the cloud 11-12: the sorted temperatures went into 验证群 twice; this check was the watch's
                // only, and the text, approved once, was not asked about again. Every run: the same text again only into
                // another chat, read off the title (not read: refused).
                // 124 over the cloud 11-12 (g05): 雨伞 searched in 淘宝 was "sent" by its Return, and typing it into 拼多多's
                // search box was refused ~290 times. Only a message sent into a chat is never typed again.
                // 125 stress test 11-12 (u05): "125压力测试艾特" went out, then "@蓝海乐 125压力测试艾特" was typed and went
                // out too: the same message with more around it is the same message.
                // 126 over the cloud 11-12 (a03): a note's first line "126回归比价" was typed with Return in 备忘录, and
                // "126回归比价完成" for 测试群 held it: refused 25 times as sent already, and the run failed. "More around
                // it" holds for messages sent into a chat only; anything else typed with Return must be the same text.
                let typedNow = Self.typedKey(act["text"]?.str ?? "")
                let sentMatch = Self.sameMessage(typedNow, in: messageSent)
                    ?? (Self.inChatApp(steps, task: task) ? Self.sameGoalMessage(typedNow, sent: messageSent, task: task) : nil)
                    // 133 over the cloud 11-14 (y3): “iPhone 17” searched in 微信's 搜一搜 counted as sent; typed again
                    // over the box's old words it was refused 16 times. What the goal says to search is a search.
                    ?? (Self.inChatApp(steps, task: task) && sentTexts.contains(typedNow)
                        && !Self.goalSearches(task).contains(typedNow) ? typedNow : nil)
                let titleNow = screen?.frame.flatMap { WatchReport.navigationTitle(in: $0) }
                // D111, z6 on 142 (item 46): told the goal's "Z6全部做完" had not gone out in this run, Codex typed
                // "Z6全部做完12:42" (item 12's "Z6验证" takes the time; 46's does not), and it went out on an approval.
                // A goal's message with something added is refused once with the words to type.
                if name == "type", Self.inChatApp(steps, task: task), let exact = Self.paddedGoalMessage(typedNow, task: task) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(
                        "Refused: the goal says to send “\(exact)” exactly. Type “\(exact)” with nothing added or left out.")])
                    DebugLog.write("type: refused; the goal's message with something added")
                    return false
                }
                if name == "type", Self.inChatApp(steps, task: task), offPatternRefusals < 2,
                   let goalMessage = Self.offPatternGoalMessage(typedNow, task: task) {
                    offPatternRefusals += 1
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.offPatternReason(goalMessage))])
                    DebugLog.write("type: refused; a goal's message without the number it stands for")
                    return false
                }
                if name == "type", !secondNoteRefused, let head = Self.secondNoteHead(steps, typed: act["text"]?.str ?? "") {
                    secondNoteRefused = true
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.secondNoteReason(head))])
                    DebugLog.write("type: refused; a second note starting \(head)")
                    return false
                }
                if name == "type", !setAgainRefused, Self.setsNameAgain(steps, typed: typedNow, task: task),
                   !(await Self.searchBarUp(in: screen?.frame ?? planned.shot)) {  // D163: a search sets nothing
                    setAgainRefused = true
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.setAgainReason(typedNow))])
                    return false
                }
                if name == "type", aheadRefusals < 2,
                   case let ahead = Self.typedAheadOfResults(act["text"]?.str ?? "", task: task, told: notes + doneParts,
                                                             sent: messageSent), !ahead.isEmpty {
                    aheadRefusals += 1
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.aheadReason(ahead))])
                    DebugLog.write("type: refused; results typed ahead of items \(Self.itemRanges(ahead))")
                    return false
                }
                if name == "type", let sent = sentMatch,
                   keyboardGuard || Self.samePlace(sentPlaces[sent] ?? [], titleNow)
                    || Self.inChatApp(steps, task: task) && Self.notAGoalGroup(titleNow, task: task, steps: steps) {
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.sentAgainReason)])  // never typed
                    return false
                }
                if name == "type", Self.inChatApp(steps, task: task),  // D26: one of an either-or pair is out already
                   let partner = Self.eitherPartnerSent(typedNow, task: task, sent: messageSent) {
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.eitherReason(partner))])
                    return false
                }
                if name == "type", keyboardGuard, let shown = screen?.frame {
                    let text = act["text"]?.str ?? "", key = Self.typedKey(text), count = CandidatePicker.shows(text, in: shown)
                    if let base = typedBase[key], count > base {
                        record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.sentAgainReason)])  // never typed
                        return false
                    }
                    if typedBase[key] == nil { typedBase[key] = count }
                }
                // What a button does can change with what was typed: a search button that did nothing may be the right one now
                // (over USB 11-09 it missed twice, the word was typed again, and it stayed refused).
                if name == "type" { noKeyboard = 0; unsent = act["text"]?.str ?? ""; quietSinceSend = 0; deadTaps = []; deadRefused = 0 }
                if name == "type" { unsentApp = Self.appInFront(steps, startedIn: startApp) }
                // 134 over the cloud 11-15 (y2): "Y2临时" typed in 备忘录's search went along to 微信 as the message to
                // send; every tap there was "the wrong place" and the thing at hand (拼多多) was skipped. Words typed in an
                // app that sends nothing stay there when another app opens. Typed in a chat app they stay held: the draft
                // is still in that chat's box and goes out only with approval.
                if name == "open", unsent != nil, let typedIn = unsentApp, !Self.isChatApp(typedIn) {
                    DebugLog.write("open: “\(unsent ?? "")” was typed in \(typedIn), not a chat; it stays there")
                    unsent = nil
                }
                // Build 121 over the cloud 11-11: a 抖音 share link was pasted into 测试群 (cmd+v) and sent with Return with
                // no approval asked: only typed text was held. What is pasted counts as typed.
                if Self.pastes(act) { unsent = Self.pastedText(pasteboard()); quietSinceSend = 0; pasteFrame = screen?.frame ?? planned.shot }
                // The tap after one that changed nothing goes through the eye (missed: aimed), so it lands on the spot.
                // Moving it around the spot moved it off the button (淘寶's 加入購物車, 10 clicks above it, over USB 11-09).
                if name == "swipe", Self.swipedToTheEnd(act, after: steps) {
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept swiping a way that moves nothing")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.endReachedReason)])
                    return false
                }
                if name == "tap", Self.deadTwiceHere(deadTaps, act, scene: screenScene) {
                    // Over USB 11-09 a run was refused here 48 times in a row, one model call each, up to its step limit.
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept tapping a spot that does nothing")
                    }
                    // 127 over the cloud 11-12 (g4): the back arrow of 淘宝's 购物车 tapped six times, the app reopened on it
                    // twice: 25 steps. A top-left spot that does nothing is no back button: this is a tab page.
                    let topLeft = (act["x"]?.double ?? 999) < 150 && (act["y"]?.double ?? 999) < 140
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.deadTapReason + (topLeft ? Self.tabPageHint : ""))])
                    return false
                }
                if name == "tap", Self.repeatsRound(steps, next: act) {
                    // D17: the same tap asked for again and again was refused 25 times (~2 minutes) before the thing was
                    // skipped, twice in y4. Three refusals of a round are a change of plan, as with dead taps.
                    roundRefused += 1
                    if roundRefused >= Self.refusalsInARow {
                        roundRefused = 0
                        return try await changeOfPlan(planned.shot, "kept asking for a round of taps already gone through")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.roundReason)])
                    return false
                }
                if name == "swipe", Self.scrollsBackAgain(steps, next: act) {
                    // D19, 134 over the cloud 11-15 (y5): 设置 › 关于本机 scrolled down, up, down; the turn back up to 型号名称
                    // was then refused 20 times. Three refusals are a change of plan, as with a round of taps (D17).
                    if let line = Self.seenWhileScrollingNote(steps, part: parts.count >= 2 && partIndex < parts.count ? parts[partIndex] : nil),
                       !notes.contains(where: { $0.hasSuffix(line.components(separatedBy: Self.seenWhileScrollingMark).last ?? line) }) {
                        notes.append(line)
                        record(nil, ["action": .str("note"), "text": .str(line), "by": .str("run")])
                    }
                    roundRefused += 1
                    if roundRefused >= Self.refusalsInARow {
                        roundRefused = 0
                        return try await changeOfPlan(planned.shot, "kept asking to scroll a page already seen whole")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.scrollBackRefusal(steps))])
                    return false
                }
                if name == "swipe", Self.swipesGoNowhere(steps, next: act) {  // D22
                    roundRefused += 1
                    if roundRefused >= Self.refusalsInARow {
                        roundRefused = 0
                        return try await changeOfPlan(planned.shot, "kept swiping a view that does not move that way")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.deadSwipeReason)])
                    return false
                }
                // D120, z3 on 143 (item 13): inside 微信's 视频号 (a full-screen video) Doubao took the page for 抖音 and sent
                // "open 微信" nine times in a row; each left the same page. A third open in a row of one app is refused.
                if name == "open", let app = act["app"]?.str, Self.opensInARow(steps, app: app) >= 2 {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.reopenReason(app))])
                    return false
                }
                // D124, q143n on 144 (n16): in 测试群 the model wanted today's newer messages and moved the finger down 13
                // times "to scroll forward"; each went further back, to Sunday, and it answered "not found". In a chat a
                // finger moving down shows older messages: refused (twice a run at most), with the way to newer ones.
                if name == "swipe", olderSwipeRefused < 2, Self.inChatApp(steps, task: task), Self.wantsNewerByOlderSwipe(act) {
                    olderSwipeRefused += 1
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.olderSwipeReason)])
                    return false
                }
                // D119, z3 on 143 (item 34): Weather's chart for 3 p.m. was held at the same spot 15 times; each landed on
                // 5 p.m. The same hold three times in a row is refused like a tap, with how to move along a chart.
                if name == "tap" || name == "hold", Self.tapsInARow(steps, like: act) >= Self.sameTapLimit {
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept tapping a spot that does nothing")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(name == "hold" ? Self.sameHoldReason : Self.sameTapReason)])
                    return false
                }
                // Over USB 11-10 淘寶's box showed a suggestion (保温水壶, grey) and the model searched it as if it had typed
                // 保溫杯: the price it found was for the wrong thing. A search in an app where nothing was typed is refused.
                if untypedSearches < 2, Self.searchesUntyped(act, after: steps, task: task) {
                    untypedSearches += 1
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.untypedSearchReason)])
                    return false
                }
                // Over USB 11-10 the way into 测试群 was followed for 验证群: WeChat opened on the last chat and the message went
                // there. Before a message goes, something looks at where it would go.
                // 121 over the cloud 11-11: the model's look said OK to 小红书's comment box and to 验证群 for a goal that named
                // 测试群, then NO, then OK again for the same screen; and it blocked a search's Return in 拼多多. Only a message
                // is checked, and when the goal names a group the title at the top decides, read off the screen.
                let sending = unsent != nil && (Self.sends(act) || act["learned"] == .str("send"))
                // 125 stress test 11-12 (s03): a new note's first line "压力测试比价" (part of the goal's message
                // "125压力测试比价完成") and then its body were each taken for that message by their Return in 備忘錄,
                // "about to send into the wrong place", and the run failed. In an app that sends nothing to anyone,
                // Return is a new line or a search.
                // 130 over the cloud 11-13 (q130b g5): "open 淘寶" left 测试群 in front; the run took itself to be in 淘寶,
                // where typing is no message, and "G5买东西做完" went out with no approval. Under a chat title the goal
                // names, Return sends a message whatever app the run thinks it is in.
                var localHere = Self.inLocalApp(steps), chatOnScreen = false
                if sending, localHere, let title = (screen?.frame ?? planned.shot).flatMap({ WatchReport.navigationTitle(in: $0) }),
                   Self.goalNamesChat(title, task: task) {
                    DebugLog.write("send: \(title) is on screen, not the app last opened: a message, approval first")
                    (localHere, chatOnScreen) = (false, true)
                }
                // D37, s3 on 136: a member's name typed into 新聊天's search, then 完成, was "about to send into the wrong
                // place: the chat at the top is 新聊天", twice, and making a group failed. A picker or a settings page
                // (新聊天, 选择联系人, 设置备注和标签…) is no chat: what is typed there goes to no one.
                if sending, !chatOnScreen, let title = (screen?.frame ?? planned.shot).flatMap({ WatchReport.navigationTitle(in: $0) }),
                   Self.notAChat(title) {
                    DebugLog.write("send: \(title) is a picker or settings page, not a chat: no message")
                    localHere = true
                }
                // D163: nor is a search box at the top, 取消 at its right end: what is typed there reaches no one.
                if sending, !chatOnScreen, !localHere, await Self.searchBarUp(in: screen?.frame ?? planned.shot) {
                    DebugLog.write("send: a search box is up (取消 at the top right): a search, no message")
                    localHere = true
                }
                // 130 over the cloud 11-13 (fourth round, g4): with the app in front not known, the note's first line
                // "第4组记录" (the goal: 第一行写“第4组记录”) and its Return were taken for a message to the wrong place,
                // blocked twice, and Codex took over. What the goal says to write (写“…”), and not to send, is no message
                // unless a chat the goal names is on the screen.
                let pendingKey = Self.typedKey(unsent ?? "")
                let writtenOnly = !pendingKey.isEmpty && Self.goalWrites(task).contains { pendingKey.contains($0) }
                    && !Self.goalMessages(task).contains { pendingKey.contains($0) }
                // Never in a chat app known to be in front, nor under a chat title the goal names ("在测试群写“你好”" is
                // a message there): only then is it a note's line.
                if sending, writtenOnly, !chatOnScreen {
                    let front = Self.appInFront(steps, startedIn: nil).map { AppNames.hans($0).lowercased() }
                    let inChat = front.map { f in Self.chatApps.contains { f.contains($0) } } ?? false
                    let title = (screen?.frame ?? planned.shot).flatMap { WatchReport.navigationTitle(in: $0) }
                    let chatTitle = title.map { Self.goalNamesChat($0, task: task) && !Self.goalWrites(task).contains(Self.typedKey($0)) } ?? false
                    if !inChat, !chatTitle {
                        DebugLog.write("send: \(unsent ?? "") is what the goal says to write, not to send: no message")
                        localHere = true
                    }
                }
                let isMessage = sending && !localHere
                    && Self.needsApproval(unsent ?? "", task: task, chatApp: chatOnScreen || Self.inChatApp(steps, task: task))
                let sendFrame = screen?.frame ?? planned.shot
                var seenTitle = isMessage ? sendFrame.flatMap { WatchReport.navigationTitle(in: $0) } : nil
                if isMessage, seenTitle == nil {
                    // B5, 122 over the cloud 11-11: the approval went out with no destination twice (q08, q11). A banner
                    // or a frame caught mid-change: one more look, a moment later.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    seenTitle = screen?.frame.flatMap { WatchReport.navigationTitle(in: $0) }
                }
                approvalPlace = seenTitle
                if sending { sendIsMessage = isMessage }
                var wrongSpot: String?
                if isMessage, endAfterSend == nil, Self.asksToSend(task) {
                    switch Self.chatCheck(seen: seenTitle, task: task, steps: steps) {
                    case .right: wrongSpot = nil
                    case .wrong(let why): wrongSpot = why
                    case .unknown: wrongSpot = await wrongPlace(frame: sendFrame)
                    }
                }
                if let wrong = wrongSpot {
                    // D93, z3 on 138: Z3验证11:07 was typed, its Return blocked as the wrong place, and it stayed in 验证群's
                    // box; at 13:22, with no task running and nothing pressed by Lan Agent, it went out. What was typed for a
                    // message that is not sent is cleared at once, as a draft not approved is: nothing is left in a box
                    // for a later tap to send.
                    if unsent != nil {
                        try? await phone?.key("cmd+a")
                        try? await phone?.key("backspace")
                        unsent = nil
                        DebugLog.write("send: blocked; what was typed is cleared from the box")
                    }
                    sendBlocks += 1
                    if sendBlocks >= 2 {
                        sendBlocks = 0
                        return try await changeOfPlan(planned.shot, "about to send into the wrong place: \(wrong)")
                    }
                    record(planned.shot, ["action": .str("send blocked"), "reason": .str(Self.wrongPlaceReason + wrong)])
                    return false
                }
                // Customer spec 11-10 (§0.6, §13.3): a message from a task the cloud gave waits for approval before it goes.
                // Over Wi-Fi 11-10 a search (行事曆, www.163.com, 牙刷) was held for approval too: what the goal itself
                // names, in a goal that posts nothing, is not a message.
                // 126 over the cloud 11-12 (g5): "第5组记录" typed in 備忘錄 and its Return waited for approval as a message;
                // s03's fix (125) had kept it out of the wrong-place check only. In an app that sends nothing, nothing waits.
                // D58, s8 on 137: "137发布测试" (标题写…) was found to be what the goal writes, not a message, and its approval
                // was asked all the same ("about to send", no destination) on 抖音's camera screen: the check below looked at
                // the app only. What was settled above (a note's line, a picker, a title) waits for nothing.
                if let text = unsent, let approveSend, Self.sends(act) || act["learned"] == .str("send"), !localHere,
                   Self.needsApproval(text, task: task, chatApp: Self.inChatApp(steps, task: task)), !approvedTexts.contains(Self.typedKey(text)) {
                    var shown = text  // what the approval shows: a paste, as read off the screen (B4)
                    if text == Self.pastePlaceholder, let before = pasteFrame, let current = screen?.frame ?? planned.shot {
                        let beforeRows = await CandidatePicker.rowsOffMain(in: before, top: 0.05, bottom: 1)
                        let afterRows = await CandidatePicker.rowsOffMain(in: current, top: 0.05, bottom: 1)
                        let words = Self.newWords(before: beforeRows, after: afterRows)
                        if !words.isEmpty { shown = "（粘贴）" + words }
                    }
                    record(planned.shot, ["action": .str("waiting approval"), "reason": .str("about to send: " + String(shown.prefix(120)))])
                    let approved = await approveSend(shown)
                    try Task.checkCancellation()
                    guard approved else {
                        // The draft stays in the box otherwise, and the next task found it there (x11, 11-10: 17 deletes).
                        try? await phone?.key("cmd+a")
                        try? await phone?.key("backspace")
                        unsent = nil
                        // The picture the cloud gets is this step's: the box once it is empty, not the draft still in it (11-10).
                        let cleared = await freshFrame()
                        record(cleared ?? screen?.frame, ["action": .str("done"), "answer": .str(Self.notApprovedAnswer), "approval": .str("rejected")])
                        return true
                    }
                    approvedTexts.insert(Self.typedKey(text))
                }
                // D28, user 11-15: publishing shows to everyone: the owner is asked before 发布, once per app a run, always
                // (a task from the cloud through its approval, one started here with a panel). No: that app is left
                // filled in and unpublished, and the run goes on with the rest. Nobody to ask: nothing is published.
                let tapAt = CGPoint(x: (act["x"]?.double ?? 0) / 1000, y: (act["y"]?.double ?? 0) / 1000)
                let tapApp = Self.appInFront(steps, startedIn: startApp)
                if name == "tap", !publishAllowed.contains(tapApp ?? ""),
                   Self.publishTap(act, label: Self.labelAt(tapAt, in: readRows), app: tapApp) {
                    if Self.forbids(task, "发布") || publishDeclined.contains(tapApp ?? "") {
                        record(planned.shot, ["action": .str("refused"), "reason": .str(Self.publishDeclinedReason)])
                        return false
                    }
                    record(planned.shot, ["action": .str("waiting approval"), "reason": .str("publish in " + (tapApp ?? "?") + "?")])
                    let yes = await askPublish?(Self.publishQuestion(tapApp)) ?? false
                    try Task.checkCancellation()
                    if yes == true {
                        publishAllowed.insert(tapApp ?? "")
                    } else {
                        publishDeclined.insert(tapApp ?? "")
                        let line = "\(tapApp ?? "这个 App")：内容已填好，机主选择不发布，没有点发布"
                        if !notes.contains(line) { notes.append(line) }
                        record(planned.shot, ["action": .str("refused"), "reason": .str(Self.publishDeclinedReason)])
                        gotOn()
                        return false
                    }
                }
                // #17 (122, 11-11): a like, a follow or a 收藏 shows to others like a message, and went unasked. A tap the
                // model says does one is refused in a goal that says not to, and waits for approval in a task from the cloud.
                if name == "tap", let what = Self.publicTap(act) {
                    if Self.forbids(task, what) {
                        record(planned.shot, ["action": .str("refused"),
                                              "reason": .str("Refused: the goal says not to \(what). Do not tap it; go on with the rest of the goal.")])
                        return false
                    }
                    if let approveSend, !approvedTexts.contains("tap:" + what) {
                        record(planned.shot, ["action": .str("waiting approval"), "reason": .str("about to tap: " + what)])
                        let approved = await approveSend("（\(what)）")
                        try Task.checkCancellation()
                        guard approved else {
                            record(planned.shot, ["action": .str("done"), "answer": .str("没有\(what)：未获批准。"), "approval": .str("rejected")])
                            return true
                        }
                        approvedTexts.insert("tap:" + what)
                    }
                }
                onDoing?(.acting(act))  // the thought (on the first act) names the target
                let started = now()
                if name == "tap", missed || aimNext || (unsent != nil && Self.sends(act)) {
                    act["precise"] = .bool(true) // a pending message's first send also requires a verified landing
                }
                if name == "path", act["smooth"] == nil, Self.isGentleBend(points(act), aspect: screen?.aspect ?? 9 / 19.5) {
                    act["smooth"] = .bool(true)  // recorded, so the review and the next look know it was a curve
                }
                momentum = name == "swipe"
                actFrame = screen?.frame
                // 130 over the cloud 11-13 (q130c c3): each "open 美团外卖" searched for an app of that name first (12-14 s)
                // and only then opened 美团, three times in one run. A part of an app no Home Screen page shows and that
                // never opened here opens its app at once.
                if name == "open", let app = act["app"]?.str, let host = Self.hostApp(app), AppPlaces.page(of: app) == nil,
                   !AppPlaces.wasOpened(app) {
                    DebugLog.write("open \(app): a part of \(host); opening \(host)")
                    act["app"] = .str(host)
                }
                do { try await perform(act) }
                catch let absent as AppNotOnPhone {
                    // 127 over the cloud 11-12 (g4): "美团外卖" is a part of 美团, not an app; the item was skipped as "not
                    // installed". A name for a part of an app opens that app.
                    if name == "open", let host = Self.hostApp(absent.name),
                       (try? await perform(["action": .str("open"), "app": .str(host)])) != nil {
                        DebugLog.write("open \(absent.name): a part of \(host); \(host) opened")
                        act["app"] = .str(host)
                    } else if name == "open", lookedAgain.insert(absent.name).inserted, (try? await perform(act)) != nil {
                        // 134 over the cloud 11-15 (y1): Search showed nothing once and 行事曆 was "not on this phone"; it
                        // opened three minutes later. Before the owner is asked to install, a second look.
                        DebugLog.write("open \(absent.name): found on a second look")
                    } else if name == "open", let askInstall, !installAsked.contains(absent.name), !Self.builtInApp(absent.name) {
                        // User 11-15: "手机没有JD这时候会反馈给我是否下载JD，然后我说是就去下载…我说否就结束这个任务".
                        installAsked.insert(absent.name)
                        record(planned.shot, ["action": .str("waiting approval"), "reason": .str("install " + absent.name + "?")])
                        // z3 on 135: the owner was asked about “閒魚”, the phone's own label: what the owner reads is Simplified.
                        let app = AppNames.hans(absent.name)
                        switch await askInstall(app) {
                        case true?:
                            let line = Self.installNote(app)
                            if !notes.contains(line) { notes.append(line) }
                            record(planned.shot, ["action": .str("install approved"), "app": .str(app), "reason": .str(line)])
                            gotOn()
                            installSteps += Self.installStepAllowance  // D194
                            try await replan(stuck: true, first: Self.installFirst(app))
                            return false
                        case false?:
                            noHelp = true  // the owner said no: the task ends here, with no pause for help
                            record(planned.shot, ["action": .str("fail"), "reason": .str(Self.installDeclined(app))])
                            return true
                        case nil:
                            record(planned.shot, ["action": .str("open failed"), "app": .str(absent.name), "reason": .str(absent.name + Self.openFailedReason)])
                            return false
                        }
                    } else {
                        record(planned.shot, ["action": .str("open failed"), "app": .str(absent.name), "reason": .str(absent.name + Self.openFailedReason)])
                        return false
                    }
                }
                catch let keys as KeysNotOnScreen {
                    record(planned.shot, ["action": .str("press failed"), "reason": .str(keys.localizedDescription)])
                    return false
                }
                catch is NothingTyped {
                    aimNext = true  // the next tap on the box is aimed, as for the guard before typing
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.noKeyboardReason)])
                    return false
                }
                catch let input as InputNeedsVerification {
                    if input.fieldMayBeComplete { pendingInput = input.expected }
                    lastActed = now()
                    record(planned.shot, ["action": .str("compose"), "expected": .str(input.expected),
                                          "remaining": .str(input.remaining), "reason": .str(input.localizedDescription),
                                          "field_may_be_complete": .bool(input.fieldMayBeComplete)])
                    timing.frameMs += try await settle()
                    return false // inspect candidates before any further action in the batch
                }
                // A rejected command did not send anything. Commit only after the gesture succeeds.
                if name == "key", ["cmd+a", "backspace", "delete"].contains(act["combo"]?.str?.lowercased() ?? "") {
                    pendingInput = nil
                }
                if let text = unsent, Self.sends(act) || act["learned"] == .str("send") {
                    if name == "tap", let x = act["x"]?.double, let y = act["y"]?.double, let before = actFrame {
                        sendTap = (CGPoint(x: x / 1000, y: y / 1000), before)  // learned at the end if the run is done
                    }
                    sentTexts.insert(Self.typedKey(text)); unsent = nil; pendingInput = nil; quietSinceSend = 0
                    if sendIsMessage {
                        messageSent.insert(Self.typedKey(text))
                        // 125 over the cloud 11-12 (k03): both messages went out, then "look at both groups once more"
                        // went back and forth with nothing written down, the loop guard ended it, and what it found
                        // said nothing of the sends. A message sent is written down, where it went and what it said.
                        let line = Self.sentNote(text, to: approvalPlace)
                        if !notes.contains(line) {
                            notes.append(line)
                            (stallsNoProgress, refusalsNoProgress) = (0, 0)
                            gotOn()
                        }
                    }
                    sendIsMessage = false
                    if let place = approvalPlace { sentPlaces[Self.typedKey(text), default: []].insert(place) }
                    justSent = text
                }
                lastActed = now()
                let s = lastActed - started
                timing.hidMs += s * 1000
                act["act_s"] = .num((s * 100).rounded() / 100)
                spots += pointerPath(act)
                pointerAt = spots.last!
                if let guarded = bounceGuard, !Self.sameSpot(guarded.stop, act), !Self.sameSpot(guarded.other, act) {
                    (bounceGuard, bounceRefused, bounceOpener) = (nil, 0, false)  // the run moved on from the back-and-forth
                }
            }
            record(planned.shot, act)
            if name == "done" || name == "fail" { return true }
            if returnSent {  // sent and checked: nothing is left to look at or tap
                record(nil, ["action": .str("done"), "answer": .str("sent with Return")])
                return true
            }
            if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil {
                // The rest of a type/send/navigation batch was planned before the send. Drop it and verify afresh.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                if let text = justSent, let sendReceipt {
                    let confirmed = await sendReceipt(text)
                    try Task.checkCancellation()
                    if confirmed {
                        record(screen?.frame, ["action": .str("done"), "answer": .str("sent message verified after the original request"),
                                               "source": .str("send receipt")])
                        return true
                    }
                }
                if name == "tap", let text = justSent, sendCorrections < 2, let before = seen, let after = screen?.frame {
                    var recovery: String?
                    if let draft = CandidatePicker.mistypedDraft(text, before: before, after: after) {
                        recovery = "The send tap added a letter to the SAME input field: \(draft). Correct only the visible extra characters."
                    } else if CandidatePicker.unchangedDraft(text, before: before, after: after) {
                        // A second frame must still show that same complete draft. A transient/unknown result
                        // or a new matching bubble keeps the existing send protection.
                        let confirmation = now()
                        await screen?.afterAction(since: confirmation)
                        try await screen?.requireFrame(after: confirmation)
                        if let checked = screen?.frame, CandidatePicker.unchangedDraft(text, before: before, after: checked) {
                            recovery = "The SAME input field still contains the complete correct draft in two post-action observations. Keep it unchanged and correct the send control's landing."
                        }
                    }
                    if let recovery {
                        sendCorrections += 1
                        sentTexts.remove(Self.typedKey(text)); unsent = text; pendingInput = text; quietSinceSend = 0
                        aimNext = true
                        record(screen?.frame, ["action": .str("send missed"), "reason": .str(recovery
                            + " No new matching message is visible. Send once with visual aim, then verify. Do not retype or replace correct text.")])
                    }
                }
                return false
            }
            if startsDrawing, drawing.contains(name) {
                // A first stroke may pan a canvas if the drawing tool was not actually active.
                // Observe it before spending the rest of the batch on the same mistaken state.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                if let share = Self.inkShare(before: seen, after: screen?.frame, stroke: strokePoints(act)) {
                    if share < 0.25 {
                        inkSeen = inkSeen ?? false
                        if let tap = Self.tapBeforeStroke(steps) { deadTaps.append((tap, screenScene)) }  // that tap picked no pen
                        record(screen?.frame, ["action": .str("no ink"), "reason": .str(Self.noInkReason)])
                    } else {
                        inkSeen = true
                    }
                }
                return false
            }
            let following = i < acts.count - 1 ? acts[i + 1].act["action"]?.str : nil
            if name == "tap", following != nil {
                // A tap may open a page, change tools or undo content. The rest of this plan was made on the
                // pre-tap screenshot; inspect its result before issuing another tap, typing or drawing.
                // Independent strokes and type-then-key batches still run together.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                noteDeadTap()
                // The keys of a calculator, a number pad, several checkboxes: the next tap still fits while the screen
                // is the same one (over USB 11-09: 1234 x 5678, one key per model call, 293 s and no answer).
                if following == "tap", let was = seen.flatMap(Vision.look), let now = screen?.frame.flatMap(Vision.look),
                   Vision.sameScreen(was, now) { continue }
                // A tap into a text field and the typing after it (build 116): Codex answered one action at a time, ~12 s
                // a look, and the typing waited a whole look to see the keyboard (11-10). With a keyboard up, it goes on.
                if following == "type", await keyboardNowUp() {
                    DebugLog.write("tap then type in one reply: a keyboard is up, typing")
                    continue
                }
                return false
            }
        }
        timing.frameMs += try await settle()
        // feedback for the next round
        steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
        // D162: a tap at the spot of the tap before it that changed the screen: did it lead to another page (its title)?
        if let last = steps.last, last["action"]?.str == "tap", last["changed"] == .bool(true),
           Self.tapsInARow(Array(steps.dropLast()), like: last) >= 1, let was = seen, let shown = screen?.frame {
            let before = WatchReport.navigationTitle(rows: await CandidatePicker.rowsOffMain(in: was, top: 0.02, bottom: 0.22))
            let after = WatchReport.navigationTitle(rows: await CandidatePicker.rowsOffMain(in: shown, top: 0.02, bottom: 0.22))
            if before != after, before != nil || after != nil {
                steps[steps.count - 1]["newPage"] = .bool(true)
                DebugLog.write("tap: led to another page (\(before ?? "-") → \(after ?? "-")): the same spot again is no dead spot")
            }
        }
        // A swipe from the margin over a page that moves by itself (Weather's sky) "changed" the screen without scrolling it:
        // over USB 11-10, 20 swipes on Beijing's forecast and the run ran out of time. The words tell whether it scrolled.
        if let last = steps.last, last["action"]?.str == "swipe", last["x1"]?.int == Self.marginX, let was = seen, let shown = screen?.frame {
            let before = await CandidatePicker.rowsOffMain(in: was, top: 0.055, bottom: 1)
            let after = await CandidatePicker.rowsOffMain(in: shown, top: 0.055, bottom: 1)
            if Self.sameWords(before, after) { steps[steps.count - 1]["scrolled"] = .bool(false) }
        }
        noteDeadTap()
        return false
    }

    private func keyboardNowUp() async -> Bool {
        if ourKeyboardOnScreen?() == true { return true }
        guard let shown = screen?.frame else { return false }
        return await CandidatePicker.keyboardUpOffMain(in: shown)
    }

    /// A tap that changed nothing on screen counts as dead, like one before a stroke that left no line: the same spot
    /// twice is refused, so the agent tries another control instead of the same one again and again.
    private func noteDeadTap() {
        noteLearnedControls()
        guard let last = steps.last, last["action"]?.str == "tap", last["changed"] == .bool(false) else { return }
        deadTaps.append((last, screenScene))
    }

    /// Learned buttons from what this action did: a learned spot that changed nothing is counted against it; the
    /// first top-of-screen tap that worked right after a back swipe did nothing is learned as this screen's back.
    private func noteLearnedControls() {
        guard let controls, let last = steps.last, let changed = last["changed"]?.bool else { return }
        if let id = last["control"]?.str {
            if !changed { controls.failed(id) } else if last["learned"] == .str("back") { controls.worked(id) }
        }
        switch last["action"]?.str {
        case "back":
            backMissed = !changed
        case "tap":
            if backMissed, changed, last["learned"] == nil, let x = last["x"]?.double, let y = last["y"]?.double,
               y <= 150, let before = actFrame {
                controls.learn("back", at: CGPoint(x: x / 1000, y: y / 1000), on: before)
            }
            backMissed = false
        default:
            break
        }
    }

    /// Text in without a model look per phrase. A paste when iOS lets this app fill the pasteboard and the text then
    /// newly shows on screen (read on this phone); uncertain input stays for inspection. Else pinyin,
    /// each candidate found on the candidate row (CandidatePicker) and tapped. A candidate not found that way is left
    /// to the model as before (InputNeedsVerification, a "compose" step).
    private func typeFast(_ text: String) async throws {
        guard let phone else { return }
        if typedInto == nil { typedInto = lastTap }
        if returnSends && !boxCleared {  // a draft, or text a swipe across the keyboard typed, would join the reply
            boxCleared = true             // (PC harness: 你好 left in 测试群's box; 给我们发微吧 from a home flick)
            try await phone.key("cmd+a")
            try await phone.key("backspace")
        }
        // Lan Agent's keyboard first: exact text in place, no pinyin candidates and no app switch (phase B).
        if Pasteboard.needed(text), let keyboardType, await keyboardType(text) {
            if returnSends {
                if ourKeyboardOnScreen?() == true, let keyboardReturn, await keyboardReturn() {} else { try await phone.key("enter") }
                returnSent = true
                return DebugLog.write("type: typed by Lan Agent's keyboard, sent with Return")
            }
            return DebugLog.write("type: typed by Lan Agent's keyboard")
        }
        if Pasteboard.needed(text), try await typedQuickly(text, phone: phone) {
            if returnSends {
                if ourKeyboardOnScreen?() == true, let keyboardReturn, await keyboardReturn() {} else { try await phone.key("enter") }
                returnSent = true
                return DebugLog.write("type: typed as pinyin, seen in the field, sent with Return")
            }
            return DebugLog.write("type: typed as pinyin and seen in the field")
        }
        // D49, y3 on 136: one hop got lost at 18:49 (Lan Agent not reached after 2 switches); 20 minutes later the
        // memo of all results (several lines) could only be pasted and was not written. Text that cannot be typed
        // tries the hop again.
        if Pasteboard.needed(text) || Pasteboard.prefersExact(text), !pasteHopOff || Pasteboard.requiresPaste(text) {
            let hop = await pasteHop?(text) ?? (Pasteboard.put(text) ? .filled : .refused)
            if hop == .lost {
                // 126 over the cloud 11-12 (g2): the trip through Lan Agent did not come back, the run paused, and a task
                // of 20 parts ended at its first. Nothing was pasted and no more paste trips this run, but the run goes
                // on: the next look sees where the phone is, and the text is typed by Lan Agent's keyboard or as pinyin.
                pasteHopOff = true
                throw DeviceError(message: "Not typed: the paste trip through Lan Agent did not come back to the field, "
                                  + "so nothing was pasted. Look at the screen, go back to the field, tap it, and type again.")
            }
            if hop == .filled {
                // A missing keyboard or uncertain OCR does not prove the paste missed. Keep the field and inspect
                // it rather than deleting a potentially correct result and issuing another paste (logs34).
                let pasted = try await pasteChecked(text, phone: phone)
                if pasted {
                    if returnSends {  // checked: exactly this text is in the box. The run ends here: a look at the
                        // empty box afterwards tapped "发送" on the keyboard's space bar (logs(20)).
                        try await phone.key("enter")
                        returnSent = true
                        return DebugLog.write("type: pasted, seen in the field, sent with Return")
                    }
                    return DebugLog.write("type: pasted and seen in the field")
                }
                trace?.write(screen?.frame, kind: "input verification", ["method": .str("paste"), "verified": .bool(false)])
                throw InputNeedsVerification(expected: text, remaining: "", fieldMayBeComplete: true)
            } else {
                DebugLog.write("type: the pasteboard refused the text")
            }
        }
        guard !Pasteboard.requiresPaste(text) else {
            throw DeviceError(message: "Exact paste is unavailable for this text. Keyboard fallback cannot preserve it safely; no replacement text was typed.")
        }
        var rest = text
        while true {
            do { return try await phone.type(rest) }
            catch let input as InputNeedsVerification {
                // Like a person: of the candidates, the longest that starts the phrase; the keyboard keeps the rest of
                // the pinyin open for the next pick. Whole six-character phrases are often not offered (logs(15)).
                var left = input.expected
                while !left.isEmpty {
                    guard let frame = await freshFrame(), let pick = CandidatePicker.longestStart(of: left, in: frame) else {
                        throw InputNeedsVerification(expected: left, remaining: input.remaining)
                    }
                    try await phone.tap(pick.spot.x, pick.spot.y, aim: false)
                    DebugLog.write("type: picked “\(pick.text)” on the candidate row")
                    left = String(left.dropFirst(pick.text.count))
                }
                if input.remaining.isEmpty { return }
                rest = input.remaining
            }
        }
    }

    /// Pinyin with the first candidate per chunk and one look at the end; true when the whole text newly shows.
    /// Uncertain text stays in the field for the next model look. Never on the 9-key pinyin keyboard, which
    /// turns letters into digit keys ("nihao" came out as 你哄啊).
    private func typedQuickly(_ text: String, phone: Gestures) async throws -> Bool {
        // Repeatedly unsupported keyboards use paste first until the next watch starts.
        guard !Pasteboard.prefersExact(text), pinyinMisses < 2, let start = await freshFrame() else { return false }
        if CandidatePicker.nineKey(in: start) {
            pinyinMisses += 1
            DebugLog.write("type: the keyboard is 9-key pinyin; switch to the full pinyin keyboard (拼音-全键盘) in iOS Settings")
            return false
        }
        let before = CandidatePicker.shows(text, in: start)
        let keyboardBefore = CandidatePicker.keyboardUp(in: start) || ourKeyboardOnScreen?() == true
        try await phone.typeQuick(text)
        var after = await freshFrame()
        if let shown = after, CandidatePicker.shows(text, in: shown) <= before {  // the frame may predate the last key
            try? await Task.sleep(nanoseconds: 600_000_000)
            after = await freshFrame()
        }
        if let shown = after, CandidatePicker.shows(text, in: shown) > before { return true }
        trace?.write(after, kind: "input verification", ["method": .str("pinyin"), "verified": .bool(false)])
        // 132 over the cloud 11-14 (c2): "keyboard: no keyboard on screen", the keys went nowhere, and the text was kept
        // as typed: typing 首尔 again was refused twice and the item given up (131 c3: 猫 in 抖音, 16 minutes). With no
        // keyboard before or after and nothing new on the screen, nothing was typed.
        let keyboardAfter = (after.map { CandidatePicker.keyboardUp(in: $0) } ?? false) || ourKeyboardOnScreen?() == true
        if !keyboardBefore, !keyboardAfter {
            DebugLog.write("type: no keyboard on screen and the text did not show; not kept as typed")
            throw NothingTyped()
        }
        DebugLog.write("type: pinyin unconfirmed; kept the field for inspection")
        throw InputNeedsVerification(expected: text, remaining: "", fieldMayBeComplete: true)
    }

    /// Cmd+V, answering iOS's paste prompt if it comes up, and true when the text newly shows on screen (looked at
    /// twice: the first frame may come from before the paste).
    private func pasteChecked(_ text: String, phone: Gestures) async throws -> Bool {
        let before = await freshFrame().map { CandidatePicker.count(text, in: $0) } ?? 0
        try await phone.key("cmd+v")
        var after = await freshFrame()
        if let shown = after, let allow = CandidatePicker.allowPaste(in: shown) {  // iOS asks: allow, once
            try await phone.tap(allow.x, allow.y, aim: false)
            DebugLog.write("type: iOS asked to allow the paste; allowed")
            after = await freshFrame()
        }
        if let shown = after, CandidatePicker.count(text, in: shown) <= before {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            after = await freshFrame()
        }
        return after.map { CandidatePicker.count(text, in: $0) > before } ?? false
    }

    /// The screen a moment after the last keys, for reading text on it.
    private func freshFrame() async -> Data? {
        let since = now()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await screen?.afterAction(since: since)
        return screen?.frame
    }

    /// The last action was a swipe: a scrolled list coasts on after the finger lifts, and a look taken meanwhile
    /// was out of date by the time the model answered ("stale plan" again and again in traces(39)).
    private var momentum = false

    private func settle() async throws -> Double {
        let started = now()
        onDoing?(.looking)
        if momentum { momentum = false; try await Task.sleep(nanoseconds: 700_000_000) }
        await screen?.afterAction(since: lastActed)
        do {
            try await screen?.requireFrame(after: lastActed)
        } catch where screen?.live == false && !(error is CancellationError) {
            // The screen dropped right after the move: not this step's failure. The next look pauses for it
            // (waitForScreen), then goes on from here.
            DebugLog.write("frame after the move: the screen is gone; the next look waits for it")
        }
        return (now() - started) * 1000
    }

    private static let observedActions: Set<String> = ["tap", "swipe", "back", "home", "key", "type", "path", "circle", "compose", "open",
                                                       "readup"]
    /// Planner and guard records never erase the result of the last actual gesture.
    private var lastObservedAction: JObject? {
        steps.last { Self.observedActions.contains($0["action"]?.str ?? "") && $0["performed"] != .bool(false) }
    }
    private var missed: Bool { lastObservedAction?["changed"] == .bool(false) }

    /// True when the actor picks the same action as its last limit-1 moves and the last one did nothing.
    /// Repeating a move that still changes the screen (e.g. scrolling down a long list) is progress, not a loop.
    func repeating(_ act: JObject, limit: Int = 3) -> Bool {
        if recoveringSend(act) { return false }
        if act["action"] == .str("tap"), act["precise"] == .bool(true),
           lastObservedAction?["precise"] != .bool(true) {
            return false // this bounded delivery-mode retry must execute before the generic loop guard
        }
        let moves = steps.filter {
            Self.observedActions.contains($0["action"]?.str ?? "") && $0["performed"] != .bool(false)
        }.suffix(limit - 1)
        return moves.count == limit - 1 && moves.allSatisfy { Actions.sameTarget($0, act) }
            && moves.last?["changed"] != .bool(true)
    }

    private func recoveringSend(_ act: JObject) -> Bool {
        aimNext && unsent != nil && (1...2).contains(sendCorrections) && act["action"] == .str("tap") && Self.sends(act)
    }

    /// D36, s2 on 136 (高德: 比较前10家川菜馆, 看评价可不可疑, 推荐三家): one thing of the goal, so the steps of one; the run
    /// ran out at the 9th place's reviews. A goal that goes through N candidates (前10家, 十来个, 4篇) counts as N things.
    static func candidateCount(_ goal: String) -> Int {
        // D195, the X bloggers over the cloud 11-20 (151): "看最新5条本人发的帖子" was one thing, about 50 steps; 4 of 18
        // ran out at the 3rd to 5th post (long posts, 顯示更多, translations). 最新/最近 N 条 goes through N as well.
        let pattern = #"(?:前|比较|对比|比一比|挑|找|看|查|最新|最近)\s*(\d{1,2}|十来|十几|二十|十|[两二三四五六七八九])\s*(?:家|个|款|篇|条|间|套|部|只|件|座)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let g = AppNames.hans(goal), ns = g as NSString
        let words = ["十来": 10, "十几": 12, "二十": 20, "十": 10, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7,
                     "八": 8, "九": 9]
        return re.matches(in: g, range: NSRange(location: 0, length: ns.length)).reduce(0) { best, m in
            let v = ns.substring(with: m.range(at: 1))
            return max(best, min(Int(v) ?? words[v] ?? 0, 30))
        }
    }

    /// Each part of a plan gets its own steps (specs/004 §2.1): the alarm + sun + group message task spent all 40 on
    /// the alarm (live test 11-08). 20 a part, never fewer than `base`, at most 240: 122 over the cloud 11-12, goals
    /// of 9 to 15 parts ran out at 100 (4 of 5 failures of the big ones), each part taking 10 to 15 steps.
    static func stepBudget(plan: String, base: Int, goal: String = "") -> Int {
        let parts = max(Self.parts(of: plan).count, goalParts(goal), candidateCount(goal))
        guard parts >= 2 else { return base }
        // 133 over the cloud 11-14 (y1–y6): goals of 50 things had 240 steps, under 5 a thing. Past 20 things each
        // gets 12 more (at most 600).
        return max(base, min(parts * 20, max(240, min(parts * 12, 600))))
    }

    /// A part that asks to find something out (记下, 查, 看, 是什么, 多少…), as against one that does something (send,
    /// open, sum up what was found).
    static func readsSomething(_ part: String) -> Bool {
        let p = AppNames.hans(part)
        let words = ["记下", "记录", "查", "看", "读", "多少", "几", "是什么", "是不是", "是否", "星期", "温度", "价格", "作者",
                     "标题", "名称", "名字", "点赞数", "版本", "电量"]
        return words.contains { p.contains($0) }
    }

    /// What a tap does that others see (点赞, 关注, 收藏), by the model's own words for it, or nil. What it says it will
    /// not do, and counts or tabs it only reads (点赞数, 已关注, Douyin's 关注 tab), are not the tap.
    static func publicTap(_ act: JObject) -> String? {
        guard act["action"]?.str == "tap" else { return nil }
        var t = AppNames.hans(((act["thought"]?.str ?? "") + " " + (act["thought_zh"]?.str ?? "")).lowercased())
        t = t.replacingOccurrences(of: #"(不要|不用|避免|别|勿|以免|而不是|don't|do not|avoid|not |without|instead of)[^，,。.；;]*"#,
                                   with: " ", options: .regularExpression)
        let like = #"点赞按钮|点个赞|给[^，,。]{0,8}点赞|点赞(这|该|视频|笔记|一下)|点击点赞|tap (the )?(heart|like)\b|like button|\blike (it|this|the video|the post|the note)"#
        // D196, the X bloggers on 151: 18 follows went through and the owner was asked about none of them: the words
        // were "点一次关注", "tap it once to follow", "按钮显示“跟随”，需要点击一次". (2 runs were asked, about a second
        // tap the model called "the follow button", which ended them.)
        let follow = #"加关注|点关注|关注按钮|点击关注(?!页|栏|tab)|点[一下次个]{1,3}关注(?!页|栏|tab)|关注(他|她|作者|博主|这个|该)|显示[“"「]?(?:关注|跟随|follow)[”"」]?[，,]?[^。.]{0,10}(?:点|tap)|follow button|\bfollow (him|her|the author|this|the account|it|them)\b|tap (it |the button )?(once )?to follow"#
        let keep = #"收藏按钮|点击收藏|收藏(这|该|一下|视频|笔记)|加入收藏|bookmark (it|this|the)|save (it|this) to"#
        for (pattern, what) in [(like, "点赞"), (follow, "关注"), (keep, "收藏")]
        where t.range(of: pattern, options: .regularExpression) != nil { return what }
        return nil
    }

    /// The goal says not to do this (不要点赞, 别关注…).
    static func forbids(_ task: String, _ what: String) -> Bool {
        AppNames.hans(task).range(of: #"(不要|不用|不必|别|勿|禁止|不能)[^，,。；;！!？?\n]{0,30}"# + what, options: .regularExpression) != nil
    }

    /// D28: the words on the screen where a tap lands (0-1 point), or nil.
    static func labelAt(_ p: CGPoint, in rows: [[CandidatePicker.Piece]]) -> String? {
        rows.joined().first { $0.box.insetBy(dx: -0.012, dy: -0.012).contains(p) }?.text
    }

    /// D28, user 11-15 (one video to 抖音, 快手, 小红书, 视频号, YouTube, TikTok…): a tap that would publish: on a button
    /// reading 发布 / 发表 / Post…, or one the model says is the publish button, in an app that publishes (any app when the
    /// button's words say so).
    static func publishTap(_ act: JObject, label: String?, app: String?) -> Bool {
        guard act["action"]?.str == "tap" else { return false }
        let words = ["发布", "发表", "发布作品", "发布笔记", "发布视频", "立即发布", "确认发布", "发布动态", "post", "publish",
                     "上传视频", "upload"]
        let shown = label.map { AppNames.hans($0).lowercased().filter { !$0.isWhitespace } } ?? ""
        if words.contains(shown) { return true }
        let publisher = ["抖音", "快手", "小红书", "微信", "视频号", "youtube", "tiktok", "微博", "哔哩哔哩", "b站", "西瓜视频", "今日头条"]
        guard let app, publisher.contains(where: { AppNames.hans(app).lowercased().contains($0) }) else { return false }
        var t = AppNames.hans(((act["thought"]?.str ?? "") + " " + (act["thought_zh"]?.str ?? "")).lowercased())
        t = t.replacingOccurrences(of: #"(不要|不用|避免|别|勿|以免|先不|暂不|don't|do not|avoid|not |without|before)[^，,。.；;]*"#,
                                   with: " ", options: .regularExpression)
        return t.range(of: #"点(击)?(右下角|底部|右上角)?的?(发布|发表)|(发布|发表)按钮|tap (the )?(post|publish)|(post|publish) button"#,
                       options: .regularExpression) != nil
    }

    static func publishQuestion(_ app: String?) -> String {
        "“\(app ?? "这个 App")”的内容已经填好，要发布吗？"
    }

    static let publishDeclinedReason = "Refused: the owner said not to publish here. Leave this page as it is (do not tap the "
        + "publish button), note that it was filled in and not published, and go on with the rest of the goal."

    static let emptyPartReason = "This part asks to find something out, but nothing was written down for it. Write what you "
        + "found with note (or note that it could not be found and why), then finish the part."

    /// 122.2 over the cloud 11-12: Weather's city row was tapped 11 times in a row (13 steps, 43 s): the pointer was not
    /// seen over its moving sky and no tap counted as one that did nothing. The same spot three times in a row, with
    /// nothing else between, is enough: the next is refused.
    static let sameTapLimit = 3
    // D193, x4 on 151 (item 10): 美团's coupon sheet ✕ at x 0.943 is past the pointer's calibrated reach; from the right
    // border it landed at 0.920, 0.205 each time, beside the ✕, eight taps, then the item was given up. A sheet closes
    // other ways as well.
    static let sameTapReason = "Refused: this spot was just tapped 3 times in a row and the task did not get on. It is not "
        + "the control you want: look at what else is on the screen, scroll, or go another way. A sheet's ✕ that does "
        + "nothing (a corner the pointer may not reach): swipe the sheet down from its top edge, or tap the dimmed page "
        + "above it, away from that page's buttons."
    /// D124: a swipe whose finger moves down (older messages, in a chat) while its thought wants newer ones.
    static func wantsNewerByOlderSwipe(_ act: JObject) -> Bool {
        guard let y1 = act["y1"]?.double, let y2 = act["y2"]?.double, y2 - y1 >= 200 else { return false }
        let thought = AppNames.hans((act["thought"]?.str ?? "") + " " + (act["thought_zh"]?.str ?? "")).lowercased()
        return thought.range(of: #"newer|scroll forward|back down|to the bottom|bottom of the chat|更新的|较新的|回到底部|到底部|滑到最下|最下面|往下翻|向下翻"#,
                             options: .regularExpression) != nil
    }
    static let olderSwipeReason = "Refused: in a chat a finger moving down (y 300 → 750) shows OLDER messages, further back. "
        + "Newer messages (toward today, at the bottom) come with the finger moving up: swipe from y 750 to y 300."

    /// D125: a goal asking for a chat's latest message(s).
    static func asksLatestMessage(_ task: String) -> Bool {
        AppNames.hans(task).range(of: #"最(后|新|近)的?[一二两三四五六七八九十几\d]*条|最新消息|最后发|最新发"#, options: .regularExpression) != nil
    }

    /// D125: since the app was last opened nothing took the chat to its bottom: no tap or back (a chat entered from the
    /// list opens at its bottom), and the last long swipe or read-up went back to older messages.
    static func mayBeScrolledUp(_ steps: [JObject]) -> Bool {
        guard let open = steps.lastIndex(where: { $0["action"]?.str == "open" }) else { return false }
        var down = false
        for s in steps[(open + 1)...] {
            switch s["action"]?.str {
            case "tap", "back": down = true
            case "readup": down = false
            case "swipe":
                let dy = (s["y2"]?.double ?? 0) - (s["y1"]?.double ?? 0)
                // D166, h03 over the cloud 11-19 (148): s6 had read 测试群 back to 11月17日; four swipes toward newer from
                // there were taken for the bottom, and "the last message" was X2首尔温差6度, hours older than the last.
                // A swipe toward newer that still moved the chat is not at its bottom; one that moved nothing is.
                if dy <= -200 { down = s["changed"] != .bool(true) } else if dy >= 200 { down = false }
            default: break
            }
        }
        return !down
    }
    static let scrolledUpReason = "Refused: WeChat opens a chat where it was left, and an earlier run may have scrolled it up: "
        + "the bottom of this screen need not be the latest message. Swipe the finger up (from y 750 to y 300) until nothing "
        + "moves, then tell the last message at the bottom. A swipe that still moved the chat did not reach its bottom."

    static let sameHoldReason = "Refused: this spot was just held 3 times in a row and showed the same each time. On a chart, a "
        + "hold that shows another time than the one wanted is moved by the difference: work out how far one hour is from the "
        + "time labels under the chart (the distance between two labels divided by the hours between them) and hold that much "
        + "further left (earlier) or right (later)."

    /// D120: how many times in a row, up to now, this app was opened (notes, waits and refusals between do not count).
    static func opensInARow(_ steps: [JObject], app: String) -> Int {
        let want = AppNames.hans(app).lowercased()
        var n = 0
        for s in steps.reversed() {
            let name = s["action"]?.str ?? ""
            if ["stale plan", "note", "refused", "wait"].contains(name) { continue }
            guard name == "open", AppNames.hans(s["app"]?.str ?? "").lowercased() == want else { break }
            n += 1
        }
        return n
    }

    static func reopenReason(_ app: String) -> String {
        "Refused: \(app) was just opened twice in a row, and it is the app in front now: the page you see is inside it (in 微信 "
            + "a 视频号 video, a mini program or an article can look like another app). Use the page's own back arrow (top left) "
            + "or close button, or its tabs, to get where you want."
    }

    /// D118, z3 on 143 (item 27): Taobao's 综合 sort menu was tapped three times and never opened: the hop there was
    /// not seen and clicked off it, and the page's moving cards made every tap count as one that changed the screen, so
    /// none was aimed. When the model says its last tap did nothing and taps the same spot again, that tap is aimed.
    static func saysTapDidNothing(_ thought: String) -> Bool {
        AppNames.hans(thought).lowercased().range(of: #"did not (open|work|respond|react|change|appear)|didn't (open|work|respond|react|change)|(is|was) not open|not open(ed)? yet|no effect|nothing happened|没(有)?(反应|打开|展开|弹出|变化|生效)|未(打开|展开|弹出|响应|生效)|还(是)?没(打开|展开|弹出|反应)|仍(然)?(未|没)"#,
                                                   options: .regularExpression) != nil
    }

    /// How many taps in a row, up to now, aimed at the same spot as `act` (notes, stale plans and refusals between
    /// them do not count as something else).
    /// D162, s4 over the cloud 11-19 (148): back at the top left, 资料设置 → 朋友资料 → 聊天信息 → 测试群, each tap to a page
    /// with another title; the fourth, from the chat to the list, was refused as a spot that does nothing, and the run
    /// went round. A tap that led to another page ends the run of taps: the spot is the same, the page under it is not.
    static func tapsInARow(_ steps: [JObject], like act: JObject) -> Int {
        var n = 0
        for s in steps.reversed() {
            let name = s["action"]?.str ?? ""
            if ["stale plan", "note", "refused"].contains(name) { continue }
            guard name == (act["action"]?.str ?? "tap"), sameSpot(s, act), s["newPage"] != .bool(true) else { break }
            n += 1
        }
        return n
    }

    /// 122 on the phone 11-12: "2027 年 1 月 1 日是星期几" was answered 星期三; it is a Friday. A date the goal names gets
    /// its weekday worked out here, not by the model.
    /// 134 over the cloud 11-15: dates without a year (12月25日) and the days from today too (y6 counted 99 for 84).
    static func dateFacts(in goal: String, today: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let said = dateLines(in: goal, today: today, calendar: calendar)
        return said.isEmpty ? "" : " Dates in the goal: " + said.joined(separator: "; ") + "."
    }

    /// D76, y1 on 138 (item 39): 2027年春节 was found to be 2027年2月6日 and the days to it were to be counted on the
    /// calculator. The actor noted "共88天" before it pressed a key (it is 81), then keyed 17 + 30 + 31 + 31 + 6 and never
    /// read the result, and the check let 88 stand: the date was in no goal. A date the notes found gets its weekday and
    /// its days from today worked out here too, the latest 20.
    static func foundDateFacts(_ notes: [String], goal: String, today: Date = Date(),
                               calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let known = Set(dateLines(in: goal, today: today, calendar: calendar))
        let found = dateLines(in: notes.joined(separator: "\n"), today: today, calendar: calendar).filter { !known.contains($0) }
        return found.isEmpty ? "" : " Dates the notes found, worked out on the phone (a count of days or a weekday that "
            + "differs is wrong): " + found.suffix(20).joined(separator: "; ") + "."
    }

    static func dateLines(in goal: String, today: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(\d{4})\s*(?:年|-|/|\.)\s*(\d{1,2})\s*(?:月|-|/|\.)\s*(\d{1,2})"#),
              let bare = try? NSRegularExpression(pattern: #"(?<![\d年/.\-])(\d{1,2})\s*月\s*(\d{1,2})\s*[日号號]"#) else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd, EEEE"
        let zh = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let ns = goal as NSString
        var said: [String] = []
        let now = calendar.startOfDay(for: today)
        func add(_ date: Date) {
            let away = calendar.dateComponents([.day], from: now, to: calendar.startOfDay(for: date)).day ?? 0
            let when = away == 0 ? "today" : away > 0 ? "\(away) days from today" : "\(-away) days ago"
            let line = "\(f.string(from: date)) (\(zh[calendar.component(.weekday, from: date) - 1])) \(when)"
            if !said.contains(line) { said.append(line) }
        }
        let full = re.matches(in: goal, range: NSRange(location: 0, length: ns.length))
        for m in full {
            guard let y = Int(ns.substring(with: m.range(at: 1))), let mo = Int(ns.substring(with: m.range(at: 2))),
                  let d = Int(ns.substring(with: m.range(at: 3))), (1...12).contains(mo), (1...31).contains(d),
                  let date = calendar.date(from: DateComponents(year: y, month: mo, day: d)),
                  calendar.component(.day, from: date) == d else { continue }
            add(date)
        }
        for m in bare.matches(in: goal, range: NSRange(location: 0, length: ns.length))
        where !full.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) {  // a date with its year: done above
            guard let mo = Int(ns.substring(with: m.range(at: 1))), let d = Int(ns.substring(with: m.range(at: 2))),
                  (1...12).contains(mo), (1...31).contains(d),
                  var date = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: mo, day: d)),
                  calendar.component(.day, from: date) == d else { continue }
            if date.timeIntervalSince(today) < -183 * 86_400, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
            add(date)
        }
        // D45, y2 on 136 (item 31): "用计算器和日历算出从今天起第100天是几月几号、星期几" was left 未完成. The day N days on is
        // worked out here too: "第N天" from today both ways (today as day 1, or N days on), "N天后" N days on.
        let weekday = { (d: Date) in zh[calendar.component(.weekday, from: d) - 1] }
        if let nth = try? NSRegularExpression(pattern: #"今天(?:起|开始|開始|算起)?\s*的?\s*第\s*(\d{1,4})\s*天"#) {
            for m in nth.matches(in: goal, range: NSRange(location: 0, length: ns.length)) {
                guard let n = Int(ns.substring(with: m.range(at: 1))), n > 0,
                      let first = calendar.date(byAdding: .day, value: n - 1, to: now),
                      let on = calendar.date(byAdding: .day, value: n, to: now) else { continue }
                let line = "day \(n) from today is \(f.string(from: first)) (\(weekday(first))) counting today as day 1, "
                    + "\(f.string(from: on)) (\(weekday(on))) counting \(n) days on"
                if !said.contains(line) { said.append(line) }
            }
        }
        if let after = try? NSRegularExpression(pattern: #"(\d{1,4})\s*天(?:后|後|以后|以後|之后|之後)"#) {
            for m in after.matches(in: goal, range: NSRange(location: 0, length: ns.length)) {
                guard let n = Int(ns.substring(with: m.range(at: 1))), n > 0,
                      let on = calendar.date(byAdding: .day, value: n, to: now) else { continue }
                add(on)
            }
        }
        return said
    }

    /// The numbered lines of a plan ("1. ...", "2) ...", "3、..."), trimmed.
    static func parts(of plan: String) -> [String] {
        plan.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{1,2}\s*[.)、．]"#, options: .regularExpression) != nil }
    }

    static let partSteps = 20       // steps on one part before Codex looks and drives

    /// The steps a part may take before Codex looks: 20, and 10 more for each further numbered thing it holds, at most
    /// 80. 127 over the cloud 11-12 (g1): a part with five of twenty things was "not getting on" at 20 steps with
    /// nothing failed, and Codex drove it at about twice the time a step.
    /// 128 over the cloud 11-13 (g1): Codex's parts name their things without numbers ("Results 13–15 and 17 are noted —
    /// open Safari…, 天氣…, 計算機…, 時鐘…"): the apps a part names count as its things too.
    static func partSteps(for part: String) -> Int {
        let ns = part as NSString
        let items = (try? NSRegularExpression(pattern: #"(?<![\d.])\d{1,2}[.、．](?!\d)"#))?
            .numberOfMatches(in: part, range: NSRange(location: 0, length: ns.length)) ?? 0
        let text = AppNames.hans(part).lowercased()
        let apps = Set(partApps.compactMap { names in names.contains { text.contains($0) } ? names[0] : nil }).count
        return min(partSteps + 10 * max(0, max(items, apps) - 1), 80)
    }

    /// Apps a part may name, each with its other names (Simplified, lowercased).
    static let partApps = [["微信", "wechat"], ["淘宝"], ["拼多多"], ["美团"], ["高德"], ["抖音"], ["safari", "浏览器"],
                           ["天气", "weather"], ["计算器", "计算机", "calculator"], ["时钟", "clock"], ["备忘录", "notes"],
                           ["日历", "行事历", "calendar"], ["京东"], ["小红书"]]
    static let troubleLimit = 3     // or this many steps that plainly failed

    /// D62, y3 on 137 (item 41): one turn of four sideways swipes on 日曆 after one swipe up made five in a row; the goal of
    /// 49 things skipped the thing at that first stall, and Codex never looked (日曆's months scroll up and down). In a
    /// goal of 10 things or more a stall of swipes gets one new plan, Codex driving; any other stall skips the thing at once.
    static func stallsToSkip(bigGoal: Bool, swiping: Bool) -> Int { bigGoal ? (swiping ? 2 : 1) : stallLimit }
    static let swipesInARow = 5     // or this many swipes in a row (a wheel: 14 wrong swipes, then one tap by Codex)

    /// A step that plainly failed: it changed nothing, or was refused, or a stroke left no ink.
    static func isTrouble(_ step: JObject) -> Bool {
        step["changed"] == .bool(false)
            || ["no ink", "blocked", "done rejected", "refused", "loop", "open failed"].contains(step["action"]?.str ?? "")
    }

    /// Whether two screens read the same: most of what was read still reads, in the same place (a video or an animation
    /// behind it moves; on a list that scrolled the words are the same and their places are not).
    /// Whether the goal asks for a chat's latest or most recent messages (最新的三条消息, 最近一条).
    /// 131 over the cloud 11-13: 测试群 opened in the middle of its history and "the latest three" were read off it as it
    /// was: in r131b g6 with no swipe at all, in g5 after one swipe up that still moved it (7-9 pm messages, not the G3/G5
    /// ones of 10-11 pm). What to say with the chat's message list, from the steps since the run came into the chat; nil
    /// once a swipe up there moved nothing (the bottom).
    static func chatBottomNote(_ steps: [JObject]) -> String? {
        for s in steps.reversed() {
            let action = s["action"]?.str ?? ""
            if action == "swipe" {
                guard let y1 = s["y1"]?.double, let y2 = s["y2"]?.double, y2 < y1 else { continue }  // down: older ones
                if s["changed"] == .bool(false) || s["scrolled"] == .bool(false) { return nil }
                return "The last swipe up still moved this chat, so newer messages may be below: swipe up again until the "
                    + "screen stops changing; only then is number 1 the newest."
            }
            if ["open", "tap", "back", "home", "type", "key", "press"].contains(action) { break }
        }
        return "It is not known yet that this is the bottom of the chat (a chat can open in the middle of its history): "
            + "before noting the latest messages, swipe up once (y 800 → 300); if nothing moves, number 1 is the newest."
    }

    static func asksLatestMessages(_ task: String) -> Bool {
        let t = AppNames.hans(task)
        return (t.contains("最新") || t.contains("最近")) && (t.contains("消息") || t.contains("条"))
    }

    /// 130 over the cloud 11-13: "the latest three" of a WeChat chat were read one short or out of order in 3 of 12 runs
    /// (the model counted bubbles off the picture). With a chat on the screen, its messages read off it, newest first,
    /// each with the grey time above it, for the model to count. nil: no chat title, or no message read.
    static func chatLines(_ rows: [[CandidatePicker.Piece]]) -> String? {
        guard let title = WatchReport.navigationTitle(rows: rows) else { return nil }
        let pieces = rows.joined().sorted { $0.box.midY < $1.box.midY }
        // Above the input bar: above the keyboard's own keys when it is up, else above the bottom bar.
        let keys: Set<String> = ["发送", "發送", "空格", "下一个", "下一個", "已填入：", "已填入", "按住说话", "按住 说话", "按住說話"]
        let bottom = pieces.filter { keys.contains($0.text) }.map { Double($0.box.minY) }.min().map { $0 - 0.09 } ?? 0.9
        var rowsOnScreen: [(y: Double, pieces: [CandidatePicker.Piece])] = []
        for p in pieces {
            let y = Double(p.box.midY)
            guard y > 0.14, y < bottom else { continue }
            if let i = rowsOnScreen.indices.last, abs(rowsOnScreen[i].y - y) < 0.012 {
                rowsOnScreen[i].pieces.append(p)
            } else {
                rowsOnScreen.append((y: y, pieces: [p]))
            }
        }
        let lines: [(y: Double, x: Double, right: Double, text: String)] = rowsOnScreen.map { row in
            let left = row.pieces.sorted { $0.box.minX < $1.box.minX }
            return (y: row.y, x: Double(left.first?.box.minX ?? 0), right: Double(left.map(\.box.maxX).max() ?? 0),
                    text: left.map(\.text).joined())
        }
        // The lines of one bubble (or a name and its bubble) are under 0.035 apart; a time stands alone. A line that starts
        // in the right half is mine; one that stays in the left half is someone else's; a full-width one cannot be told.
        var messages: [(side: String, text: String, time: String?)] = []
        var time: String?, lastY = -1.0, afterTime = true
        for line in lines {
            if WatchReport.timeLabel(line.text) { (time, afterTime) = (line.text, true); continue }
            if !afterTime, line.y - lastY < 0.035, !messages.isEmpty {
                messages[messages.count - 1].text += line.text
            } else {
                let side = line.x >= 0.4 ? "me (right, green)" : line.right < 0.62 ? "other (left)" : "a long message (side: see the picture)"
                messages.append((side: side, text: line.text, time: time))
            }
            (lastY, afterTime) = (line.y, false)
        }
        guard !messages.isEmpty else { return nil }
        let newestFirst = messages.reversed().prefix(8).enumerated().map { i, m in
            "\(i + 1). \(m.side): \(m.text)" + (m.time.map { "  [time above: \($0)]" } ?? "")
        }
        return "A WeChat chat is on the screen (\(title)). Its messages read off this screen, NEWEST FIRST (grey times are "
            + "not messages):\n" + newestFirst.joined(separator: "\n")
            + "\nThe latest N messages are numbers 1 to N here. Check them against the picture; when fewer than N are listed, "
            + "the older ones are above: swipe down a little to see them."
    }

    /// The words around a tap target (±0.09 across, ±0.06 down) on two looks are the same ones in the same places, with
    /// none gone and none new. A target with no words around it (an icon alone) cannot be told: false.
    static func sameWordsNear(_ a: [[CandidatePicker.Piece]], _ b: [[CandidatePicker.Piece]], around p: CGPoint) -> Bool {
        func near(_ q: CandidatePicker.Piece) -> Bool { abs(q.box.midX - p.x) <= 0.09 && abs(q.box.midY - p.y) <= 0.06 }
        func key(_ s: String) -> String { AppPlaces.normalized(s) }
        let before = a.joined().filter { near($0) && !key($0.text).isEmpty }
        let after = b.joined().filter { near($0) && !key($0.text).isEmpty }
        guard !before.isEmpty else { return false }
        func found(_ x: CandidatePicker.Piece, in list: [CandidatePicker.Piece]) -> Bool {
            list.contains { key($0.text) == key(x.text) && abs($0.box.midX - x.box.midX) < 0.02 && abs($0.box.midY - x.box.midY) < 0.012 }
        }
        return before.allSatisfy { found($0, in: after) } && after.allSatisfy { found($0, in: before) }
    }

    static func sameWords(_ a: [[CandidatePicker.Piece]], _ b: [[CandidatePicker.Piece]]) -> Bool {
        func words(_ rows: [[CandidatePicker.Piece]]) -> [CandidatePicker.Piece] { rows.flatMap { $0 }.filter { AppPlaces.normalized($0.text).count >= 2 } }
        let (x, y) = (words(a), words(b))
        guard x.count >= 3, !y.isEmpty else { return false }
        let kept = x.filter { p in
            y.contains { AppPlaces.normalized($0.text) == AppPlaces.normalized(p.text) && abs($0.box.midX - p.box.midX) < 0.02 && abs($0.box.midY - p.box.midY) < 0.01 }
        }
        return kept.count * 10 >= max(x.count, y.count) * 7
    }

    /// 133 over the cloud 11-14: goals of 24 to 50 things (x2, x3, x5, x6, y2, y3) and of 20 (g3, g6, c4) ended whole
    /// at one thing that would not go: three new plans with nothing got on, 25 refusals, or a loop after Codex had looked
    /// once; x3 stopped at item 3 of 26. Things of a goal that may fail and be skipped: one in five, at least two.
    static func itemFailsAllowed(_ task: String) -> Int { max(2, goalParts(task) / 5) }

    /// The run is stuck on one thing of a goal of several: it is written down as 未能完成, its part closed, the counters
    /// cleared, and Codex plans the rest. False (the caller stops the run) for a goal of one thing or when none are left.
    private func skipStuckThing(_ shot: Data?, _ why: String) async throws -> Bool {
        guard presetPlan.isEmpty else { return false }
        // D130, q133x on 144 (x4): item 12 was noted and 天气 opened for item 13 with part 12 still open; stuck in 天气,
        // "未能完成：第12项" was written (12 had its answer) and 13 was planned and skipped again. Parts already noted close
        // first: the stuck part is the one the work is in.
        skipPartsNoted()
        var why = why
        // A way learned for this step did not get it on: counted against the way (two misses and no win: dropped).
        if let tip = tryingTip { lessons?.tipResult(tip, worked: false); tryingTip = nil }
        // User 11-15: "这种问题以后出现了要让codex学会怎么解决…要让codex自己能解决这个问题". Before the thing is skipped,
        // the planner looks at what was tried and the screen, once per thing: a way that works in this app is kept as an
        // app tip (every later task naming the app gets it) and tried at once; a thing that cannot be done on this phone
        // now (a service off, a password, the app's error page) is skipped at once, without going round.
        let part = parts.count >= 2 && partIndex < parts.count ? parts[partIndex] : task  // one thing: the goal itself
        let key = Self.thingKey(part)
        if planner != nil, !part.isEmpty, coached.count < Self.coachLimit, coached.insert(key).inserted {
            switch try await coach(part, why: why) {
            case .way(let way):
                let app = Self.appInFront(steps, startedIn: startApp) ?? ""
                tryingTip = lessons?.learnAppTip(app: app, goal: part, text: way, run: trace?.dir?.lastPathComponent ?? "run")
                let line = "新学到的做法：" + way
                if !notes.contains(line) { notes.append(line) }
                (bounceGuard, bounceRefused, circleRefused, bounceOpener) = (nil, 0, 0, false)
                (stallsNoProgress, refusalsNoProgress, troubles, stepsInPart) = (0, 0, 0, 0)
                record(shot, ["action": .str("learned way"), "app": .str(app), "reason": .str(way)])
                try await replan(stuck: true)
                gotOn()
                return true
            case .blocked(let reason):
                why = "做不成：" + reason
            case .unknown:
                break
            }
        }
        // D132, x4 on 144: 美团 not signed in took two of the five skips. A thing the coach found cannot be done on this
        // phone now (sign-in, a service off) is a skip the goal allows, not the run going wrong: it spends nothing.
        let blocked = why.hasPrefix("做不成：")
        guard Self.goalParts(task) >= 3, itemFailsLeft > 0 || blocked else { return false }  // one thing: the run stops as before
        if !blocked { (itemFailsLeft, skipOwed) = (itemFailsLeft - 1, true) }
        let what = parts.count >= 2 && partIndex < parts.count ? Self.failedPartNote(parts[partIndex], why: why) : CloudBridge.failureWords(why)
        let line = "未能完成：" + String(what.prefix(160))
        if !notes.contains(line) { notes.append(line) }
        // D186: the note just written names this part's items; the part failing is this one.
        _ = closeFailedPart(why, by: nil, named: parts.count >= 2 && partIndex < parts.count ? Set(Self.partItems(parts[partIndex]) ?? []) : Set<Int>())
        (bounceGuard, bounceRefused, circleRefused, bounceOpener) = (nil, 0, 0, false)
        (stallsNoProgress, refusalsNoProgress, troubles, stepsInPart) = (0, 0, 0, 0)
        record(shot, ["action": .str("thing skipped"), "reason": .str(why + ". " + Self.oneThingFailedReason)])
        try await replan(stuck: true)
        gotOn()
        return true
    }

    /// Things (thingKey of the part) the planner was asked about in this run, and the app tip being tried now (its id).
    private var coached: Set<String> = []
    private var tryingTip: String?
    static let coachLimit = 6  // asks a run at most

    static func tracedPrompt(_ prompt: String) -> String {
        guard prompt.count > 2200 else { return prompt }
        return String(prompt.prefix(400)) + " … " + String(prompt.suffix(1600))
    }

    static func thingKey(_ s: String) -> String {
        String(AppNames.hans(s).lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }.prefix(80))
    }

    enum Coaching: Equatable { case way(String), blocked(String), unknown }

    /// D63, y3 on 137: the coach, not shown what is known of 日曆, gave "swipe the month grid left for later months" (its
    /// months scroll up and down); the way was kept, a later step got on and counted it as worked, and item 41 swiped
    /// left until it was skipped. The lines of the app rules that name the app go with the stuck steps.
    static func appRuleLines(_ app: String, rules: String = Prompts.appRules, limit: Int = 2000) -> String {
        let names = AppNames.variants(app).map { AppNames.hans($0).lowercased() }.filter { $0.count >= 2 }
        guard !names.isEmpty else { return "" }
        let lines = rules.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            let l = AppNames.hans(line).lowercased()
            return names.contains { l.contains($0) }
        }
        return String(lines.joined(separator: "\n").prefix(limit))
    }

    static let coachPrompt = """
    You coach an AI agent that operates an iPhone for its owner with a mouse pointer. It is stuck on one thing of a \
    longer goal. From the steps it tried and the screen now (the image), find why it did not work and what the right \
    way is IN THIS APP: one concrete method that works with this app's own screens (which page or list, which control, \
    which gesture), never "try again", "be careful" or screen coordinates. Reply with exactly one line, in the language \
    of the goal:
    WAY: <how to do this kind of step in this app, at most 80 characters: a method that works another day for another \
    goal, never this run's results, the numbers on the screen, or how far it got>
    or BLOCKED: <why it cannot be done on this phone now: a permission or service turned off, the app not installed, a \
    login, code or password needed, the app's own error page>
    or NONE when you cannot tell. Never suggest typing a password, paying, ordering, or changing a system setting.
    """

    static func parseCoaching(_ reply: String) -> Coaching {
        for raw in reply.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            for (tag, make) in [("WAY:", Coaching.way), ("BLOCKED:", Coaching.blocked)] where upper.hasPrefix(tag) {
                let text = line.dropFirst(tag.count).trimmingCharacters(in: .whitespaces)
                // A remembered spot is wrong once the screen moves (LessonBook.parseLessons).
                let spot = text.range(of: #"\d{2,4}\s*[,，]\s*\d{2,4}"#, options: .regularExpression) != nil
                // D30, 135 over the cloud 11-15 (y2): "深圳天气页的日落卡已显示日出6:36、日落17:40" and "第10项已听取并记录；当前在
                // 淘宝商品页" were kept as ways, and every later task in that app would get them. A way is a method: one that
                // tells this run's values (a time, a price, a percentage, an item number) or its progress is not kept.
                let runFact = tag == "WAY:" && text.range(of: runFactPattern, options: .regularExpression) != nil
                // D112b, 143 z5: "在商品页点“加入购物车”打开规格选择弹窗，查看默认选中规格" was kept for 淘宝; on a one-spec
                // item that tap puts it in the cart. A way that adds, buys or pays is never kept for later tasks.
                let spends = tag == "WAY:" && Self.waySpends(text)
                return text.isEmpty || spot || runFact || spends ? .unknown : make(String(text.prefix(160)))
            }
            if upper.hasPrefix("NONE") { return .unknown }
        }
        return .unknown
    }

    static func waySpends(_ way: String) -> Bool { tipSpends(way) }

    /// The planner looks at a stuck thing: what was tried (the last steps) and the screen now.
    private func coach(_ part: String, why: String) async throws -> Coaching {
        guard let planner else { return .unknown }
        let app = Self.appInFront(steps, startedIn: startApp) ?? "unknown"
        let tried = steps.suffix(16).compactMap { s -> String? in
            guard let a = s["action"]?.str, !["plan", "replan (stuck)", "planner drives"].contains(a) else { return nil }
            var line = a
            if let t = s["text"]?.str { line += " “\(t.prefix(40))”" }
            if let t = s["thought"]?.str { line += " — " + String(t.prefix(110)) }
            else if let r = s["reason"]?.str { line += " — " + String(r.prefix(110)) }
            if s["changed"] == .bool(false) { line += " (screen did not change)" }
            return line
        }
        let known = Self.appRuleLines(app)
        let prompt = "Goal: \(task)\n\nThe stuck thing: \(part)\nApp in front: \(app)\nWhy it stopped: \(why)\n\nLast steps:\n"
            + tried.joined(separator: "\n")
            + (known.isEmpty ? "" : "\n\nWhat is known of this app (a way against it is wrong):\n" + known)
        do {
            let (reply, _, _) = try await ask("planner", planner, Self.coachPrompt, prompt)
            DebugLog.write("coach: \(reply.replacingOccurrences(of: "\n", with: " ").prefix(200))")
            return Self.parseCoaching(reply)
        } catch let e where e is CancellationError || Task.isCancelled {
            throw e
        } catch {
            DebugLog.write("coach failed: \(error.localizedDescription)")
            return .unknown
        }
    }

    /// A guard saw the run go round: Codex looks afresh once, another way. If it goes round again the run stops. True: it stopped.
    private func changeOfPlan(_ shot: Data?, _ why: String) async throws -> Bool {
        guard !rescued else {
            // 129 over the cloud 11-13 (g8): item 4 opened the wrong lamp; the executor and then Codex went product page ↔
            // spec sheet (its ✕, then 加入购物车 again) and the whole twenty-thing run failed at 337 s with 3 things done.
            // A goal of several things leaves this one as 未能完成 and goes on with the rest (skipStuckThing).
            if try await skipStuckThing(shot, why) { return false }
            record(shot, ["action": .str("fail"), "reason": .str(why)])
            return true
        }
        rescued = true
        circleRefused = 0
        record(shot, ["action": .str("loop"), "reason": .str(why)])
        try await replan(stuck: true)
        // The new plan starts clean. Build 118, 11-11: Weather's map was opened twice by mistake, Codex planned "close the
        // map, open the list on the right", and its first move, closing the map, was refused as the old circle; the run
        // failed. A second circle under the new plan still fails (rescued).
        gotOn()
        return false
    }

    static let takeoverSteps = 15   // steps Codex drives after a stall, until its part is done

    /// D35: the model service's stock refusal (short, no THINK/DO): "抱歉，您的问题我无法识别", "你好，这个问题我无法回答",
    /// "抱歉，没有找到相关的结果", "你好，我无法给到相关内容". The service would not take the prompt; the model did not answer.
    static func serviceRefused(_ reply: String) -> Bool {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 40, !t.contains("DO"), !t.contains("THINK") else { return false }
        return t.range(of: #"^(抱歉|很抱歉|对不起|你好|您好)[，,。！!\s]*.*(无法|没有找到|未找到|不能|不便)"#,
                       options: .regularExpression) != nil
    }

    /// What the executor is told about its part (nothing for a plan of one part or a fixed plan).
    private var partFocus: String {
        guard parts.count >= 2, planner != nil, partIndex < parts.count else { return "" }
        var text = "Current part (\(partIndex + 1) of \(parts.count)): \(parts[partIndex])\n"
        if !doneParts.isEmpty { text += "Already done, with what it found: " + doneParts.joined(separator: " | ") + "\n" }
        return text + "Work on the current part only. When it is finished on the screen, answer done with what it achieved;"
            + " then the next part begins.\n\n"
    }

    /// Something was found or finished: coming back to a screen from here is the work, not a circle. A task of several
    /// parts goes back and forth by nature, and the guard stopped runs with the first part done (e01, f02, f06 on 11-09).
    private func gotOn() {
        (departures, circleRefused, bounceGuard, bounceRefused, deadRefused, bounceOpener) = ([], 0, nil, 0, 0, false)
        roundRefused = 0  // D129: one refusal in item 12 and one in 13 made the third, in item 14, a change of plan
        pressRuns = [:]
        stepsSinceProgress = 0
    }

    /// Steps since something was last found, sent or finished (gotOn), or new text was written (typedNewText).
    private var stepsSinceProgress = 0

    /// D78, y2 on 138 (item 46): writing 45 results into a memo is a type and a return a line. 30 steps of new lines went
    /// in, the thing was skipped as "no result in 30 steps" and the owner was told 第46项 未能完成; the memo was finished
    /// later, after three new plans. Text not typed before, of 20 characters or more, is the work getting on; a search
    /// typed again, or a short one, is not.
    static func typedNewText(_ step: JObject, earlier: ArraySlice<JObject>) -> Bool {
        let clean = { (s: JObject) in (s["text"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        guard step["action"]?.str == "type", clean(step).count >= 20 else { return false }
        return !earlier.contains { $0["action"]?.str == "type" && clean($0) == clean(step) }
    }
    static let bigGoalPatience = 30

    /// Key presses (typedKey of the press text) since something was last found or finished.
    private var pressRuns: [String: Int] = [:]
    static let samePressReason = "Refused: you already pressed exactly these keys 3 times. They went in: a calculator shows "
        + "only the end of a long expression, so its start looks missing when it is not. Read the result line instead. With "
        + "brackets in the sum, the calculator does × and ÷ before + and −: press = after the bracketed part, then go on "
        + "from that result. Note the result and go on with the next thing."

    /// A list is scrolled from the screen's margin: a press that starts on a button can click it (over USB 11-09 three
    /// swipes each moved a permission sheet a step on). Measured in Settings: from the margin it scrolls the same. Not from
    /// the floating bars at the bottom either. What the margin does not move (a time picker) gets the model's own spot.
    static let marginX = 40
    static let homeBarTop = 900.0

    /// D184, h22 on 148 (r148h2b three times, r148hb once): on Baidu's results for 深圳天气 a swipe up from the margin
    /// (x 0.04) began on the weather card, a link edge to edge but for a thin border, and Safari opened its page instead
    /// of scrolling (a pointer pressed on a link and moved drags the link, and dropped it opens). The same swipe from a
    /// spot with no link scrolled. In a browser the margin is the page's very edge, outside the cards.
    static let browserMarginX = 12
    static func inBrowser(_ steps: [JObject], startedIn: String?, thought: String) -> Bool {
        let words = ["safari", "浏览器", "chrome"]
        if let app = appInFront(steps, startedIn: startedIn) {
            let name = AppNames.hans(app).lowercased()
            return words.contains { name.contains($0) }
        }
        let said = AppNames.hans(thought).lowercased()
        return (words + ["百度", "baidu", "网页", "web page", "webpage"]).contains { said.contains($0) }
    }

    static func safeSwipe(_ act: JObject, after steps: [JObject], browser: Bool = false) -> JObject {
        guard let x1 = act["x1"]?.double, let y1 = act["y1"]?.double, let x2 = act["x2"]?.double, let y2 = act["y2"]?.double,
              abs(x2 - x1) < 100, abs(y2 - y1) > 100 else { return act }
        if let last = steps.last(where: { $0["action"]?.str != "stale plan" }), last["action"]?.str == "swipe",
           last["changed"] == .bool(false) || last["scrolled"] == .bool(false) {
            // D176, x2 over the cloud 11-19 (148): Calendar's year view did not move from the margin, so the model's own
            // "swipe 500 1000 500 350" went as it was: from the home bar, and the phone went to its Home Screen. The
            // run then took that for a picture, dragged it down (Spotlight) and lost 2027. The model's spot, but never
            // from the home bar.
            let low = max(0, max(y1, y2) - homeBarTop)
            guard low > 0 else { return act }
            var own = act
            own["y1"] = .int(Int(y1 - low)); own["y2"] = .int(Int(y2 - low))
            return own
        }
        let shift = max(0, max(y1, y2) - 800)
        var safe = act
        let margin = browser ? browserMarginX : marginX
        safe["x1"] = .int(margin); safe["x2"] = .int(margin)
        safe["y1"] = .int(Int(y1 - shift)); safe["y2"] = .int(Int(y2 - shift))
        return safe
    }

    static let doneCheck = """
    You check another agent's finished work on an iPhone. You get the goal, its answer, what it did and noted, and the screen now.
    Reply with exactly one line: OK, or NO: what is wrong, in a few words.
    Say NO only for one of these:
    - Something the goal asks for was not done or is missing from the answer.
    - A value in the answer (date, number, price, name, count) differs from the notes or from what the screen shows.
    - The answer reports something from an app the steps never opened.
    - The answer says something was sent or saved, the screen is where it would show, and it does not show.
    - The goal names no city or place and the answer is for a city an app kept from before, not the phone's own location.
    - A cart or order on the screen holds more of an item than the goal asked for (×3 for one cup), or the answer leaves out how many.
    The screen may have moved on: what was noted or done earlier stands unless the screen contradicts it. Work out dates from today's date. Never judge style or wording, nor the answer's language.
    A page that does not name the city, chat or item it is about (Weather's hourly chart, a detail sheet, a picture) is no contradiction: which one it is comes from the steps (the search typed and the result tapped). Never say NO only because the screen does not show that name.
    What the run itself changed after reading it is no contradiction: it read a chat's latest messages and then sent more there, or counted a cart and then added to it. The answer stands as read at the time.
    A note, memo or document has no separate title field: its first line is its title.
    In a list of days (a 10-day forecast), today's row is first and tomorrow is the row right under it; a weekday name further down is a later week. An answer for "tomorrow" read off a lower row is wrong.
    An app counts as opened when a step opened it, or tapped its icon (a tap that says it opens the app).
    Simplified and traditional Chinese of the same words are the same (压力测试 = 壓力測試). A value that moves by itself (a live price, a time, a count) may differ a little from the screen now: that is not wrong.
    A message that was to carry the time at the top of the screen carries the time when it was typed; the screen's time now is later (the run went on), so a message sent an hour ago with an earlier time is right.
    A line "程序按时间行算出" in the notes is worked out by the program from the chat itself (a time line heads the messages under it): it is right; never say NO against it.
    A message the steps typed and then sent with enter counts as sent, unless that chat is on the screen and it is not there.
    A recommended feed or a search result list (小红书, 抖音, 视频号, 淘宝, 拼多多…) can show other items, or the same in another order, each time it is opened: what was noted from it earlier stands. Never say NO because the list on the screen now differs from what was noted.
    Weather's 10-day forecast starts with 今天 and runs ten days, so weekday names come twice: 明天 is the row right under 今天, and a later row with the same weekday is a week on. An answer for today or tomorrow read from a later row is wrong: say NO.
    """

    /// The models have no clock. Over USB 11-09, today the 9th: a check said next Wednesday was the 25th and threw out the right
    /// answer, the 18th, and the run went on to "today is 2025-06-03" and its step limit.
    static func todayLine(_ date: Date = Date(), goal: String = "", found: [String] = []) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd, EEEE"
        // Build 117 on the phone: the check worked a weekday out wrong from a forecast. The next two days are given too.
        let day = { (n: Int) in f.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: date) ?? date) }
        return "Today is \(f.string(from: date)). Tomorrow is \(day(1)); the day after is \(day(2))." + dateFacts(in: goal)
            + (found.isEmpty ? "" : foundDateFacts(found, goal: goal, today: date)) + mathFacts(in: goal) + invoiceFacts(in: goal)
    }

    /// D29, user 11-15 (每月申请发票): for a goal about 发票, the owner's invoice details from Settings › 发票资料; "" for any
    /// other goal.
    static func invoiceFacts(in goal: String, profile: InvoiceProfile = .load()) -> String {
        guard AppNames.hans(goal).contains("发票") else { return "" }
        guard !profile.title.isEmpty else {
            return " The owner has not filled in 发票资料 in Lan Agent's settings: where an invoice form needs 抬头 or 税号, leave "
                + "that one not done and say the owner should fill in 发票资料 first."
        }
        return " The owner's invoice details (Lan Agent settings › 发票资料), to fill in exactly as given: 抬头类型 \(profile.kind); 抬头 "
            + profile.title + (profile.taxID.isEmpty ? "" : "; 税号 " + profile.taxID)
            + (profile.email.isEmpty ? "" : "; 邮箱 " + profile.email) + "."
    }

    /// D24, 135 over the cloud 11-15 (y1 item 30): "(12345 × 678 − 9876) ÷ 3.5" was keyed as 12345 × 678 − 9876 ÷ 3.5 =
    /// and 8,367,… was noted (2,388,581.14). The goal's sums are worked out on the phone and given with the date facts, so
    /// a calculator result that differs shows the keys were wrong. "" when the goal has none.
    static func mathFacts(in goal: String) -> String {
        var facts: [String] = []
        let allowed = Set("0123456789. ()（）×*÷/+-−√")
        var runs: [String] = [], current = ""
        for ch in goal {
            if allowed.contains(ch) { current.append(ch) } else { runs.append(current); current = "" }
        }
        runs.append(current)
        for raw in runs {
            var s = raw.trimmingCharacters(in: .whitespaces)
            // a bracket of the words around it (a note in （…）) is not part of the sum
            while let c = s.first, "()（）".contains(c), !sumBalanced(s) { s.removeFirst(); s = s.trimmingCharacters(in: .whitespaces) }
            while let c = s.last, "()（）".contains(c), !sumBalanced(s) { s.removeLast(); s = s.trimmingCharacters(in: .whitespaces) }
            guard s.count >= 3, s.contains(where: { "×*÷/√−".contains($0) }), s.contains(where: { $0.isASCII && $0.isNumber }),
                  s.range(of: #"^\d{2,4}/\d{1,2}(/\d{1,2})?$"#, options: .regularExpression) == nil,  // a date, 2026/12/25
                  sumBalanced(s), let value = sumValue(s), value.isFinite, !facts.contains(where: { $0.hasPrefix(s + " =") })
            else { continue }
            facts.append(s + " = " + sumPlain(value))
        }
        if let re = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*的\s*(\d{1,2})\s*次方"#) {
            let ns = goal as NSString
            for m in re.matches(in: goal, range: NSRange(location: 0, length: ns.length)) {
                guard let b = Double(ns.substring(with: m.range(at: 1))), let e = Double(ns.substring(with: m.range(at: 2))) else { continue }
                let line = ns.substring(with: m.range) + " = " + sumPlain(pow(b, e))
                if !facts.contains(line) { facts.append(line) }
            }
        }
        guard !facts.isEmpty else { return "" }
        return " Sums in the goal, worked out on the phone (a calculator result that differs means the keys were wrong: key a "
            + "bracketed part first and press = before the rest): " + facts.joined(separator: "; ") + "."
    }

    static func sumBalanced(_ s: String) -> Bool {
        var depth = 0
        for c in s {
            if c == "(" || c == "（" { depth += 1 } else if c == ")" || c == "）" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }

    /// + − × ÷ with brackets and √ (a minus sign may be - or −); nil for anything else.
    static func sumValue(_ s: String) -> Double? {
        var reader = SumReader(s)
        guard let v = reader.sum(), reader.atEnd else { return nil }
        return v
    }

    static func sumPlain(_ v: Double) -> String {
        if abs(v) < 1e15, abs(v - v.rounded()) < 1e-9 { return String(Int64(v.rounded())) }
        var t = String(format: "%.6f", v)
        while t.hasSuffix("0") { t.removeLast() }
        return t
    }

    private struct SumReader {
        let chars: [Character]
        var i = 0
        init(_ s: String) { chars = Array(s.filter { !$0.isWhitespace }) }
        var atEnd: Bool { i == chars.count }
        func peek() -> Character? { i < chars.count ? chars[i] : nil }
        mutating func sum() -> Double? {
            guard var v = product() else { return nil }
            while let c = peek(), c == "+" || c == "-" || c == "−" {
                i += 1
                guard let r = product() else { return nil }
                v = c == "+" ? v + r : v - r
            }
            return v
        }
        mutating func product() -> Double? {
            guard var v = factor() else { return nil }
            while let c = peek(), c == "×" || c == "*" || c == "÷" || c == "/" {
                i += 1
                guard let r = factor() else { return nil }
                v = c == "×" || c == "*" ? v * r : v / r
            }
            return v
        }
        mutating func factor() -> Double? {
            guard let c = peek() else { return nil }
            if c == "√" { i += 1; return factor().map { $0.squareRoot() } }
            if c == "-" || c == "−" { i += 1; return factor().map { -$0 } }
            if c == "(" || c == "（" {
                i += 1
                guard let v = sum(), let close = peek(), close == ")" || close == "）" else { return nil }
                i += 1
                return v
            }
            var digits = ""
            while let d = peek(), d.isASCII, d.isNumber || d == "." { digits.append(d); i += 1 }
            return Double(digits)
        }
    }

    /// Over USB 11-09, 5 of 14 "done" were wrong: a Pinduoduo price from an app never opened, a message never sent, the 17th
    /// read off a screen saying the 16th. The model's word is not the result: something else looks. What it says, or nil when
    /// nothing is wrong or the check itself failed (a check must not stop the work).
    private func wrongClaim(_ answer: String, frame: Data?) async -> String? {
        guard let model = doneChecker ?? planner ?? actor else { return nil }
        let prompt = checkPrompt(answer)
        do {
            let reply = try await model.chat(system: Self.doneCheck, text: prompt, image: frame, maxTokens: 120, temperature: 0).text
            trace?.write(kind: "done check", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("done check: \(reply.prefix(160))")
            return Self.wrongness(reply)
        } catch {
            DebugLog.write("done check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func checkPrompt(_ answer: String) -> String {
        Self.checkPrompt(goal: task, today: Self.todayLine(goal: task, found: notes), answer: answer, did: Self.whatItDid(steps), notes: notes,
                         sent: sent, parts: max(parts.count, Self.goalParts(task)))
    }

    /// Build 121 over the cloud 11-11: goals of 7 and 8 parts were answered right and reported "（未能核實）": the check saw
    /// only the last screen (高德, 验证群), so the battery read in Settings and the message sent to 测试群 earlier were "not
    /// on screen", twice. What it wrote down and what it sent go with the check now, and why the screen cannot show them.
    static func checkPrompt(goal: String, today: String, answer: String, did: String, notes: [String], sent: [String],
                            parts: Int) -> String {
        var text = "Goal: \(goal)\n\(today)\n\nIts answer: \(answer)\n\nWhat it did:\n\(did)"
        if !notes.isEmpty {
            text += "\n\nWhat it wrote down while it worked (read off earlier screens):\n" + notes.map { "- " + $0 }.joined(separator: "\n")
        }
        if !sent.isEmpty { text += "\n\nMessages it sent in this run and saw go out: " + sent.joined(separator: "、") }
        if parts > 1 {
            text += "\n\nThis goal has \(parts) parts done one after another, and the screen shows only where the last one ended. "
                + "A value or a send from an earlier part is checked against what it did and wrote down above, not against this "
                + "screen: call it wrong only when this screen or those lines contradict it."
                // D33, y5 on 135: "淘宝首个保温杯价格记为¥12，当前屏幕显示为¥9.5" — ¥12 was read off the search list for item
                // 7, and the screen was a shop page of other cups for item 44. Refused twice; the run ended worse.
                + " This screen contradicts a value only when it shows that very thing (the same product, place or message "
                + "on the same kind of page); another page, list or product with a different number is no contradiction."
        }
        return text + "\n\nThe image is the screen now."
    }

    /// The same answer again after the quick check refused it: the check may be the one that is wrong. Build 117 on the
    /// phone, 11-10: it worked out today as Monday from a forecast, and once took the second headline for the first; right
    /// answers were reported "not checked" or cost a round. The planner (Codex) looks once; only its OK counts, so a
    /// failed call changes nothing.
    private func confirmedBySecondModel(_ answer: String, frame: Data?) async -> Bool {
        guard let second = planner, second !== (doneChecker ?? planner ?? actor) else { return false }
        do {
            let reply = try await second.chat(system: Self.doneCheck, text: checkPrompt(answer), image: frame, maxTokens: 120, temperature: 0).text
            trace?.write(kind: "done check (second)", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("done check (second model): \(reply.prefix(160))")
            return Self.wrongness(reply) == nil
        } catch {
            DebugLog.write("done check (second model) failed: \(error.localizedDescription)")
            return false
        }
    }

    static func wrongness(_ reply: String) -> String? {
        let line = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        guard line.range(of: #"^NO\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let why = line.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: " :：,，-"))
        return checkSays + (why.isEmpty ? "the answer is not supported" : why) + checkFix
    }

    static let checkSays = "A check of the finished work says: "
    static let checkFix = ". Fix it on the phone or correct the answer, then finish again."

    /// D32, y5 on 135: Codex drove parts to "done 第39项：(12345 × 678 − 9876) ÷ 3.5 = 2,388,581.14" and "done 第11项：2027年2月共有
    /// 4个星期一…", and that went only into the list of parts done, which a plan of one part never shows. The last part (Codex,
    /// "第49项：report all") answered from the notes: 未记录 for 11, 22, 35, 38, 39, 40 and more. What a part found is a note
    /// like any other, headed with its item; nil when it says nothing.
    // MARK: D149, user 11-19 ("token也是错啊"): fewer input tokens a step, the same things told

    /// 145's regression (1742 executor steps, 23:25–03:49): 16,000 input tokens a step, 10,600 from Ark's prefix cache (the
    /// system prompt) and 5,400 at the full price: the screenshot (~590×1280, about 960 tokens) and ~4,400 of text. The text
    /// told the same things again every step: the whole plan with its parts done, each part done with what it found (also
    /// in the notes), a 1500-character goal (x4), and the circle bounds a drawing needs, in every task.

    /// The drawing hints go to a goal that draws, or to a run that drew already.
    static func drawsOnScreen(_ task: String, steps: [JObject]) -> Bool {
        AppNames.hans(task).range(of: #"画|描|涂|draw|sketch|circle|圆圈"#, options: [.regularExpression, .caseInsensitive]) != nil
            || steps.contains { ["circle", "path"].contains($0["action"]?.str ?? "") }
    }

    /// A goal this long goes at the end of the system prompt, which Ark's prefix cache bills at a fifth from the second step.
    static let goalInSystemChars = 400
    static let goalAboveLine = "Goal: at the end of the system prompt (GOAL OF THIS RUN)."

    static func goalLine(_ task: String) -> String {
        task.count >= goalInSystemChars ? goalAboveLine : "Goal: \(task)"
    }

    static func systemWithGoal(_ system: String, task: String, prompt: String) -> String {
        prompt.hasPrefix(goalAboveLine) ? system + "\n\nGOAL OF THIS RUN (the owner's words, the same for every step):\n" + task : system
    }

    /// The plan without the lines of the parts already done.
    static func planLeft(_ plan: String, parts: [String], from index: Int) -> String {
        guard parts.count >= 2, index >= 1 else { return plan }
        let done = Set(parts.prefix(index))
        let kept = plan.components(separatedBy: "\n").filter { !done.contains($0.trimmingCharacters(in: .whitespaces)) }
        return "(parts 1–\(min(index, parts.count)) are done and left out)\n" + kept.joined(separator: "\n")
    }

    /// What a part found stays beside the part in partFocus ("1. read a price -> 價格 19": the next part needs to know
    /// which part found it; StressNightTests), and the note partFinished made of the same words is what is left out of
    /// the executor's step: notes whose words (after their 第N项：) a part done already shows whole.
    static func notesNotShown(_ notes: [String], in done: [String]) -> [String] {
        let found = done.compactMap { d -> String? in
            guard let r = d.range(of: " -> ") else { return nil }
            return String(d[r.upperBound...])
        }
        guard !found.isEmpty else { return notes }
        return notes.filter { note in
            let body = note.replacingOccurrences(of: #"^\s*第\s*\d{1,3}\s*[项項]\s*[：:]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return body.count < 4 || !found.contains { $0.contains(body) }
        }
    }

    static func partResultNote(part: String, found: String) -> String? {
        let t = found.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = t.replacingOccurrences(of: #"[\s。．.!！]"#, with: "", options: .regularExpression)
        guard bare.count >= 4, !["已经完成", "已完成了", "已做完了"].contains(bare) else { return nil }
        let item = #"^第\s*\d{1,3}\s*[项項]"#
        guard let head = part.range(of: item, options: .regularExpression), t.range(of: item, options: .regularExpression) == nil
        else { return t }
        return part[head].replacingOccurrences(of: " ", with: "") + "：" + t
    }

    /// The executor's (or Codex's) "done" on a plan of several parts: the next part begins, the last one ends the run.
    /// A part Codex rescued is done: the executor takes the next one. True: the run goes on.
    /// D142, s7 on 145 (小红书, three notes): part 2 was finished with "笔记2（YESKY数码）：发布日期01-22；设置步骤已在早前运行中
    /// 读出，无需再打开" and never opened in this run; the check found the three named were not the top three. What a run
    /// before this one saw is no result of this one.
    static func fromAnEarlierRun(_ text: String) -> Bool {
        AppNames.hans(text).range(of: #"(早前|之前|上次|上一次|此前|以前|先前|前一次)的?(运行|任务|执行|测试|对话|那次)"#,
                                  options: .regularExpression) != nil
    }

    static let earlierRunReason = "Not done: what an earlier run found is no result of this run (the page can have changed "
        + "since). Open it again now and write down what the screen shows."

    private func partFinished(_ act: JObject, shot: Data?) -> Bool {
        guard parts.count >= 2, partIndex < parts.count else { return false }
        let n = partIndex + 1
        // What a part found is what the next one needs: a price read in one app goes into a message in another.
        let found = String((act["answer"]?.str ?? "").prefix(300))
        if earlierRunRefused != partIndex, Self.fromAnEarlierRun(found) {  // D142
            earlierRunRefused = partIndex
            record(shot, ["action": .str("part not done"), "part": .int(n), "reason": .str(Self.earlierRunReason)])
            return true
        }
        // B8, 122 over the cloud 11-12: the 视频号 part of an 11-part goal was finished with nothing found or written
        // down, and its result was simply missing. A part that asks to find something out is sent back once.
        if found.isEmpty, notes.count == notesAtPart, emptyPartRefused != partIndex, Self.readsSomething(parts[partIndex]) {
            emptyPartRefused = partIndex
            record(shot, ["action": .str("part not done"), "part": .int(n), "reason": .str(Self.emptyPartReason)])
            return true
        }
        // D69, y5 on 137: a stuck replan put items 10–21 into one part; the executor did 10–15, 20, 21 (and 28), said
        // "当前部分（第10–21项）全部完成" with a made-up line for the rest (16 "定位服务关闭", 18 and 19 "已记录"), and 16–19 were
        // never started. A part over a run of items is done when each of them is in a note written on the way (what was
        // found, or why it could not be); what the "done" itself says of them does not count. Sent back twice at most.
        if let run = Self.partItemRange(parts[partIndex]), rangeRefused.part != partIndex || rangeRefused.times < 2 {
            let missing = Self.itemsLeft(task: task, told: notes + doneParts, sent: messageSent).filter { run.contains($0) }
            if !missing.isEmpty {
                rangeRefused = (partIndex, rangeRefused.part == partIndex ? rangeRefused.times + 1 : 1)
                DebugLog.write("part \(n) not done: nothing noted for items \(missing)")
                record(shot, ["action": .str("part not done"), "part": .int(n), "reason": .str(Self.itemsLeftInPartReason(missing))])
                return true
            }
        }
        doneParts.append(found.isEmpty ? parts[partIndex] : parts[partIndex] + " -> " + found)
        let line = Self.partResultNote(part: parts[partIndex], found: String((act["answer"]?.str ?? "").prefix(600)))
        if let line, !notes.contains(line) { notes.append(line) }
        // D72: what the part found goes on its record, so a run that stops later still sends it back (foundNotes).
        var done: JObject = ["action": .str("part done"), "part": .int(n), "by": .str(act["by"]?.str ?? "actor")]
        if let line { done["found"] = .str(line) }
        record(shot, done)
        if let tip = tryingTip { lessons?.tipResult(tip, worked: true); tryingTip = nil }  // the way learned worked
        gotOn()
        (stallsNoProgress, refusalsNoProgress) = (0, 0)
        (partIndex, stepsInPart, notesAtPart) = (partIndex + 1, 0, notes.count)
        skipPartsNoted()
        if act["by"]?.str == "planner" { takeover = 0 }
        return partIndex < parts.count
    }

    /// D82: the parts next whose items were all noted on the way are done (partsNoted).
    private func skipPartsNoted(named: Set<Int> = []) {
        let k = Self.partsNotedBefore(Self.partsNoted(parts, from: partIndex, task: task, told: notes + doneParts, sent: messageSent),
                                      parts: parts, from: partIndex, named: named)
        for _ in 0..<k {
            doneParts.append(parts[partIndex] + " -> 已在前面记录")
            record(nil, ["action": .str("part done"), "part": .int(partIndex + 1), "reason": .str("its items were noted on the way")])
            partIndex += 1
        }
        if k > 0 { DebugLog.write("parts: \(k) already noted on the way; part \(partIndex + 1) is next") }
    }

    /// D71, y6 on 137: on 抖音's and 视频号's playing feeds every look differs, and the stale-plan guard dropped the swipe to
    /// the next video four and five times in a row (item 20 never got past its first video; both times a stuck replan
    /// followed); seven opens of an app were dropped as well. An app is opened by its name, a back swipe starts at the edge,
    /// and a long up-or-down swipe scrolls whatever moved under it: none of them aims at a spot that can move.
    static func staleProof(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "open", "back": return true
        case "swipe":
            let p = pointerPath(act)
            guard p.count == 2 else { return false }
            let (dx, dy) = (abs(p[1].x - p[0].x), abs(p[1].y - p[0].y))
            return dy >= 0.2 && dy > 2 * dx
        default: return false
        }
    }

    /// D69: the run of goal items a part is over ("第10–21项：…" → 10...21); nil for a part of one item.
    /// D80, y3 on 138: a plan's parts keep their own number ("3. 第21–30项：…"), so the range was never found and D69 never
    /// ran: the executor said "第21–30项已完成：…第24项待后续记录；…第28项待后续记录；…", part 3 was done, and 24 and 28 were
    /// never started. The part's own number goes before the range.
    static func partItemRange(_ part: String) -> ClosedRange<Int>? {
        guard let re = try? NSRegularExpression(pattern: #"^\s*(?:\d{1,2}\s*[.)、．]\s*)?第\s*(\d{1,3})\s*[–—\-~～至到]\s*(?:第\s*)?(\d{1,3})\s*[项項]"#),
              let m = re.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)),
              let a = Range(m.range(at: 1), in: part).flatMap({ Int(part[$0]) }),
              let b = Range(m.range(at: 2), in: part).flatMap({ Int(part[$0]) }),
              a < b, b - a <= 40 else { return nil }
        return a...b
    }

    static func itemsLeftInPartReason(_ missing: [Int]) -> String {
        "Not done: nothing is written down yet for " + missing.map { "第\($0)项" }.joined(separator: "、")
            + ". Do them now in order and note each one headed with its item (or why it cannot be done); then finish the part."
    }

    /// D65, y3 on 137 (item 20): the check said tomorrow is 11月17日 (周二), not 11月18日; the note on the phone was put
    /// right, and the answer written from the run's notes at the end said 11月18日 again. The objection is kept as a note.
    /// D95, z4 on 139: the note kept "A check of the finished work says: … Fix it on the phone or correct the answer, then
    /// finish again." as it was, and when Codex's whole answer could not be used the notes went to the owner, English and
    /// all. The note keeps what the check said, without the words for the run.
    static func objectionNote(_ wrong: String) -> String {
        var why = Substring(wrong)
        if let r = why.range(of: checkSays) { why = why[r.upperBound...] }
        if let r = why.range(of: checkFix) { why = why[..<r.lowerBound] }
        return "核对更正（以此为准，改掉前面相应的记录）：" + String(why.prefix(300))
    }

    /// A fail right after a refused one, with nothing done since, is the same item again (c3, 132): free twice in a row.
    static func failIsRepeat(refusedAt: Double, lastActed: Double, free: Int) -> Bool {
        refusedAt >= 0 && lastActed <= refusedAt && free < 2
    }

    static let alreadyNotedReason = " That item is already noted as 未能完成: do not report it again; start the next item now."

    /// The part now open, for a refusal ("" without parts, or when every part is closed).
    private var nextPartText: String {
        parts.count >= 2 && partIndex < parts.count ? " Next part (\(partIndex + 1) of \(parts.count)): \(parts[partIndex])" : ""
    }

    /// A refused fail closes the part it was in as 未能完成, so the next part is worked on: the run kept the part that
    /// cannot be done open, and Codex failed on it again and again (c3, 132). Returns what the refusal says about the next part.
    private func closeFailedPart(_ why: String, by: String?, named: Set<Int>? = nil) -> String {
        if let tip = tryingTip { lessons?.tipResult(tip, worked: false); tryingTip = nil }
        guard parts.count >= 2, partIndex < parts.count else { return "" }
        skipPartsNoted(named: named ?? Self.itemsNamed(why))  // D130; D186: never past the part the fail names
        doneParts.append(parts[partIndex] + " -> 未能完成：" + String(why.prefix(80)))
        record(nil, ["action": .str("part failed"), "part": .int(partIndex + 1)])
        gotOn()
        (partIndex, stepsInPart, notesAtPart) = (partIndex + 1, 0, notes.count)
        skipPartsNoted()
        if by == "planner" { takeover = 0 }
        return nextPartText
    }

    /// The executor gave up: Codex takes over once before the user is asked. Never after a message went out (it must
    /// not go twice), nor when Codex itself gave up.
    private func rescue() async throws -> Bool {
        guard let last = steps.last, last["action"]?.str == "fail", last["by"]?.str == "actor",
              planner != nil, !rescued, sentTexts.isEmpty else { return false }
        rescued = true
        try await replan(stuck: true)
        return true
    }

    /// What a run did, for the check: every app opened, text typed and note, and the last taps. Over USB 11-10 50 calculator
    /// taps pushed the opening of 淘寶 and 拼多多 out of the last 40 lines, and the check said they were never opened.
    /// D175, x1 over the cloud 11-19 (148): the 22 results went into the note in one type (839 characters) and the note
    /// held them all, but the check got the first 80 ("…3. 淘宝首个蓝牙耳机") with the screen showing 13-22, said "仅写到第3项开头"
    /// twice, and the run typed the whole record twice more into the note and ended "（未能核實）". A long text typed is
    /// told by its start and end and its length: the middle left out is not missing.
    static func typedForCheck(_ text: String) -> String {
        guard text.count > 180 else { return text }
        return String(text.prefix(80)) + " … " + String(text.suffix(80))
            + " (\(text.count) characters typed in one go; the middle is left out here, not missing)"
    }

    static func whatItDid(_ steps: [JObject], taps: Int = 20) -> String {
        let tapIndices = steps.indices.filter { steps[$0]["action"]?.str == "tap" }
        let kept = Set(tapIndices.suffix(taps))
        return steps.indices.compactMap { i -> String? in
            let s = steps[i]
            switch s["action"]?.str {
            case "open": return "opened " + (s["app"]?.str ?? "?")
            case "type": return "typed " + Self.typedForCheck(s["text"]?.str ?? "")
            case "press": return "pressed the keys " + String((s["text"]?.str ?? "").prefix(80))
            case "note": return "noted " + String((s["text"]?.str ?? "").prefix(200))
            case "listen": return "listened to the video and read its subtitles (the text is in the notes)"
            case "readup": return "read back up the chat (what it read is in the notes)"
            case "hold": return "long-pressed at (\(s["x"]?.int ?? 0), \(s["y"]?.int ?? 0))"
            case "key" where sends(s): return "pressed enter"
            // Over USB 11-10 拼多多 was opened by its icon on the Home Screen, and the check said it never was: that tap
            // had dropped out of the last 20 and its words were cut at 60.
            case "tap" where opensByIcon(s): return "tapped " + String((s["thought"]?.str ?? "").prefix(120))
            // Over USB 11-09 a note was reopened from the list, twice, and the check said it never was: it saw no taps.
            case "tap" where kept.contains(i): return "tapped " + String((s["thought"]?.str ?? "").prefix(60))
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// A tap that says it opens an app by its icon (the Home Screen), in the model's own words.
    static func opensByIcon(_ step: JObject) -> Bool {
        guard step["action"]?.str == "tap", let t = step["thought"]?.str?.lowercased() else { return false }
        let icon = ["圖示", "图示", "圖標", "图标", "icon", "主畫面", "主画面", "主屏", "home screen"].contains { t.contains($0) }
        let opens = ["打開", "打开", "開啟", "开启", "啟動", "启动", "open", "launch"].contains { t.contains($0) }
        return icon && opens
    }

    /// D155, h22 over the cloud 11-19 (147): Baidu's page was still loading after a wait; the model asked to wait again,
    /// was told twice that it "changed nothing last time", and the run went to a stuck plan (the planner then drove into a
    /// 149-second open of the Safari it was in). A loading page changes nothing until it has loaded: up to three waits in
    /// a row go through.
    static let waitsInARow = 3
    static func mayWaitAgain(_ act: JObject, steps: [JObject]) -> Bool {
        guard act["action"]?.str == "wait" else { return false }
        let between: Set<String> = ["stale plan", "hiccup"]
        let trailing = steps.reversed().filter { !between.contains($0["action"]?.str ?? "") }
            .prefix(while: { $0["action"]?.str == "wait" }).count
        return trailing < waitsInARow
    }

    /// A remembered way as the plan: its steps as hints, not numbered parts.
    static func rememberedPlan(_ recipe: RouteBook.Recipe) -> String {
        "Do it the way it was done before; adapt any text, time or name to this goal. Where the next steps are clear, "
            + "answer several DO lines at once (each step costs seconds of thinking), and look at the result. "
            + "The earlier run may have begun somewhere else (already inside a chat or a page): before typing, check that the "
            + "screen is where this goal says (the title at the top), and go there first if it is not:\n"
            + recipe.lines.map { "- " + $0 }.joined(separator: "\n")
    }

    func replan(stuck: Bool = false, rest: [Int] = [], first: String? = nil) async throws {
        guard let planner else { throw LLMError(message: "no planner model") }
        var prompt = Self.goalLine(task) + "\n" + Self.todayLine(goal: task, found: notes)  // D149
        // D16: a new plan of a goal of 10+ things names the things left, so it does not stop at the next few.
        let left = rest.isEmpty && stuck && presetPlan.isEmpty
            ? Self.itemsLeft(task: task, told: notes + doneParts, sent: messageSent) : rest
        if !rest.isEmpty {
            prompt += "\n\nThe last plan is finished:\n\(plan)"
            if !doneParts.isEmpty {
                prompt += "\n\nAlready done and checked on the screen (never redo): " + doneParts.joined(separator: " | ")
            }
        }
        if stuck {
            let last = steps.last ?? JObject()
            prompt += "\n\nThe previous plan got stuck (last event: \(pyStr(last["action"])) \(last["reason"]?.str ?? "")):"
                + "\n\(plan)\nLook at the current screen and plan from here, another way if needed."
                + "\nKeep steps that already succeeded; resume from the current screen."
                + "\n\nRecent actions:\n\(recentActions)"
            if !doneParts.isEmpty {
                prompt += "\n\nAlready done and checked on the screen (never redo): " + doneParts.joined(separator: " | ")
                    + "\nPlan only what is left."
            }
        }
        if let first {  // D23: what must come before anything else (an install the owner just allowed)
            prompt += "\n\nThe new plan's part 1, before any other part: " + first
        }
        if !left.isEmpty {
            prompt += "\n\n" + Self.itemsLeftLine(left)
        } else if presetPlan.isEmpty, Self.goalParts(task) >= 10 {
            // y5: a thing skipped was planned again at once (its part had no number, so nothing showed it was given up).
            prompt += "\n\nOne part per thing of the goal, each starting with 第N项： (N = its number in the goal)."
        }
        prompt += notesText
        let asked = try await ask("planner", planner, plannerPrompt, prompt)
        var (reply, seconds) = (asked.0, asked.1)
        let frame = asked.2
        if Self.holdsToolCall(reply) {  // D157
            DebugLog.write("plan: the reply called a tool; asking once more for plain numbered steps")
            let again = try await ask("planner", planner, plannerPrompt, prompt + Self.noToolCallsLine)
            (reply, seconds) = (again.0, seconds + again.1)
        }
        let (en, zh) = Actions.parsePlan(Self.withoutToolCalls(reply))
        // build105 live 11-08: Plus timed out, and the fallback answered {"action":"search",...}, which became the plan.
        if !plan.isEmpty, en.isEmpty || en.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            DebugLog.write("plan: the reply was not a plan; keeping the last one")
        } else {
            plan = en
            (parts, partIndex, stepsInPart) = (Self.parts(of: en), 0, 0)
        }
        record(frame, ["action": .str(stuck ? "replan (stuck)" : "plan"), "plan": .str(en), "plan_zh": .str(zh),
                       "think_s": .num(seconds)])
        if stuck {
            takeover = Self.takeoverSteps
            record(nil, ["action": .str("planner drives"),
                         "reason": .str("the executor did not get on: Codex drives until this part is done, at most \(Self.takeoverSteps) steps")])
        }
    }

    /// D157, 147 over the cloud 11-19: 20 of 191 plans ended in the model's own tool-call markup ("我会按顺序完成剩余的所有
    /// 项目……<seed:tool_call><function name="open_app">…"), and that text was the plan: x2 went through six stuck plans and
    /// took 1901 s (145: 987 s), s3 replanned into "<seed:tool_call><function name="list_available_functions">". A reply
    /// that calls a tool is asked once more for plain steps, and what it says after the markup is never part of the plan.
    static func holdsToolCall(_ reply: String) -> Bool {
        reply.contains("<seed:tool_call") || reply.contains("<function=") || reply.contains("<function name=")
    }
    static func withoutToolCalls(_ reply: String) -> String {
        let cut = ["<seed:tool_call", "<function=", "<function name="].compactMap { reply.range(of: $0)?.lowerBound }.min()
        return cut.map { String(reply[..<$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? reply
    }
    static let noToolCallsLine = "\n\nYour last answer called a tool. There are no tools or functions here: answer with "
        + "the plan only, numbered steps in plain text (1. … 2. …)."

    /// D149: the notes for the executor's step, less those partFocus already shows with their part.
    private var stepNotesText: String {
        let shown = parts.count >= 2 && planner != nil && partIndex < parts.count ? doneParts : []
        let kept = Self.notesNotShown(notes, in: shown)
        return kept.isEmpty ? "" : "\n\nYour notes from this run (already read: use them, never go back to read these again):\n"
            + kept.map { "- " + $0 }.joined(separator: "\n")
    }

    /// The notes, for a prompt ("" when there are none).
    private var notesText: String {
        notes.isEmpty ? "" : "\n\nYour notes from this run (already read: use them, never go back to read these again):\n"
            + notes.map { "- " + $0 }.joined(separator: "\n")
    }

    private var recentActions: String {
        // actions and their effect only: echoing earlier thoughts makes the model repeat them instead of looking
        let hidden: Set<String> = ["t", "plan", "plan_zh", "think_s", "act_s", "shot", "thought", "thought_zh", "changed", "by"]
        let history = steps.suffix(8).filter { $0["plan"] == nil }.map { s -> String in
            let effect = s["changed"] == .bool(true) ? " -> screen changed"
                : s["changed"] == .bool(false) ? " -> screen did NOT change" : ""
            return String(PyJSON.dumps(s.without(hidden)).prefix(300)) + effect
        }.joined(separator: "\n")
        return history.isEmpty ? "(none)" : history
    }

    func nextActions() async throws -> [Planned] {
        guard let actor else { throw LLMError(message: "no actor model") }
        let index = steps.count - 1
        if index > learnedThrough, let last = steps.last {
            learnedThrough = index
            if let frame = shots[index] ?? screen?.frame, let scene = Vision.experienceScene(frame), let image = Vision.image(frame) {
                experience?.observeUnconfirmedTap(goal: task, scene: scene,
                    aspect: Double(image.width) / Double(image.height), action: last)
            }
        }
        // D149: the plan without the parts done (they are in partFocus), the goal as goalLine.
        var prompt = Self.goalLine(task) + "\n" + Self.todayLine(goal: task, found: notes) + "\n\nPlan:\n"
            + Self.planLeft(plan, parts: parts, from: partIndex) + "\n\n\(partFocus)Recent actions:\n\(recentActions)\(stepNotesText)"
            + (Self.scrollingHint(steps).map { "\n\n" + $0 } ?? "") + "\n\nNext action?"
        let driving = (plannerLeads || takeover > 0 || actorClosed) && planner != nil
        if takeover > 0 { takeover -= 1 }
        if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil { prompt += "\n\n" + Self.sendVerificationReason }
        if let controls, let shown = screen?.frame {
            if unsent != nil, let hit = controls.find("send", in: shown) {
                prompt += "\n\nLearned on this phone: this screen's send button is at x \(Int(Double(hit.point.x) * 1000)), "
                    + "y \(Int(Double(hit.point.y) * 1000)); a message went out from there before. Tap it there once the text is complete."
            }
            if let hit = controls.find("back", in: shown) {
                prompt += "\n\nLearned on this phone: on this screen the back swipe does nothing; to go back, tap the back "
                    + "button at x \(Int(Double(hit.point.x) * 1000)), y \(Int(Double(hit.point.y) * 1000))."
            }
        }
        // Phase B (specs/004): the text read on this phone with where it is, so a labelled control is tapped where it
        // really is instead of where the model estimates it from the picture.
        // 127 over the cloud 11-12 (g3): the text read came from the frame cached before the look (the page before the
        // search), the picture from a fresh one (the results): "今天油价"'s first result was answered as 中国银行, the old
        // page's. The frame is made fresh first, read, and the same one is sent as the picture.
        var readFrame: Data?
        if readsScreenText, screen?.live == true {
            try? await screen?.requireFrame(after: nil)
            readFrame = screen?.frame
        }
        if let shown = readFrame {
            readRows = await CandidatePicker.rowsOffMain(in: shown, top: 0.055, bottom: 1)
        } else {
            readRows = []
        }
        // D18: what showed only while the last hold was down (a chart's value under the finger).
        if let held = heldFrame {
            heldFrame = nil
            var after = readRows
            if after.isEmpty, let shown = screen?.frame { after = await CandidatePicker.rowsOffMain(in: shown, top: 0.055, bottom: 1) }
            let heldRows = await CandidatePicker.rowsOffMain(in: held, top: 0.055, bottom: 1)
            let words = Self.shownOnlyWhileHeld(heldRows, now: after)
            if !words.isEmpty {
                prompt += "\n\nShown only while your finger was held down (gone once it let go): " + words
                DebugLog.write("hold: shown only while held: " + words)
            }
        }
        // 125 stress test 11-12 (s01): 加入购物车 was tapped again and again and the cart held ×5 of a cup the goal asked
        // for once. Each time the "added" toast comes up it is written down, and the model is told at once.
        // 131 over the cloud 11-13 (r131b g3): two of three counts were read in 备忘录 (an old note's "…台灯已加入购物车", then
        // the model's own "淘宝雨伞两次出现加购成功提示"), and the done check took the cart to hold three umbrellas.
        let frontApp = Self.appInFront(steps, startedIn: startApp)
        let cartToast = Self.addedToCart(readRows) && Self.sellsThings(frontApp)
        // In 美团 / 饿了么 each + that changed the screen is one add (no toast comes); a toast as well is not counted twice.
        var tapAdded = false
        let cartItemHead = Self.cartItemHead(part: parts.count >= 2 && partIndex < parts.count ? parts[partIndex] : nil,
                                             goalParts: Self.goalParts(task))
        if Self.addsWithoutToast(frontApp) {
            for i in min(cartTapsChecked, steps.count)..<steps.count where steps[i]["action"]?.str == "tap"
                && steps[i]["changed"] != .bool(false) && Self.addsDish(steps[i]["thought"]?.str ?? "", in: frontApp) {
                tapAdded = true
                cartAdds += 1
                cartAddsIn[AppNames.hans(frontApp ?? "").lowercased(), default: 0] += 1
                let line = cartItemHead + Self.cartTapNote(cartAdds)  // D148
                notes.append(line)
                prompt += "\n\n" + line
            }
            if tapAdded { gotOn() }
        }
        cartTapsChecked = steps.count
        if cartToast, !cartToastShown, !tapAdded {
            cartAdds += 1
            cartAddsIn[frontApp.map { AppNames.hans($0).lowercased() } ?? "", default: 0] += 1
            let line = cartItemHead + Self.cartNote(cartAdds)  // D148
            notes.append(line)
            gotOn()
            prompt += "\n\n" + line
        }
        cartToastShown = cartToast
        // 132 over the cloud 11-14 (g5, g7): "待收货 1 个" with no order anywhere: the cursor disk sat on the icon.
        if pointerAt != .zero { prompt += "\n\n" + Self.cursorNote(pointerAt) }
        appErrorLooks = Self.appErrorShown(readRows) ? appErrorLooks + 1 : 0
        if appErrorLooks >= 3 { prompt += "\n\n" + Self.appErrorNote }
        if Self.locationOffShown(readRows) { prompt += "\n\n" + Self.locationOffNote }
        if Self.screenTimePasscodeShown(readRows) {
            prompt += "\n\n" + Self.screenTimePasscodeNote
        } else if Self.screenTimeShown(readRows) {
            prompt += "\n\n" + Self.screenTimeNote
        }
        if readsScreenText, let list = Self.screenText(readRows) {
            prompt += "\n\nText read on this screen (\"text\" x y, 0-1000; tap these coordinates for a labelled control):\n" + list
        }
        if Self.inChatApp(steps, task: task) {  // D115
            let title = WatchReport.navigationTitle(rows: readRows)
            if let line = Self.chatPlaceLine(title, after: lastGroupTitle, task: task, steps: steps) { prompt += "\n\n" + line }
            if let title, Self.looksLikeGroup(title) { lastGroupTitle = title }
        }
        // Only inside a chat app, under a chat title the goal names: a note titled 第5组记录 has a centred title too, and
        // its lines must never be listed as messages.
        if Self.asksLatestMessages(task), Self.inChatApp(steps, task: task),
           let title = WatchReport.navigationTitle(rows: readRows), Self.goalNamesChat(title, task: task),
           let chat = Self.chatLines(readRows) {
            prompt += "\n\n" + chat
            // Before the run sends anything: what it sends lands at the bottom, and the latest it reads come before that.
            if sentTexts.isEmpty, let bottom = Self.chatBottomNote(steps) { prompt += "\n" + bottom }
        }
        if ourKeyboardOnScreen?() == true {
            prompt += "\n\nThe keyboard on screen is the app's own (\"Lan Agent 輸入法\"): the field is focused, use type."
        }
        var reply = ""
        for attempt in 0..<3 {  // retry unparseable replies, a little less deterministically
            let (text, seconds, frame) = try await ask("actor", driving ? planner ?? actor : actor, actorPrompt, prompt,
                                                       temperature: 0.4 * Double(attempt), pinned: readFrame)
            reply = text
            var acts: [JObject]
            do { acts = try Actions.parseActions(text) } catch {
                if driving, !actorClosed {  // Codex answered with no action: Doubao goes on rather than Codex being asked again and again
                    (takeover, plannerLeads) = (0, false)
                    DebugLog.write("takeover: Codex's reply held no action; the executor goes on")
                    return try await nextActions()
                }
                // D35, y6 on 135: once a note held a news line naming a state leader (read off a memo), Doubao's service
                // answered 13 looks with its stock refusal ("抱歉，您的问题我无法识别"), three tries each, and every one
                // became a stuck plan. The service would not read this look: Codex takes this one step.
                if Self.serviceRefused(text), planner != nil, refusalRedirectAt != steps.count {
                    refusalRedirectAt = steps.count
                    takeover = max(takeover, 1)
                    DebugLog.write("actor: the model service would not read this look (\(text.prefix(30))); Codex takes this step")
                    return try await nextActions()
                }
                prompt += "\n\nYour previous reply could not be parsed (\(String(error.localizedDescription.prefix(160))))."
                    + " No action from that reply was executed."
                    + " Reply with one brief THINK line followed immediately by valid DO lines; no extra explanation."
                continue
            }
            if missed, let last = lastObservedAction, acts[0]["action"] == .str("home"),
               last["action"] == .str("home") || last["home_recovery"] == .bool(true) {
                if !homeRecoveryTried {
                    homeRecoveryTried = true
                    return [Planned(act: ["action": .str("key"), "combo": .str("cmd+h"), "home_recovery": .bool(true),
                                          "reason": .str("Home changed nothing; trying keyboard Home once"),
                                          "think_s": .num(seconds)], shot: frame)]
                }
                return [Planned(act: ["action": .str("fail"),
                                      "reason": .str("Home changed nothing after the keyboard fallback; the Home route could not be verified"),
                                      "think_s": .num(seconds)], shot: frame)]
            }
            if missed, let last = lastObservedAction, Actions.sameTarget(acts[0], last), !recoveringSend(acts[0]),
               !Self.mayWaitAgain(acts[0], steps: steps) {
                if acts[0]["action"] == .str("tap") {
                    if last["precise"] == .bool(true) {
                        let reason = "tap target unchanged after a precision retry; inspect another route, keep completed work"
                        return [Planned(act: ["action": .str("replan"), "reason": .str(reason), "think_s": .num(seconds)], shot: frame)]
                    }
                    // The reply is syntactically valid. Spend one closed-loop aim attempt rather than asking
                    // the model the same question three times and misreporting it as a parsing failure.
                    acts[0]["precise"] = .bool(true)
                    acts[0]["think_s"] = .num(seconds)
                    return [Planned(act: acts[0], shot: frame)]
                }
                prompt += "\n\nYou just proposed \(PyJSON.dumps(Actions.key(acts[0]))) again, but it changed nothing last "
                    + "time. Choose a different action (another position, a shorter swipe, or another way)."
                continue
            }
            acts[0]["think_s"] = .num(seconds)
            for i in acts.indices { acts[i]["by"] = .str(driving ? "planner" : "actor") }
            return acts.map { Planned(act: $0, shot: frame) }
        }
        throw Actions.ParseError(message: "actor gave no valid action: \(reply.prefix(200))")
    }

    /// Half the size of the text a tap lands on (a little smaller than its box): the tap is surely on it inside that.
    /// 122.1 on the phone: only 10 of 60 taps used it; the model aims at a button's middle, its label's box is smaller,
    /// so a tap up to 1.2% outside the text counts as on it (122.2).
    static func textHalf(at p: CGPoint, in rows: [[CandidatePicker.Piece]]) -> (x: Double, y: Double)? {
        for piece in rows.joined() where piece.box.insetBy(dx: -0.012, dy: -0.012).contains(p) {
            let hx = Double(piece.box.width) / 2 * 0.8, hy = Double(piece.box.height) / 2 * 0.8
            return hx > 0.008 || hy > 0.008 ? (hx, hy) : nil
        }
        return nil
    }

    private func perform(_ a: JObject) async throws {
        guard let phone else { throw DeviceError(message: "no phone") }
        func p(_ k: String) -> Double { (a[k]?.double ?? 0) / 1000 }
        switch a["action"]?.str {
        case "tap":
            // D118: the same spot again after the model said the last tap there did nothing: aimed.
            let again = lastTap.map { abs(Double($0.x) - p("x")) <= 0.03 && abs(Double($0.y) - p("y")) <= 0.03 } ?? false
                && Self.saysTapDidNothing((a["thought"]?.str ?? "") + " " + (a["thought_zh"]?.str ?? ""))
            lastTap = CGPoint(x: p("x"), y: p("y"))
            if let half = Self.textHalf(at: CGPoint(x: p("x"), y: p("y")), in: readRows) { phone.aimLoosely(half.x, half.y) }
            try await phone.tap(p("x"), p("y"), aim: (a["precise"]?.bool ?? false) || missed || aimNext || again)
            aimNext = false
        case "swipe":
            // D109: up or down a feed of one video a screen (抖音, 快手): one quick stroke, as a finger does.
            if let pointer = phone as? Pointer,
               Self.flicks(app: Self.appInFront(steps, startedIn: startApp), p("x1"), p("y1"), p("x2"), p("y2"))
                || Self.turnsSideways(after: steps, thought: a["thought"]?.str ?? "", p("x1"), p("y1"), p("x2"), p("y2")) {
                try await pointer.flick(p("x1"), p("y1"), p("x2"), p("y2"))
            } else {
                try await phone.swipe(p("x1"), p("y1"), p("x2"), p("y2"), hold: true)
            }
        case "hold":
            // D18, 134 over the cloud 11-15 (y4, y5): Weather's page for tomorrow shows an hour's value (下午3時) only under
            // a finger held on its chart, and every look came after the finger let go: ten minutes of swipes, then
            // skipped. The screen is caught while held; the next look is told what showed only then (nextActions).
            heldFrame = nil
            let caught = screen
            try await phone.longPress(p("x"), p("y"), seconds: 0.8, whileHeld: { [weak self] in
                guard let caught, caught.live else { return }
                try? await caught.requireFrame(after: now() - 0.5)  // 0.1 s after the press or later
                self?.heldFrame = caught.frame
            })
        case "listen":
            // User 11-11: a video's spoken words (口播文案) and what it is about, from WeChat, 抖音, 视频号.
            guard let listen else { throw DeviceError(message: "Listening is not available here.") }
            let seconds = min(max(a["seconds"]?.double ?? 60, 5), 180)
            let earlier = notes.filter { $0.hasPrefix("听到和字幕") }
            let heard = await listen(seconds)
            notes.append("听到和字幕（\(Int(seconds)) 秒）：" + String(heard.prefix(4000)))
            // 124 on the phone 11-12 (h07): a short 抖音 video plays round and round, and it was listened to six times
            // over. Heard again is heard all.
            if Self.repeatsHeard(heard, before: earlier) {
                listenedAll = true
                notes.append(Self.videoLoopedNote)
            }
        case "readup":
            // D27, user 11-15 (客户场景: 微信群或个人聊天记录爬楼): reading back through a chat was a swipe and a model call a
            // screen. Up to readUpScreens screens are scrolled and read on the phone, the text only, until the words
            // given or the top (nothing moves), and what was read goes into the notes oldest first.
            let targets = Self.readUpTargets(a["until"]?.str ?? "")  // D133
            var screens: [[String]] = [], last: [String] = [], top = false, still = 0
            var chat: String?, untitled = 0  // D172
            for i in 0..<Self.readUpScreens {
                guard let frame = await freshFrame() else { break }
                // D172: the chat read is the one under the title the read began with (the bar only, not the messages).
                let title = WatchReport.navigationTitle(rows: await CandidatePicker.rowsOffMain(in: frame, top: 0.02, bottom: 0.12))
                if i == 0 {
                    chat = title
                } else if Self.leftChat(chat, title, untitled: untitled) {
                    DebugLog.write("readup: the screen is no longer \(chat ?? "-") (\(title ?? "no title")): stopped, nothing more read")
                    break
                }
                untitled = title == nil ? untitled + 1 : 0
                let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.1, bottom: 0.88).map(Self.readUpLine)
                // D143, s6 on 145: "一直读到11月14日" stopped after 5 screens at 11月17日凌晨 as "the top": nothing moved
                // once, while WeChat was loading older messages (or the swipe was lost). The top is the same screen after
                // two more swipes, each after a wait.
                if i > 0, rows == last {
                    if still >= Self.readUpStillTries { top = true; break }
                    still += 1
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    let x = still == 1 ? 0.5 : Self.readUpX  // D164
                    try await phone.swipe(x, 0.32, x, 0.78, hold: true)
                    await screen?.settled()
                    continue
                }
                still = 0
                screens.append(rows)
                last = rows
                if rows.contains(where: { row in
                    let bare = AppNames.hans(row).filter { !$0.isWhitespace }
                    return targets.contains { bare.contains($0) }
                }) { break }
                try await phone.swipe(Self.readUpX, 0.32, Self.readUpX, 0.78, hold: true)  // D164
                await screen?.settled()
            }
            notes.append(Self.readUpNote(Self.readUpMerge(screens), screens: screens.count, until: a["until"]?.str ?? "", top: top))
        case "path":
            let pts = a["smooth"]?.bool == true ? smoothCurve(points(a)) : points(a)
            try await phone.drag(pts.map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }, hold: true)
        case "circle":
            // A small circle (an eye) came out as an open arc, its first or last bit lost: go a quarter turn
            // further so the ends overlap.
            try await phone.drag(circle(p("x"), p("y"), p("r"), aspect: screen?.aspect ?? 9 / 19.5,
                                        extra: p("r") < 0.06 ? 0.25 : 0), hold: true)
        case "type":
            let text = a["text"]?.str ?? ""
            if fastText || Pasteboard.prefersExact(text) || (Pasteboard.needed(text) && keyboardType != nil) {
                try await typeFast(text)
            } else { try await phone.type(text) }
        case "key":
            let combo = a["combo"]?.str ?? ""
            if ["enter", "return"].contains(combo.lowercased()), ourKeyboardOnScreen?() == true,
               let keyboardReturn, await keyboardReturn() { break }
            try await phone.key(combo)
        case "press":
            guard let shown = screen?.frame else { throw DeviceError(message: "no screen to find the keys on") }
            // Over USB 11-10 Calculator took typed sums at once (128*0.85= gave 108.8, esc cleared it), while reading its
            // keys found 9 of 19 labels and three cloud tasks gave up there. Typed first; the read keys only if nothing changed.
            let text = a["text"]?.str ?? ""
            // D64: "2x" may be the 2ˣ key: the screen's keys are read first to tell.
            var read: [CandidatePicker.Piece]? = nil
            if Self.namesFunctionKey(text) { read = await CandidatePicker.rowsOffMain(in: shown, top: 0.1, bottom: 1).flatMap { $0 } }
            if let typed = Self.typedKeys(Self.keyTokens(text, keys: Set((read ?? []).map { Self.keyLabel($0.text) }))) {
                for piece in typed {
                    if piece == "esc" { try await phone.key("esc") } else { try await phone.type(piece) }
                }
                if let after = await freshFrame(), Vision.changed(shown, after) {
                    DebugLog.write("press: typed \(typed.joined(separator: " ")) on the keyboard")
                    break
                }
                DebugLog.write("press: typing changed nothing; tapping the keys")
            }
            var pieces = read ?? []
            if read == nil { pieces = await CandidatePicker.rowsOffMain(in: shown, top: 0.1, bottom: 1).flatMap { $0 } }
            let found = Self.keySpots(text, in: pieces)
            if found.missing.isEmpty, !found.spots.isEmpty {
                for spot in found.spots {
                    try await phone.tap(Double(spot.x), Double(spot.y), aim: false)
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            } else if Self.typedKeys(Self.keyTokens(text, keys: Set(pieces.map { Self.keyLabel($0.text) }))) == nil,
                      let mixed = Self.mixedKeys(text, in: pieces) {
                // D64: keys the screen reading missed (0, =) but the keyboard has are typed; the function keys tapped.
                DebugLog.write("press: typed what the keyboard has, tapped the rest")
                for step in mixed {
                    switch step {
                    case .type(let run): if run == "esc" { try await phone.key("esc") } else { try await phone.type(run) }
                    case .tap(let spot):
                        try await phone.tap(Double(spot.x), Double(spot.y), aim: false)
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                }
            } else {
                throw KeysNotOnScreen(missing: found.missing, seen: Self.keysSeen(pieces))
            }
        case "home": try await phone.goHome()
        case "back": try await phone.goBack()
        case "open":
            let app = a["app"]?.str ?? ""
            guard let openApp else { throw DeviceError(message: "Opening apps by name is not available here; use the Home Screen.") }
            guard try await openApp(app) else { throw AppNotOnPhone(name: app) }
        case "wait": break
        case let other: throw Actions.ParseError(message: "unknown action \(other ?? "nil")")
        }
    }

    /// Show a run without running it (demo data).
    func showMock(task: String, plan: String, steps: [JObject], running: Bool) {
        self.task = task
        self.plan = plan
        self.steps = steps
        self.running = running
    }

    /// Python's str() of a value in an f-string (None for a missing key).
    private func pyStr(_ v: JValue?) -> String {
        guard let v else { return "None" }
        if case .str(let s) = v { return s }
        return PyJSON.dumps(v)
    }
}

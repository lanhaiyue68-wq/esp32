import Foundation

/// What an owner's message can use besides the phone's own screen (user 11-11): a chat's recent talk summed up, the
/// listed GitHub repositories read (code, files, runs, commits, issues), and the endpoints listed in Settings (the
/// customer's server: nothing is known of it yet, so it is a list of names and addresses filled in later).
/// Reading tools only read. An endpoint that is not a GET changes something: it waits for the owner's "确认".
enum OwnerTools {
    static let githubTokenAccount = "watch-github-token", apiTokenAccount = "watch-api-token"  // Keychain
    static let reposKey = "watchGitHubReposV1", endpointsKey = "watchEndpointsV1"

    struct Endpoint: Equatable { var name: String; var method: String; var url: String; var about: String }

    enum Call: Equatable {
        case summary(chat: String, hours: Int)
        case githubSearch(repo: String, query: String)
        case githubFile(repo: String, path: String)
        case githubList(repo: String, path: String)
        case githubRuns(repo: String)
        case githubCommits(repo: String)
        case githubIssues(repo: String)
        case api(Endpoint, json: String)
    }

    static var repos: [String] { repos(from: UserDefaults.standard.string(forKey: reposKey) ?? "") }
    static var endpoints: [Endpoint] { endpoints(from: UserDefaults.standard.string(forKey: endpointsKey) ?? "") }
    static var githubToken: String { (Keychain.get(githubTokenAccount) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var apiToken: String { (Keychain.get(apiTokenAccount) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "owner/name", one a line.
    static func repos(from text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+$"#, options: .regularExpression) != nil }
    }

    /// One a line: 名称 | GET 或 POST | https://… | 说明（参数）
    static func endpoints(from text: String) -> [Endpoint] {
        text.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3, !parts[0].isEmpty, ["GET", "POST", "PUT", "DELETE"].contains(parts[1].uppercased()),
                  let url = URL(string: parts[2]), url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
            return Endpoint(name: parts[0], method: parts[1].uppercased(), url: parts[2], about: parts.count > 3 ? parts[3] : "")
        }
    }

    /// Whether the words ask for a tool at all, decided here and not by a model: most requests are for the phone.
    static func wants(_ request: String, repos: [String], endpoints: [Endpoint]) -> Bool {
        let t = request.lowercased()
        let has = { (words: [String]) in words.contains { t.contains($0) } }
        // "这个群最近在聊什么" is a summary; "总结这个视频" is the phone's work.
        if has(["群", "聊天", "会话", "會話"]), has(["总结", "總結", "在聊", "聊了", "聊什", "说了什么", "說了什麼", "讨论", "討論"]),
           !has(["视频", "視頻", "影片", "链接", "連結", "图片", "圖片", "这张", "這張", "文案"]) { return true }
        if !repos.isEmpty, has(["github", "仓库", "倉庫", "知识库", "知識庫", "源码", "原始碼", "代码", "程式碼", "编译", "編譯"]) { return true }
        return endpoints.contains { !$0.name.isEmpty && request.contains($0.name) }
    }

    static func choosePrompt(request: String, chat: String, repos: [String], endpoints: [Endpoint]) -> String {
        var tools = ["""
            {"tool":"summary","chat":"会话名，留空表示当前会话“\(chat)”","hours":24}  总结某个会话最近若干小时的聊天
            """]
        if !repos.isEmpty {
            tools.append("""
                可用的 GitHub 仓库：\(repos.joined(separator: "、"))
                {"tool":"github_search","repo":"owner/name","query":"关键词"}  在仓库里搜代码或文档
                {"tool":"github_file","repo":"owner/name","path":"文件路径"}  读一个文件
                {"tool":"github_list","repo":"owner/name","path":"目录，根目录留空"}  列出目录
                {"tool":"github_runs","repo":"owner/name"}  最近的编译（Actions）情况
                {"tool":"github_commits","repo":"owner/name"}  最近的提交
                {"tool":"github_issues","repo":"owner/name"}  未关闭的 issue
                """)
        }
        for e in endpoints {
            tools.append(#"{"tool":"api","name":"\#(e.name)","args":{}}  \#(e.method)，\#(e.about.isEmpty ? "参数写进 args" : e.about)"#)
        }
        return """
        主人的要求：\(request)
        从下面的工具里选最合适的一个，只输出那一行 JSON（照格式填好参数），不要别的文字。都不合适就输出 {"tool":"none"}。
        \(tools.joined(separator: "\n"))
        """
    }

    /// The model's choice, checked: a repository that is not listed, or an endpoint that is not configured, is no call.
    static func call(from reply: String, chat: String, repos: [String], endpoints: [Endpoint]) -> Call? {
        guard let data = WatchReport.object(reply),
              let box = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let tool = box["tool"] as? String else { return nil }
        let text = { (k: String) in ((box[k] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func repo() -> String? {
            let asked = text("repo").lowercased()
            if let exact = repos.first(where: { $0.lowercased() == asked }) { return exact }
            let named = repos.filter { $0.lowercased().hasSuffix("/" + asked) }
            if named.count == 1 { return named[0] }
            return asked.isEmpty && repos.count == 1 ? repos[0] : nil
        }
        switch tool {
        case "summary":
            let hours = (box["hours"] as? Int) ?? Int((box["hours"] as? Double) ?? 24)
            return .summary(chat: text("chat").isEmpty ? chat : text("chat"), hours: min(max(hours, 1), 72))
        case "github_search": return repo().flatMap { text("query").isEmpty ? nil : .githubSearch(repo: $0, query: text("query")) }
        case "github_file": return repo().flatMap { text("path").isEmpty ? nil : .githubFile(repo: $0, path: text("path")) }
        case "github_list": return repo().map { .githubList(repo: $0, path: text("path")) }
        case "github_runs": return repo().map { .githubRuns(repo: $0) }
        case "github_commits": return repo().map { .githubCommits(repo: $0) }
        case "github_issues": return repo().map { .githubIssues(repo: $0) }
        case "api":
            guard let e = endpoints.first(where: { $0.name == text("name") }) else { return nil }
            let args = box["args"] as? [String: Any] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return .api(e, json: json)
        default: return nil
        }
    }

    /// A summary reads what this phone already keeps. Everything else reaches outside: only for a fully proven owner.
    static func needsFullOwner(_ call: Call) -> Bool {
        if case .summary = call { return false }
        return true
    }

    /// Anything that is not a GET changes something on the server.
    static func needsConfirmation(_ call: Call) -> Bool {
        if case .api(let e, _) = call { return e.method != "GET" }
        return false
    }

    static func describe(_ call: Call) -> String {
        switch call {
        case .summary(let chat, let hours): return "总结“\(chat)”最近 \(hours) 小时的聊天"
        case .githubSearch(let repo, let query): return "在 \(repo) 里搜“\(query)”"
        case .githubFile(let repo, let path): return "读 \(repo) 的 \(path)"
        case .githubList(let repo, let path): return "列出 \(repo) 的 \(path.isEmpty ? "根目录" : path)"
        case .githubRuns(let repo): return "看 \(repo) 最近的编译"
        case .githubCommits(let repo): return "看 \(repo) 最近的提交"
        case .githubIssues(let repo): return "看 \(repo) 未关闭的 issue"
        case .api(let e, let json): return "调用“\(e.name)”（\(e.method)），参数 \(json)"
        }
    }

    static func isConfirmation(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet(charactersIn: " \n，。！!.,"))
        return ["确认", "確認", "确认执行", "確認執行", "确定", "確定"].contains(t)
    }

    typealias Fetch = (URLRequest) async throws -> (Data, Int)

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func githubRequest(_ path: String, token: String, accept: String = "application/vnd.github+json") -> URLRequest? {
        guard let url = URL(string: "https://api.github.com" + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LanAgent", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func escaped(_ s: String, path: Bool = false) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: path ? "?#" : "&+=?#/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The tool's result as plain text for the answer (at most `limit` characters). Never throws: what went wrong is the text.
    static func run(_ call: Call, githubToken: String, apiToken: String, fetch: Fetch = OwnerTools.fetch, limit: Int = 6000) async -> String {
        func rows(_ data: Data) -> [[String: Any]] { ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? [] }
        func dict(_ data: Data) -> [String: Any] { ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:] }
        func firstLine(_ s: Any?) -> String { String(((s as? String) ?? "").split(separator: "\n").first ?? "") }
        func github(_ path: String, accept: String = "application/vnd.github+json") async -> (Data, Int)? {
            guard !githubToken.isEmpty else { return nil }
            guard let request = githubRequest(path, token: githubToken, accept: accept) else { return nil }
            return try? await fetch(request)
        }
        func failed(_ code: Int?) -> String {
            guard !githubToken.isEmpty else { return "还没有填 GitHub 的访问令牌（守候微信设置 › 工具）。" }
            switch code {
            case 401?, 403?: return "GitHub 拒绝了这次访问（\(code!)）：令牌无效、权限不够或次数用完。"
            case 404?: return "GitHub 上找不到（404）：仓库、路径不对，或令牌看不到它。"
            case let c?: return "GitHub 返回 \(c)。"
            default: return "连不上 GitHub。"
            }
        }
        let out: String
        switch call {
        case .summary: out = ""  // made from the read log by the watch itself
        case .githubSearch(let repo, let query):
            let q = escaped(query + " repo:" + repo)
            let got = await github("/search/code?per_page=6&q=" + q, accept: "application/vnd.github.text-match+json")
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            let items = (dict(data)["items"] as? [[String: Any]]) ?? []
            out = items.isEmpty ? "没有搜到。" : items.map { item in
                let hits = ((item["text_matches"] as? [[String: Any]]) ?? []).prefix(2).map { firstLine($0["fragment"]) }.joined(separator: " … ")
                return "\((item["path"] as? String) ?? "")：\(hits)"
            }.joined(separator: "\n")
        case .githubFile(let repo, let path):
            let got = await github("/repos/\(repo)/contents/" + escaped(path, path: true), accept: "application/vnd.github.raw")
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            out = String(decoding: data, as: UTF8.self)
        case .githubList(let repo, let path):
            let got = await github("/repos/\(repo)/contents/" + escaped(path, path: true))
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            out = rows(data).map { "\(($0["type"] as? String) == "dir" ? "目录" : "文件") \(($0["name"] as? String) ?? "")" }.joined(separator: "\n")
        case .githubRuns(let repo):
            let got = await github("/repos/\(repo)/actions/runs?per_page=5")
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            let runs = (dict(data)["workflow_runs"] as? [[String: Any]]) ?? []
            out = runs.isEmpty ? "没有编译记录。" : runs.map { r in
                let commit = firstLine((r["head_commit"] as? [String: Any])?["message"])
                return "\((r["created_at"] as? String) ?? "") \((r["name"] as? String) ?? "") \((r["conclusion"] as? String) ?? (r["status"] as? String) ?? "")：\(commit)"
            }.joined(separator: "\n")
        case .githubCommits(let repo):
            let got = await github("/repos/\(repo)/commits?per_page=6")
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            out = rows(data).map { c in
                let commit = (c["commit"] as? [String: Any]) ?? [:]
                let author = (commit["author"] as? [String: Any]) ?? [:]
                return "\((author["date"] as? String) ?? "") \((author["name"] as? String) ?? "")：\(firstLine(commit["message"]))"
            }.joined(separator: "\n")
        case .githubIssues(let repo):
            let got = await github("/repos/\(repo)/issues?state=open&per_page=10")
            guard let (data, code) = got, code == 200 else { return failed(got?.1) }
            let open = rows(data).filter { $0["pull_request"] == nil }
            out = open.isEmpty ? "没有未关闭的 issue。" : open.map { "#\(($0["number"] as? Int) ?? 0) \(($0["title"] as? String) ?? "")" }.joined(separator: "\n")
        case .api(let e, let json):
            guard var parts = URLComponents(string: e.url) else { return "“\(e.name)”的地址不对。" }
            let args = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]) ?? [:]
            if e.method == "GET", !args.isEmpty {
                parts.queryItems = (parts.queryItems ?? []) + args.keys.sorted().map { URLQueryItem(name: $0, value: "\(args[$0]!)") }
            }
            guard let url = parts.url else { return "“\(e.name)”的地址不对。" }
            var request = URLRequest(url: url)
            request.httpMethod = e.method
            if !apiToken.isEmpty { request.setValue("Bearer " + apiToken, forHTTPHeaderField: "Authorization") }
            if e.method != "GET" {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(json.utf8)
            }
            let got = try? await fetch(request)
            guard let (data, code) = got else { return "连不上“\(e.name)”的服务器。" }
            let body = String(decoding: data.prefix(4000), as: UTF8.self)
            out = (200..<300).contains(code) ? (body.isEmpty ? "已执行，服务器没有返回内容。" : body) : "服务器返回 \(code)：\(body.prefix(300))"
        }
        return out.count > limit ? String(out.prefix(limit)) + "\n（后面省略）" : out
    }

    static func answerPrompt(request: String, result: String) -> String {
        """
        主人的要求：\(request)
        工具返回的结果：
        \(result)
        根据结果直接回答主人，用简体中文，简洁清楚，不超过 300 字；只用汉字、数字、英文和常见标点，不要链接、表情和 Markdown；结果里没有的不要编。
        """
    }
}

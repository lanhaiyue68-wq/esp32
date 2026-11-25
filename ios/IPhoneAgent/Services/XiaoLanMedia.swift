import Foundation
import Photos
import UIKit
import os

/// 小藍 iPad 版 (161): what an order needs from the app itself (XiaoLanOrders) — files fetched before the agent picks
/// them (images and videos into Photos, other files into Documents/orders, which Files shows under 小藍), the reads that
/// need no screen (509 files, 510 / 514 log, 513 device), and 跟圈's result post to its backend.
enum XiaoLanMedia {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("orders", isDirectory: true)
    }

    struct Failure: LocalizedError {
        var reason: String
        var errorDescription: String? { reason }
    }

    /// Downloads each http(s) URL into Documents/orders (named `names[i]` when given) and, for `.photos`, adds it to
    /// Photos as the newest item, in order, so the agent picks "the newest".
    static func fetch(_ urls: [String], kind: XiaoLanOrders.MediaKind, names: [String] = []) async throws {
        guard kind != .none else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (i, s) in urls.enumerated() {
            guard let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw Failure(reason: "文件地址不是 http(s)：\(s)")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (temp, response) = try await URLSession.shared.download(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw Failure(reason: "下载返回 \(code)：\(s)") }
            let mime = response.mimeType ?? ""
            var name = i < names.count ? names[i] : url.lastPathComponent
            if name.isEmpty || name == "/" { name = "file\(i)" }
            if (name as NSString).pathExtension.isEmpty, let ext = extensionFor(mime) { name += "." + ext }
            let dest = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            if kind == .photos { try await saveToPhotos(dest, mime: mime) }
            DebugLog.write("xiaolan: fetched \(name) (\(mime))")
        }
    }

    static func extensionFor(_ mime: String) -> String? {
        ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/heic": "heic", "image/webp": "webp",
         "video/mp4": "mp4", "video/quicktime": "mov", "application/pdf": "pdf"][mime.lowercased()]
    }

    static func saveToPhotos(_ file: URL, mime: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw Failure(reason: "小藍没有存入相册的权限（设置 › 小藍 › 照片 › 仅添加照片）")
        }
        let video = mime.hasPrefix("video") || ["mp4", "mov", "m4v"].contains(file.pathExtension.lowercased())
        try await PHPhotoLibrary.shared().performChanges {
            if video {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
            } else {
                _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file)
            }
        }
    }

    /// 509 / 510 / 513 / 514: the order's data bean, made here.
    @MainActor static func local(_ what: XiaoLanOrders.Local, type: Int) -> [String: Any] {
        switch what {
        case .files:
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return ["type": type, "nameList": names.sorted()]
        case .log:
            return ["type": type, "log": DebugLog.tail(400).joined(separator: "\n")]
        case .logRange(let from, let to):
            let a = from.replacingOccurrences(of: " ", with: "T").prefix(19), b = to.replacingOccurrences(of: " ", with: "T").prefix(19)
            let lines = DebugLog.tail(5000).filter { line in
                let stamp = line.prefix(19)
                return (a.isEmpty || stamp >= a) && (b.isEmpty || stamp <= b)
            }
            return ["type": type, "startDate": from, "endDate": to, "log": lines.suffix(800).joined(separator: "\n")]
        case .resources:
            var sys = utsname()
            uname(&sys)
            let model = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let values = try? URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            let total = Int64(ProcessInfo.processInfo.physicalMemory), appFree = Int64(os_proc_available_memory())
            UIDevice.current.isBatteryMonitoringEnabled = true
            let info: [String: Any] = [
                "deviceModel": model, "androidVersion": "iPadOS " + UIDevice.current.systemVersion, "sdkVersion": 0,
                "totalMemory": total, "appMaxMemory": appFree, "availableMemory": appFree, "usedMemory": max(0, total - appFree),
                "memoryUsagePercent": total > 0 ? Double(total - appFree) / Double(total) * 100 : 0,
                "totalInternalStorage": Int64(values?.volumeTotalCapacity ?? 0),
                "availableInternalStorage": values?.volumeAvailableCapacityForImportantUsage ?? 0,
                "battery": Double(UIDevice.current.batteryLevel),
            ]
            return ["type": type, "resourceInfo": info]
        }
    }

    /// A picture as WeChat's viewer shows it, without the black around it. The viewer's background is pure black: a row
    /// (then a column) is picture when over 3% of it is not near-black, and the picture is the longest unbroken run of
    /// such rows, so the status bar, the page dots and the pointer (short runs) are left out and a dark photo's own dark
    /// edge stays in (checked on simulated frames 11-25). JPEG; the whole frame when the cut looks wrong; nil when the
    /// frame cannot be read.
    static func trimmed(_ frame: Data) -> Data? {
        guard let image = UIImage(data: frame), let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 10, h > 10 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        func shown(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) >= 40
        }
        /// The longest unbroken run of true, as first...last (last < first when there is none).
        func longest(_ flags: [Bool]) -> (Int, Int) {
            var best = (0, -1), start: Int?
            for (i, f) in (flags + [false]).enumerated() {
                if f, start == nil { start = i }
                if !f, let s = start {
                    if i - 1 - s > best.1 - best.0 { best = (s, i - 1) }
                    start = nil
                }
            }
            return best
        }
        let rows = (0..<h).map { y -> Bool in
            var n = 0
            for x in stride(from: 0, to: w, by: 2) where shown(x, y) { n += 1 }
            return n * 2 * 100 > w * 3
        }
        let (top, bottom) = longest(rows)
        guard bottom > top else { return image.jpegData(compressionQuality: 0.9) }
        let columns = (0..<w).map { x -> Bool in
            var n = 0
            for y in stride(from: top, through: bottom, by: 2) where shown(x, y) { n += 1 }
            return n * 2 * 100 > (bottom - top + 1) * 3
        }
        let (left, right) = longest(columns)
        guard right - left > w / 5, bottom - top > h / 8,
              let cut = cg.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else {
            return image.jpegData(compressionQuality: 0.9)
        }
        return UIImage(cgImage: cut).jpegData(compressionQuality: 0.9)
    }

    /// 跟圈: one kept picture to the run's upload address; the URL the backend gives it, or nil. Only to the host the
    /// order came from.
    static func upload(_ jpeg: Data, moments m: XiaoLanOrders.Moments, host: String?) async -> String? {
        guard let url = m.uploadURL, let to = url.host, let host, to.caseInsensitiveCompare(host) == .orderedSame else {
            DebugLog.write("xiaolan: 跟圈 picture not uploaded (no upload address on the order's server)")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let u = o["url"] as? String else {
                DebugLog.write("xiaolan: 跟圈 picture upload answered \(code)")
                return nil
            }
            return u
        } catch {
            DebugLog.write("xiaolan: 跟圈 picture upload failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// 跟圈: tells the backend how its run went (owner-gequan /gequan/result/<run>?robotId=…&token=…). Only to the host
    /// the order came from: a result URL elsewhere is not posted to.
    static func postMoments(_ m: XiaoLanOrders.Moments, ok: Bool, entries: [[String: Any]]?, reason: String, host: String?) async -> Bool {
        guard let url = m.resultURL, let to = url.host, let host, to.caseInsensitiveCompare(host) == .orderedSame else {
            DebugLog.write("xiaolan: 跟圈 result not posted (its address is not the order's server)")
            return false
        }
        var body: [String: Any] = ["runId": m.runId, "ok": ok]
        if let entries { body["entries"] = entries }
        if !reason.isEmpty { body["reason"] = reason }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DebugLog.write("xiaolan: 跟圈 result posted (\(code))")
            return code == 200
        } catch {
            DebugLog.write("xiaolan: 跟圈 result failed: \(error.localizedDescription)")
            return false
        }
    }
}

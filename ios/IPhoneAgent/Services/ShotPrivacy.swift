import CoreGraphics
import Foundation
import UIKit

/// The picture a cloud task gets back is the phone's own screen. Build 116 over the cloud 11-10: "how much storage is
/// left" went out with Settings' About page, IMEI, ICCID and the rest in full. Before a picture leaves the phone, the
/// device numbers on it (long digit or letter-digit runs, MAC addresses, and what stands on the row of such a label) are
/// blacked out. The answer itself is the model's words and is not touched.
enum ShotPrivacy {
    /// Labels whose row holds a device number.
    static let labels = ["IMEI", "ICCID", "MEID", "EID", "IMSI", "序號", "序号", "序列號", "序列号", "SERIAL", "UDID",
                         "WI-FI 位址", "WI-FI 地址", "WLAN 位址", "WLAN 地址", "藍牙", "蓝牙"]

    /// A device number in itself: 10+ letters and digits with at least 6 digits (IMEI, ICCID, EID, a serial), or a MAC.
    static func isNumber(_ text: String) -> Bool {
        let t = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if t.range(of: #"^([0-9A-F]{2}:){5}[0-9A-F]{2}$"#, options: .regularExpression) != nil { return true }
        guard t.count >= 10, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isUppercase) }) else { return false }
        return t.filter(\.isNumber).count >= 6
    }

    /// The boxes to black out (0-1 of the screen, origin top-left).
    static func boxes(_ rows: [[CandidatePicker.Piece]]) -> [CGRect] {
        var out: [CGRect] = []
        for row in rows {
            let labelled = row.first { piece in
                let t = piece.text.uppercased().trimmingCharacters(in: .whitespaces)
                return labels.contains { t == $0 || t.hasPrefix($0 + " ") }
            }
            for piece in row where isNumber(piece.text) || (labelled.map { piece != $0 && piece.box.minX > $0.box.minX } ?? false) {
                // Bluetooth's row only when it carries an address, not the word 開啟/On.
                if let label = labelled, ["藍牙", "蓝牙"].contains(label.text.trimmingCharacters(in: .whitespaces)), !isNumber(piece.text) { continue }
                out.append(piece.box.insetBy(dx: -0.01, dy: -0.006))
            }
        }
        return out
    }

    static func masked(_ jpeg: Data) async -> Data {
        let rows = await CandidatePicker.rowsOffMain(in: jpeg, top: 0, bottom: 1)
        let hide = boxes(rows)
        guard !hide.isEmpty, let image = UIImage(data: jpeg) else { return jpeg }
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for box in hide {
                ctx.fill(CGRect(x: box.minX * size.width, y: box.minY * size.height, width: box.width * size.width, height: box.height * size.height))
            }
        }
        DebugLog.write("cloud: \(hide.count) device number(s) blacked out of the picture")
        return out.jpegData(compressionQuality: 0.7) ?? jpeg
    }
}

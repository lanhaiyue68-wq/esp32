import Foundation
import UIKit
import Vision
import ImageIO

/// Reads text on this phone (on-device text recognition) so typing needs no model look per phrase: the pinyin
/// candidate to tap, and whether a paste really put the reply in the field. Asking the model for each candidate took
/// seconds a phrase, and it picked wrong ones it then had to delete (build 31). Anything not found here is left to the
/// model as before.
enum CandidatePicker {
    /// Text on one line of the screen, split where the gap between two characters is wide (two candidates).
    struct Piece: Equatable { var text: String; var box: CGRect }  // box: 0-1 of the screen, origin top-left

    /// Keys of the Chinese keyboards that look like candidates.
    static let keyLabels: Set<String> = ["选拼音", "选定", "确认", "分隔", "换行", "发送", "空格", "重输", "拼音", "中", "英"]

    /// Where the candidate `phrase` is, in 0-1 screen coordinates: an exact piece on a row of several (the candidate
    /// row; a field holds one), the lowest such row (chat bubbles are above the keyboard and its candidates).
    static func find(_ phrase: String, in jpeg: Data) -> CGPoint? {
        guard !phrase.isEmpty, !keyLabels.contains(phrase) else { return nil }
        return find(phrase, rows: rows(in: jpeg, top: 0.4, bottom: 1))
    }

    static func find(_ phrase: String, rows: [[Piece]]) -> CGPoint? {
        let hits = rows.filter { $0.count >= 2 }.flatMap { $0 }.filter { $0.text == phrase }
        guard let hit = hits.max(by: { $0.box.midY < $1.box.midY }) else { return nil }
        return CGPoint(x: hit.box.midX, y: hit.box.midY)
    }

    /// How often the start of `text` (letters and digits only) shows in the lower part of the screen: a paste is
    /// confirmed when this goes up, so text already in a bubble above does not count.
    static func count(_ text: String, in jpeg: Data) -> Int {
        count(text, lines: rows(in: jpeg, top: 0.3, bottom: 0.9).map { $0.map(\.text).joined() })
    }

    static func count(_ text: String, lines: [String]) -> Int {
        let probe = String(bare(text).prefix(6))
        guard probe.count >= 2 else { return 0 }  // too short to tell apart: not confirmed
        return lines.reduce(0) { $0 + bare($1).components(separatedBy: probe).count - 1 }
    }

    static func bare(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).contains($0) }))
    }

    /// Splits recognized characters into pieces where the gap is wider than 0.6 of a typical character.
    static func split(_ chars: [(Character, CGRect)]) -> [Piece] {
        guard let first = chars.first else { return [] }
        let widths = chars.map { $0.1.width }.sorted()
        let gap = widths[widths.count / 2] * 0.6
        var pieces: [Piece] = [], current = Piece(text: "", box: first.1)
        for (k, c) in chars.enumerated() {
            if k > 0, c.1.minX - chars[k - 1].1.maxX > gap {
                pieces.append(current)
                current = Piece(text: "", box: c.1)
            }
            current.text.append(c.0)
            current.box = current.box.union(c.1)
        }
        pieces.append(current)
        return pieces
    }

    /// The text lines in a band of the screen (top and bottom 0-1 from the top), each split into pieces.
    static func rows(in jpeg: Data, top: Double, bottom: Double) -> [[Piece]] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let h = Double(image.height)
        let band = CGRect(x: 0, y: top * h, width: Double(image.width), height: (bottom - top) * h).integral
        guard let crop = image.cropping(to: band) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: crop, options: [:]).perform([request]) } catch { return [] }
        func onScreen(_ r: CGRect) -> CGRect {  // Vision: 0-1 of the crop, origin bottom-left
            CGRect(x: r.minX, y: top + (1 - r.maxY) * (bottom - top), width: r.width, height: r.height * (bottom - top))
        }
        return (request.results ?? []).compactMap { observation -> [Piece]? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let s = best.string
            var chars: [(Character, CGRect)] = []
            var i = s.startIndex
            while i < s.endIndex {
                let next = s.index(after: i)
                if !s[i].isWhitespace, let box = try? best.boundingBox(for: i..<next)?.boundingBox {
                    chars.append((s[i], onScreen(box)))
                }
                i = next
            }
            let pieces = split(chars)
            return pieces.isEmpty ? nil : pieces
        }
    }
}

/// How putting a reply on the pasteboard went (AppModel.hopToPaste): filled, refused, or lost on the way (not back in
/// WeChat, or never in Lan Agent).
enum PasteHopResult { case filled, refused, lost }

/// The general pasteboard, for pasting a reply.
enum Pasteboard {
    /// True when some character is not on a US keyboard (Chinese, full-width punctuation, emoji).
    static func needed(_ text: String) -> Bool {
        !text.unicodeScalars.allSatisfy { (32...126).contains($0.value) || $0 == "\n" || $0 == "\t" }
    }

    /// Puts `text` on it; false when iOS did not take it (it refuses an app in the background, and Cmd+V then pasted
    /// what the user had copied: an API key, build 25).
    @MainActor static func put(_ text: String) -> Bool {
        let board = UIPasteboard.general, before = board.changeCount
        board.string = text
        return board.changeCount != before
    }
}

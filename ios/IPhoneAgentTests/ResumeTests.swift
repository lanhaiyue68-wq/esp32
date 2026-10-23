import XCTest
@testable import IPhoneAgent

/// logs(15): after a Wi-Fi drop the decoder lost a few units and mirroring had to be restarted; the fallback typing
/// got stuck on a six-character pinyin phrase.
@MainActor final class ResumeTests: XCTestCase {
    private func chunk(_ seq: UInt16, _ flags: VideoAssembler.Flags, _ payload: [UInt8], ms: UInt32? = nil) -> Data {
        var d = Data([UInt8(seq & 0xff), UInt8(seq >> 8), flags.rawValue])
        if let ms { d.append(contentsOf: [UInt8(ms & 0xff), UInt8(ms >> 8 & 0xff), UInt8(ms >> 16 & 0xff), UInt8(ms >> 24)]) }
        d.append(contentsOf: payload)
        return d
    }
    private let idr: [UInt8] = [0, 0, 0, 1, 0x65, 9, 9]
    private let p: [UInt8] = [0, 0, 0, 1, 0x41, 7]

    func testAResumedStreamGoesOnAfterAGap() {
        var a = VideoAssembler()
        _ = a.add(chunk(10, [.start, .end, .idr], idr, ms: 1))
        XCTAssertNotNil(a.add(chunk(11, [.start, .end], p, ms: 2)))
        XCTAssertNotNil(a.add(chunk(12, [.start, .end], p, ms: 3)))
        // 13-15 went into the dead socket; the board resumes at the last unit this side has (ms 3)
        XCTAssertEqual(a.add(chunk(16, [.start, .end], p, ms: 3))?.boardMs, 3)  // the repeat: the feed skips it
        XCTAssertEqual(a.add(chunk(17, [.start, .end], p, ms: 4))?.boardMs, 4)  // and the missed ones follow
        XCTAssertEqual(a.drops, 3)
    }

    func testAStreamThatDidNotResumeStillWaitsForAKeyUnit() {
        var a = VideoAssembler()
        _ = a.add(chunk(10, [.start, .end, .idr], idr, ms: 1))
        _ = a.add(chunk(11, [.start, .end], p, ms: 2))
        XCTAssertNil(a.add(chunk(20, [.start, .end], p, ms: 9)))  // newer than anything here: units are missing
        XCTAssertNotNil(a.add(chunk(21, [.start, .end, .idr], idr, ms: 10)))
    }

    func testThePickIsTheLongestCandidateThatStartsThePhrase() {
        // logs(15): "这个我不太确" was not offered whole; a person takes "这个", then the next.
        func piece(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: 0.08, height: 0.03))
        }
        let bubble = [piece("这个", 0.2, 0.42), piece("我不太确定", 0.35, 0.42)]  // higher up: a chat line
        let candidates = [piece("这个我不太去", 0.02, 0.6), piece("这个", 0.4, 0.6), piece("这", 0.55, 0.6)]
        let pick = CandidatePicker.longestStart(of: "这个我不太确", rows: [bubble, candidates])
        XCTAssertEqual(pick?.text, "这个")
        XCTAssertEqual(pick?.spot.y ?? 0, 0.615, accuracy: 0.001)
        XCTAssertNil(CandidatePicker.longestStart(of: "确定", rows: [candidates]))
    }
}

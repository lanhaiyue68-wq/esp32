import XCTest
@testable import IPhoneAgent

/// logs26: owner authority was a nickname; the report of a task went into the chat the task had used; a reply that
/// was already sent with 发送 was typed and sent again.
@MainActor final class OwnerPasscodeTests: XCTestCase {
    private func line(_ text: String, mine: Bool = false) -> WatchReport.Line {
        WatchReport.Line(sender: mine ? "" : "蓝海乐", text: text, mine: mine)
    }

    func testPasscodeInAPrivateChatProvesTheOwnerAndIsTakenOut() {
        let read = WatchReport.Screen(title: "蓝海乐", group: false, lines: [line("#8642 你去给测试群发一个你好"), line("在吗")])
        let screen = WatchSettings.masked(read, pin: "#8642")
        XCTAssertEqual(screen.lines.map(\.text), ["你去给测试群发一个你好", "在吗"])
        XCTAssertTrue(screen.proven.contains(WatchReport.proofKey(screen.lines[0])))
        XCTAssertFalse(screen.proven.contains(WatchReport.proofKey(screen.lines[1])))
    }

    /// build 64: the read wrote 蓝海乐 above the owner's bubbles in the chat 主人蓝海乐; the white list holds 主人蓝海乐.
    func testInAPrivateChatTheSenderIsTheChatWhateverTheReadWrote() {
        let read = WatchReport.Screen(title: "主人蓝海乐", group: false, lines: [line("#8642 去测试群发你好"), line("好的", mine: true)])
        let screen = WatchSettings.masked(WatchReport.privateSenders(read, chat: "主人蓝海乐"), pin: "#8642")
        let m = ReadMessage(chat: "主人蓝海乐", group: false, sender: screen.lines[0].sender, text: screen.lines[0].text,
                            atMe: false, verified: screen.proven.contains(WatchReport.proofKey(screen.lines[0])))
        XCTAssertTrue(WatchSettings.isOwner(m, WatchSettings.Rules(targets: ["主人蓝海乐"], senders: ["主人蓝海乐"])))
        XCTAssertEqual(screen.lines[1].sender, "", "my own lines stay mine")
        let group = WatchReport.Screen(title: "测试群(3)", group: true, lines: [line("你好")])
        XCTAssertEqual(WatchReport.privateSenders(group, chat: "测试群").lines[0].sender, "蓝海乐", "a group keeps its names")
    }

    /// build 65: a broken decision lost the task, then the navigator's 蓝海乐 for 主人蓝海乐 made every read a mismatch.
    func testStraightQuotesInADecisionAndAShortenedChatNameAreRecovered() {
        let d = WatchReport.decision(#"{"reply":"收到","task":"去测试群发"你好""}"#)
        XCTAssertEqual(d?.reply, "收到"); XCTAssertEqual(d?.task, #"去测试群发"你好""#)
        XCTAssertNil(WatchReport.decision(#"{"reply":"收到","#))
        XCTAssertEqual(WatchReport.listed("蓝海乐", ["主人蓝海乐", "测试群"]), "主人蓝海乐")
        XCTAssertEqual(WatchReport.listed("测试群", ["主人蓝海乐", "测试群"]), "测试群")
        XCTAssertEqual(WatchReport.listed("群", ["测试群", "虾笔刀群"]), "群", "not unique: left for readChat to refuse")
    }

    func testPasscodeInAGroupProvesNothingButIsStillHidden() {
        let read = WatchReport.Screen(title: "测试群(3)", group: true, lines: [line("@蓝 #8642 打开备忘录")])
        let screen = WatchSettings.masked(read, pin: "#8642")
        XCTAssertFalse(screen.lines[0].text.contains("8642"))
        XCTAssertTrue(screen.proven.isEmpty)
    }

    func testShortOrMissingPasscodeProvesNothing() {
        let read = WatchReport.Screen(title: "蓝海乐", group: false, lines: [line("12 打开备忘录")])
        XCTAssertTrue(WatchSettings.masked(read, pin: "12").proven.isEmpty)
        XCTAssertTrue(WatchSettings.masked(read, pin: "").proven.isEmpty)
        XCTAssertEqual(WatchSettings.hidePIN("a 12 b", "12"), "a 12 b")
        XCTAssertEqual(WatchSettings.hidePIN("a #8642 b", "#8642"), "a ‹passcode› b")
    }

    /// A Chinese keyboard types ＃８６４２; the read may space it out.
    func testFullWidthOrSpacedPasscodeStillProvesTheOwner() {
        for typed in ["＃８６４２ 去测试群发你好", "# 8642 去测试群发你好", "#8642去测试群发你好"] {
            let read = WatchReport.Screen(title: "蓝海乐", group: false, lines: [line(typed)])
            let screen = WatchSettings.masked(read, pin: "#8642")
            XCTAssertEqual(screen.lines[0].text, "去测试群发你好", typed)
            XCTAssertTrue(screen.proven.contains(WatchReport.proofKey(screen.lines[0])), typed)
        }
        let other = WatchReport.Screen(title: "蓝海乐", group: false, lines: [line("#8643 去测试群发你好")])
        XCTAssertTrue(WatchSettings.masked(other, pin: "#8642").proven.isEmpty)
    }

    func testOwnerNeedsListedSenderPrivateChatAndProof() {
        let r = WatchSettings.Rules(targets: ["蓝海乐"], senders: ["蓝海乐"])
        let m = ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "打开备忘录", verified: true)
        XCTAssertTrue(WatchSettings.isOwner(m, r))
        var x = m; x.verified = false
        XCTAssertFalse(WatchSettings.isOwner(x, r))
        x = m; x.group = true
        XCTAssertFalse(WatchSettings.isOwner(x, r))
        x = m; x.sender = "蓝海乐2"
        XCTAssertFalse(WatchSettings.isOwner(x, r))
    }

    func testSendRunNeverTypesInAnotherChat() {
        var baseline: Int?
        let why = WatchSettings.sendRefusal(chat: "蓝海乐", inChat: false, shown: 0, baseline: &baseline)
        XCTAssertNotNil(why)
        XCTAssertTrue(why!.contains("蓝海乐"))
        XCTAssertNil(baseline, "a refused type sets no baseline")
    }

    func testSendRunTypesTheTextOnceThenRefusesWhenItAlreadyShows() {
        var baseline: Int?
        XCTAssertNil(WatchSettings.sendRefusal(chat: "蓝海乐", inChat: true, shown: 1, baseline: &baseline))  // an old copy above
        XCTAssertEqual(baseline, 1)
        XCTAssertNil(WatchSettings.sendRefusal(chat: "蓝海乐", inChat: true, shown: 1, baseline: &baseline),
                     "a paste that did not land leaves nothing new: typing again is fine")
        XCTAssertNotNil(WatchSettings.sendRefusal(chat: "蓝海乐", inChat: true, shown: 2, baseline: &baseline),
                        "logs26: sent with 发送, then typed again")
    }
}

import XCTest
@testable import IrisKit

final class ThreadSubjectTests: XCTestCase {
    func testRemovesReplyAndForwardPrefixesInAnyCase() {
        for subject in ["Budget", "Re: Budget", "RE: Budget", "re: Budget", "Fwd: Budget", "FWD: Budget", "Fw: Budget", "FW: Budget"] {
            XCTAssertEqual(ThreadSubject.normalized(subject), "budget", subject)
        }
    }

    func testRemovesRepeatedPrefixesAndTheWhitespaceAroundThem() {
        XCTAssertEqual(ThreadSubject.normalized("Re: Re: Fwd: Budget"), "budget")
        XCTAssertEqual(ThreadSubject.normalized("  RE:Fw:   re :  Budget  "), "budget")
        XCTAssertEqual(ThreadSubject.normalized("Re:\tBudget"), "budget")
    }

    func testKeepsPrefixesThatAreNotAtTheStart() {
        XCTAssertEqual(ThreadSubject.normalized("Budget Re: Q4"), "budget re: q4")
        XCTAssertEqual(ThreadSubject.normalized("Re: Budget (Fwd: notes)"), "budget (fwd: notes)")
    }

    func testKeepsWordsThatOnlyStartLikeAPrefix() {
        XCTAssertEqual(ThreadSubject.normalized("Report: Q4"), "report: q4")
        XCTAssertEqual(ThreadSubject.normalized("Fwding rules"), "fwding rules")
        XCTAssertEqual(ThreadSubject.normalized("Request"), "request")
    }

    func testMakesEachRunOfWhitespaceOneSpace() {
        // A folded Subject header can keep a tab or two spaces where the line was folded.
        XCTAssertEqual(ThreadSubject.normalized("Q4  budget\t plan"), ThreadSubject.normalized("Re: Q4 budget plan"))
    }

    func testIgnoresCase() {
        XCTAssertEqual(ThreadSubject.normalized("Impact Champion Role"), ThreadSubject.normalized("RE: impact champion role"))
    }

    func testAMissingSubjectAndAPrefixAloneAreEmpty() {
        XCTAssertEqual(ThreadSubject.normalized(nil), "")
        XCTAssertEqual(ThreadSubject.normalized(""), "")
        XCTAssertEqual(ThreadSubject.normalized("Re:"), "")
        XCTAssertEqual(ThreadSubject.normalized("Re: Fwd: "), "")
    }

    func testDifferentSubjectsStayDifferent() {
        XCTAssertNotEqual(ThreadSubject.normalized("Re: Budget"), ThreadSubject.normalized("Re: Party"))
    }

    func testRemovesLeadingBracketedTagsInAnyOrderWithThePrefixes() {
        // Mailman 3 writes "[list] Re: x" on replies; gateways add "[EXTERNAL]".
        let subjects = [
            "[list] Re: Budget", "Re: [list] Budget", "[list] Budget", "[EXTERNAL] RE: Budget",
            "Re: [list] Re: [list] Budget", "[EXTERNAL][list] Fwd: Budget", "  [ext]   re:  Budget",
        ]
        for subject in subjects {
            XCTAssertEqual(ThreadSubject.normalized(subject), "budget", subject)
        }
    }

    func testKeepsBracketsThatAreNotAtTheStart() {
        XCTAssertEqual(ThreadSubject.normalized("Re: Budget [draft]"), "budget [draft]")
        XCTAssertEqual(ThreadSubject.normalized("[list] Re: Q4 [v2] plan"), "q4 [v2] plan")
    }

    func testATagAloneIsEmpty() {
        XCTAssertEqual(ThreadSubject.normalized("[list]"), "")
        XCTAssertEqual(ThreadSubject.normalized("[list] Re:"), "")
    }

    // MARK: - ASCII words

    func testASCIIWordsSplitAtPunctuationSymbolsAndTheCurlyApostrophe() {
        XCTAssertEqual(
            ThreadSubject.asciiWords("josh ←→ anthony: introduction for ai application work"),
            ["introduction", "application", "anthony", "josh", "work"]
        )
        XCTAssertEqual(ThreadSubject.asciiWords("your bill’s ready"), ["ready", "your", "bill"])
        XCTAssertEqual(ThreadSubject.asciiWords("your single-use code"), ["single", "your", "code", "use"])
        XCTAssertEqual(ThreadSubject.asciiWords("🎉 paid today (10/20/2026)"), ["today", "paid", "2026"])
    }

    func testASCIIWordsLeaveOutWordsWithAnASCIIApostropheOrALetterThatIsNotASCII() {
        // Zoho keeps "don't" whole, so "don" would find nothing.
        XCTAssertEqual(ThreadSubject.asciiWords("don't lose your benefits"), ["benefits", "lose", "your"])
        XCTAssertEqual(ThreadSubject.asciiWords("café plans"), ["plans"])
        XCTAssertEqual(ThreadSubject.asciiWords("分享制作新专辑的点滴。"), [])
    }

    func testASCIIWordsLeaveOutShortWordsAndRepeats() {
        XCTAssertEqual(ThreadSubject.asciiWords("ai is ok"), [])
        XCTAssertEqual(ThreadSubject.asciiWords("plan b for the plan"), ["plan", "for", "the"])
    }

    func testASCIIWordsAreTheFiveLongestEarlierFirstOnATie() {
        XCTAssertEqual(
            ThreadSubject.asciiWords("one two three four five sixsix seven"),
            ["sixsix", "three", "seven", "four", "five"]
        )
    }
}

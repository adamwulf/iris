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
}

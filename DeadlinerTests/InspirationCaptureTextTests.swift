import XCTest
@testable import Deadliner

final class InspirationCaptureTextTests: XCTestCase {
    func testNormalizedTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            InspirationCaptureText.normalized("  一条灵感\n"),
            "一条灵感"
        )
    }

    func testNormalizedPreservesMeaningfulLineBreaks() {
        XCTAssertEqual(
            InspirationCaptureText.normalized("第一行\n第二行"),
            "第一行\n第二行"
        )
    }

    func testNormalizedRejectsWhitespaceOnlyText() {
        XCTAssertNil(InspirationCaptureText.normalized(" \n\t "))
    }
}

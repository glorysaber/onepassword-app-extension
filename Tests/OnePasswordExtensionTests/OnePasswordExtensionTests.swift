import XCTest
@testable import OnePasswordExtension

final class OnePasswordExtensionTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(OnePasswordExtension().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

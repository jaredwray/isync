import XCTest

@testable import ISyncCore

final class AttributedBodyDecoderTests: XCTestCase {
    func testDecodesTheTextThatMessagesStores() {
        let long = String(repeating: "x", count: 300)
        let cases: [(name: String, body: Data, expected: String)] = [
            ("one-byte length", attributedBody("Hello there"), "Hello there"),
            ("two-byte length", attributedBody(long), long),
            ("multibyte UTF-8", attributedBody("Café 👋"), "Café 👋"),
            ("NSMutableString class chain", attributedBody("Edited", mutable: true), "Edited"),
        ]
        for testCase in cases {
            XCTAssertEqual(AttributedBodyDecoder.text(from: testCase.body), testCase.expected, testCase.name)
        }
    }

    #if os(macOS)
        /// NSArchiver writes the typedstream format that Messages stores. This test checks the decoder
        /// against real archives, not only against the fixture in this target.
        @available(macOS, deprecated: 10.13, message: "NSArchiver is deprecated, but it is the format of chat.db.")
        func testDecodesRealNSArchiverOutput() {
            let texts = ["Hello 👋", String(repeating: "a", count: 300), String(repeating: "b", count: 70_000)]
            for text in texts {
                let objects: [NSAttributedString] = [
                    NSAttributedString(string: text),
                    NSMutableAttributedString(string: text),
                ]
                for object in objects {
                    let data = NSArchiver.archivedData(withRootObject: object)
                    XCTAssertEqual(
                        AttributedBodyDecoder.text(from: data),
                        text,
                        "\(type(of: object)), \(text.utf8.count) bytes"
                    )
                }
            }
        }
    #endif

    func testReturnsNilForDataThatItCannotRead() {
        let complete = attributedBody("Hello there")
        let cases: [(name: String, body: Data)] = [
            ("empty", Data()),
            ("no NSString record", Data("streamtyped NSObject".utf8)),
            ("length past the end", complete.prefix(complete.count - 12)),
            ("cut after the type tag", complete.prefix(through: complete.firstIndex(of: 0x2B)!)),
        ]
        for testCase in cases {
            XCTAssertNil(AttributedBodyDecoder.text(from: testCase.body), testCase.name)
        }
    }
}

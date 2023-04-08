@testable import PennyBOT
@testable import PennyModels
import XCTest

class OtherTests: XCTestCase {
    
    func testContainsSequence() throws {
        let array = ["a", "bc", "def", "g", "hi"]
        
        XCTAssertTrue(array.containsSequence(["bc"]))
        XCTAssertTrue(array.containsSequence(["bc", "def"]))
        XCTAssertTrue(array.containsSequence(["a"]))
        XCTAssertTrue(array.containsSequence(["a", "bc"]))
        XCTAssertTrue(array.containsSequence(array))
        XCTAssertTrue(array.containsSequence(["hi"]))
        XCTAssertTrue(array.containsSequence(["g", "hi"]))
        XCTAssertTrue(array.containsSequence([]))
        XCTAssertTrue([String]().containsSequence([]))
        
        XCTAssertFalse(array.containsSequence(["g", "h"]))
        XCTAssertFalse(array.containsSequence(["s", "hi"]))
        XCTAssertFalse(array.containsSequence(["a", "def"]))
        
        XCTAssertFalse([].containsSequence(["j"]))
    }
    
    func testRemovingOccurrencesCharacterSetInString() throws {
        XCTAssertEqual(
            "".removingOccurrences(of: CharacterSet.punctuationCharacters),
            ""
        )
        
        XCTAssertEqual(
            "a".removingOccurrences(of: CharacterSet.punctuationCharacters),
            "a"
        )
        
        XCTAssertEqual(
            "a,".removingOccurrences(of: CharacterSet.punctuationCharacters),
            "a"
        )
        
        XCTAssertEqual(
            ",".removingOccurrences(of: CharacterSet.punctuationCharacters),
            ""
        )
        
        XCTAssertEqual(
            ",.?/!{}".removingOccurrences(of: CharacterSet.punctuationCharacters),
            ""
        )
        
        XCTAssertEqual(
            "asad,.?/!{d}d".removingOccurrences(of: CharacterSet.whitespaces),
            "asad,.?/!{d}d"
        )
        
        XCTAssertEqual(
            "as , .?/! {d } d".removingOccurrences(of: CharacterSet.whitespaces),
            "as,.?/!{d}d"
        )
        
        XCTAssertEqual(
            "a’b, ".removingOccurrences(of: CharacterSet.punctuationCharacters),
            "ab "
        )
    }
    
    /// The `Codable` logic of `S3AutoPingItems.Expression` is manual, so we
    /// need to make sure it actually works or it might corrupt the repository file.
    func testAutoPingItemExpressionCodable() throws {
        typealias Expression = S3AutoPingItems.Expression
        
        do { /// Expression.text
            let exp = Expression.match("Hello-world")
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(exp)
            let string = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            
            XCTAssertEqual(string, #""T-Hello-world""#)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Expression.self, from: encoded)
            
            switch decoded {
            case .match("Hello-world"): break
            default:
                XCTFail("\(Expression.self) decoded wrong value: \(decoded)")
            }
        }
        
        do { /// Expression.contain
            let exp = Expression.contain("Hello-world")
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(exp)
            let string = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            
            XCTAssertEqual(string, #""C-Hello-world""#)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Expression.self, from: encoded)
            
            switch decoded {
            case .contain("Hello-world"): break
            default:
                XCTFail("\(Expression.self) decoded wrong value: \(decoded)")
            }
        }
    }
}

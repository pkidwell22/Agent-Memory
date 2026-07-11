import XCTest
@testable import QMDMenuBar

final class CollectionNamingTests: XCTestCase {
    func testCanonicalNamesOnlyContainQMDAllowedCharacters() {
        XCTAssertEqual(CollectionNaming.canonicalName(for: " Client / Alpha 🚀 "), "Client-Alpha")
        XCTAssertEqual(CollectionNaming.canonicalName(for: "___"), "collection")
        XCTAssertEqual(CollectionNaming.canonicalName(for: "snake_case"), "snake_case")
    }

    func testUniqueNamesResolveCaseInsensitiveCollisionsAndReservedNames() {
        let names = CollectionNaming.uniqueNames(
            for: ["Foo Bar", "Foo-Bar", "foo bar", "agent-memory-root"],
            reserved: ["agent-memory-root"]
        )

        XCTAssertEqual(names, ["Foo-Bar", "Foo-Bar-2", "foo-bar-3", "agent-memory-root-2"])
    }
}

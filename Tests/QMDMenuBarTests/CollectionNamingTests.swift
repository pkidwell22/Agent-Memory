import XCTest
@testable import QMDMenuBar

final class CollectionNamingTests: XCTestCase {
    func testCanonicalNamesOnlyContainQMDAllowedCharacters() {
        XCTAssertEqual(CollectionNaming.canonicalName(for: " Client / Alpha 🚀 "), "client-alpha")
        XCTAssertEqual(CollectionNaming.canonicalName(for: "___"), "collection")
        XCTAssertEqual(CollectionNaming.canonicalName(for: "snake_case"), "snake-case")
    }

    func testUniqueNamesResolveCaseInsensitiveCollisionsAndReservedNames() {
        let names = CollectionNaming.uniqueNames(
            for: ["Foo Bar", "Foo-Bar", "foo bar", "agent-memory-root"],
            reserved: ["agent-memory-root"]
        )

        XCTAssertEqual(names, ["foo-bar", "foo-bar-2", "foo-bar-3", "agent-memory-root-2"])
    }
}

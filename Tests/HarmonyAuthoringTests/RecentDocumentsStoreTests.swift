import XCTest
@testable import HarmonyAuthoring

final class RecentDocumentsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "RecentDocumentsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).json")
    }

    func test_record_newURL_prependsToEmptyList() {
        let store = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        store.record(url("a"))
        XCTAssertEqual(store.recentURLs(), [url("a")])
    }

    func test_record_ordersNewestFirst() {
        let store = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        store.record(url("a"))
        store.record(url("b"))
        XCTAssertEqual(store.recentURLs(), [url("b"), url("a")])
    }

    func test_record_existingURL_movesToFrontWithoutDuplicate() {
        let store = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        store.record(url("a"))
        store.record(url("b"))
        store.record(url("a"))
        XCTAssertEqual(store.recentURLs(), [url("a"), url("b")])
    }

    func test_record_respectsLimit() {
        let store = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 2)
        store.record(url("a"))
        store.record(url("b"))
        store.record(url("c"))
        XCTAssertEqual(store.recentURLs(), [url("c"), url("b")])
    }

    func test_persistsAcrossInstancesWithSameDefaultsAndKey() {
        let first = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        first.record(url("a"))

        let second = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        XCTAssertEqual(second.recentURLs(), [url("a")])
    }

    func test_clear_removesAllEntries() {
        let store = RecentDocumentsStore(defaults: defaults, key: "test.recent", limit: 10)
        store.record(url("a"))
        store.clear()
        XCTAssertEqual(store.recentURLs(), [])
    }
}

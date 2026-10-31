import XCTest
@testable import CamCardClone

/// `FileCardImageStore` 单元测试。
///
/// 覆盖 5.1 第二段「详情页展示原始图」的数据层：图像按名片落盘、按名字取回、
/// 名字可安全写入 `BusinessCard`（不含路径分隔符），以及名片删除后清理两张图。
///
/// 只验证存储语义，不涉及真实界面的图像呈现（属人工验收，见 `docs/UI验收清单.md`）。
final class CardImageStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardImageStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    private func makeStore() -> FileCardImageStore {
        FileCardImageStore(directory: directory)
    }

    private let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    // MARK: - 读写往返

    func testSaveThenLoadReturnsSameBytes() throws {
        let store = makeStore()
        let cardID = UUID()

        let name = try XCTUnwrap(store.save(bytes, cardID: cardID, kind: .original))

        XCTAssertEqual(store.load(named: name), bytes)
    }

    func testSaveCreatesDirectoryOnDemand() {
        let store = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        XCTAssertNotNil(store.save(bytes, cardID: UUID(), kind: .processed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testOriginalAndProcessedUseDistinctNames() throws {
        let store = makeStore()
        let cardID = UUID()

        let original = try XCTUnwrap(store.save(bytes, cardID: cardID, kind: .original))
        let processed = try XCTUnwrap(store.save(bytes, cardID: cardID, kind: .processed))

        XCTAssertNotEqual(original, processed, "原始图与校正图不得互相覆盖")
    }

    func testSavedNameHasNoPathSeparator() throws {
        let store = makeStore()
        let cardID = UUID()

        let name = try XCTUnwrap(store.save(bytes, cardID: cardID, kind: .original))

        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains("\\"))
        XCTAssertTrue(name.contains(cardID.uuidString.lowercased()))
    }

    // MARK: - 边界

    func testSaveRejectsEmptyData() {
        let store = makeStore()

        XCTAssertNil(store.save(Data(), cardID: UUID(), kind: .original))
    }

    func testLoadReturnsNilForMissingName() {
        let store = makeStore()
        _ = store.save(bytes, cardID: UUID(), kind: .original)

        XCTAssertNil(store.load(named: nil))
        XCTAssertNil(store.load(named: ""))
        XCTAssertNil(store.load(named: "not-a-real-file.jpg"))
    }

    func testLoadReturnsNilWhenFileWasRemoved() throws {
        let store = makeStore()
        let cardID = UUID()
        let name = try XCTUnwrap(store.save(bytes, cardID: cardID, kind: .original))

        store.deleteImages(for: cardID)

        XCTAssertNil(store.load(named: name))
    }

    // MARK: - 清理

    func testDeleteImagesRemovesBothKinds() {
        let store = makeStore()
        let cardID = UUID()
        _ = store.save(bytes, cardID: cardID, kind: .original)
        _ = store.save(bytes, cardID: cardID, kind: .processed)

        store.deleteImages(for: cardID)

        XCTAssertNil(store.load(named: FileCardImageStore.fileName(cardID: cardID, kind: .original)))
        XCTAssertNil(store.load(named: FileCardImageStore.fileName(cardID: cardID, kind: .processed)))
    }

    func testDeleteImagesLeavesOtherCardsUntouched() throws {
        let store = makeStore()
        let kept = UUID()
        let removed = UUID()
        let keptName = try XCTUnwrap(store.save(bytes, cardID: kept, kind: .original))
        _ = store.save(bytes, cardID: removed, kind: .original)

        store.deleteImages(for: removed)

        XCTAssertEqual(store.load(named: keptName), bytes)
    }
}

//
//  ClipboardHistoryStoreTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Saving and restoring clipboard history in a throwaway directory: the round
//  trip, image and thumbnail files, and cleanup of files nothing refers to.
//

import AppKit
import XCTest
@testable import boringNotch

final class ClipboardHistoryStoreTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipboardHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    private var store: ClipboardHistoryStore { ClipboardHistoryStore(directory: directory) }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testLoadsNothingBeforeTheFirstSave() {
        XCTAssertEqual(store.load(), [])
    }

    func testRoundTripsTextFilesAndImages() throws {
        let image = try saveImage(width: 40, height: 30)
        let items = [
            ClipboardItem(content: .text("hello"), sourceBundleIdentifier: "com.apple.Safari"),
            ClipboardItem(content: .files([URL(fileURLWithPath: "/tmp/a.txt")]), sourceBundleIdentifier: nil),
            ClipboardItem(content: .image(image), sourceBundleIdentifier: "com.apple.screencaptureui")
        ]
        try store.save(items)

        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.id), items.map(\.id))
        XCTAssertEqual(loaded.map(\.content), items.map(\.content))
        XCTAssertEqual(loaded.map(\.sourceBundleIdentifier), items.map(\.sourceBundleIdentifier))
        for (loadedItem, item) in zip(loaded, items) {
            XCTAssertEqual(loadedItem.copiedAt.timeIntervalSince1970, item.copiedAt.timeIntervalSince1970, accuracy: 0.001)
        }
        XCTAssertEqual(loaded.last?.image?.pixelWidth, 40)
    }

    func testStoresEachImageOnceWithASmallThumbnail() throws {
        let png = try ClipboardTestImage.png(width: 1200, height: 800)
        let image = try store.saveImage(ClipboardImageData(png: png, pixelWidth: 1200, pixelHeight: 800))
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: image)), png)

        let thumbnail = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: store.thumbnailURL(for: image))))
        XCTAssertEqual(max(thumbnail.pixelsWide, thumbnail.pixelsHigh), ClipboardHistoryStore.thumbnailMaxPixelSize)

        let again = try store.saveImage(ClipboardImageData(png: png, pixelWidth: 1200, pixelHeight: 800))
        XCTAssertEqual(again.hash, image.hash)
        XCTAssertEqual(try imageFileNames().count, 2)
    }

    func testLoadDropsEntriesWithMissingImagesAndDeletesUnusedFiles() throws {
        let kept = try saveImage(width: 10, height: 10)
        let lost = try saveImage(width: 20, height: 20)
        let unused = try saveImage(width: 30, height: 30)
        try store.save([
            ClipboardItem(content: .image(kept), sourceBundleIdentifier: nil),
            ClipboardItem(content: .image(lost), sourceBundleIdentifier: nil)
        ])
        try FileManager.default.removeItem(at: store.imageURL(for: lost))

        XCTAssertEqual(store.load().compactMap(\.image?.hash), [kept.hash])
        XCTAssertEqual(try imageFileNames(), ["\(kept.hash)-thumb.png", "\(kept.hash).png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: unused).path))
    }

    func testRemovesBothFilesOfAnImage() throws {
        let image = try saveImage(width: 8, height: 8)
        store.removeImageFiles(for: [image.hash])
        XCTAssertEqual(try imageFileNames(), [])
    }

    func testKeepsHistoryOutOfBackups() throws {
        try store.save([])
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - Helpers

    private func saveImage(width: Int, height: Int) throws -> ClipboardImage {
        let png = try ClipboardTestImage.png(width: width, height: height)
        return try store.saveImage(ClipboardImageData(png: png, pixelWidth: width, pixelHeight: height))
    }

    private func imageFileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path).sorted()
    }
}

//
//  ClipboardDropReaderTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  What a drop on the notch turns into, from item providers shaped like the
//  ones Finder, browsers and text fields hand over.
//

import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import boringNotch

final class ClipboardDropReaderTests: XCTestCase {
    @MainActor
    func testDroppedFilesAndFoldersBecomeOneEntry() async {
        let urls = [URL(fileURLWithPath: "/tmp/notes.txt"), URL(fileURLWithPath: "/tmp/Projects", isDirectory: true)]
        let providers = urls.map { NSItemProvider(object: $0 as NSURL) }

        guard case .content(.files(let files)) = await ClipboardDropReader.read(providers) else {
            return XCTFail("Expected one files entry")
        }
        XCTAssertEqual(files.map(\.path), urls.map(\.path))
    }

    @MainActor
    func testDroppedPictureBecomesAnImage() async throws {
        let png = try ClipboardTestImage.png(width: 6, height: 4)
        let provider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)

        guard case .image(let image) = await ClipboardDropReader.read([provider]) else {
            return XCTFail("Expected an image")
        }
        XCTAssertEqual(image.pixelWidth, 6)
        XCTAssertEqual(image.pixelHeight, 4)
    }

    @MainActor
    func testDroppedLinkBecomesText() async throws {
        let link = try XCTUnwrap(NSURL(string: "https://example.com/article"))

        guard case .content(.text(let text)) = await ClipboardDropReader.read([NSItemProvider(object: link)]) else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "https://example.com/article")
    }

    @MainActor
    func testDroppedTextBecomesText() async {
        guard case .content(.text(let text)) = await ClipboardDropReader.read([NSItemProvider(object: "Call Ana at 10" as NSString)]) else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Call Ana at 10")
    }

    @MainActor
    func testEmptyDropIsIgnored() async {
        let dropped = await ClipboardDropReader.read([])
        XCTAssertNil(dropped)
    }
}

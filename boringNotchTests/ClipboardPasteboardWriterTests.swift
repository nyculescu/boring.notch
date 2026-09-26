//
//  ClipboardPasteboardWriterTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  What a restored or dropped entry leaves on the pasteboard, checked on a
//  private, uniquely named pasteboard rather than the user's clipboard.
//

import AppKit
import XCTest
@testable import boringNotch

final class ClipboardPasteboardWriterTests: XCTestCase {
    private let pasteboard = NSPasteboard.withUniqueName()
    private let files = [
        URL(fileURLWithPath: "/Users/me/Documents/Report Q3.pdf"),
        URL(fileURLWithPath: "/Users/me/Pictures/Holiday", isDirectory: true)
    ]

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testFilesPasteAsFilesInFinderAndAsPathsInText() {
        ClipboardPasteboardWriter.write(files: files, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), files.map(\.path))
        XCTAssertEqual(pasteboard.string(forType: .string), "/Users/me/Documents/Report Q3.pdf\n/Users/me/Pictures/Holiday")
    }

    func testWrittenFilesReadBackAsTheSameFilesEntry() {
        ClipboardPasteboardWriter.write(files: files, to: pasteboard)
        guard case .content(.files(let urls)) = ClipboardPasteboardReader.read(pasteboard) else {
            return XCTFail("Expected a files entry")
        }
        XCTAssertEqual(urls.map(\.path), files.map(\.path))
    }

    func testTextReplacesEarlierFiles() {
        ClipboardPasteboardWriter.write(files: files, to: pasteboard)
        ClipboardPasteboardWriter.write(text: "hello", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertFalse(pasteboard.types?.contains(.fileURL) ?? false)
    }

    func testImagesGoOnAsPNGAndTIFF() throws {
        let png = try ClipboardTestImage.png(width: 6, height: 4)
        ClipboardPasteboardWriter.write(png: png, to: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }
}

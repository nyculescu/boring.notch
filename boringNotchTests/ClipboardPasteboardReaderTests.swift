//
//  ClipboardPasteboardReaderTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Fixtures go on a private, uniquely named pasteboard rather than the
//  general one, so running the tests leaves the user's clipboard alone.
//

import AppKit
import XCTest
@testable import boringNotch

final class ClipboardPasteboardReaderTests: XCTestCase {
    private let pasteboard = NSPasteboard.withUniqueName()

    override func setUp() {
        super.setUp()
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testReadsPlainText() {
        write([.string: Data("hello world".utf8)])
        XCTAssertEqual(readContent(), .text("hello world"))
    }

    func testSkipsWhitespaceOnlyText() {
        write([.string: Data("  \n\t ".utf8)])
        assertSkipped()
    }

    func testSkipsCopiesMarkedConcealed() {
        write([
            .string: Data("hunter2".utf8),
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"): Data()
        ])
        assertSkipped()
    }

    func testPrefersFilesOverTheirNames() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        write([.fileURL: Data(url.absoluteString.utf8), .string: Data("report.pdf".utf8)])
        XCTAssertEqual(readContent(), .files([url]))
    }

    func testReadsScreenshotPNG() throws {
        let png = try ClipboardTestImage.png(width: 4, height: 3)
        write([.png: png])
        let image = try XCTUnwrap(readImage())
        XCTAssertEqual(image.png, png)
        XCTAssertEqual(image.pixelWidth, 4)
        XCTAssertEqual(image.pixelHeight, 3)
    }

    func testConvertsTIFFToPNG() throws {
        write([.tiff: try ClipboardTestImage.tiff(width: 5, height: 2)])
        let image = try XCTUnwrap(readImage())
        XCTAssertEqual(image.png.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertEqual(image.pixelWidth, 5)
        XCTAssertEqual(image.pixelHeight, 2)
    }

    func testImageWinsOverALinkToIt() throws {
        write([.png: try ClipboardTestImage.png(width: 4, height: 4), .string: Data("https://example.com/cat.png".utf8)])
        XCTAssertNotNil(readImage())
    }

    func testTextWinsOverARenderedPictureOfIt() throws {
        write([.png: try ClipboardTestImage.png(width: 4, height: 4), .string: Data("Q1\tQ2\n10\t20".utf8)])
        XCTAssertEqual(readContent(), .text("Q1\tQ2\n10\t20"))
    }

    // MARK: - Helpers

    private func write(_ representations: [NSPasteboard.PasteboardType: Data]) {
        let item = NSPasteboardItem()
        for (type, data) in representations {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    private func readContent() -> ClipboardItem.Content? {
        if case .content(let content) = ClipboardPasteboardReader.read(pasteboard) {
            return content
        }
        return nil
    }

    private func readImage() -> ClipboardImageData? {
        if case .image(let image) = ClipboardPasteboardReader.read(pasteboard) {
            return image
        }
        return nil
    }

    private func assertSkipped(file: StaticString = #filePath, line: UInt = #line) {
        guard case .skipped = ClipboardPasteboardReader.read(pasteboard) else {
            return XCTFail("Expected the copy to be skipped", file: file, line: line)
        }
    }
}

/// Small generated images for the clipboard tests.
enum ClipboardTestImage {
    static func png(width: Int, height: Int) throws -> Data {
        try XCTUnwrap(bitmap(width: width, height: height).representation(using: .png, properties: [:]))
    }

    static func tiff(width: Int, height: Int) throws -> Data {
        try XCTUnwrap(bitmap(width: width, height: height).tiffRepresentation)
    }

    private static func bitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        // Deterministic pixels, so equal sizes give equal data and hashes.
        let pixels = try XCTUnwrap(rep.bitmapData)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rep.bytesPerRow + x * 4
                pixels[offset] = UInt8(x % 256)
                pixels[offset + 1] = UInt8(y % 256)
                pixels[offset + 2] = 128
                pixels[offset + 3] = 255
            }
        }
        return rep
    }
}

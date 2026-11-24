import CoreGraphics
import Foundation
import XCTest

@testable import Lucide

final class LucideSVGTests: XCTestCase {
  func testParsesLucideRootAttributesAndStrokedPaths() throws {
    let glyph = try LucideSVG.parse(Fixtures.x)
    XCTAssertEqual(glyph.viewBox, CGRect(x: 0, y: 0, width: 24, height: 24))
    XCTAssertEqual(glyph.strokeWidth, 2)
    XCTAssertEqual(glyph.lineCap, .round)
    XCTAssertEqual(glyph.lineJoin, .round)
    XCTAssertEqual(glyph.elements.count, 2)
    XCTAssertTrue(glyph.elements.allSatisfy { $0.isStroked && !$0.isFilled })
  }

  func testShapesAndElementFillInheritStrokeFromRoot() throws {
    let glyph = try LucideSVG.parse(Fixtures.svg("""
      <circle cx="12" cy="12" r="1" fill="currentColor" />
      <rect x="3" y="3" width="18" height="18" rx="2" />
      <line x1="1" y1="2" x2="3" y2="4" />
      <ellipse cx="12" cy="5" rx="9" ry="3" />
      <polygon points="1,1 5,1 3,4" />
      <polyline points="1 1 2 2 3 1" />
      """))
    XCTAssertEqual(glyph.elements.count, 6)
    XCTAssertTrue(glyph.elements[0].isFilled && glyph.elements[0].isStroked)
    XCTAssertTrue(glyph.elements.dropFirst().allSatisfy { !$0.isFilled && $0.isStroked })
    XCTAssertEqual(glyph.elements[2].segments, [.move(CGPoint(x: 1, y: 2)), .line(CGPoint(x: 3, y: 4))])
    XCTAssertEqual(glyph.elements[4].segments.last, .close)
    XCTAssertNotEqual(glyph.elements[5].segments.last, .close)

    let rect = glyph.path(.stroke, in: CGRect(x: 0, y: 0, width: 24, height: 24))
    XCTAssertEqual(rect.boundingBoxOfPath.minX, 1, accuracy: 1e-9)
    XCTAssertEqual(rect.boundingBoxOfPath.maxX, 21, accuracy: 1e-9)
  }

  func testIgnoresUnsupportedElementsAndTheirChildren() throws {
    let glyph = try LucideSVG.parse(Fixtures.svg("""
      <script>alert(1)</script>
      <defs><path d="M0 0 24 24" /></defs>
      <image href="https://example.com/a.png" />
      <g><path d="M1 1 2 2" /></g>
      """))
    XCTAssertEqual(glyph.elements.map(\.segments), [[.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2))]])
  }

  func testRejectsDocumentTypesEntitiesAndNonSVG() {
    let entity = Data("""
      <?xml version="1.0"?><!DOCTYPE svg [<!ENTITY a "aaaa">]>
      <svg viewBox="0 0 24 24"><path d="M0 0&a;" /></svg>
      """.utf8)
    XCTAssertThrowsError(try LucideSVG.parse(entity)) { XCTAssertEqual($0 as? LucideSVGError, .malformedDocument) }
    XCTAssertThrowsError(try LucideSVG.parse(Data("<html><path d=\"M0 0\"/></html>".utf8))) {
      XCTAssertEqual($0 as? LucideSVGError, .notSVG)
    }
    XCTAssertThrowsError(try LucideSVG.parse(Data("<svg".utf8)))
  }

  func testReportsInvalidPathDataAndElementLimit() {
    XCTAssertThrowsError(try LucideSVG.parse(Fixtures.svg("<path d=\"M0 0\"/><path d=\"M1\"/>"))) {
      XCTAssertEqual($0 as? LucideSVGError, .invalidPathData(element: 1))
    }
    let many = String(repeating: "<path d=\"M0 0 1 1\"/>", count: LucideSVG.maximumElementCount + 1)
    XCTAssertThrowsError(try LucideSVG.parse(Fixtures.svg(many))) {
      XCTAssertEqual($0 as? LucideSVGError, .tooManyElements)
    }
  }

  func testMapsViewBoxIntoRectWithRelativeOrAbsoluteStroke() throws {
    let glyph = try LucideSVG.parse(Fixtures.svg("<path d=\"M0 0 24 24\"/>"))
    let rect = CGRect(x: 10, y: 0, width: 48, height: 48)
    XCTAssertEqual(glyph.path(.stroke, in: rect).boundingBoxOfPath, CGRect(x: 10, y: 0, width: 48, height: 48))
    XCTAssertEqual(glyph.lineWidth(in: rect), 4)
    XCTAssertEqual(glyph.lineWidth(1.5, absolute: true, in: rect), 1.5)
  }

  func testRasterizesTransparentTemplateBitmap() throws {
    let glyph = try LucideSVG.parse(Fixtures.x)
    let image = try XCTUnwrap(glyph.cgImage(pointSize: 16, scale: 3))
    XCTAssertEqual(image.width, 48)
    XCTAssertEqual(image.height, 48)
    XCTAssertEqual(image.alphaInfo, .premultipliedLast)
  }

  func testPlatformImageIsATemplateAtPointSize() throws {
    let glyph = try LucideSVG.parse(Fixtures.x)
    #if canImport(UIKit)
    let image = try XCTUnwrap(glyph.image(pointSize: 20, scale: 3))
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
    XCTAssertEqual(image.size, CGSize(width: 20, height: 20))
    XCTAssertEqual(image.scale, 3)
    #elseif canImport(AppKit)
    let image = try XCTUnwrap(glyph.image(pointSize: 20, scale: 2))
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size, NSSize(width: 20, height: 20))
    #endif
  }

  /// Every icon in a published release must parse. Point `LUCIDE_ICONS_DIR` at the `icons`
  /// directory of an unpacked `lucide-static` package to run it.
  func testParsesEveryIconInLucideRelease() throws {
    guard let directory = ProcessInfo.processInfo.environment["LUCIDE_ICONS_DIR"] else {
      throw XCTSkip("LUCIDE_ICONS_DIR is not set")
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasSuffix(".svg") }
    XCTAssertFalse(files.isEmpty)
    for file in files {
      let data = try Data(contentsOf: URL(filePath: directory).appending(path: file))
      XCTAssertLessThanOrEqual(data.count, LucidePipeline.maximumDocumentSize, file)
      let glyph = try LucideSVG.parse(data)
      XCTAssertFalse(glyph.elements.isEmpty, file)
    }
  }
}

enum Fixtures {
  static let x = svg("<path d=\"M18 6 6 18\" />\n<path d=\"m6 6 12 12\" />")

  static func svg(_ body: String) -> Data {
    Data("""
      <!-- @license lucide-static v1.70.0 - ISC -->
      <svg class="lucide" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      \(body)
      </svg>
      """.utf8)
  }
}

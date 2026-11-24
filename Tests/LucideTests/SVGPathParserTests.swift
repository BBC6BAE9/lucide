import CoreGraphics
import XCTest

@testable import Lucide

final class SVGPathParserTests: XCTestCase {
  func testMoveRepeatsAsLineInBothCases() throws {
    XCTAssertEqual(try SVGPathParser.parse("M18 6 6 18"), [.move(CGPoint(x: 18, y: 6)), .line(CGPoint(x: 6, y: 18))])
    XCTAssertEqual(try SVGPathParser.parse("m6 6 12 12"), [.move(CGPoint(x: 6, y: 6)), .line(CGPoint(x: 18, y: 18))])
  }

  func testCompactNumbersSignsAndExponents() throws {
    XCTAssertEqual(try SVGPathParser.parse("M1.5.5-1-2"), [.move(CGPoint(x: 1.5, y: 0.5)), .line(CGPoint(x: -1, y: -2))])
    XCTAssertEqual(try SVGPathParser.parse("M1e1,2E-1"), [.move(CGPoint(x: 10, y: 0.2))])
  }

  func testRelativeHorizontalVerticalAndClose() throws {
    XCTAssertEqual(try SVGPathParser.parse("M2 2h4v4zl1 1"), [
      .move(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 6, y: 2)), .line(CGPoint(x: 6, y: 6)), .close,
      .line(CGPoint(x: 3, y: 3)),
    ])
  }

  func testSmoothCurvesReflectThePreviousControlPoint() throws {
    XCTAssertEqual(try SVGPathParser.parse("M0 0C1 1 2 1 3 0S5 -1 6 0"), [
      .move(.zero),
      .cubic(CGPoint(x: 3, y: 0), control1: CGPoint(x: 1, y: 1), control2: CGPoint(x: 2, y: 1)),
      .cubic(CGPoint(x: 6, y: 0), control1: CGPoint(x: 4, y: -1), control2: CGPoint(x: 5, y: -1)),
    ])
    XCTAssertEqual(try SVGPathParser.parse("M0 0Q1 1 2 0t2 0"), [
      .move(.zero), .quad(CGPoint(x: 2, y: 0), control: CGPoint(x: 1, y: 1)),
      .quad(CGPoint(x: 4, y: 0), control: CGPoint(x: 3, y: -1)),
    ])
    XCTAssertEqual(try SVGPathParser.parse("M0 0L1 1S2 2 3 3")[2],
                   .cubic(CGPoint(x: 3, y: 3), control1: CGPoint(x: 1, y: 1), control2: CGPoint(x: 2, y: 2)))
  }

  func testSemicircleArcPassesThroughItsApex() throws {
    let segments = try SVGPathParser.parse("M0 0A1 1 0 0 1 2 0")
    XCTAssertEqual(segments.count, 3)
    assertEnd(segments[1], near: CGPoint(x: 1, y: -1))
    assertEnd(segments[2], near: CGPoint(x: 2, y: 0))
  }

  func testArcFlagsWithoutSeparatorsAndUndersizedRadii() throws {
    let compact = try SVGPathParser.parse("M0 0a1 1 0 011 1")
    assertEnd(try XCTUnwrap(compact.last), near: CGPoint(x: 1, y: 1))

    let scaled = try SVGPathParser.parse("M0 0A0.5 0.5 0 0 1 4 0")
    assertEnd(scaled[1], near: CGPoint(x: 2, y: -2))
    assertEnd(try XCTUnwrap(scaled.last), near: CGPoint(x: 4, y: 0))
  }

  func testZeroRadiusArcIsALine() throws {
    XCTAssertEqual(try SVGPathParser.parse("M0 0A0 1 0 0 1 2 0"), [.move(.zero), .line(CGPoint(x: 2, y: 0))])
  }

  func testRejectsMalformedData() {
    for data in ["M1", "M0 0Z 1 1", "1 1", "M0 0A1 1 0 2 1 2 0", "M0 0X1 1", "M. 1"] {
      XCTAssertThrowsError(try SVGPathParser.parse(data), data)
    }
  }

  private func assertEnd(_ segment: PathSegment, near point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
    guard case .cubic(let end, _, _) = segment else { return XCTFail("\(segment) is not a curve", file: file, line: line) }
    XCTAssertEqual(end.x, point.x, accuracy: 1e-9, file: file, line: line)
    XCTAssertEqual(end.y, point.y, accuracy: 1e-9, file: file, line: line)
  }
}

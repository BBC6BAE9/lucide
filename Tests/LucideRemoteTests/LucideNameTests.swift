import Foundation
import XCTest

@testable import LucideRemote

final class LucideNameTests: XCTestCase {
  func testRawValuesAreLucideFileNames() {
    XCTAssertEqual(LucideName.allCases.count, 2029)
    XCTAssertEqual(Set(LucideName.allCases.map(\.rawValue)).count, LucideName.allCases.count)
    XCTAssertEqual(LucideName.arrowUpRight.rawValue, "arrow-up-right")
    XCTAssertEqual(LucideName.arrowDown01.rawValue, "arrow-down-0-1")
    XCTAssertEqual(LucideName.repeat.rawValue, "repeat")
    let kebab = /^[a-z0-9]+(-[a-z0-9]+)*$/
    XCTAssertTrue(LucideName.allCases.allSatisfy { $0.rawValue.wholeMatch(of: kebab) != nil })
  }

  func testServerProvidedNamesRoundTripThroughRawValue() {
    XCTAssertEqual(LucideName(rawValue: "book-open"), .bookOpen)
    XCTAssertNil(LucideName(rawValue: "../book-open"))
    XCTAssertNil(LucideName(rawValue: "alert-triangle"))
  }

  @available(*, deprecated)
  func testRenamedIconsResolveToTheirCurrentName() {
    XCTAssertEqual(LucideName.alertTriangle, .triangleExclamationPoint)
  }

  func testDefaultSourceMatchesTheGeneratedRelease() {
    XCTAssertEqual(LucideSource.defaultVersion, LucideName.version)
    XCTAssertEqual(LucidePipeline.shared.source.version, LucideName.version)
  }

  /// With `LUCIDE_ICONS_DIR` set (see `LucideSVGTests`), every case must exist in the release.
  func testEveryCaseExistsInLucideRelease() throws {
    guard let directory = ProcessInfo.processInfo.environment["LUCIDE_ICONS_DIR"] else {
      throw XCTSkip("LUCIDE_ICONS_DIR is not set")
    }
    for name in LucideName.allCases {
      XCTAssertTrue(FileManager.default.fileExists(atPath: "\(directory)/\(name.rawValue).svg"), name.rawValue)
    }
  }
}

import Foundation
import XCTest
import os

@testable import Lucide

final class LucidePipelineTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "LucideTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    StubProtocol.reset()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    StubProtocol.reset()
  }

  func testConcurrentRequestsShareOneDownloadAndFillMemory() async throws {
    StubProtocol.respond { _ in (200, Fixtures.x) }
    let pipeline = makePipeline()
    try await withThrowingTaskGroup(of: LucideGlyph.self) { group in
      for _ in 0..<8 { group.addTask { try await pipeline.glyph(.x) } }
      for try await glyph in group { XCTAssertEqual(glyph.elements.count, 2) }
    }
    XCTAssertEqual(StubProtocol.requests, ["https://icons.test/1.70.0/x.svg"])
    XCTAssertNotNil(pipeline.cachedGlyph(.x))
  }

  func testDiskCacheServesLaterPipelinesWithoutNetwork() async throws {
    StubProtocol.respond { _ in (200, Fixtures.x) }
    _ = try await makePipeline().glyph(.x)
    StubProtocol.respond { _ in (500, Data()) }

    let offline = makePipeline()
    XCTAssertNil(offline.cachedGlyph(.x))
    let glyph = try await offline.glyph(.x)
    XCTAssertEqual(glyph.elements.count, 2)
    XCTAssertEqual(StubProtocol.requests.count, 1)
  }

  func testCorruptDiskEntryIsDownloadedAgain() async throws {
    let cached = directory.appending(path: "1.70.0/x.svg")
    try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("<svg".utf8).write(to: cached)
    StubProtocol.respond { _ in (200, Fixtures.x) }

    let glyph = try await makePipeline().glyph(.x)
    XCTAssertEqual(glyph.elements.count, 2)
    XCTAssertEqual(StubProtocol.requests.count, 1)
    XCTAssertEqual(try Data(contentsOf: cached), Fixtures.x)
  }

  func testBundledFallbackRendersWithoutNetwork() async throws {
    let bundleDirectory = directory.appending(path: "Fallback.bundle/Icons")
    try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
    try Fixtures.x.write(to: bundleDirectory.appending(path: "x.svg"))
    let bundle = try XCTUnwrap(Bundle(url: directory.appending(path: "Fallback.bundle")))
    StubProtocol.respond { _ in (500, Data()) }

    let pipeline = makePipeline(bundle: bundle, subdirectory: "Icons")
    let glyph = try await pipeline.glyph(.x)
    XCTAssertEqual(glyph.elements.count, 2)
    XCTAssertTrue(StubProtocol.requests.isEmpty)
  }

  func testLocalGlyphReadsBundleAndDiskButNeverTheNetwork() async throws {
    let bundleDirectory = directory.appending(path: "Local.bundle")
    try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
    try Fixtures.x.write(to: bundleDirectory.appending(path: "x.svg"))
    let disk = directory.appending(path: "1.70.0/search.svg")
    try FileManager.default.createDirectory(at: disk.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Fixtures.x.write(to: disk)
    StubProtocol.respond { _ in (200, Fixtures.x) }

    let pipeline = makePipeline(bundle: Bundle(url: bundleDirectory))
    XCTAssertNotNil(pipeline.localGlyph(.x))
    XCTAssertNotNil(pipeline.localGlyph(.search))
    XCTAssertNil(pipeline.localGlyph(.trash))
    XCTAssertNotNil(pipeline.cachedGlyph(.x))
    XCTAssertTrue(StubProtocol.requests.isEmpty)
  }

  func testMapsHTTPFailuresAndLeavesNoCacheEntry() async {
    let pipeline = makePipeline()
    StubProtocol.respond { _ in (404, Data()) }
    await assertThrows(.notFound(.bellOff)) { try await pipeline.glyph(.bellOff) }
    StubProtocol.respond { _ in (503, Data()) }
    await assertThrows(.httpStatus(503)) { try await pipeline.glyph(.bellOff) }
    XCTAssertNil(pipeline.cachedGlyph(.bellOff))
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "1.70.0/bell-off.svg").path()))
  }

  func testRejectsOversizedAndInvalidDocuments() async {
    let pipeline = makePipeline()
    StubProtocol.respond { _ in (200, Data(count: LucidePipeline.maximumDocumentSize + 1)) }
    await assertThrows(.tooLarge) { try await pipeline.glyph(.monitor) }
    StubProtocol.respond { _ in (200, Data("<html/>".utf8)) }
    await assertThrows(.invalidSVG(.notSVG)) { try await pipeline.glyph(.panelLeft) }
  }

  func testMemoryLimitEvictsOldestEntries() async throws {
    StubProtocol.respond { _ in (200, Fixtures.x) }
    let pipeline = makePipeline(memoryLimit: 2)
    for name in [LucideName.x, .search, .trash] { _ = try await pipeline.glyph(name) }
    XCTAssertNil(pipeline.cachedGlyph(.x))
    XCTAssertNotNil(pipeline.cachedGlyph(.search))
    XCTAssertNotNil(pipeline.cachedGlyph(.trash))
  }

  func testPublicSourcesPinTheVersion() {
    XCTAssertEqual(LucideSource.jsDelivr(version: "1.70.0").url(for: .x).absoluteString,
                   "https://cdn.jsdelivr.net/npm/lucide-static@1.70.0/icons/x.svg")
    XCTAssertEqual(LucideSource.unpkg(version: "1.70.0").url(for: .x).absoluteString,
                   "https://unpkg.com/lucide-static@1.70.0/icons/x.svg")
    XCTAssertEqual(LucideSource.mirror(URL(string: "https://cdn.example.com/lucide")!).url(for: .x).absoluteString,
                   "https://cdn.example.com/lucide/x.svg")
  }

  private func makePipeline(bundle: Bundle? = nil, subdirectory: String? = nil, memoryLimit: Int = 1024) -> LucidePipeline {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let source = LucideSource(version: "1.70.0") { URL(string: "https://icons.test/1.70.0/\($0).svg")! }
    return LucidePipeline(source: source, session: URLSession(configuration: configuration), bundle: bundle,
                          bundleSubdirectory: subdirectory, diskCache: directory, memoryLimit: memoryLimit)
  }

  private func assertThrows(_ expected: LucideIconError, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> some Any) async {
    do {
      _ = try await body()
      XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
      XCTAssertEqual(error as? LucideIconError, expected, file: file, line: line)
    }
  }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) -> (Int, Data)

  private struct State {
    var handler: Handler?
    var requests: [String] = []
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())

  static var requests: [String] { state.withLock { $0.requests } }
  static func respond(_ handler: @escaping Handler) { state.withLock { $0.handler = handler } }
  static func reset() { state.withLock { $0 = State() } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let handler = Self.state.withLock { state -> Handler? in
      state.requests.append(request.url?.absoluteString ?? "")
      return state.handler
    }
    let (status, data) = handler?(request) ?? (500, Data())
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

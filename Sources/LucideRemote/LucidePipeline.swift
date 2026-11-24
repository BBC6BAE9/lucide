import Foundation
import os

/// Where icon documents are downloaded from. `version` also namespaces the disk cache, so a
/// pinned version is never mixed with another one.
public struct LucideSource: Sendable {
  /// The release `LucideName` was generated from; other versions may lack some names.
  public static let defaultVersion = LucideName.version

  public let version: String
  private let resolve: @Sendable (String) -> URL

  public init(version: String, url: @escaping @Sendable (_ name: String) -> URL) {
    self.version = version
    self.resolve = url
  }

  public func url(for name: LucideName) -> URL { resolve(name.rawValue) }

  public static func jsDelivr(version: String = defaultVersion) -> LucideSource {
    LucideSource(version: version) { URL(string: "https://cdn.jsdelivr.net/npm/lucide-static@\(version)/icons/\($0).svg")! }
  }

  public static func unpkg(version: String = defaultVersion) -> LucideSource {
    LucideSource(version: version) { URL(string: "https://unpkg.com/lucide-static@\(version)/icons/\($0).svg")! }
  }

  /// A self-hosted mirror laid out as `<base>/<name>.svg`.
  public static func mirror(_ base: URL, version: String = defaultVersion) -> LucideSource {
    LucideSource(version: version) { base.appending(path: "\($0).svg") }
  }
}

public enum LucideIconError: Error, Equatable {
  case notFound(LucideName)
  case httpStatus(Int)
  case tooLarge
  case invalidSVG(LucideSVGError)
}

/// Loads icons: memory cache, then the bundled fallback directory, then the disk cache, then
/// the network. Concurrent requests for one icon share a single download.
public final class LucidePipeline: Sendable {
  public static let shared = LucidePipeline()
  public static let maximumDocumentSize = 64 * 1024

  public let source: LucideSource
  private let session: URLSession
  private let fallbackDirectory: URL?
  private let diskDirectory: URL?
  private let memoryLimit: Int
  private let state = OSAllocatedUnfairLock(initialState: State())

  private struct State {
    var memory: [LucideName: LucideGlyph] = [:]
    var insertionOrder: [LucideName] = []
    var inFlight: [LucideName: Task<LucideGlyph, Error>] = [:]
  }

  /// - Parameters:
  ///   - bundle: Ships `<name>.svg` files that must render offline and on first launch.
  ///   - diskCache: Pass `nil` to keep downloads in memory only.
  public init(source: LucideSource = .jsDelivr(), session: URLSession = .shared,
              bundle: Bundle? = nil, bundleSubdirectory: String? = nil,
              diskCache: URL? = LucidePipeline.defaultDiskCache, memoryLimit: Int = 1024) {
    self.source = source
    self.session = session
    self.fallbackDirectory = bundle?.resourceURL.map { url in
      bundleSubdirectory.map { url.appending(path: $0, directoryHint: .isDirectory) } ?? url
    }
    let version = String(source.version.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    self.diskDirectory = diskCache?.appending(path: version, directoryHint: .isDirectory)
    self.memoryLimit = max(1, memoryLimit)
  }

  public static var defaultDiskCache: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "LucideRemote", directoryHint: .isDirectory)
  }

  /// Synchronous memory lookup, so an already-loaded icon renders without a placeholder frame.
  public func cachedGlyph(_ name: LucideName) -> LucideGlyph? {
    state.withLock { $0.memory[name] }
  }

  /// Memory, the bundled fallback or the disk cache, never the network. For surfaces that need
  /// the icon in the same frame, such as menu items, which only accept a finished image.
  public func localGlyph(_ name: LucideName) -> LucideGlyph? {
    if let glyph = cachedGlyph(name) { return glyph }
    guard let glyph = try? loadLocal(name) else { return nil }
    remember(glyph, for: name)
    return glyph
  }

  public func glyph(_ name: LucideName) async throws -> LucideGlyph {
    if let glyph = cachedGlyph(name) { return glyph }
    let task = state.withLock { state -> Task<LucideGlyph, Error> in
      if let task = state.inFlight[name] { return task }
      let task = Task.detached { [self] in
        defer { self.state.withLock { _ = $0.inFlight.removeValue(forKey: name) } }
        let glyph = try await self.load(name)
        self.remember(glyph, for: name)
        return glyph
      }
      state.inFlight[name] = task
      return task
    }
    return try await task.value
  }

  /// Starts loading without waiting; failures are left for the next `glyph(_:)` call.
  public func prefetch(_ names: some Sequence<LucideName>) {
    for name in names {
      Task.detached { [self] in _ = try? await self.glyph(name) }
    }
  }

  public func removeAllFromMemory() {
    state.withLock {
      $0.memory.removeAll()
      $0.insertionOrder.removeAll()
    }
  }

  private func remember(_ glyph: LucideGlyph, for name: LucideName) {
    state.withLock { state in
      if state.memory.updateValue(glyph, forKey: name) == nil { state.insertionOrder.append(name) }
      while state.insertionOrder.count > memoryLimit {
        state.memory.removeValue(forKey: state.insertionOrder.removeFirst())
      }
    }
  }

  /// `nil` when neither local store has the icon; throws only for a broken bundled document.
  private func loadLocal(_ name: LucideName) throws -> LucideGlyph? {
    let file = "\(name.rawValue).svg"
    if let url = fallbackDirectory?.appending(path: file), let data = try? Data(contentsOf: url) {
      return try decode(data)
    }
    if let url = diskDirectory?.appending(path: file), let data = try? Data(contentsOf: url) {
      return try? decode(data)
    }
    return nil
  }

  private func load(_ name: LucideName) async throws -> LucideGlyph {
    if let glyph = try loadLocal(name) { return glyph }
    let cached = diskDirectory?.appending(path: "\(name.rawValue).svg")

    let (data, response) = try await session.data(from: source.url(for: name))
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 404 { throw LucideIconError.notFound(name) }
    guard (200..<300).contains(status) else { throw LucideIconError.httpStatus(status) }
    let glyph = try decode(data)

    if let cached, let directory = diskDirectory {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? data.write(to: cached, options: .atomic)
    }
    return glyph
  }

  private func decode(_ data: Data) throws -> LucideGlyph {
    guard data.count <= Self.maximumDocumentSize else { throw LucideIconError.tooLarge }
    do {
      return try LucideSVG.parse(data)
    } catch let error as LucideSVGError {
      throw LucideIconError.invalidSVG(error)
    }
  }
}

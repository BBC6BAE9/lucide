import SwiftUI

extension EnvironmentValues {
  @Entry public var lucidePipeline: LucidePipeline = .shared
}

/// A Lucide icon drawn as vector shapes in the current foreground style. Bundled and cached
/// icons draw in the first frame; others reserve their frame while they download, so layout
/// does not jump when they arrive.
///
/// Like a bare `Shape`, the icon carries no accessibility label; label the control around it.
public struct LucideIcon: View {
  private let name: LucideName
  private let size: CGFloat
  private let strokeWidth: CGFloat?
  private let absoluteStrokeWidth: Bool

  @Environment(\.lucidePipeline) private var pipeline
  @State private var loaded: (name: LucideName, glyph: LucideGlyph)?

  /// - Parameters:
  ///   - strokeWidth: Overrides the document's stroke width (Lucide uses 2 on a 24-unit grid).
  ///   - absoluteStrokeWidth: Keeps the line `strokeWidth` points wide at every size.
  public init(_ name: LucideName, size: CGFloat = 24, strokeWidth: CGFloat? = nil, absoluteStrokeWidth: Bool = false) {
    self.name = name
    self.size = size
    self.strokeWidth = strokeWidth
    self.absoluteStrokeWidth = absoluteStrokeWidth
  }

  public var body: some View {
    let glyph = loaded?.name == name ? loaded?.glyph : pipeline.localGlyph(name)
    ZStack {
      if let glyph {
        LucideGlyphView(glyph: glyph, strokeWidth: strokeWidth, absoluteStrokeWidth: absoluteStrokeWidth)
      }
    }
    .frame(width: size, height: size)
    .task(id: name) {
      guard pipeline.cachedGlyph(name) == nil, let glyph = try? await pipeline.glyph(name) else { return }
      loaded = (name, glyph)
    }
  }
}

/// Draws an already-loaded glyph to fill the proposed size.
public struct LucideGlyphView: View {
  let glyph: LucideGlyph
  let strokeWidth: CGFloat?
  let absoluteStrokeWidth: Bool

  public init(glyph: LucideGlyph, strokeWidth: CGFloat? = nil, absoluteStrokeWidth: Bool = false) {
    self.glyph = glyph
    self.strokeWidth = strokeWidth
    self.absoluteStrokeWidth = absoluteStrokeWidth
  }

  public var body: some View {
    GeometryReader { proxy in
      let rect = CGRect(origin: .zero, size: proxy.size)
      ZStack {
        LucideGlyphShape(glyph: glyph, part: .fill).fill()
        LucideGlyphShape(glyph: glyph, part: .stroke)
          .stroke(style: StrokeStyle(
            lineWidth: glyph.lineWidth(strokeWidth, absolute: absoluteStrokeWidth, in: rect),
            lineCap: glyph.lineCap.cgLineCap, lineJoin: glyph.lineJoin.cgLineJoin))
      }
    }
  }
}

public struct LucideGlyphShape: Shape {
  public let glyph: LucideGlyph
  public let part: LucideGlyph.Part

  public init(glyph: LucideGlyph, part: LucideGlyph.Part) {
    self.glyph = glyph
    self.part = part
  }

  public func path(in rect: CGRect) -> Path {
    Path(glyph.path(part, in: rect))
  }
}

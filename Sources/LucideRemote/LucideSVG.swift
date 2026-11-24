import CoreGraphics
import Foundation

public enum LucideSVGError: Error, Equatable {
  case malformedDocument
  case notSVG
  case invalidViewBox
  case invalidPathData(element: Int)
  case tooManyElements
}

/// Parses the SVG subset Lucide publishes: `path`, `circle`, `ellipse`, `rect`, `line`,
/// `polyline` and `polygon`, inside `svg` and `g`. Other elements and their children are
/// ignored, so scripts, images, `use` references and `defs` never draw or load anything.
public enum LucideSVG {
  public static let maximumElementCount = 512

  public static func parse(_ data: Data) throws -> LucideGlyph {
    if data.range(of: Data("<!DOCTYPE".utf8)) != nil || data.range(of: Data("<!ENTITY".utf8)) != nil {
      throw LucideSVGError.malformedDocument
    }
    let delegate = DocumentDelegate()
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.shouldProcessNamespaces = false
    parser.delegate = delegate
    let succeeded = parser.parse()
    if let failure = delegate.failure { throw failure }
    guard succeeded else { throw LucideSVGError.malformedDocument }
    guard let root = delegate.root else { throw LucideSVGError.notSVG }
    return LucideGlyph(viewBox: root.viewBox, strokeWidth: root.strokeWidth, lineCap: root.lineCap,
                       lineJoin: root.lineJoin, elements: delegate.elements)
  }
}

private struct Paint {
  var fill: String?
  var stroke: String?

  func inheriting(_ attributes: [String: String]) -> Paint {
    Paint(fill: attributes["fill"] ?? fill, stroke: attributes["stroke"] ?? stroke)
  }

  /// SVG defaults: fill is black and stroke is none unless set on the element or an ancestor.
  var isFilled: Bool { (fill ?? "black").trimmingCharacters(in: .whitespaces) != "none" }
  var isStroked: Bool { (stroke ?? "none").trimmingCharacters(in: .whitespaces) != "none" }
}

private struct Root {
  var viewBox: CGRect
  var strokeWidth: CGFloat
  var lineCap: LucideGlyph.LineCap
  var lineJoin: LucideGlyph.LineJoin
}

private final class DocumentDelegate: NSObject, XMLParserDelegate {
  var root: Root?
  var elements: [LucideGlyph.Element] = []
  var failure: LucideSVGError?
  private var paints: [Paint] = []
  private var skippedDepth = 0

  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
              qualifiedName: String?, attributes: [String: String] = [:]) {
    guard failure == nil else { return }
    if skippedDepth > 0 || (root == nil && name != "svg") {
      skippedDepth += 1
      return
    }
    let paint = (paints.last ?? Paint()).inheriting(attributes)
    switch name {
    case "svg" where root == nil:
      guard let viewBox = Self.viewBox(attributes) else { return fail(.invalidViewBox, parser) }
      root = Root(viewBox: viewBox,
                  strokeWidth: Self.number(attributes["stroke-width"]) ?? 1,
                  lineCap: Self.lineCap(attributes["stroke-linecap"]),
                  lineJoin: Self.lineJoin(attributes["stroke-linejoin"]))
    case "g":
      break
    case "path", "circle", "ellipse", "rect", "line", "polyline", "polygon":
      guard elements.count < LucideSVG.maximumElementCount else { return fail(.tooManyElements, parser) }
      do {
        let segments = try Self.segments(name, attributes)
        if !segments.isEmpty {
          elements.append(.init(segments: segments, isFilled: paint.isFilled, isStroked: paint.isStroked))
        }
      } catch {
        return fail(.invalidPathData(element: elements.count), parser)
      }
    default:
      skippedDepth = 1
      return
    }
    paints.append(paint)
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    if skippedDepth > 0 {
      skippedDepth -= 1
    } else if !paints.isEmpty {
      paints.removeLast()
    }
  }

  private func fail(_ error: LucideSVGError, _ parser: XMLParser) {
    failure = error
    parser.abortParsing()
  }

  private static func segments(_ name: String, _ a: [String: String]) throws -> [PathSegment] {
    func value(_ key: String) -> CGFloat { number(a[key]) ?? 0 }
    switch name {
    case "path":
      return try SVGPathParser.parse(a["d"] ?? "")
    case "circle":
      let r = value("r")
      return ellipse(center: CGPoint(x: value("cx"), y: value("cy")), radii: CGSize(width: r, height: r))
    case "ellipse":
      return ellipse(center: CGPoint(x: value("cx"), y: value("cy")),
                     radii: CGSize(width: value("rx"), height: value("ry")))
    case "rect":
      let rect = CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height"))
      return roundedRect(rect, rx: number(a["rx"]), ry: number(a["ry"]))
    case "line":
      return [.move(CGPoint(x: value("x1"), y: value("y1"))), .line(CGPoint(x: value("x2"), y: value("y2")))]
    case "polyline", "polygon":
      let numbers = try list(a["points"] ?? "")
      guard numbers.count >= 4 else { return [] }
      var segments: [PathSegment] = [.move(CGPoint(x: numbers[0], y: numbers[1]))]
      for i in stride(from: 2, to: numbers.count - 1, by: 2) {
        segments.append(.line(CGPoint(x: numbers[i], y: numbers[i + 1])))
      }
      if name == "polygon" { segments.append(.close) }
      return segments
    default:
      return []
    }
  }

  /// Four cubic quadrants; the handle length keeps radial error below 0.03%.
  private static func ellipse(center c: CGPoint, radii r: CGSize) -> [PathSegment] {
    guard r.width > 0, r.height > 0 else { return [] }
    let k: CGFloat = 0.552_284_749_8
    let ox = r.width * k, oy = r.height * k
    return [
      .move(CGPoint(x: c.x + r.width, y: c.y)),
      .cubic(CGPoint(x: c.x, y: c.y + r.height), control1: CGPoint(x: c.x + r.width, y: c.y + oy),
             control2: CGPoint(x: c.x + ox, y: c.y + r.height)),
      .cubic(CGPoint(x: c.x - r.width, y: c.y), control1: CGPoint(x: c.x - ox, y: c.y + r.height),
             control2: CGPoint(x: c.x - r.width, y: c.y + oy)),
      .cubic(CGPoint(x: c.x, y: c.y - r.height), control1: CGPoint(x: c.x - r.width, y: c.y - oy),
             control2: CGPoint(x: c.x - ox, y: c.y - r.height)),
      .cubic(CGPoint(x: c.x + r.width, y: c.y), control1: CGPoint(x: c.x + ox, y: c.y - r.height),
             control2: CGPoint(x: c.x + r.width, y: c.y - oy)),
      .close,
    ]
  }

  /// SVG rect radius rules: a missing radius copies the other, both clamp to half the side.
  private static func roundedRect(_ rect: CGRect, rx: CGFloat?, ry: CGFloat?) -> [PathSegment] {
    guard rect.width > 0, rect.height > 0 else { return [] }
    let x = min(max(rx ?? ry ?? 0, 0), rect.width / 2)
    let y = min(max(ry ?? rx ?? 0, 0), rect.height / 2)
    guard x > 0, y > 0 else {
      return [.move(rect.origin), .line(CGPoint(x: rect.maxX, y: rect.minY)),
              .line(CGPoint(x: rect.maxX, y: rect.maxY)), .line(CGPoint(x: rect.minX, y: rect.maxY)), .close]
    }
    let kx = x * 0.552_284_749_8, ky = y * 0.552_284_749_8
    let (l, t, r, b) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    return [
      .move(CGPoint(x: l + x, y: t)),
      .line(CGPoint(x: r - x, y: t)),
      .cubic(CGPoint(x: r, y: t + y), control1: CGPoint(x: r - x + kx, y: t), control2: CGPoint(x: r, y: t + y - ky)),
      .line(CGPoint(x: r, y: b - y)),
      .cubic(CGPoint(x: r - x, y: b), control1: CGPoint(x: r, y: b - y + ky), control2: CGPoint(x: r - x + kx, y: b)),
      .line(CGPoint(x: l + x, y: b)),
      .cubic(CGPoint(x: l, y: b - y), control1: CGPoint(x: l + x - kx, y: b), control2: CGPoint(x: l, y: b - y + ky)),
      .line(CGPoint(x: l, y: t + y)),
      .cubic(CGPoint(x: l + x, y: t), control1: CGPoint(x: l, y: t + y - ky), control2: CGPoint(x: l + x - kx, y: t)),
      .close,
    ]
  }

  private static func viewBox(_ attributes: [String: String]) -> CGRect? {
    if let text = attributes["viewBox"] {
      guard let v = try? list(text), v.count == 4, v[2] > 0, v[3] > 0 else { return nil }
      return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
    let width = number(attributes["width"]) ?? 24, height = number(attributes["height"]) ?? 24
    return width > 0 && height > 0 ? CGRect(x: 0, y: 0, width: width, height: height) : nil
  }

  private static func list(_ text: String) throws -> [CGFloat] {
    try text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map {
      guard let value = Double($0), value.isFinite else { throw LucideSVGError.malformedDocument }
      return CGFloat(value)
    }
  }

  /// Accepts plain numbers and a trailing `px`; other units are not used by icon sets.
  private static func number(_ text: String?) -> CGFloat? {
    guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
    if text.hasSuffix("px") { text.removeLast(2) }
    guard let value = Double(text), value.isFinite else { return nil }
    return CGFloat(value)
  }

  private static func lineCap(_ text: String?) -> LucideGlyph.LineCap {
    switch text { case "round": .round; case "square": .square; default: .butt }
  }

  private static func lineJoin(_ text: String?) -> LucideGlyph.LineJoin {
    switch text { case "round": .round; case "bevel": .bevel; default: .miter }
  }
}

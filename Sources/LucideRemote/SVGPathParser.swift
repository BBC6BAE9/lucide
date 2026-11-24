import CoreGraphics
import Foundation

/// SVG 1.1 path data (`d`), all commands. Arcs are converted to cubic Béziers.
struct SVGPathParser {
  struct Failure: Error, Equatable { let offset: Int }

  private let bytes: [UInt8]
  private var index = 0

  static func parse(_ data: String) throws -> [PathSegment] {
    var parser = SVGPathParser(bytes: Array(data.utf8))
    return try parser.run()
  }

  private init(bytes: [UInt8]) { self.bytes = bytes }

  private mutating func run() throws -> [PathSegment] {
    var segments: [PathSegment] = []
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?
    var command: UInt8?

    while true {
      skipSeparators()
      guard index < bytes.count else { break }
      if Self.isCommand(bytes[index]) {
        command = bytes[index]
        index += 1
      } else if command == nil || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
        throw Failure(offset: index)
      }
      guard let letter = command else { break }
      let relative = letter >= UInt8(ascii: "a")
      let base = relative ? current : .zero
      var cubicControl: CGPoint?
      var quadControl: CGPoint?

      switch letter | 0x20 {
      case UInt8(ascii: "m"):
        let p = try point(base)
        segments.append(.move(p))
        current = p
        start = p
        command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
      case UInt8(ascii: "l"):
        current = try point(base)
        segments.append(.line(current))
      case UInt8(ascii: "h"):
        current = CGPoint(x: try number() + base.x, y: current.y)
        segments.append(.line(current))
      case UInt8(ascii: "v"):
        current = CGPoint(x: current.x, y: try number() + base.y)
        segments.append(.line(current))
      case UInt8(ascii: "c"):
        let c1 = try point(base), c2 = try point(base), p = try point(base)
        segments.append(.cubic(p, control1: c1, control2: c2))
        cubicControl = c2
        current = p
      case UInt8(ascii: "s"):
        let c1 = Self.reflect(lastCubicControl, around: current)
        let c2 = try point(base), p = try point(base)
        segments.append(.cubic(p, control1: c1, control2: c2))
        cubicControl = c2
        current = p
      case UInt8(ascii: "q"):
        let c = try point(base), p = try point(base)
        segments.append(.quad(p, control: c))
        quadControl = c
        current = p
      case UInt8(ascii: "t"):
        let c = Self.reflect(lastQuadControl, around: current)
        let p = try point(base)
        segments.append(.quad(p, control: c))
        quadControl = c
        current = p
      case UInt8(ascii: "a"):
        let rx = try number(), ry = try number(), rotation = try number()
        let largeArc = try flag(), sweep = try flag()
        let p = try point(base)
        segments += SVGArc.segments(from: current, to: p, radii: CGSize(width: rx, height: ry),
                                    rotation: rotation, largeArc: largeArc, sweep: sweep)
        current = p
      case UInt8(ascii: "z"):
        segments.append(.close)
        current = start
      default:
        throw Failure(offset: index - 1)
      }
      lastCubicControl = cubicControl
      lastQuadControl = quadControl
    }
    return segments
  }

  private static func isCommand(_ byte: UInt8) -> Bool {
    switch byte | 0x20 {
    case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"), UInt8(ascii: "c"),
         UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"), UInt8(ascii: "a"), UInt8(ascii: "z"):
      return true
    default:
      return false
    }
  }

  private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
    guard let control else { return point }
    return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
  }

  private mutating func point(_ base: CGPoint) throws -> CGPoint {
    let x = try number()
    let y = try number()
    return CGPoint(x: x + base.x, y: y + base.y)
  }

  private mutating func skipSeparators() {
    while index < bytes.count, Self.isSeparator(bytes[index]) { index += 1 }
  }

  private static func isSeparator(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C || byte == UInt8(ascii: ",")
  }

  /// Arc flags are single characters and may be written without separators (`a1 1 0 011 1`).
  private mutating func flag() throws -> Bool {
    skipSeparators()
    guard index < bytes.count else { throw Failure(offset: index) }
    defer { index += 1 }
    switch bytes[index] {
    case UInt8(ascii: "0"): return false
    case UInt8(ascii: "1"): return true
    default: throw Failure(offset: index)
    }
  }

  private mutating func number() throws -> CGFloat {
    skipSeparators()
    let begin = index
    if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
    var digits = 0
    while index < bytes.count, Self.isDigit(bytes[index]) { index += 1; digits += 1 }
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      index += 1
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1; digits += 1 }
    }
    guard digits > 0 else { throw Failure(offset: begin) }
    if index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
      var exponentEnd = index + 1
      if exponentEnd < bytes.count, bytes[exponentEnd] == UInt8(ascii: "+") || bytes[exponentEnd] == UInt8(ascii: "-") {
        exponentEnd += 1
      }
      if exponentEnd < bytes.count, Self.isDigit(bytes[exponentEnd]) {
        index = exponentEnd
        while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
      }
    }
    guard let text = String(bytes: bytes[begin..<index], encoding: .ascii), let value = Double(text),
          value.isFinite else { throw Failure(offset: begin) }
    return CGFloat(value)
  }

  private static func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
}

/// Endpoint-to-center arc conversion from SVG 1.1 implementation notes F.6.5–F.6.6.
enum SVGArc {
  static func segments(from start: CGPoint, to end: CGPoint, radii: CGSize, rotation degrees: CGFloat,
                       largeArc: Bool, sweep: Bool) -> [PathSegment] {
    if start == end { return [] }
    var rx = abs(radii.width), ry = abs(radii.height)
    guard rx > 0, ry > 0 else { return [.line(end)] }

    let phi = degrees * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy

    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      let factor = lambda.squareRoot()
      rx *= factor
      ry *= factor
    }

    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var coefficient = denominator == 0 ? 0 : max(0, numerator / denominator).squareRoot()
    if largeArc == sweep { coefficient = -coefficient }
    let cx1 = coefficient * rx * y1 / ry
    let cy1 = -coefficient * ry * x1 / rx
    let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
    let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

    let theta = angle(from: CGPoint(x: 1, y: 0), to: CGPoint(x: (x1 - cx1) / rx, y: (y1 - cy1) / ry))
    var delta = angle(from: CGPoint(x: (x1 - cx1) / rx, y: (y1 - cy1) / ry),
                      to: CGPoint(x: (-x1 - cx1) / rx, y: (-y1 - cy1) / ry))
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    let count = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / CGFloat(count)
    let handle = 4 / 3 * tan(step / 4)

    func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
    }

    var segments: [PathSegment] = []
    var a1 = theta
    for i in 0..<count {
      let a2 = a1 + step
      let c1 = map(cos(a1) - handle * sin(a1), sin(a1) + handle * cos(a1))
      let c2 = map(cos(a2) + handle * sin(a2), sin(a2) - handle * cos(a2))
      let p = i == count - 1 ? end : map(cos(a2), sin(a2))
      segments.append(.cubic(p, control1: c1, control2: c2))
      a1 = a2
    }
    return segments
  }

  private static func angle(from u: CGPoint, to v: CGPoint) -> CGFloat {
    atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
  }
}

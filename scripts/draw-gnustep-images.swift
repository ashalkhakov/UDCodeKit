// draw-gnustep-images.swift
//
// The toolbar's and the navigator's images for GNUstep, which has no SF
// Symbols: drawn here, our own, under the symbols' names (the XIBs name the
// symbols; on GNUstep -imageNamed: finds these instead). Run on macOS:
//
//     swift scripts/draw-gnustep-images.swift Images/GNUstep
//
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Images/GNUstep"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let ink = NSColor(calibratedWhite: 0.25, alpha: 1)

/// One image, @a size pixels square, drawn in a 16-unit square.
func image(_ name: String, size: Int, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 16
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    ink.setStroke()
    ink.setFill()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func stroke(_ path: NSBezierPath, _ width: CGFloat = 1.2) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ width: CGFloat = 1.2) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x0, y: y0))
    path.line(to: NSPoint(x: x1, y: y1))
    stroke(path, width)
}

// The toolbar's: 24 pixels.
image("play.fill", size: 24) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 4.5, y: 2.5))
    path.line(to: NSPoint(x: 13, y: 8))
    path.line(to: NSPoint(x: 4.5, y: 13.5))
    path.close()
    path.lineJoinStyle = .round
    path.fill()
}
image("stop.fill", size: 24) {
    NSBezierPath(roundedRect: NSRect(x: 3.5, y: 3.5, width: 9, height: 9), xRadius: 1.2, yRadius: 1.2).fill()
}
for (name, left) in [("sidebar.left", true), ("sidebar.right", false)] {
    image(name, size: 24) {
        stroke(NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 13, height: 10), xRadius: 2, yRadius: 2))
        let x: CGFloat = left ? 6 : 10
        line(x, 3, x, 13)
        for y in [10.5, 8.5, 6.5] as [CGFloat] {
            let x0: CGFloat = left ? 3 : 11.5
            line(x0, y, x0 + 1.5, y, 1)
        }
    }
}

// The navigator's: 16 pixels.
image("folder", size: 16) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 1.5, y: 3))
    path.line(to: NSPoint(x: 1.5, y: 13))
    path.line(to: NSPoint(x: 6, y: 13))
    path.line(to: NSPoint(x: 7.5, y: 11.5))
    path.line(to: NSPoint(x: 14.5, y: 11.5))
    path.line(to: NSPoint(x: 14.5, y: 3))
    path.close()
    stroke(path)
    line(1.5, 9.5, 14.5, 9.5, 1)
}
image("arrow.triangle.branch", size: 16) {
    // Source Control: a branch leaving its trunk
    line(4, 2, 4, 14)
    let branch = NSBezierPath()
    branch.move(to: NSPoint(x: 4, y: 6))
    branch.curve(to: NSPoint(x: 12, y: 12), controlPoint1: NSPoint(x: 4, y: 10), controlPoint2: NSPoint(x: 12, y: 8))
    stroke(branch)
    NSBezierPath(ovalIn: NSRect(x: 10, y: 11, width: 4, height: 4)).fill()
    NSBezierPath(ovalIn: NSRect(x: 2, y: 0.5, width: 4, height: 4)).fill()
}
image("arrow.left.arrow.right", size: 16) {
    // Code Review: the two sides, each toward the other
    line(2, 11, 14, 11)
    line(11, 14, 14, 11)
    line(11, 8, 14, 11)
    line(14, 5, 2, 5)
    line(5, 8, 2, 5)
    line(5, 2, 2, 5)
}
image("magnifyingglass", size: 16) {
    stroke(NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 8, height: 8)), 1.4)
    line(9, 7, 14, 2, 1.8)
}
image("exclamationmark.triangle", size: 16) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 8, y: 14))
    path.line(to: NSPoint(x: 15, y: 2))
    path.line(to: NSPoint(x: 1, y: 2))
    path.close()
    stroke(path)
    line(8, 10, 8, 6.5, 1.5)
    NSBezierPath(ovalIn: NSRect(x: 7.2, y: 3.4, width: 1.6, height: 1.6)).fill()
}
image("gauge.with.dots.needle.33percent", size: 16) {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 8, y: 5), radius: 6.5, startAngle: 0, endAngle: 180)
    stroke(arc)
    line(1.5, 5, 14.5, 5)
    line(8, 5, 5, 9.5, 1.5)
    for angle in [30.0, 90.0, 150.0] {
        let radians = angle * .pi / 180
        let x = 8 + 4.6 * CGFloat(cos(radians)), y = 5 + 4.6 * CGFloat(sin(radians))
        NSBezierPath(ovalIn: NSRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)).fill()
    }
}
image("arrowshape.right", size: 16) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 1.5, y: 4))
    path.line(to: NSPoint(x: 10.5, y: 4))
    path.line(to: NSPoint(x: 14.5, y: 8))
    path.line(to: NSPoint(x: 10.5, y: 12))
    path.line(to: NSPoint(x: 1.5, y: 12))
    path.close()
    stroke(path)
}
image("text.bubble", size: 16) {
    let path = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 13, height: 9), xRadius: 2.5, yRadius: 2.5)
    stroke(path)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 4, y: 4.5))
    tail.line(to: NSPoint(x: 3.5, y: 1.5))
    tail.line(to: NSPoint(x: 7, y: 4.5))
    stroke(tail)
    line(4.5, 10.5, 11.5, 10.5, 1)
    line(4.5, 7.5, 9.5, 7.5, 1)
}
image("ladybug", size: 16) {
    stroke(NSBezierPath(ovalIn: NSRect(x: 3.5, y: 1.5, width: 9, height: 10)))
    stroke(NSBezierPath(ovalIn: NSRect(x: 5.5, y: 10.5, width: 5, height: 4)))
    line(8, 1.5, 8, 11.5, 1)
    line(1.5, 8, 3.5, 7, 1)
    line(14.5, 8, 12.5, 7, 1)
    line(1.5, 3, 3.8, 4, 1)
    line(14.5, 3, 12.2, 4, 1)
}
image("terminal", size: 16) {
    stroke(NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 13, height: 11), xRadius: 2, yRadius: 2))
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 4, y: 10))
    prompt.line(to: NSPoint(x: 6.5, y: 8))
    prompt.line(to: NSPoint(x: 4, y: 6))
    stroke(prompt)
    line(8, 5.5, 11.5, 5.5)
}
image("checkmark.diamond", size: 16) {
    let diamond = NSBezierPath()
    diamond.move(to: NSPoint(x: 8, y: 14.5))
    diamond.line(to: NSPoint(x: 14.5, y: 8))
    diamond.line(to: NSPoint(x: 8, y: 1.5))
    diamond.line(to: NSPoint(x: 1.5, y: 8))
    diamond.close()
    stroke(diamond)
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 5.2, y: 8.2))
    check.line(to: NSPoint(x: 7.2, y: 6))
    check.line(to: NSPoint(x: 10.8, y: 10.2))
    stroke(check, 1.4)
}
image("doc.plaintext", size: 16) {
    let page = NSBezierPath()
    page.move(to: NSPoint(x: 3.5, y: 1.5))
    page.line(to: NSPoint(x: 3.5, y: 14.5))
    page.line(to: NSPoint(x: 9.5, y: 14.5))
    page.line(to: NSPoint(x: 12.5, y: 11.5))
    page.line(to: NSPoint(x: 12.5, y: 1.5))
    page.close()
    stroke(page)
    line(5.5, 10.5, 8.5, 10.5, 1)
    line(5.5, 8, 10.5, 8, 1)
    line(5.5, 5.5, 10.5, 5.5, 1)
}
image("eye", size: 16) {
    let lid = NSBezierPath()
    lid.move(to: NSPoint(x: 1.5, y: 8))
    lid.curve(to: NSPoint(x: 14.5, y: 8), controlPoint1: NSPoint(x: 4.5, y: 13), controlPoint2: NSPoint(x: 11.5, y: 13))
    lid.curve(to: NSPoint(x: 1.5, y: 8), controlPoint1: NSPoint(x: 11.5, y: 3), controlPoint2: NSPoint(x: 4.5, y: 3))
    lid.close()
    stroke(lid)
    NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 4, height: 4)).fill()
}
print("drawn in \(out)")

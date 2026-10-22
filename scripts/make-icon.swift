import AppKit

let outputPath = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let silhouette = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 202, yRadius: 202)
NSColor(srgbRed: 52 / 255, green: 75 / 255, blue: 57 / 255, alpha: 1).setFill()
silhouette.fill()
NSColor(srgbRed: 216 / 255, green: 233 / 255, blue: 196 / 255, alpha: 1).setStroke()
let cap = NSBezierPath()
cap.move(to: NSPoint(x: 267, y: 737))
cap.line(to: NSPoint(x: 757, y: 737))
cap.lineWidth = 44
cap.lineCapStyle = .round
cap.stroke()
for i in 0..<4 {
    let x = 267 + CGFloat(i) * 490 / 3
    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: x, y: 288))
    bar.line(to: NSPoint(x: x, y: 370 + CGFloat(i) * 68))
    bar.lineWidth = 44
    bar.lineCapStyle = .round
    bar.stroke()
}
image.unlockFocus()
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render Headroom icon")
}
try png.write(to: URL(fileURLWithPath: outputPath))

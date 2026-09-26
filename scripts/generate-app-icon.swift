import AppKit
import ImageIO
import UniformTypeIdentifiers

// Micodex: a microphone between two code brackets, in the same violet as the UI.
func render(size: Int, mac: Bool, to output: URL) {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor(red: 0.70, green: 0.46, blue: 1, alpha: 1).setFill()
    let inset: CGFloat = mac ? 60 : 0
    NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2),
                 xRadius: mac ? 204 : 0, yRadius: mac ? 204 : 0).fill()
    let ink = NSColor(red: 0.10, green: 0.055, blue: 0.17, alpha: 1)
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 446, y: 447, width: 132, height: 290), xRadius: 66, yRadius: 66).fill()
    let microphone = NSBezierPath()
    microphone.move(to: NSPoint(x: 370, y: 499))
    microphone.line(to: NSPoint(x: 370, y: 453))
    microphone.curve(to: NSPoint(x: 512, y: 315), controlPoint1: NSPoint(x: 370, y: 376), controlPoint2: NSPoint(x: 434, y: 315))
    microphone.curve(to: NSPoint(x: 654, y: 453), controlPoint1: NSPoint(x: 590, y: 315), controlPoint2: NSPoint(x: 654, y: 376))
    microphone.line(to: NSPoint(x: 654, y: 499))
    microphone.move(to: NSPoint(x: 512, y: 315))
    microphone.line(to: NSPoint(x: 512, y: 251))
    microphone.move(to: NSPoint(x: 453, y: 251))
    microphone.line(to: NSPoint(x: 571, y: 251))
    microphone.lineWidth = 32; microphone.lineCapStyle = .round
    ink.setStroke(); microphone.stroke()
    let brackets = NSBezierPath()
    brackets.move(to: NSPoint(x: 280, y: 630))
    brackets.line(to: NSPoint(x: 223, y: 630))
    brackets.line(to: NSPoint(x: 223, y: 394))
    brackets.line(to: NSPoint(x: 280, y: 394))
    brackets.move(to: NSPoint(x: 744, y: 630))
    brackets.line(to: NSPoint(x: 801, y: 630))
    brackets.line(to: NSPoint(x: 801, y: 394))
    brackets.line(to: NSPoint(x: 744, y: 394))
    brackets.lineWidth = 30; brackets.lineCapStyle = .round; brackets.lineJoinStyle = .round
    ink.withAlphaComponent(0.6).setStroke(); brackets.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot write icon")
}

render(size: 1024, mac: false, to: URL(fileURLWithPath: "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
let directory = URL(fileURLWithPath: "Mac/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        render(size: size * scale, mac: true, to: directory.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let catalog: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("Contents.json"))
print("Generated Micodex icons for Watch and Mac")

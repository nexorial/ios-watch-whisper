import AppKit
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let background = NSRect(x: 0, y: 0, width: side, height: side)
NSColor(red: 0.025, green: 0.075, blue: 0.08, alpha: 1).setFill()
background.fill()
let mint = NSColor(red: 0.06, green: 0.85, blue: 0.72, alpha: 1)
NSColor(red: 0.07, green: 0.24, blue: 0.23, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 402, y: 45, width: 220, height: 934), xRadius: 64, yRadius: 64).fill()
let face = NSBezierPath(roundedRect: NSRect(x: 234, y: 187, width: 556, height: 650), xRadius: 150, yRadius: 150)
NSColor(red: 0.035, green: 0.12, blue: 0.13, alpha: 1).setFill()
face.fill()
mint.withAlphaComponent(0.75).setStroke()
face.lineWidth = 16
face.stroke()
mint.setFill()
NSBezierPath(roundedRect: NSRect(x: 798, y: 456, width: 44, height: 112), xRadius: 18, yRadius: 18).fill()
NSBezierPath(roundedRect: NSRect(x: 451, y: 425, width: 122, height: 250), xRadius: 61, yRadius: 61).fill()
let microphone = NSBezierPath()
microphone.move(to: NSPoint(x: 366, y: 500))
microphone.line(to: NSPoint(x: 366, y: 450))
microphone.curve(to: NSPoint(x: 512, y: 313), controlPoint1: NSPoint(x: 366, y: 370), controlPoint2: NSPoint(x: 431, y: 313))
microphone.curve(to: NSPoint(x: 658, y: 450), controlPoint1: NSPoint(x: 593, y: 313), controlPoint2: NSPoint(x: 658, y: 370))
microphone.line(to: NSPoint(x: 658, y: 500))
microphone.move(to: NSPoint(x: 512, y: 312))
microphone.line(to: NSPoint(x: 512, y: 262))
microphone.move(to: NSPoint(x: 459, y: 262))
microphone.line(to: NSPoint(x: 565, y: 262))
microphone.lineWidth = 28
microphone.lineCapStyle = .round
mint.setStroke()
microphone.stroke()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Cannot write icon")
print(output.path)

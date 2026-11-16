import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220).fill()
let name = NSAttributedString(string: "FocusNest", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 132, weight: .medium),
    .foregroundColor: NSColor.black
])
let textSize = name.size()
name.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: (1024 - textSize.height) / 2))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)

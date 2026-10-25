// Рисует иконку 1024×1024 в духе macOS Big Sur+: скруглённый квадрат, градиент,
// мягкий блик сверху и символ. Запуск: swift icon.swift out.png
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let inset = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

// База: тёплый диагональный градиент
shape.addClip()
NSGradient(colors: [NSColor(red: 0.95, green: 0.62, blue: 0.47, alpha: 1),
                    NSColor(red: 0.80, green: 0.40, blue: 0.28, alpha: 1),
                    NSColor(red: 0.68, green: 0.30, blue: 0.22, alpha: 1)],
          atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    .draw(in: shape, angle: -62)

// Мягкий блик сверху — как у стеклянных иконок macOS
let highlight = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.55,
                                            width: rect.width * 1.4, height: rect.height * 0.9))
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: highlight, relativeCenterPosition: .zero)

// Тонкая внутренняя обводка сверху — глубина
let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
NSColor.white.withAlphaComponent(0.25).setStroke()
rim.lineWidth = 2
rim.stroke()

// Символ: волшебная палочка — чистка как по волшебству
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.34, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - size * 0.01, width: s.width, height: s.height))
    NSGraphicsContext.current?.restoreGraphicsState()
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

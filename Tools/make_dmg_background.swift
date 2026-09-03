import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Uso: make_dmg_background.swift output.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 600, height: 400)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
canvas.fill()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    .paragraphStyle: titleStyle
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1),
    .paragraphStyle: titleStyle
]

NSString(string: "Installa iBlock").draw(
    in: NSRect(x: 40, y: 332, width: 520, height: 40),
    withAttributes: titleAttributes
)
NSString(string: "Trascina iBlock nella cartella Applicazioni").draw(
    in: NSRect(x: 40, y: 300, width: 520, height: 24),
    withAttributes: subtitleAttributes
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 250, y: 193))
arrow.line(to: NSPoint(x: 335, y: 193))
arrow.line(to: NSPoint(x: 335, y: 218))
arrow.line(to: NSPoint(x: 385, y: 172))
arrow.line(to: NSPoint(x: 335, y: 126))
arrow.line(to: NSPoint(x: 335, y: 151))
arrow.line(to: NSPoint(x: 250, y: 151))
arrow.close()
NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.96, alpha: 0.20).setFill()
arrow.fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Impossibile generare lo sfondo.\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    print("Creato: \(CommandLine.arguments[1])")
} catch {
    fputs("Impossibile salvare lo sfondo: \(error.localizedDescription)\n", stderr)
    exit(1)
}

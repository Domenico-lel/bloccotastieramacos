import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Uso: remove_icon_background.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Impossibile leggere l'immagine sorgente.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Impossibile creare il buffer grafico.\n", stderr)
    exit(1)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func isExteriorBackground(_ pixelIndex: Int) -> Bool {
    let offset = pixelIndex * bytesPerPixel
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)

    // Lo sfondo e la sua ombra sono quasi neutri. Il riquadro dell'icona,
    // invece, rimane nettamente blu e non viene attraversato dal flood fill.
    return maximum - minimum <= 42 && maximum >= 72
}

var exterior = [Bool](repeating: false, count: width * height)
var queue = [Int]()
queue.reserveCapacity(width * height / 3)

func enqueueIfBackground(x: Int, y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * width + x
    guard !exterior[index], isExteriorBackground(index) else { return }
    exterior[index] = true
    queue.append(index)
}

for x in 0..<width {
    enqueueIfBackground(x: x, y: 0)
    enqueueIfBackground(x: x, y: height - 1)
}
for y in 0..<height {
    enqueueIfBackground(x: 0, y: y)
    enqueueIfBackground(x: width - 1, y: y)
}

var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % width
    let y = index / width
    enqueueIfBackground(x: x - 1, y: y)
    enqueueIfBackground(x: x + 1, y: y)
    enqueueIfBackground(x: x, y: y - 1)
    enqueueIfBackground(x: x, y: y + 1)
}

for index in exterior.indices where exterior[index] {
    let offset = index * bytesPerPixel
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
}

guard
    let outputContext = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    let outputImage = outputContext.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Impossibile preparare l'immagine finale.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Impossibile salvare l'immagine finale.\n", stderr)
    exit(1)
}

print("Creata icona trasparente: \(outputURL.path)")

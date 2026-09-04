import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Uso: chroma_key_to_alpha.swift input.png output.png\n", stderr)
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

for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
    let red = Double(pixels[offset])
    let green = Double(pixels[offset + 1])
    let blue = Double(pixels[offset + 2])

    // Il verde generato e circa RGB 24/240/24 e ha una dominanza di 210.
    // Sul bordo antialias, questa formula ricostruisce anche l'opacita parziale.
    let greenDominance = green - max(red, blue)
    var alpha = 1.0 - max(0.0, min(210.0, greenDominance)) / 210.0

    // Elimina i minimi residui prodotti dal renderer sul fondale verde.
    if alpha < 0.08 { alpha = 0.0 }
    if alpha > 0.985 { alpha = 1.0 }

    let alphaByte = UInt8((alpha * 255.0).rounded())
    if alphaByte == 0 {
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
        continue
    }

    // Rimuove il contributo del fondale verde dai pixel semitrasparenti.
    // Il buffer finale e premoltiplicato, come richiesto da Core Graphics.
    let backgroundRed = 24.0
    let backgroundGreen = 240.0
    let backgroundBlue = 24.0
    let premultipliedRed = max(0.0, red - backgroundRed * (1.0 - alpha))
    let premultipliedGreen = max(0.0, green - backgroundGreen * (1.0 - alpha))
    let premultipliedBlue = max(0.0, blue - backgroundBlue * (1.0 - alpha))
    pixels[offset] = UInt8(max(0.0, min(premultipliedRed, alpha * 255.0)).rounded())
    pixels[offset + 1] = UInt8(max(0.0, min(premultipliedGreen, alpha * 255.0)).rounded())
    pixels[offset + 2] = UInt8(max(0.0, min(premultipliedBlue, alpha * 255.0)).rounded())
    pixels[offset + 3] = alphaByte
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

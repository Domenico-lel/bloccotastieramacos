import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Uso: make_icns cartella.iconset output.icns\n", stderr)
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    let bigEndian = value.bigEndian
    return withUnsafeBytes(of: bigEndian) { Array($0) }
}

var body = Data()
for entry in entries {
    let fileURL = directory.appendingPathComponent(entry.file)
    guard let png = try? Data(contentsOf: fileURL) else {
        fputs("File mancante: \(fileURL.path)\n", stderr)
        exit(1)
    }

    body.append(contentsOf: entry.type.utf8)
    body.append(contentsOf: bigEndianBytes(UInt32(png.count + 8)))
    body.append(png)
}

var result = Data("icns".utf8)
result.append(contentsOf: bigEndianBytes(UInt32(body.count + 8)))
result.append(body)

do {
    try result.write(to: output, options: .atomic)
    print("Creato: \(output.path)")
} catch {
    fputs("Impossibile scrivere il file ICNS: \(error.localizedDescription)\n", stderr)
    exit(1)
}

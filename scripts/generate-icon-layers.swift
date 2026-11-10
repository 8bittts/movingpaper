#!/usr/bin/env swift
//
// generate-icon-layers.swift
// Splits the flattened night-sky art into the two layers of the Icon Composer
// document, so the system can render the app icon as Liquid Glass and derive
// its dark, tinted and clear variants.
//
//   swift scripts/generate-icon-layers.swift
//
// Reads  build/movingpaper-1024.png
// Writes build/MovingPaper.icon/Assets/sky.png and clouds.png
//
// Run it only when the art changes; the layers are tracked.

import AppKit

let sourcePath = "build/movingpaper-1024.png"
let out = URL(filePath: "build/MovingPaper.icon/Assets")

guard let image = NSImage(contentsOf: URL(filePath: sourcePath)),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("ERROR: Could not load \(sourcePath)")
    exit(1)
}
let srcSize = cg.width
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ side: Int) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
let srcCtx = context(srcSize)
srcCtx.draw(cg, in: CGRect(x: 0, y: 0, width: srcSize, height: srcSize))
let src = srcCtx.data!.assumingMemoryBound(to: UInt8.self)
// The art sits inset in its canvas with small rounded corners; the layers are
// full-bleed, because the system applies the icon shape itself.
let lo = 116, hi = 906, side = hi - lo + 1, size = 1024
let skyCtx = context(size), cloudCtx = context(size)
let sky = skyCtx.data!.assumingMemoryBound(to: UInt8.self)
let clouds = cloudCtx.data!.assumingMemoryBound(to: UInt8.self)
// Pass 1: the sky layer, plus the top contour of the cloud bank per column.
// A column's contour is its highest bright pixel below the star field.
var contour = [Int?](repeating: nil, count: size)
for y in 0..<size {
    for x in 0..<size {
        // Nearest-neighbour keeps the pixel-art edges crisp.
        var sx = min(hi, lo + x * side / size), sy = min(hi, lo + y * side / size)
        if src[(sy * srcSize + sx) * 4 + 3] < 128 {
            // The source has small rounded corners; fill them from the nearest opaque pixel inward.
            sx = min(max(sx, lo + 48), hi - 48); sy = min(max(sy, lo + 48), hi - 48)
        }
        let s = (sy * srcSize + sx) * 4, d = (y * size + x) * 4
        let r = src[s], g = src[s + 1], b = src[s + 2]
        sky[d] = r; sky[d + 1] = g; sky[d + 2] = b; sky[d + 3] = 255
        let luma = (299 * Int(r) + 587 * Int(g) + 114 * Int(b)) / 1000
        // Row 0 is the top of the image in this buffer.
        if contour[x] == nil, luma > 158, y > size * 40 / 100 { contour[x] = y }
    }
}
// A column with no bright pixel takes its neighbour's contour.
var last = contour.compactMap { $0 }.first ?? size
for x in 0..<size { if let c = contour[x] { last = c } else { contour[x] = last } }
// Pass 2: the cloud layer is everything from the contour down, so its only
// visible edge is the top of the bank. A luminance cut alone left a ragged,
// speckled lower edge that the glass highlight exaggerated.
var cloudPixels = 0
for x in 0..<size {
    for y in contour[x]!..<size {
        let d = (y * size + x) * 4
        clouds[d] = sky[d]; clouds[d + 1] = sky[d + 1]; clouds[d + 2] = sky[d + 2]; clouds[d + 3] = 255
        cloudPixels += 1
    }
}
func write(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
}
write(skyCtx, "sky.png"); write(cloudCtx, "clouds.png")
print("Wrote sky.png and clouds.png (cloud layer covers \(cloudPixels * 100 / (size * size))% of the canvas)")

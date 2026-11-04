// Generates the image fixtures in Tests/Fixtures/images.
//
//     swift Tests/Fixtures/make-images.swift
//
// Every image is 64×48, small enough to stay far under the 200 KB limit, with a
// gradient so a broken decode can't pass for a correct one. HEIC, JPEG and TIFF
// carry EXIF and GPS so the metadata tests have something to keep or strip.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 64
let height = 48

let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("images", isDirectory: true)

func makeContext() -> CGContext {
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("couldn't create a bitmap context") }
    return context
}

func gradient() -> CGImage {
    let context = makeContext()
    for x in 0..<width {
        let t = CGFloat(x) / CGFloat(width - 1)
        context.setFillColor(red: t, green: 0.4, blue: 1 - t, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    guard let image = context.makeImage() else { fatalError("couldn't render the gradient") }
    return image
}

/// Transparent all over, with an opaque red block in the middle.
func transparent() -> CGImage {
    let context = makeContext()
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 16, y: 12, width: 32, height: 24))
    guard let image = context.makeImage() else { fatalError("couldn't render the image") }
    return image
}

let metadata: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05",
        kCGImagePropertyExifLensModel: "Fixture Lens",
    ],
    kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFMake: "Morph",
        kCGImagePropertyTIFFModel: "Fixture Camera",
    ],
    kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 43.0389,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 76.1322,
        kCGImagePropertyGPSLongitudeRef: "W",
    ],
]

func write(_ image: CGImage, as type: UTType, to name: String, properties: [CFString: Any]) {
    let url = output.appendingPathComponent(name)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil)
    else { fatalError("ImageIO can't write \(type.identifier)") }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(name)") }
    print("wrote \(name)")
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let image = gradient()
write(image, as: .heic, to: "heic-64x48.heic", properties: metadata)
write(image, as: .jpeg, to: "jpg-64x48.jpg", properties: metadata)
write(image, as: .png, to: "png-64x48.png", properties: [:])
write(image, as: .tiff, to: "tiff-64x48.tiff", properties: metadata)
write(image, as: .bmp, to: "bmp-64x48.bmp", properties: [:])
write(transparent(), as: .png, to: "png-transparent.png", properties: [:])

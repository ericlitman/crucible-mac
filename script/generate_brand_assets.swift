#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AssetError: Error, CustomStringConvertible {
    case cannotLoad(URL)
    case cannotCreateContext
    case cannotCreateImage
    case cannotWrite(URL)

    var description: String {
        switch self {
        case let .cannotLoad(url): "Cannot load \(url.path)"
        case .cannotCreateContext: "Cannot create bitmap context"
        case .cannotCreateImage: "Cannot create rendered image"
        case let .cannotWrite(url): "Cannot write \(url.path)"
        }
    }
}

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath)
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceRoot = root.appending(path: "Assets/Brand")
let catalogRoot = root.appending(path: "Crucible/Crucible/Assets.xcassets")
let appIconRoot = catalogRoot.appending(path: "AppIcon.appiconset")
let menuIconRoot = catalogRoot.appending(path: "MenuBarIcon.imageset")

func loadImage(_ url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw AssetError.cannotLoad(url)
    }
    return image
}

func makeContext(width: Int, height: Int, bytes: UnsafeMutableRawPointer? = nil) throws -> CGContext {
    guard let context = CGContext(
        data: bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw AssetError.cannotCreateContext
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    return context
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw AssetError.cannotWrite(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw AssetError.cannotWrite(url)
    }
}

func renderAppIcon(source: CGImage, size: Int) throws -> CGImage {
    let context = try makeContext(width: size, height: size)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // The source contains the finished rounded plate on an opaque canvas.
    // Clip to the observed plate so derivatives have real transparent corners.
    let plate = CGRect(
        x: CGFloat(size) * 0.069,
        y: CGFloat(size) * 0.053,
        width: CGFloat(size) * 0.861,
        height: CGFloat(size) * 0.875
    )
    let radius = CGFloat(size) * 0.125
    context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let image = context.makeImage() else { throw AssetError.cannotCreateImage }
    return image
}

func monochromeTemplateSource(_ source: CGImage) throws -> CGImage {
    let width = source.width
    let height = source.height
    let byteCount = width * height * 4
    let input = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
    let output = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
    defer {
        input.deallocate()
        output.deallocate()
    }

    let inputContext = try makeContext(width: width, height: height, bytes: input)
    inputContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    let inputBytes = input.bindMemory(to: UInt8.self, capacity: byteCount)
    let outputBytes = output.bindMemory(to: UInt8.self, capacity: byteCount)
    for pixel in 0..<(width * height) {
        let offset = pixel * 4
        let red = Double(inputBytes[offset])
        let green = Double(inputBytes[offset + 1])
        let blue = Double(inputBytes[offset + 2])
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        let alpha = UInt8(clamping: Int(((235 - luminance) * 1.5).rounded()))
        outputBytes[offset] = 0
        outputBytes[offset + 1] = 0
        outputBytes[offset + 2] = 0
        outputBytes[offset + 3] = alpha
    }

    let outputContext = try makeContext(width: width, height: height, bytes: output)
    guard let image = outputContext.makeImage() else { throw AssetError.cannotCreateImage }
    return image
}

func renderMenuIcon(source: CGImage, size: Int) throws -> CGImage {
    let context = try makeContext(width: size, height: size)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Crop the source whitespace and fit the monochrome alpha mask with a
    // small optical margin at menu-bar scale.
    let crop = CGRect(
        x: CGFloat(source.width) * 0.238,
        y: CGFloat(source.height) * 0.205,
        width: CGFloat(source.width) * 0.524,
        height: CGFloat(source.height) * 0.585
    )
    guard let cropped = source.cropping(to: crop.integral) else { throw AssetError.cannotCreateImage }
    let inset = CGFloat(size) * 0.08
    let available = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let scale = min(available.width / CGFloat(cropped.width), available.height / CGFloat(cropped.height))
    let targetSize = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
    let target = CGRect(
        x: available.midX - targetSize.width / 2,
        y: available.midY - targetSize.height / 2,
        width: targetSize.width,
        height: targetSize.height
    )
    context.draw(cropped, in: target)

    guard let image = context.makeImage() else { throw AssetError.cannotCreateImage }
    return image
}

do {
    try fileManager.createDirectory(at: appIconRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: menuIconRoot, withIntermediateDirectories: true)

    let appSource = try loadImage(sourceRoot.appending(path: "AppIcon.source.png"))
    let menuSource = try monochromeTemplateSource(
        loadImage(sourceRoot.appending(path: "MenuBarIcon.source.png"))
    )

    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let image = try renderAppIcon(source: appSource, size: size)
        try writePNG(image, to: appIconRoot.appending(path: "AppIcon-\(size).png"))
    }

    try writePNG(try renderMenuIcon(source: menuSource, size: 18), to: menuIconRoot.appending(path: "MenuBarIcon.png"))
    try writePNG(try renderMenuIcon(source: menuSource, size: 36), to: menuIconRoot.appending(path: "MenuBarIcon@2x.png"))
    print("Generated app and menu-bar asset derivatives from Assets/Brand sources.")
} catch {
    fputs("Asset generation failed: \(error)\n", stderr)
    exit(1)
}

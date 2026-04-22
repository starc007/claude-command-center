#!/usr/bin/env swift
// Renders the app icon as an iconset folder of PNGs at every size macOS needs.
// Usage: swift Scripts/generate-icon.swift <output-iconset-folder>

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: generate-icon.swift <iconset-folder>\n".data(using: .utf8)!)
    exit(1)
}
let iconsetURL = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// macOS iconset manifest: (filename, pixel size)
let manifest: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

/// Draws the app icon into a rep of the given pixel size.
func render(pixelSize: Int) -> NSBitmapImageRep {
    let px = CGFloat(pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect mask. 22.37% radius is the macOS icon standard after Big Sur.
    let canvas = NSRect(x: 0, y: 0, width: px, height: px)
    let radius = px * 0.2237
    let path = NSBezierPath(roundedRect: canvas, xRadius: radius, yRadius: radius)
    path.addClip()

    // Background: top-left lit, darker toward bottom-right — subtle warm cast.
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1.0),
    ])!
    bg.draw(in: canvas, angle: -75)

    // Subtle inner glow behind the mark.
    let glowRadius = px * 0.5
    let glowRect = NSRect(
        x: (px - glowRadius) / 2 - glowRadius * 0.15,
        y: (px - glowRadius) / 2 + glowRadius * 0.10,
        width: glowRadius * 2, height: glowRadius * 2
    )
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.02, alpha: 0.28),
        NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.02, alpha: 0.00),
    ])!
    glow.draw(in: glowRect, relativeCenterPosition: .zero)

    // Sparkles mark in Claude-orange, centered.
    let symbolPoint = px * 0.60
    let config = NSImage.SymbolConfiguration(pointSize: symbolPoint, weight: .medium)
        .applying(.init(paletteColors: [
            NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.10, alpha: 1.0)
        ]))

    if let base = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil),
       let symbol = base.withSymbolConfiguration(config) {
        let s = symbol.size
        let rect = NSRect(
            x: (px - s.width) / 2,
            y: (px - s.height) / 2,
            width: s.width, height: s.height
        )
        symbol.draw(in: rect)
    }

    // Hairline inner stroke so the icon reads on both light and dark backdrops.
    NSColor(white: 1.0, alpha: 0.06).setStroke()
    let stroke = NSBezierPath(roundedRect: canvas.insetBy(dx: 0.5, dy: 0.5),
                              xRadius: radius, yRadius: radius)
    stroke.lineWidth = max(1, px / 512)
    stroke.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, size) in manifest {
    let rep = render(pixelSize: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent(name))
}

print("wrote \(manifest.count) PNGs to \(iconsetURL.path)")

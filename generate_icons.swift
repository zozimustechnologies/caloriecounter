#!/usr/bin/env swift
// Generates the AppIcon PNGs from a SwiftUI logo view.
// Usage:  swift generate_icons.swift <output-folder>

import SwiftUI
import AppKit

// MARK: - Icon designs

struct LightIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.50, blue: 1.00),
                    Color(red: 0.20, green: 0.85, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .trim(from: 0.0, to: 0.78)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 90, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(180)

            Image(systemName: "flame.fill")
                .font(.system(size: 480, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.85, blue: 0.45), .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: 1024, height: 1024)
    }
}

struct DarkIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.18),
                    Color(red: 0.07, green: 0.20, blue: 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .trim(from: 0.0, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.40, green: 0.75, blue: 1.0),
                            Color(red: 0.20, green: 0.95, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 90, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(180)

            Image(systemName: "flame.fill")
                .font(.system(size: 480, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.3, blue: 0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: 1024, height: 1024)
    }
}

// Tinted icons should be a grayscale/transparent design; iOS recolors them.
// We render solid white shapes on a transparent background.
struct TintedIcon: View {
    var body: some View {
        ZStack {
            Color.black

            Circle()
                .trim(from: 0.0, to: 0.78)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 90, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(180)

            Image(systemName: "flame.fill")
                .font(.system(size: 480, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Render helper

@MainActor
func render<V: View>(_ view: V, to url: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Render failed"])
    }
    try png.write(to: url)
    print("✓ Wrote \(url.lastPathComponent)")
}

// MARK: - Main

@MainActor
func main() throws {
    guard CommandLine.arguments.count >= 2 else {
        print("Usage: swift generate_icons.swift <output-folder>")
        exit(1)
    }
    let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    try render(LightIcon(),  to: outDir.appendingPathComponent("Icon-Light.png"))
    try render(DarkIcon(),   to: outDir.appendingPathComponent("Icon-Dark.png"))
    try render(TintedIcon(), to: outDir.appendingPathComponent("Icon-Tinted.png"))
}

try MainActor.assumeIsolated { try main() }

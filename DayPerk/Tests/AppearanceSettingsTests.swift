import AppKit
@testable import DayPerk
import Testing

struct AppearanceSettingsTests {
    @Test func cropFillsBothWindowsAndHonorsSelection() {
        let image = CGSize(width: 1600, height: 900)
        for size in [CGSize(width: 980, height: 740), CGSize(width: 430, height: 560)] {
            let left = BackgroundCrop(x: 0, y: 0).imageFrame(image: image, viewport: size)
            let right = BackgroundCrop(x: 1, y: 1).imageFrame(image: image, viewport: size)
            #expect(left.width >= size.width && left.height >= size.height)
            #expect(left.minX == 0 && left.minY == 0)
            #expect(abs(right.maxX - size.width) < 0.001)
            #expect(abs(right.maxY - size.height) < 0.001)
            let zoomed = BackgroundCrop(zoom: 2).imageFrame(image: image, viewport: size)
            #expect(zoomed.width == left.width * 2)
        }
    }

    @Test func invalidCropValuesAndEmptyImageCannotEscapeBounds() {
        let crop = BackgroundCrop(x: .nan, y: -20, zoom: .infinity).sanitized
        #expect(crop == BackgroundCrop(x: 0.5, y: 0, zoom: 1))
        #expect(BackgroundCrop(x: 4, y: 8, zoom: 20).sanitized == BackgroundCrop(x: 1, y: 1, zoom: 3))
        #expect(crop.imageFrame(image: .zero, viewport: CGSize(width: 10, height: 10)) == .zero)
    }

    @Test func backgroundPreferencesPersistIndependentlyForEachWindow() {
        let defaults = UserDefaults(suiteName: "appearance-\(UUID().uuidString)")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        let settings = AppearanceSettings(defaults: defaults, imageURL: url)
        var value = settings.background
        value.enabled = true; value.windowCrop.x = 0.1; value.panelCrop.x = 0.9; value.panelCrop.zoom = 2
        settings.updateBackground(value)
        let restored = AppearanceSettings(defaults: defaults, imageURL: url)
        #expect(restored.background == value)
        value.dimming = 9; value.windowCrop.zoom = -2
        settings.updateBackground(value)
        #expect(settings.background.dimming == 0.8 && settings.background.windowCrop.zoom == 1)
    }

    @Test func importedImageSurvivesReloadAndInvalidReplacementKeepsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brew-background-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = folder.appendingPathComponent("input.png")
        let output = folder.appendingPathComponent("stored/background.png")
        let pixels = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(pixels.representation(using: .png, properties: [:])).write(to: input)
        let defaults = UserDefaults(suiteName: "appearance-\(UUID().uuidString)")!
        let settings = AppearanceSettings(defaults: defaults, imageURL: output)
        try settings.importBackground(from: input)
        #expect(settings.background.enabled && settings.backgroundImage != nil)
        #expect(AppearanceSettings(defaults: defaults, imageURL: output).backgroundImage != nil)
        let previous = try Data(contentsOf: output)
        let invalid = folder.appendingPathComponent("invalid.png")
        try Data("invalid".utf8).write(to: invalid)
        #expect(throws: DayPerkInputError.self) { try settings.importBackground(from: invalid) }
        #expect(try Data(contentsOf: output) == previous)
        try settings.importBackground(from: input)
        #expect(try Data(contentsOf: output.deletingPathExtension().appendingPathExtension("backup.png")) == previous)
    }
}

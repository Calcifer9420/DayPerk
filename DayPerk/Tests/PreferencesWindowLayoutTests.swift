import AppKit
import SwiftUI
import Testing
@testable import DayPerk

struct PreferencesWindowLayoutTests {
    @MainActor @Test func tallContentAndReplacementCannotResizeTheWindow() async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesWindowLayout.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let original = window.frame
        let tall = NSHostingView(rootView: ScrollView { Text("test").frame(height: 2500) })
        tall.sizingOptions = []
        PreferencesWindowLayout.install(tall, in: window)
        tall.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.frame == original)
        let replacement = NSHostingView(rootView: ScrollView { Color.clear.frame(height: 4000) })
        replacement.sizingOptions = []
        PreferencesWindowLayout.install(replacement, in: window)
        replacement.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.frame == original)
        #expect(replacement.frame.size == window.contentView?.bounds.size)
        #expect(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        #expect(replacement.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        #expect(PreferencesWindowLayout.defaultSize.width > PreferencesWindowLayout.defaultSize.height)
        #expect(PreferencesWindowLayout.defaultSize.width / PreferencesWindowLayout.defaultSize.height < 1.25)
    }
}

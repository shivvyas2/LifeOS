import Testing
import SwiftUI
@testable import DesignSystem

@Suite struct ColorSchemePreferenceTests {
    @Test func systemLeavesTheSchemeToTheDevice() {
        #expect(ColorSchemePreference.system.colorScheme == nil)
    }

    @Test func lightAndDarkOverrideTheDevice() {
        #expect(ColorSchemePreference.light.colorScheme == .light)
        #expect(ColorSchemePreference.dark.colorScheme == .dark)
    }
}

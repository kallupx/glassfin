import SwiftUI

struct DesignAccessibilityValues: Equatable, Sendable {
    var reduceTransparency = false
    var increaseContrast = false
    var reduceMotion = false

    var contrast: ColorSchemeContrast {
        increaseContrast ? .increased : .standard
    }
}

/// System accessibility settings are read-only. Debug renders can supply explicit
/// values for custom surfaces without attempting to write SwiftUI's environment.
@propertyWrapper
struct DesignAccessibility: DynamicProperty {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if DEBUG
        @Environment(\.designAccessibilityOverride) private var override
    #endif

    var wrappedValue: DesignAccessibilityValues {
        #if DEBUG
            if let override {
                return override
            }
        #endif
        return DesignAccessibilityValues(
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased,
            reduceMotion: reduceMotion
        )
    }
}

#if DEBUG
    private enum DesignAccessibilityOverrideKey: EnvironmentKey {
        static let defaultValue: DesignAccessibilityValues? = nil
    }

    extension EnvironmentValues {
        var designAccessibilityOverride: DesignAccessibilityValues? {
            get { self[DesignAccessibilityOverrideKey.self] }
            set { self[DesignAccessibilityOverrideKey.self] = newValue }
        }
    }
#endif

import GlassfinCore

/// UI lifecycle markers complement the model's Performance category. Instruments owns the clock.
@MainActor
enum DeviceLaunchMeasurement {
    private static var row: DevicePerformance.Interval?
    private static var interactive: DevicePerformance.Interval?

    static func begin() {
        row = DevicePerformance.begin(.launchHomeRow)
        interactive = DevicePerformance.begin(.launchInteractive)
    }

    static func homeRowAppeared() {
        row?.end()
        row = nil
    }

    static func homeReceivedFocus() {
        interactive?.end()
        interactive = nil
    }

    static func cancel() {
        row?.end(completed: false)
        interactive?.end(completed: false)
        row = nil
        interactive = nil
    }
}

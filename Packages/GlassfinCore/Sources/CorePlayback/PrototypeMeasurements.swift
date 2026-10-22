import Foundation

/// Device numbers are absent until someone measures them. CI must not invent a pass.
///
/// TODO(Q8-2-04): case 2 scrub is either P7 (direct play only) or PB1's 3 s transcode limit.
/// TODO(Q8-2-08): P5/P6/P7 need a person with an Apple TV. This process does not record them.
/// TODO(Q8-2-10): whether these ADR results cover iOS is open. The builder is shared.
/// TODO(Q8-2-11): App Store review of the undocumented header key is not decided by a simulator run.
public enum PrototypeMeasurements {
    public static let directPlayStartLimitLAN = Duration.milliseconds(1_500)
    public static let directPlayStartLimitOldest = Duration.milliseconds(2_500)
    public static let directPlayScrubLimitLAN = Duration.milliseconds(1_000)
    public static let transcodeStartLimitLAN = Duration.milliseconds(4_000)
    public static let case2ScrubLimitUnresolved = true

    public static var recordedFirstFrame: Duration? { nil }
    public static var recordedScrub: Duration? { nil }
    public static var recordedTranscodeStart: Duration? { nil }
    public static var recordedMemoryGrowth: Int? { nil }
}

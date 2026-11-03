import Foundation

enum MonotonicClock {
    /// Seconds from a monotonic clock that keeps counting while the device sleeps and is not
    /// affected by the user changing the wall-clock time.
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

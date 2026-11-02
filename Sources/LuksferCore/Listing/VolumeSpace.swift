import Foundation

/// How much free space a folder's disk has.
public enum VolumeSpace {
    /// The larger of the two numbers macOS gives. The "important usage" number counts space macOS
    /// can free on the startup disk, but it is 0 on other disks. The plain number is right there.
    public static func free(important: Int64?, plain: Int?) -> Int64? {
        switch (important, plain.map(Int64.init)) {
        case (nil, nil): return nil
        case let (a, b): return max(a ?? 0, b ?? 0)
        }
    }

    public static func free(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                          .volumeAvailableCapacityKey])
        return free(important: values?.volumeAvailableCapacityForImportantUsage, plain: values?.volumeAvailableCapacity)
    }
}

import Darwin
import Foundation

/// Private functions looked up at run time, so a missing one turns its feature off
/// instead of keeping the bar from launching. None of them needs SIP off.
enum Private {
    static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    static let mediaRemote = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    static func function<T>(_ name: String, in framework: String) -> T? {
        guard let handle = dlopen(framework, RTLD_LAZY), let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

/// The Mission Control spaces shown now.
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let connection: MainConnection? = Private.function("CGSMainConnectionID", in: Private.skyLight)
    private static let copySpaces: CopyManagedDisplaySpaces? = Private.function("CGSCopyManagedDisplaySpaces", in: Private.skyLight)

    /// display (1-based, in the order macOS lists them) -> the space it shows (1-based,
    /// counted over every display's spaces, like Mission Control and sketchybar)
    static func current() -> [Int: Int] {
        guard let connection, let copySpaces,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        var result: [Int: Int] = [:]
        var index = 0
        for (display, info) in displays.enumerated() {
            let shown = (info["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            for space in info["Spaces"] as? [[String: Any]] ?? [] {
                index += 1
                if let id = space["ManagedSpaceID"] as? Int, id == shown { result[display + 1] = index }
            }
        }
        return result
    }
}

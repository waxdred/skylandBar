// swift-tools-version: 5.9
// Swift 5 language mode on purpose: AppKit, sockets and run loop callbacks without the
// strict concurrency annotations; the core (SkylandBarCore) is plain value types.
import PackageDescription

let package = Package(
    name: "skylandbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "skylandbar", targets: ["skylandbar"]),
        .library(name: "SkylandBarCore", targets: ["SkylandBarCore"]),
    ],
    targets: [
        // commands, properties, model, layout: no AppKit, unit tested
        .target(name: "SkylandBarCore"),
        // sketchybar's Mach messages (its CLI, SbarLua), in C like sketchybar's own
        .target(name: "SkylandMach"),
        // the bar: socket server and client, windows, drawing, events, scripts
        .executableTarget(
            name: "skylandbar",
            dependencies: ["SkylandBarCore", "SkylandMach"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .testTarget(name: "SkylandBarCoreTests", dependencies: ["SkylandBarCore"]),
    ]
)

import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import IOKit.ps

// The system events: front_app_switched, space_change, display_change,
// system_woke, system_will_sleep, power_source_change, volume_change, wifi_change,
// brightness_change, media_change, and the custom events tied to a distributed
// notification (--add event <name> <notification>).

final class SystemEvents {
    /// (event, INFO)
    var onEvent: ((String, String) -> Void)?
    /// the now playing artwork changed (media.artwork)
    var onArtwork: ((NSImage?) -> Void)?
    private let wifi = WifiWatcher()
    private let brightness = BrightnessWatcher()
    private let media = MediaWatcher()
    private var customObservers: [NSObjectProtocol] = []
    private var lastVolume: Int?
    private var volumeDevice = AudioObjectID(kAudioObjectUnknown)
    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reportVolume() }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.watchDefaultOutput() }
    fileprivate static weak var current: SystemEvents?

    func start() {
        SystemEvents.current = self
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onEvent?("front_app_switched", app?.localizedName ?? "")
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?("space_change", "")
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?("system_woke", "")
        }
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?("system_will_sleep", "")
        }
        if let source = IOPSNotificationCreateRunLoopSource({ _ in SystemEvents.current?.reportPowerSource() }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, deviceListener)
        watchDefaultOutput()
        wifi.onChange = { [weak self] ssid in self?.onEvent?("wifi_change", ssid) }
        wifi.start()
        brightness.onChange = { [weak self] percent in self?.onEvent?("brightness_change", String(percent)) }
        brightness.start()
        media.onChange = { [weak self] info in self?.onEvent?("media_change", info) }
        media.onArtwork = { [weak self] image in self?.onArtwork?(image) }
        media.start()
    }

    /// The custom events with a distributed notification, observed again after each change.
    func observeCustom(_ events: [String: String]) {
        let center = DistributedNotificationCenter.default()
        for observer in customObservers { center.removeObserver(observer) }
        customObservers = events.filter { !$0.value.isEmpty }.map { event, notification in
            center.addObserver(forName: NSNotification.Name(notification), object: nil, queue: .main) { [weak self] note in
                var info = ""
                if let userInfo = note.userInfo, JSONSerialization.isValidJSONObject(userInfo),
                   let data = try? JSONSerialization.data(withJSONObject: userInfo)
                {
                    info = String(decoding: data, as: UTF8.self)
                }
                self?.onEvent?(event, info)
            }
        }
    }

    // MARK: power source: INFO = AC | BATTERY

    fileprivate func reportPowerSource() {
        onEvent?("power_source_change", Self.powerSource())
    }

    static func powerSource() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot) else { return "AC" }
        return type.takeUnretainedValue() as String == kIOPSACPowerValue ? "AC" : "BATTERY"
    }

    // MARK: volume: INFO = 0...100

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Follows the default output device: the volume listener moves to the new one.
    private func watchDefaultOutput() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != volumeDevice else { return }
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        if volumeDevice != AudioObjectID(kAudioObjectUnknown) {
            AudioObjectRemovePropertyListenerBlock(volumeDevice, &volumeAddress, DispatchQueue.main, volumeListener)
        }
        volumeDevice = device
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, DispatchQueue.main, volumeListener)
        reportVolume()
    }

    private func reportVolume() {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(volumeDevice, &address, 0, nil, &size, &volume) == noErr else { return }
        let percent = Int((volume * 100).rounded())
        guard percent != lastVolume else { return }
        let first = lastVolume == nil
        lastVolume = percent
        if !first { onEvent?("volume_change", String(percent)) }
    }
}

// MARK: wifi_change: INFO = the network's name ("" when macOS keeps it from apps without
// Location Services)

final class WifiWatcher: NSObject, CWEventDelegate {
    var onChange: ((String) -> Void)?
    private let client = CWWiFiClient.shared()
    private var pending = false

    func start() {
        client.delegate = self
        try? client.startMonitoringEvent(with: .ssidDidChange)
        try? client.startMonitoringEvent(with: .linkDidChange)
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { report() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { report() }

    /// once for a burst (joining a network changes the link and the name)
    private func report() {
        DispatchQueue.main.async {
            guard !self.pending else { return }
            self.pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.pending = false
                self.onChange?(self.client.interface()?.ssid() ?? "")
            }
        }
    }
}

// MARK: brightness_change: INFO = 0...100, the main display's

final class BrightnessWatcher {
    var onChange: ((Int) -> Void)?
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Register = @convention(c) (UInt32, UInt32, CFNotificationCallback) -> Int32
    private let get: GetBrightness? = Private.function("DisplayServicesGetBrightness", in: Private.displayServices)
    private let register: Register? = Private.function("DisplayServicesRegisterForBrightnessChangeNotifications", in: Private.displayServices)
    private var last: Int?
    private var poll: Timer?
    fileprivate static weak var current: BrightnessWatcher?

    func start() {
        guard get != nil else { return }
        last = read()
        BrightnessWatcher.current = self
        let display = CGMainDisplayID()
        if let register, register(display, display, { _, _, _, _, _ in
            DispatchQueue.main.async { BrightnessWatcher.current?.check() }
        }) == 0 {
            return
        }
        // no notifications: look twice a second
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func read() -> Int? {
        var value: Float = 0
        guard let get, get(CGMainDisplayID(), &value) == 0 else { return nil }
        return Int((value * 100).rounded())
    }

    fileprivate func check() {
        guard let percent = read(), percent != last else { return }
        last = percent
        onChange?(percent)
    }
}

// MARK: media_change: INFO = {"state", "title", "album", "artist", "app"}
// MediaRemote where macOS still answers apps (before 15.4), the Music and Spotify
// notifications everywhere.

final class MediaWatcher {
    var onChange: ((String) -> Void)?
    var onArtwork: ((NSImage?) -> Void)?
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private let register: Register? = Private.function("MRMediaRemoteRegisterForNowPlayingNotifications", in: Private.mediaRemote)
    private let getInfo: GetInfo? = Private.function("MRMediaRemoteGetNowPlayingInfo", in: Private.mediaRemote)
    private let getPlaying: GetPlaying? = Private.function("MRMediaRemoteGetNowPlayingApplicationIsPlaying", in: Private.mediaRemote)
    private var last = ""
    private var lastArtwork: Data?

    func start() {
        if let register {
            register(DispatchQueue.main)
            for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"] {
                NotificationCenter.default.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.askMediaRemote()
                }
            }
        }
        let center = DistributedNotificationCenter.default()
        for (name, app) in [("com.apple.Music.playerInfo", "Music"), ("com.spotify.client.PlaybackStateChanged", "Spotify")] {
            center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = (info["Player State"] as? String ?? "").lowercased()
                self?.report(state: state == "playing" ? "playing" : state == "paused" ? "paused" : "stopped",
                             title: info["Name"] as? String ?? "", album: info["Album"] as? String ?? "",
                             artist: info["Artist"] as? String ?? "", app: app)
            }
        }
    }

    private func askMediaRemote() {
        guard let getInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            guard let self, !info.isEmpty else { return }
            let report = { (playing: Bool) in
                self.report(state: playing ? "playing" : "paused",
                            title: info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "",
                            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                            artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "", app: "")
                let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                if artwork != self.lastArtwork {
                    self.lastArtwork = artwork
                    self.onArtwork?(artwork.flatMap { NSImage(data: $0) })
                }
            }
            if let getPlaying = self.getPlaying {
                getPlaying(DispatchQueue.main) { playing in report(playing) }
            } else {
                report((info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0)
            }
        }
    }

    private func report(state: String, title: String, album: String, artist: String, app: String) {
        let json: [String: String] = ["state": state, "title": title, "album": album, "artist": artist, "app": app]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return }
        let info = String(decoding: data, as: UTF8.self)
        guard info != last else { return }
        last = info
        onChange?(info)
    }
}

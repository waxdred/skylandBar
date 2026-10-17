import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps

// sketchybar's system events: front_app_switched, space_change, display_change,
// system_woke, system_will_sleep, power_source_change, volume_change, and the custom
// events tied to a distributed notification (--add event <name> <notification>).

final class SystemEvents {
    /// (event, INFO)
    var onEvent: ((String, String) -> Void)?
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

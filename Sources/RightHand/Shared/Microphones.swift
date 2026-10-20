import AVFoundation
import CoreAudio

/// Which microphone RightHand listens with — for Ellipse and for the "My voice" track of a recording.
/// Empty = the Mac's default input (System Settings → Sound).
enum Microphones {
    static let key = "audio.microphone"

    struct Device: Identifiable, Hashable {
        let id: String // AVCaptureDevice.uniqueID, the same as the Core Audio device UID
        let name: String
    }

    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var all: [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The chosen microphone if it's still connected (a USB microphone may be unplugged).
    static var selected: Device? {
        let id = selectedID
        return id.isEmpty ? nil : all.first { $0.id == id }
    }

    /// "MacBook Pro Microphone", or the default one's name.
    static var selectedName: String {
        if let selected { return selected.name }
        return AVCaptureDevice.default(for: .audio)?.localizedName ?? L("Default microphone")
    }

    /// A fresh audio engine listening to the chosen microphone, and the format to tap it with —
    /// nil when that microphone gives no usable sound (then nothing is recorded instead of crashing:
    /// tapping with the previous device's format makes macOS abort the app).
    static func engine() -> (engine: AVAudioEngine, format: AVAudioFormat)? {
        let engine = AVAudioEngine()
        apply(to: engine)
        var format = engine.inputNode.inputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate == 0 {
            // The chosen microphone isn't usable right now: fall back to the Mac's default input.
            let fallback = AVAudioEngine()
            format = fallback.inputNode.inputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { return nil }
            return (fallback, format)
        }
        return (engine, format)
    }

    /// Points an audio engine's input at the chosen microphone (before the engine starts).
    static func apply(to engine: AVAudioEngine) {
        guard let device = selected, var deviceID = coreAudioID(of: device.id),
              let unit = engine.inputNode.audioUnit else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private static func coreAudioID(of uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), pointer, &size, &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }
}

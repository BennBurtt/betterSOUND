// betterSOUND — gérer et réinitialiser facilement les entrées et sorties audio du Mac.
// Compilation : ./build.sh   (nécessite les Command Line Tools : xcode-select --install)

import SwiftUI
import AppKit
import CoreAudio
import AudioToolbox

// MARK: - Accès Core Audio

enum Scope {
    case output, input
    var value: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func addr(_ selector: AudioObjectPropertySelector,
          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

enum CA {
    static func has(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        return AudioObjectHasProperty(id, &a)
    }

    static func settable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        var ok: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &a),
              AudioObjectIsPropertySettable(id, &a, &ok) == noErr else { return false }
        return ok.boolValue
    }

    static func get<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var a = address
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    static func set<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        guard settable(id, address) else { return false }
        var a = address
        var v = value
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = addr(selector)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0)
        }
        guard status == noErr, let s = value else { return nil }
        return s.takeRetainedValue() as String
    }

    static func deviceIDs() -> [AudioDeviceID] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func channelCount(_ id: AudioDeviceID, _ scope: Scope) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, scope.value)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Élément principal (0) puis chaque canal (1…n).
    static func elements(_ id: AudioDeviceID, _ scope: Scope) -> [AudioObjectPropertyElement] {
        let n = channelCount(id, scope)
        return [kAudioObjectPropertyElementMain] + (n > 0 ? (1...n).map { UInt32($0) } : [])
    }

    // Volume ---------------------------------------------------------------

    static func virtualVolume(_ scope: Scope) -> AudioObjectPropertyAddress {
        addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.value)
    }

    static func canSetVolume(_ id: AudioDeviceID, _ scope: Scope) -> Bool {
        if settable(id, virtualVolume(scope)) { return true }
        return elements(id, scope).contains { settable(id, addr(kAudioDevicePropertyVolumeScalar, scope.value, $0)) }
    }

    static func volume(_ id: AudioDeviceID, _ scope: Scope) -> Float? {
        if let v = get(id, virtualVolume(scope), Float32(0)) { return v }
        let values = elements(id, scope).compactMap {
            get(id, addr(kAudioDevicePropertyVolumeScalar, scope.value, $0), Float32(0))
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    static func setVolume(_ id: AudioDeviceID, _ scope: Scope, _ value: Float) {
        let v = Float32(min(max(value, 0), 1))
        if set(id, virtualVolume(scope), v) { return }
        for e in elements(id, scope) {
            set(id, addr(kAudioDevicePropertyVolumeScalar, scope.value, e), v)
        }
    }

    // Muet -----------------------------------------------------------------

    static func canMute(_ id: AudioDeviceID, _ scope: Scope) -> Bool {
        elements(id, scope).contains { settable(id, addr(kAudioDevicePropertyMute, scope.value, $0)) }
    }

    static func isMuted(_ id: AudioDeviceID, _ scope: Scope) -> Bool? {
        let values = elements(id, scope).compactMap {
            get(id, addr(kAudioDevicePropertyMute, scope.value, $0), UInt32(0))
        }
        return values.isEmpty ? nil : values.contains { $0 != 0 }
    }

    static func setMuted(_ id: AudioDeviceID, _ scope: Scope, _ muted: Bool) {
        for e in elements(id, scope) {
            set(id, addr(kAudioDevicePropertyMute, scope.value, e), UInt32(muted ? 1 : 0))
        }
    }

    // Balance --------------------------------------------------------------

    static func centerBalance(_ id: AudioDeviceID, _ scope: Scope) {
        set(id, addr(kAudioHardwareServiceDeviceProperty_VirtualMainBalance, scope.value), Float32(0.5))
    }

    // Appareils par défaut -------------------------------------------------

    static func defaultDevice(_ scope: Scope) -> AudioDeviceID {
        let sel = scope == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        return get(systemObject, addr(sel), AudioDeviceID(0)) ?? 0
    }

    static func setDefault(_ id: AudioDeviceID, _ scope: Scope) {
        if scope == .output {
            set(systemObject, addr(kAudioHardwarePropertyDefaultOutputDevice), id)
            set(systemObject, addr(kAudioHardwarePropertyDefaultSystemOutputDevice), id) // sons d'alerte
        } else {
            set(systemObject, addr(kAudioHardwarePropertyDefaultInputDevice), id)
        }
    }
}

// MARK: - Modèle

struct Device: Identifiable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32
    var volume: Float?
    var canSetVolume: Bool
    var muted: Bool
    var canMute: Bool

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }

    static func load(_ id: AudioDeviceID, _ scope: Scope) -> Device? {
        guard CA.channelCount(id, scope) > 0 else { return nil }
        if let hidden = CA.get(id, addr(kAudioDevicePropertyIsHidden), UInt32(0)), hidden != 0 { return nil }
        return Device(
            id: id,
            name: CA.string(id, kAudioObjectPropertyName) ?? "Appareil \(id)",
            transport: CA.get(id, addr(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0,
            volume: CA.volume(id, scope),
            canSetVolume: CA.canSetVolume(id, scope),
            muted: CA.isMuted(id, scope) ?? false,
            canMute: CA.canMute(id, scope)
        )
    }
}

@MainActor
final class AudioModel: ObservableObject {
    @Published var outputs: [Device] = []
    @Published var inputs: [Device] = []
    @Published var defaultOutput: AudioDeviceID = 0
    @Published var defaultInput: AudioDeviceID = 0
    @Published var status = ""

    init() {
        refresh()
        listen()
    }

    func refresh() {
        let ids = CA.deviceIDs()
        outputs = ids.compactMap { Device.load($0, .output) }
        inputs = ids.compactMap { Device.load($0, .input) }
        defaultOutput = CA.defaultDevice(.output)
        defaultInput = CA.defaultDevice(.input)
    }

    /// Met à jour automatiquement quand un appareil est branché/débranché ou change de défaut.
    private func listen() {
        let selectors = [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice]
        for sel in selectors {
            var a = addr(sel)
            AudioObjectAddPropertyListenerBlock(systemObject, &a, DispatchQueue.main) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    private func reload(_ id: AudioDeviceID, _ scope: Scope) {
        guard let d = Device.load(id, scope) else { return }
        if scope == .output, let i = outputs.firstIndex(where: { $0.id == id }) { outputs[i] = d }
        if scope == .input, let i = inputs.firstIndex(where: { $0.id == id }) { inputs[i] = d }
    }

    func setVolume(_ id: AudioDeviceID, _ scope: Scope, _ value: Float) {
        CA.setVolume(id, scope, value)
        reload(id, scope)
    }

    func toggleMute(_ d: Device, _ scope: Scope) {
        CA.setMuted(d.id, scope, !d.muted)
        reload(d.id, scope)
    }

    func setDefault(_ id: AudioDeviceID, _ scope: Scope) {
        CA.setDefault(id, scope)
        refresh()
    }

    func resetAll(outputLevel: Float, inputLevel: Float, useBuiltIn: Bool) {
        refresh()
        for d in outputs {
            CA.setMuted(d.id, .output, false)
            CA.setVolume(d.id, .output, outputLevel)
            CA.centerBalance(d.id, .output)
        }
        for d in inputs {
            CA.setMuted(d.id, .input, false)
            CA.setVolume(d.id, .input, inputLevel)
        }
        if useBuiltIn {
            if let b = outputs.first(where: \.isBuiltIn) { CA.setDefault(b.id, .output) }
            if let b = inputs.first(where: \.isBuiltIn) { CA.setDefault(b.id, .input) }
        }
        refresh()
        status = "✅ Réinitialisé : sorties à \(Int(outputLevel * 100)) %, entrées à \(Int(inputLevel * 100)) %, son réactivé, balance centrée"
            + (useBuiltIn ? ", appareils intégrés par défaut." : ".")
    }

    /// Redémarre le service audio de macOS (demande le mot de passe administrateur).
    func restartCoreAudio() {
        let cmd = "launchctl kickstart -kp system/com.apple.audio.coreaudiod || killall coreaudiod"
        let source = "do shell script \"\(cmd)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) == -128 {
            status = "Redémarrage annulé."
            return
        }
        if let error {
            status = "❌ Échec : \(error[NSAppleScript.errorMessage] as? String ?? "erreur inconnue")"
            return
        }
        status = "🔄 Service audio redémarré."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }
}

// MARK: - Interface

func transportIcon(_ t: UInt32, _ scope: Scope) -> String {
    switch t {
    case kAudioDeviceTransportTypeBuiltIn: return scope == .output ? "laptopcomputer" : "mic"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
    case kAudioDeviceTransportTypeUSB: return "cable.connector"
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
    case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
    case kAudioDeviceTransportTypeVirtual: return "waveform"
    case kAudioDeviceTransportTypeAggregate: return "square.stack.3d.up"
    default: return scope == .output ? "hifispeaker" : "music.mic"
    }
}

struct DeviceRow: View {
    let device: Device
    let scope: Scope
    let isDefault: Bool
    @ObservedObject var model: AudioModel

    private var muteIcon: String {
        scope == .output
            ? (device.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            : (device.muted ? "mic.slash.fill" : "mic.fill")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { model.setDefault(device.id, scope) } label: {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Utiliser cet appareil par défaut")

                Image(systemName: transportIcon(device.transport, scope))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(device.name)
                    .fontWeight(isDefault ? .semibold : .regular)
                    .lineLimit(1)
                if isDefault {
                    Text("Par défaut")
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button { model.toggleMute(device, scope) } label: {
                    Image(systemName: muteIcon)
                        .foregroundStyle(device.muted ? Color.red : Color.primary)
                        .frame(width: 22)
                }
                .buttonStyle(.borderless)
                .disabled(!device.canMute)
                .help(device.canMute ? (device.muted ? "Réactiver le son" : "Couper le son") : "Pas de fonction muet")

                if device.canSetVolume {
                    Slider(value: Binding(
                        get: { Double(device.volume ?? 0) },
                        set: { model.setVolume(device.id, scope, Float($0)) }
                    ), in: 0...1)
                    Text("\(Int(((device.volume ?? 0) * 100).rounded())) %")
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                } else {
                    Text("Volume non réglable par logiciel")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.leading, 23)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView: View {
    static let logo: NSImage? = Bundle.main.url(forResource: "logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    @StateObject private var model = AudioModel()
    @AppStorage("outputLevel") private var outputLevel = 0.5
    @AppStorage("inputLevel") private var inputLevel = 0.75
    @AppStorage("useBuiltIn") private var useBuiltIn = true
    @State private var confirmRestart = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("better").font(.system(size: 22, weight: .light))
                if let logo = Self.logo {
                    Image(nsImage: logo)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 21)
                } else {
                    Text("SOUND").font(.system(size: 24, weight: .black))
                }
                Spacer()
            }
            .padding([.horizontal, .top])

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Sorties", icon: "speaker.wave.2", devices: model.outputs,
                            scope: .output, defaultID: model.defaultOutput)
                    section("Entrées", icon: "mic", devices: model.inputs,
                            scope: .input, defaultID: model.defaultInput)
                }
                .padding()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sorties à").frame(width: 70, alignment: .leading)
                    Slider(value: $outputLevel, in: 0...1, step: 0.05)
                    Text("\(Int(outputLevel * 100)) %").monospacedDigit().frame(width: 46, alignment: .trailing)
                }
                HStack {
                    Text("Entrées à").frame(width: 70, alignment: .leading)
                    Slider(value: $inputLevel, in: 0...1, step: 0.05)
                    Text("\(Int(inputLevel * 100)) %").monospacedDigit().frame(width: 46, alignment: .trailing)
                }
                Toggle("Remettre les haut-parleurs et le micro intégrés par défaut", isOn: $useBuiltIn)

                HStack {
                    Button {
                        model.resetAll(outputLevel: Float(outputLevel), inputLevel: Float(inputLevel),
                                       useBuiltIn: useBuiltIn)
                    } label: {
                        Label("Tout réinitialiser", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        confirmRestart = true
                    } label: {
                        Label("Redémarrer le service audio…", systemImage: "bolt.horizontal.circle")
                    }
                    .help("En cas de son qui grésille, coupe ou disparaît : relance coreaudiod")

                    Spacer()
                }
                if !model.status.isEmpty {
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 600)
        .toolbar {
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Actualiser")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .alert("Redémarrer le service audio ?", isPresented: $confirmRestart) {
            Button("Redémarrer") { model.restartCoreAudio() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le son sera coupé une ou deux secondes. Votre mot de passe administrateur sera demandé.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, devices: [Device],
                         scope: Scope, defaultID: AudioDeviceID) -> some View {
        GroupBox {
            if devices.isEmpty {
                Text("Aucun appareil").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 4) {
                    ForEach(devices) { d in
                        DeviceRow(device: d, scope: scope, isDefault: d.id == defaultID, model: model)
                        if d.id != devices.last?.id { Divider() }
                    }
                }
            }
        } label: {
            Label(title, systemImage: icon).font(.headline)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BetterSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("betterSOUND") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}

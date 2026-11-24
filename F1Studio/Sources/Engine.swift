import Foundation
import CoreMIDI
import Combine

// Only the F1 is subscribed. Network input can never feed its own output.
final class Route {
    private let lock = NSLock()
    private var held: [UInt32: UInt32] = [:]
    private var notes = Array(36...51)
    private var host: RTPHost?
    private var count = 0
    private var error: OSStatus = 0

    func configure(notes: [Int]) {
        lock.lock(); defer { lock.unlock() }
        self.notes = notes
    }
    private var assignments = [String:Int]()
    func configure(assignments:[String:Int]) {
        lock.lock(); defer { lock.unlock() }
        self.assignments = assignments
    }
    private var ccOutputs = [String:Bool]()
    func configure(ccOutputs:[String:Bool]) {
        lock.lock(); defer { lock.unlock() }
        self.ccOutputs = ccOutputs
    }
    func activate(_ host: RTPHost) {
        lock.lock(); defer { lock.unlock() }
        self.host = host
        count = 0
        error = 0
    }
    func status() -> (Int, OSStatus) {
        lock.lock(); defer { lock.unlock() }
        return (count, error)
    }
    private func send(_ word: UInt32, _ time: MIDITimeStamp) {
        if host?.send(word, time) == true { count += 1 } else { error = -1 }
    }
    func panic(stop: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        for target in Set(held.values) { release(target,time:0) }
        held.removeAll()
        if stop { host = nil }
    }
    private func release(_ target:UInt32,time:UInt64) {
        let off = target >> 20 & 15 == 9 ? target ^ 0x00100000 : target
        send(off,time)
    }
    func process(_ word: UInt32, time: MIDITimeStamp, touch: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard host != nil, word >> 28 == 2 else { return }
        let status = (word >> 20) & 15
        guard [8,9,11].contains(status) else { send(word,time); return }
        let continuous = status == 11
        let number = Int((word >> 8) & 127)
        let value = word & 127
        let channel = word & 0xf0000
        let key = channel | UInt32(number) | (touch ? 0x1000000 : 0) | (continuous ? 0x2000000 : 0)
        let control = (continuous ? "c" : "n") + String(number)
        let cc = ccOutputs[control] ?? continuous
        let mapped = !continuous && (36...51).contains(number) ? notes[number-36] : assignments[control] ?? number
        let target = (cc ? UInt32(0x20b00000) : 0x20900000) | channel | UInt32(mapped)<<8
        // A held gesture keeps its original assignment through release, even after an edit.
        let gateOpen = status != 8 && value != 0
        if let previous = held[key] {
            if gateOpen { return }
            held.removeValue(forKey:key)
            if !held.values.contains(previous) { release(previous,time:time) }
            return
        }
        if continuous && cc { send(target | value,time); return }
        guard gateOpen else { return }
        let shared = held.values.contains(target)
        held[key] = target
        if !shared { send(target | (cc ? 127 : value),time) }
    }
}

final class Engine: ObservableObject {
    @Published var notes: [Int] {
        didSet { route.configure(notes: notes); UserDefaults.standard.set(notes, forKey: "gridNotes") }
    }
    @Published private(set) var running = false
    @Published private(set) var input = "Waiting for F1"
    @Published private(set) var sessionInfo = ""
    @Published private(set) var peers = ""
    @Published private(set) var sent = 0
    @Published private(set) var issue = ""
    @Published var ccOutputs = UserDefaults.standard.dictionary(forKey:"outputTypesCC") as? [String:Bool] ?? [:] {
        didSet { route.configure(ccOutputs:ccOutputs); UserDefaults.standard.set(ccOutputs,forKey:"outputTypesCC") }
    }
    @Published var controlLabels = UserDefaults.standard.dictionary(forKey:"controlLabels") as? [String:String] ?? [:] {
        didSet { UserDefaults.standard.set(controlLabels,forKey:"controlLabels") }
    }
    @Published var assignments:[String:Int] {
        didSet { route.configure(assignments:assignments); UserDefaults.standard.set(assignments,forKey:"surfaceAssignments") }
    }
    func surfaceEvent(_ number:Int,cc:Bool,value:Int) {
        guard running else { return }
        let status:UInt32 = cc ? 0x20b00000 : value==0 ? 0x20800000 : 0x20900000
        route.process(status | UInt32(number)<<8 | UInt32(value),time:0,touch:true)
    }
    private let route = Route()
    private let host = RTPHost()
    private var client: MIDIClientRef = 0
    private var reader: MIDIPortRef = 0
    private var current: MIDIEndpointRef = 0
    private let inputName: String
    init(inputName: String = "Traktor Kontrol F1") {
        assignments = (UserDefaults.standard.dictionary(forKey:"surfaceAssignments") as? [String:Int] ?? [:]).filter { (0...127).contains($0.value) }
        self.inputName = inputName
        let saved = UserDefaults.standard.array(forKey: "gridNotes") as? [Int]
        notes = saved.flatMap { $0.count == 16 && $0.allSatisfy { (0...127).contains($0) } ? $0 : nil } ?? Array(36...51)
        route.configure(notes: notes)
        route.configure(assignments:assignments)
        route.configure(ccOutputs:ccOutputs)
    }
    func start() {
        guard !running else { return }
        issue = ""
        let route = route
        var status = MIDIClientCreateWithBlock("F1 Studio" as CFString, &client) { _ in }
        if status == 0 {
            status = MIDIInputPortCreateWithProtocol(client, "USB F1" as CFString, ._1_0, &reader) { events, _ in
                ForEachF1Message(events) { word, stamp in
                    route.process(word, time: stamp)
                }
            }
        }
        guard status == 0 else { issue = "Core MIDI error \(status)"; dispose(); return }
        guard host.start() else { issue = "Could not open the RTP-MIDI ports"; dispose(); return }
        route.activate(host)
        running = true
        refresh()
    }
    @Published private(set) var connectionState = ""
    func isOwnService(_ service:NetService) -> Bool { running && service.name == host.name && service.domain == "local." }
    func connect(_ address:sockaddr_in,_ name:String) {
        if !running { start() }
        guard running else { return }
        host.invite(address,name)
        refresh()
    }
    func refresh() {
        guard running else { return }
        let sources = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }
        let f1 = sources.first { endpoint in
            var name: Unmanaged<CFString>?
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            guard offline == 0,
                  MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == 0 else { return false }
            return (name?.takeRetainedValue() as String?)?.localizedCaseInsensitiveContains(inputName) == true
        } ?? 0
        if current != f1 {
            route.panic()
            if current != 0 { MIDIPortDisconnectSource(reader, current) }
            current = 0
            if f1 != 0 && MIDIPortConnectSource(reader, f1, nil) == 0 { current = f1 }
        }
        input = current == 0 ? "Waiting for F1" : inputName
        sessionInfo = "\(host.name) · UDP \(host.port)"
        connectionState = host.invitationStatus
        peers = host.connected.joined(separator: ", ")
        if peers.isEmpty { peers = "Waiting for a peer" }
        let stats = route.status()
        sent = stats.0
        if stats.1 != 0 { issue = "MIDI send error \(stats.1)" }
    }
    func touchPad(_ index: Int, down: Bool) {
        guard running && (0..<16).contains(index) else { return }
        route.process((down ? 0x2090007f : 0x20800000) | UInt32(36+index)<<8,time:0,touch:true)
    }
    func touchFader(_ index: Int, value: Int) {
        guard running && (0..<4).contains(index) && (0...127).contains(value) else { return }
        route.process(0x20b00000 | UInt32(20+index)<<8 | UInt32(value),time:0,touch:true)
    }
    func panic() { route.panic() }
    private func dispose() {
        if client != 0 { MIDIClientDispose(client) }
        client = 0; reader = 0; current = 0
    }
    func stop() {
        guard running else { return }
        route.panic(stop: true)
        dispose()
        host.stop()
        connectionState = ""
        running = false
    }
}

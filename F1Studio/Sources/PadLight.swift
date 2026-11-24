import SwiftUI
import CoreMIDI

final class PadLight: ObservableObject {
    @Published private(set) var status = "Connect the F1 to edit its lights."
    @Published private(set) var available = false
    @Published private(set) var lastRead: [Int: [UInt8]] = [:]
    @Published private(set) var busy = false
    // Keep unscaled colors so a sweep back from zero can restore every pad.
    private var originals = [Int: [UInt8]]()
    private var applied = [Int: [UInt8]]()
    private var masterLevel: Int?
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var output: MIDIPortRef = 0
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private var partial = [UInt8]()
    private var generation = 0
    private var tag: UInt8 = 0
    private var pending: (pad: UInt8, tag: UInt8, writing: Bool, expected: [UInt8]?)?
    init() {
        var result = MIDIClientCreateWithBlock("F1 Studio lights" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        if result == 0 {
            result = MIDIInputPortCreateWithBlock(client,"Pad color replies" as CFString,&input) { [weak self] packets, token in
                let origin = UInt(bitPattern: token)
                F1VisitBytes(packets) { bytes, count in
                    guard let bytes, count > 0 else { return }
                    let copy = Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
                    DispatchQueue.main.async {
                        guard let self, origin == UInt(self.source) else { return }
                        self.receive(copy)
                    }
                }
            }
        }
        if result == 0 { result = MIDIOutputPortCreate(client,"Pad color requests" as CFString,&output) }
        if result == 0 { refresh() } else { status = "Light editor MIDI error \(result)" }
    }
    deinit { if client != 0 { MIDIClientDispose(client) } }
    func refresh() {
        guard input != 0 && output != 0 else { return }
        var pairs: [(MIDIEndpointRef,MIDIEndpointRef)] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            var entity: MIDIEntityRef = 0
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(d,kMIDIPropertyOffline,&offline)
            guard offline == 0, MIDIObjectGetStringProperty(d,kMIDIPropertyDisplayName,&name)==0,
                  (name?.takeRetainedValue() as String?)?.localizedCaseInsensitiveContains("Traktor Kontrol F1")==true,
                  MIDIEndpointGetEntity(d,&entity)==0, entity != 0 else { continue }
            var device: MIDIDeviceRef = 0
            guard MIDIEntityGetDevice(entity,&device)==0, device != 0 else { continue }
            var matches = [MIDIEndpointRef]()
            for j in 0..<MIDIDeviceGetNumberOfEntities(device) {
                let sibling = MIDIDeviceGetEntity(device,j)
                for k in 0..<MIDIEntityGetNumberOfSources(sibling) {
                    let s = MIDIEntityGetSource(sibling,k)
                    var disabled: Int32 = 0
                    MIDIObjectGetIntegerProperty(s,kMIDIPropertyOffline,&disabled)
                    if s != 0 && disabled == 0 { matches.append(s) }
                }
            }
            if matches.count == 1 { pairs.append((matches[0],d)) }
        }
        let new = pairs.count == 1 ? pairs[0] : (0,0)
        if new.0 == 0 || new.1 == 0 {
            if source != 0 { MIDIPortDisconnectSource(input,source) }
            source=0; destination=0; available=false; resetDevice()
            status = pairs.count > 1 ? "Connect one F1 to edit its lights." : "Waiting for an F1 with two-way MIDI firmware."
            return
        }
        guard source != new.0 || destination != new.1 else { return }
        resetDevice()
        if source != 0 { MIDIPortDisconnectSource(input,source) }
        guard MIDIPortConnectSource(input,new.0,UnsafeMutableRawPointer(bitPattern: UInt(new.0)))==0 else {
            source=0; destination=0; available=false; status="Could not open F1 light replies."; return
        }
        source=new.0; destination=new.1; available=true; status="Ready to read or preview a pad color."
    }
    private func resetDevice() {
        clear()
        originals.removeAll()
        applied.removeAll()
        lastRead.removeAll()
    }
    func setGridBrightness(_ percent: Int) {
        guard available, !busy, (0...100).contains(percent) else { return }
        masterLevel = percent
        transmit(0,write:nil,expected:nil)
    }
    private func advanceGrid(pad: UInt8, rgb: [UInt8], verified: Bool, level: Int) {
        let key = Int(pad)
        if verified {
            applied[key] = rgb
            if pad == 15 {
                status = "All 16 pads confirmed at \(level)%."
            } else {
                masterLevel = level
                transmit(pad+1,write:nil,expected:nil)
            }
        } else {
            if applied[key] != rgb || originals[key] == nil { originals[key] = rgb }
            let target = (originals[key] ?? rgb).map { UInt8((Int($0)*level+50)/100) }
            if target == rgb {
                advanceGrid(pad:pad,rgb:rgb,verified:true,level:level)
            } else {
                masterLevel = level
                transmit(pad,write:target,expected:target)
            }
        }
    }
    private func clear() { generation += 1; masterLevel=nil; pending=nil; partial=[]; busy=false }
    func request(pad: Int, color: [UInt8]?) {
        guard !busy, available, (0..<16).contains(pad) else { return }
        if let color, color.count != 3 || color.contains(where: { $0 > 127 }) { return }
        transmit(UInt8(pad),write:color,expected:color)
    }
    private func transmit(_ pad: UInt8, write: [UInt8]?, expected: [UInt8]?) {
        tag = (tag + 1) & 127
        let msg: [UInt8] = [240,125,70,49,1,tag,write == nil ? 1 : 2,pad] + (write ?? []) + [247]
        pending=(pad,tag,write != nil,expected); busy=true
        generation += 1
        let revision = generation
        let result = msg.withUnsafeBufferPointer { F1SendColorBytes(output,destination,$0.baseAddress,UInt16($0.count)) }
        guard result == 0 else { clear(); status="Could not send color command (\(result))."; return }
        status = "Waiting for pad \(pad+1)…"
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
            guard let self, self.generation == revision else { return }
            self.clear(); self.status="Color readback timed out."
        }
    }
    private func receive(_ bytes: [UInt8]) {
        guard busy else { return }
        for b in bytes {
            if b >= 248 { continue }
            if b == 240 { partial=[240]; continue }
            guard !partial.isEmpty else { continue }
            if b == 247 {
                let m=partial+[247]; partial=[]
                guard m.count==12, m.starts(with:[240,125,70,49,1]), let q=pending,
                      m[5]==q.tag, m[6]==3, m[7]==q.pad else {continue}
                let rgb=Array(m[8...10])
                let level = masterLevel
                clear()
                if let expected=q.expected, rgb != expected { status="Pad \(q.pad+1) returned a different color: \(rgb)."; continue }
                if q.writing { masterLevel = level; transmit(q.pad,write:nil,expected:rgb) }
                else if let level { advanceGrid(pad:q.pad,rgb:rgb,verified:q.expected != nil,level:level) }
                else { lastRead[Int(q.pad)] = rgb; status="Pad \(q.pad+1) · RGB \(rgb[0]), \(rgb[1]), \(rgb[2]) · read from F1" }
            } else if b < 128 && partial.count < 11 { partial.append(b) }
            else { partial=[] }
        }
    }
}

struct PadLightControls: View {
    let pad: Int
    @ObservedObject var lights: PadLight
    @State private var rgb: [UInt8] = [127,0,0]
    private let names = ["Red","Amber","Green","Cyan","Blue","Violet","White","Off"]
    private let colors: [[UInt8]] = [[127,0,0],[127,55,0],[0,127,0],[0,100,127],[0,0,127],[90,0,127],[127,127,127],[0,0,0]]
    var body: some View {
        GroupBox("Hardware light · Pad \(pad+1)") {
            VStack(alignment:.leading) {
                Picker("Palette",selection:Binding(get:{ colors.firstIndex(of:rgb) ?? -1 },set:{ i in
                    if colors.indices.contains(i) { rgb=colors[i] }
                })) {
                    Text("Custom").tag(-1)
                    ForEach(names.indices,id:\.self) { i in Text(names[i]).tag(i) }
                }
                ForEach(0..<3) { i in
                    HStack {
                        Text(["Red","Green","Blue"][i]).frame(width:48,alignment:.leading)
                        Slider(value:Binding(get:{Double(rgb[i])},set:{rgb[i]=UInt8($0.rounded())}),in:0...127,step:1)
                        Text("\(rgb[i])").monospacedDigit().frame(width:32)
                    }
                }
                HStack {
                    Button("Preview on F1") { lights.request(pad:pad,color:rgb) }
                    Button("Read from F1") { lights.request(pad:pad,color:nil) }
                }.disabled(!lights.available || lights.busy)
                Text(lights.status).font(.footnote)
                    .onReceive(lights.$lastRead) { values in
                        if let value=values[pad] { rgb=value }
                    }
            }.onChange(of:pad) { _,new in
                if let value=lights.lastRead[new] { rgb=value }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

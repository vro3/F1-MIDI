import SwiftUI
import UniformTypeIdentifiers

@main
struct Studio: App {
    @StateObject private var engine = Engine()
    var body: some Scene {
        WindowGroup { Console(engine: engine) }
    }
}

struct Console: View {
    @ObservedObject var engine: Engine
    @StateObject private var padLights = PadLight()
    @State private var editor = false
    @State private var choosingPort = false
    @State private var importing = false
    @State private var importStatus = ""
    @State private var levels = Array(repeating:0.0,count:4)
    @Environment(\.scenePhase) private var phase
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var selection = 36
    @State private var knobs = Array(repeating:0.0,count:4)
    private let buttonNames = [52:"Shift",53:"Reverse",54:"Type",55:"Size",56:"Browse",57:"Encoder push",60:"Stop 1",61:"Stop 2",62:"Stop 3",63:"Stop 4",64:"Sync",65:"Quant",66:"Capture"]
    func defaultName(_ n:Int)->String {
        if (36...51).contains(n) { return "Pad " + String(n-35) }
        if (16...19).contains(n) { return "Knob " + String(n-15) }
        if (20...23).contains(n) { return "Fader " + String(n-19) }
        return buttonNames[n] ?? "Encoder turn"
    }
    func name(_ n:Int)->String {
        guard let label=engine.controlLabels[String(n)], !label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return defaultName(n) }
        return label
    }
    func ccOutput(_ n:Int)->Binding<Bool> {
        let key=(n<36 ? "c":"n")+String(n)
        return Binding(get:{engine.ccOutputs[key] ?? (n<36)},set:{engine.ccOutputs[key]=$0})
    }
    func assignment(_ n:Int)->Binding<Int> {
        if (36...51).contains(n) { return $engine.notes[n-36] }
        let key=(n<36 ? "c":"n")+String(n)
        return Binding(get:{engine.assignments[key] ?? n},set:{engine.assignments[key]=$0})
    }
    func key(_ n:Int, pad:Bool=false)->some View {
        StudioKey(label:pad && name(n)==defaultName(n) ? String(format:"%02d",n-35) : name(n), detail:pad ? (ccOutput(n).wrappedValue ? "CC " : "N ") + String(assignment(n).wrappedValue) : "", selected:editor && selection==n, pad:pad) { down in
            selection=n
            if !editor { engine.surfaceEvent(n,cc:false,value:down ? 127:0) }
        }
    }
    func axis(_ i:Int, fader:Bool)->some View {
        let n=(fader ? 20:16)+i
        let binding=fader ? $levels[i] : $knobs[i]
        return VStack(spacing:3) {
            ZStack {
                if fader {
                    Capsule().fill(.black).frame(width:5,height:66)
                    RoundedRectangle(cornerRadius:3).fill(.gray.gradient).frame(width:34,height:12)
                        .overlay(Rectangle().fill(.white).frame(height:1)).offset(y:27-54*binding.wrappedValue/127)
                } else {
                    Circle().fill(.gray.gradient).frame(width:36,height:36)
                    Capsule().fill(.mint).frame(width:3,height:11).offset(y:-10).rotationEffect(.degrees(-135+270*binding.wrappedValue/127))
                }
            }.frame(maxWidth:.infinity).frame(height:fader ? 70:40)
            Text(name(n)).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.65)
        }.padding(3).background(editor && selection==n ? Color.mint.opacity(0.23):Color.clear,in:RoundedRectangle(cornerRadius:5))
        .contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0,coordinateSpace:.local).onChanged { g in
            selection=n
            guard !editor else { return }
            let v=max(0,min(127,Int((1-g.location.y/(fader ? 70:40))*127)))
            binding.wrappedValue=Double(v);engine.surfaceEvent(n,cc:true,value:v)
        }).accessibilityLabel(name(n)).accessibilityAction { selection=n }
    }
    var panel:some View {
        VStack(spacing:8) {
            HStack { Text("KONTROL F1").font(.headline).tracking(2); Spacer() }
            HStack { ForEach(0..<4) { axis($0,fader:false) } }
            HStack { ForEach(0..<4) { axis($0,fader:true) } }
            Divider()
            HStack { key(64);key(65);key(66)
                Text("88").font(.system(size:22,weight:.thin,design:.monospaced)).foregroundStyle(.gray).accessibilityLabel("Display illustration")
                VStack(spacing:0) {
                    HStack(spacing:3) { ForEach([-1,1],id:\.self) { d in
                        Button(d<0 ? "−":"+") { selection=24;if !editor {engine.surfaceEvent(24,cc:true,value:d<0 ? 127:1)} }
                    } }
                    key(57)
                }
            }
            HStack { ForEach(52..<57) { key($0) } }
            ForEach(0..<4) { row in HStack { ForEach(0..<4) { col in key(36+4*row+col,pad:true) } } }
            HStack { ForEach(60..<64) { key($0) } }
        }.padding(14).frame(maxWidth:440).foregroundStyle(.white)
        .background(LinearGradient(colors:[Color(white:0.18),Color(white:0.07)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:15))
    }
    var inspector:some View {
        VStack(alignment:.leading,spacing:14) {
            Picker("Workspace",selection:$editor) { Text("Perform").tag(false);Text("Edit").tag(true) }.pickerStyle(.segmented)
            if editor {
                Text(name(selection)).font(.title2.bold())
                LabeledContent("Label") {
                    TextField(defaultName(selection),text:Binding(get:{engine.controlLabels[String(selection)] ?? ""},set:{ value in
                        if value.isEmpty { engine.controlLabels.removeValue(forKey:String(selection)) }
                        else { engine.controlLabels[String(selection)]=value }
                    })).textFieldStyle(.roundedBorder).id(selection)
                }
                Text("MIDI channel 1").font(.subheadline)
                if selection != 24 {
                    Picker("Message type",selection:ccOutput(selection)) { Text("Note").tag(false); Text("CC").tag(true) }.pickerStyle(.segmented)
                }
                Stepper((ccOutput(selection).wrappedValue ? "CC number " : "Note number ") + String(assignment(selection).wrappedValue),value:assignment(selection),in:0...127)
                if selection < 24 && !ccOutput(selection).wrappedValue {
                    Text("Move above zero to play the note. Return to zero to release it.").font(.caption)
                } else if selection >= 36 && ccOutput(selection).wrappedValue {
                    Text("Press sends 127. Release sends 0.").font(.caption)
                } else if selection < 24 {
                    Text("CC value follows position, from 0 to 127.").font(.caption)
                }
                if (36...51).contains(selection) { PadLightControls(pad:selection-36,lights:padLights) }
                Button("Import pad notes") { importing=true }
                if !importStatus.isEmpty {Text(importStatus)}
            } else {
                Text("Performance").font(.title2.bold())
                LabeledContent("USB input",value:engine.running ? engine.input:"Stopped")
                if engine.running { LabeledContent("Session",value:engine.sessionInfo); LabeledContent("Peers",value:engine.peers); LabeledContent("Messages",value:String(engine.sent)) }
                Button(engine.running ? "Close RTP-MIDI session":"Open RTP-MIDI session") { if engine.running { engine.stop() } else { engine.start() } }.buttonStyle(.borderedProminent)
                Button("Connect to…") { choosingPort=true }
                if engine.running { Button("Release held notes") {engine.panic()} }
                if !engine.connectionState.isEmpty {Text(engine.connectionState)}
                if !engine.issue.isEmpty {Text(engine.issue)}
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
    }
    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                HStack(alignment:.top,spacing:0) {
                    ScrollView {panel.padding(12)}.frame(width:max(330,geo.size.width-max(300,min(390,geo.size.width*0.4))))
                    Divider()
                    ScrollView {inspector}.frame(width:max(300,min(390,geo.size.width*0.4)))
                }.frame(height:geo.size.height)
            }
        }.sheet(isPresented:$choosingPort) { ConnectionPicker(engine:engine) }.fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            do {
                struct Incoming: Decodable {
                    struct Row: Decodable { let kind: String; let channel, number: Int; let midiNumber, midiChannel: Int? }
                    let version: Int; let routes:[Row]
                }
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try JSONDecoder().decode(Incoming.self,from:Data(contentsOf:url))
                guard data.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                var layout = engine.notes, seen = Set<Int>()
                for row in data.routes where row.kind == "note" && row.channel == 1 && (36...51).contains(row.number) {
                    let note = row.midiNumber ?? row.number
                    guard (0...127).contains(note), (row.midiChannel ?? 1) == 1, seen.insert(row.number).inserted else { throw CocoaError(.fileReadCorruptFile) }
                    layout[row.number-36] = note
                }
                guard !seen.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                engine.notes = layout; importStatus = "Imported \(seen.count) pad assignments."
            } catch { importStatus = "Could not import this channel 1 pad layout." }
        }.onAppear { if !engine.running { engine.start() } }.onReceive(tick) { _ in engine.refresh() }
    }
}

private struct StudioKey:View {
    let label:String, detail:String
    let selected:Bool,pad:Bool
    let change:(Bool)->Void
    @GestureState private var down=false
    var body:some View {
        VStack(spacing:2) { Text(label).font(pad ? .headline:.caption2.bold()).lineLimit(1).minimumScaleFactor(0.65)
            if !detail.isEmpty {Text(detail).font(.caption2.monospacedDigit())}
        }.frame(maxWidth:.infinity,minHeight:pad ? 50:30)
        .background(down ? Color.teal : pad ? Color.teal.opacity(0.28):Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:5))
        .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? Color.mint:Color.white.opacity(0.16),lineWidth:selected ? 2:1))
        .contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).updating($down) { _,state,_ in state=true })
        .onChange(of:down) { _,v in change(v) }.onDisappear { if down {change(false)} }
        .accessibilityAction { change(true);change(false) }
    }
}

private final class SessionDirectory: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var sessions = [NetService]()
    @Published var message = "Looking for MIDI ports…"
    private let browser = NetServiceBrowser()
    private var resolving: NetService?
    var resolved: ((sockaddr_in,String)->Void)?
    func start() {
        browser.delegate = self
        browser.searchForServices(ofType:"_apple-midi._udp.",inDomain:"local.")
    }
    func stop() {
        browser.stop(); resolving?.stop(); resolving=nil; resolved=nil
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool) {
        if !sessions.contains(service) { sessions.append(service); sessions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool) { sessions.removeAll { $0 == service } }
    func netServiceBrowser(_ browser:NetServiceBrowser,didNotSearch error:[String:NSNumber]) { message="Discovery failed. Check local network access." }
    func choose(_ service:NetService) {
        resolving?.stop(); resolving=service; service.delegate=self
        message="Finding " + service.name + "…"; service.resolve(withTimeout:5)
    }
    func netService(_ sender:NetService,didNotResolve error:[String:NSNumber]) { if sender == resolving { message="Could not resolve this port. Try again." } }
    func netServiceDidResolveAddress(_ sender:NetService) {
        guard sender == resolving else { return }
        for data in sender.addresses ?? [] where data.count >= MemoryLayout<sockaddr_in>.size {
            let addr=data.withUnsafeBytes { $0.loadUnaligned(as:sockaddr_in.self) }
            if Int32(addr.sin_family)==AF_INET && addr.sin_port != 0 && addr.sin_port != UInt16.max { resolved?(addr,sender.name); return }
        }
        message="This port has no usable IPv4 address."
    }
}

private struct ConnectionPicker: View {
    @ObservedObject var engine:Engine
    @StateObject private var directory=SessionDirectory()
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading) {
            Text("Connect to a MIDI port").font(.title2.bold())
            List(directory.sessions.filter { !engine.isOwnService($0) },id:\.self) { service in
                Button(service.name) { directory.choose(service) }
            }
            Text(directory.message).font(.caption)
            Button("Cancel") { dismiss() }
        }.padding().frame(minWidth:280,minHeight:320)
        .onAppear {
            directory.resolved = { address,name in engine.connect(address,name); dismiss() }
            directory.start()
        }.onDisappear { directory.stop() }
    }
}

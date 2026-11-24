import SwiftUI
import CoreMIDI
import UniformTypeIdentifiers

struct PresetFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
final class Remote: ObservableObject {
    @Published var profile: Profile { didSet { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data,forKey:profile.device == "X1 MK2" ? "profile.X1" : "profile") } } }
    @Published var selection = 0
    @Published var learn = false
    @Published var armed = false
    @Published var input = "Waiting for F1"
    @Published var log = "Ready"
    @Published var issue = ""
    private var output: OSCOutput?, client: MIDIClientRef = 0, port: MIDIPortRef = 0, source: MIDIEndpointRef = 0
    private var midiOutput: MIDIEndpointRef = 0
    let lights = PadLight()
    @Published var feedbackStatus = ""
    private var receiver: FeedbackReceiver?
    private var colorQueue = [Int:[UInt8]]()
    private var colorOrder = [Int]()
    private var colorPumpScheduled = false
    func preview(_ colors: [Int:[UInt8]]) {
        guard lights.available else {feedbackStatus="Waiting for the F1 MIDI destination.";return}
        for (pad,rgb) in colors.sorted(by:{$0.key<$1.key}) {
            if colorQueue[pad] == nil {colorOrder.append(pad)}
            colorQueue[pad]=rgb
        }
        pump()
    }
    private func pump() {
        guard !colorPumpScheduled,!colorOrder.isEmpty else {return}
        guard lights.available else {colorOrder=[];colorQueue=[:];return}
        if !lights.busy {
            let pad=colorOrder.removeFirst()
            if let rgb=colorQueue.removeValue(forKey:pad){lights.request(pad:pad,color:rgb)}
        }
        if !colorOrder.isEmpty {
            colorPumpScheduled=true
            DispatchQueue.main.asyncAfter(deadline:.now()+0.025){[weak self] in self?.colorPumpScheduled=false;self?.pump()}
        }
    }
    func stopFeedback(){receiver?.stop();receiver=nil;colorOrder=[];colorQueue=[:];feedbackStatus=""}
    private func startFeedback() throws {
        guard let port=profile.feedbackPort, profile.device != "X1 MK2" else {return}
        receiver=try FeedbackReceiver(port:port,update:{[weak self] event in
            guard let self,self.armed else {return}
            var updates=[Int:[UInt8]]()
            for m in self.profile.routes where m.feedbackPath==event.path {
                if let id=m.controlID,(0..<16).contains(id){updates[id]=event.rgb}
            }
            if !updates.isEmpty {self.preview(updates)}
        },status:{[weak self] text in self?.feedbackStatus=text})
    }
    private var held = Set<Int>()
    init() {
        profile = Self.load("F1")
        var result = MIDIClientCreateWithBlock("F1 Remote" as CFString,&client) { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        if result == 0 {
            result = MIDIInputPortCreateWithProtocol(client,"F1 Controls" as CFString,._1_0,&port) { [weak self] events,_ in
                ForEachF1Message(events) { word,_ in
                    DispatchQueue.main.async { self?.receive(Int(word>>16 & 255),Int(word>>8 & 127),Int(word & 127)) }
                }
            }
        }
        if result == 0 {
            result = MIDISourceCreateWithProtocol(client,"F1 Remote Output" as CFString,._1_0,&midiOutput)
        }
        if result != 0 { issue = "Core MIDI error \(result)" }
        refresh()
    }
    static func load(_ device:String) -> Profile {
        let key = device == "F1" ? "profile" : "profile.X1"
        let url = Bundle.main.url(forResource:device == "F1" ? "Companion" : "X1",withExtension:"json")!
        let factory = try! JSONDecoder().decode(Profile.self,from:Data(contentsOf:url))
        guard let data=UserDefaults.standard.data(forKey:key), var saved=try? JSONDecoder().decode(Profile.self,from:data),
              (try? saved.validate()) != nil else {return factory}
        saved.device = factory.device
        for i in saved.routes.indices where saved.routes[i].controlID == nil {
            let row = saved.routes[i]
            saved.routes[i].controlID = factory.routes.first { $0.channel == row.channel && $0.kind == row.kind && $0.number == row.number }?.controlID
        }
        return saved
    }
    func switchDevice(_ name:String) {
        guard !armed else {return}
        stopFeedback();selection=0; profile=Self.load(name); issue=""; refresh()
    }
    func refresh() {
        guard port != 0 else { return }
        let endpoint = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).first { e in
            var name: Unmanaged<CFString>?, offline: Int32 = 0
            MIDIObjectGetIntegerProperty(e,kMIDIPropertyOffline,&offline)
            return offline == 0 && MIDIObjectGetStringProperty(e,kMIDIPropertyDisplayName,&name) == 0 && (name?.takeRetainedValue() as String?)?.localizedCaseInsensitiveContains(self.profile.device == "X1 MK2" ? "X1 MK2 Mapped" : "Traktor Kontrol F1") == true
        } ?? 0
        if endpoint == 0 {input = profile.device == "X1 MK2" ? "Waiting for X1 MK2 Mapped" : "Waiting for F1"}
        guard endpoint != source else { return }
        releaseAll()
        if source != 0 { MIDIPortDisconnectSource(port,source) }
        source = 0
        if endpoint != 0 && MIDIPortConnectSource(port,endpoint,nil) == 0 { source = endpoint }
        input = source == 0 ? "Waiting for controller" : (profile.device ?? "Traktor Kontrol F1")
    }
    func toggle() {
        if armed { releaseAll(); stopFeedback(); output = nil; armed = false; return }
        do { try profile.validate()
            if profile.routes.contains(where: { $0.outputMode != "midi" }) { output = try OSCOutput(profile) }
            if profile.routes.contains(where: { ["both","midi"].contains($0.outputMode ?? "osc") }) && midiOutput == 0 { throw RouteError.invalid("Core MIDI output unavailable.") }
            try startFeedback(); armed = true; issue = "" } catch { stopFeedback();output=nil;issue = error.localizedDescription }
    }
    func releaseAll() {
        for id in Array(held) { receive(0x80 | id/128,id%128,0) }
        held.removeAll()
    }
    func receive(_ status: Int,_ key: Int,_ value: Int) {
        let type = status >> 4
        guard [8,9,11].contains(type) else { return }
        let id = (status & 15)*128+key
        if type == 9 && value != 0 && armed { held.insert(id) }
        if type == 8 || type == 9 && value == 0 { held.remove(id) }
        for (i,m) in profile.routes.enumerated() where m.channel == (status & 15)+1 && m.number == key && ((type == 11) == (m.kind != "note")) {
            if learn { selection = i }
            if armed && ["both","midi"].contains(m.outputMode ?? "osc") {
                let result = PublishF1Message(midiOutput,m.midiWord(status,value))
                if result != 0 { issue = "MIDI output error \(result)" }
                log = "\(m.label) → MIDI \(m.midiNumber ?? m.number) · \(value)"
            }
            for (path,bytes) in m.messages(status,key,value) {
                if armed, let output {
                    do { try output.write(bytes); log = "\(m.label) · \(value) → \(path)" } catch { issue = error.localizedDescription }
                } else { log = "\(m.label) · \(value)" }
            }
        }
    }
}
@main struct F1RemoteApp: App {
    @StateObject var remote = Remote()
    var body: some Scene { WindowGroup { RemoteView(r:remote) } }
}
struct RemoteView: View {
    @ObservedObject var r: Remote
    @State var importing = false
    @State var exporting = false
    @State var testValue = 64
    @Environment(\.scenePhase) var phase
    var body: some View {
        let m = $r.profile.routes[r.selection]
        GeometryReader { geo in
            VStack(spacing:0) {
                HStack {
                    Image(systemName:"dial.medium.fill").foregroundStyle(.mint)
                    Text("Controller Studio").font(.title3.bold())
                    Spacer()
                    Button(r.armed ? "Stop routing" : "Start routing") { r.toggle() }.buttonStyle(.borderedProminent).tint(.teal)
                }.padding(16)
                Divider()
                if geo.size.width >= 720 {
                    HStack(spacing:0) {
                        ScrollView { surface }.frame(maxWidth:.infinity)
                        Divider()
                        ScrollView { inspector(m) }.frame(width:min(360,geo.size.width*0.42))
                    }
                } else {
                    ScrollView { surface; Divider(); inspector(m) }
                }
            }.background(Color(red:0.06,green:0.075,blue:0.085)).preferredColorScheme(.dark)
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let p = try JSONDecoder().decode(Profile.self,from:Data(contentsOf:url)); try p.validate()
                var imported = p
                let factory=Remote.load(p.device ?? "F1")
                for i in imported.routes.indices where imported.routes[i].controlID == nil {
                    let row=imported.routes[i]
                    imported.routes[i].controlID=factory.routes.first { $0.kind==row.kind && $0.number==row.number && $0.channel==row.channel }?.controlID
                }
                r.selection = 0; r.profile = imported; r.refresh(); r.issue = ""
            } catch { r.issue = error.localizedDescription }
        }
        .fileExporter(isPresented:$exporting,document:PresetFile((try? JSONEncoder().encode(r.profile)) ?? Data()),contentType:.json,defaultFilename:"F1 Remote") { result in if case .failure(let e) = result { r.issue = e.localizedDescription } }
        .onChange(of:phase) { _,new in if new == .background && r.armed { r.toggle() } }
    }
    @State private var editorRGB: [UInt8] = [127,0,0]
    @ObservedObject private var gridLights: PadLight
    init(r:Remote){self.r=r;self.gridLights=r.lights}
    @State private var brightness = 100.0
    @State private var showLabels = true
    var surface: some View {
        VStack(spacing:14) {
            HStack {
                Picker("Controller",selection:Binding(get:{r.profile.device ?? "F1"},set:{r.switchDevice($0)})) {
                    Text("Kontrol F1").tag("F1"); Text("Kontrol X1 MK2").tag("X1 MK2")
                }.labelsHidden().disabled(r.armed)
                Spacer()
                Toggle("Labels",isOn:$showLabels).toggleStyle(.switch)
            }
            Faceplate(remote:r,labels:showLabels)
            if r.profile.device != "X1 MK2" {
                VStack(alignment:.leading) {
                    HStack { Text("Pad grid brightness"); Spacer(); Text("\(Int(brightness))%").monospacedDigit() }
                    HStack {
                        Slider(value:$brightness,in:0...100,step:1).accessibilityLabel("Pad grid brightness")
                        Button("Apply") { gridLights.setGridBrightness(Int(brightness)) }
                    }.disabled(!gridLights.available || gridLights.busy)
                    Text(gridLights.status).font(.caption)
                }
            }
            HStack {Circle().fill(r.input.hasPrefix("Waiting") ? Color.gray : .mint).frame(width:7,height:7);Text(r.input);Spacer()}.font(.caption)
        }.padding(16)
    }
    @ViewBuilder func paletteEditor(_ pad:Int,_ mapping:Binding<Mapping>) -> some View {
        GroupBox("Preset palette") {
            VStack(alignment:.leading) {
                ForEach(0..<3) { i in
                    HStack {Text(["R","G","B"][i]); Slider(value:Binding(get:{Double(editorRGB[i])},set:{editorRGB[i]=UInt8($0.rounded())}),in:0...127,step:1);Text("\(editorRGB[i])").monospacedDigit()}
                }
                HStack {
                    ForEach(["Pad","Row","Column"],id:\.self) { scope in
                        Button(scope) {
                            var colors=r.profile.palette ?? Array(repeating:[127,0,0],count:16)
                            for i in 0..<16 where i==pad || (scope=="Row" && i/4==pad/4) || (scope=="Column" && i%4==pad%4) {colors[i]=editorRGB}
                            r.profile.palette=colors
                        }
                    }
                }.disabled(r.armed)
                Button("Apply preset colors to F1") {
                    if let colors=r.profile.palette {r.preview(Dictionary(uniqueKeysWithValues:colors.enumerated().map{($0.offset,$0.element)}))}
                }.disabled(r.profile.palette == nil || !gridLights.available)
                Toggle("Receive OSC pad colors",isOn:Binding(get:{r.profile.feedbackPort != nil},set:{r.profile.feedbackPort=$0 ? 12322:nil})).disabled(r.armed)
                if r.profile.feedbackPort != nil {
                    TextField("Listen port",value:Binding(get:{r.profile.feedbackPort ?? 12322},set:{r.profile.feedbackPort=$0}),format:.number.grouping(.never))
                    TextField("/pad/1/color",text:Binding(get:{mapping.wrappedValue.feedbackPath ?? ""},set:{mapping.wrappedValue.feedbackPath=$0}))
                    Text("Send three OSC integers (R, G, B), each 0–127.").font(.caption)
                    Text(r.feedbackStatus).font(.caption)
                }
            }.onAppear {editorRGB=r.profile.palette?[pad] ?? [127,0,0]}
             .onChange(of:pad) {_,p in editorRGB=r.profile.palette?[p] ?? [127,0,0]}
        }
    }
    func inspector(_ m:Binding<Mapping>) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Text("Assignment").font(.caption).foregroundStyle(.mint)
            Text(m.wrappedValue.label).font(.title2.bold())
            Picker("Control",selection:$r.selection) { ForEach(r.profile.routes.indices,id:\.self) { i in Text(r.profile.routes[i].label).tag(i) } }
            Toggle("Select from hardware",isOn:$r.learn)
            Divider()
                Group {
                    TextField("Control name",text:m.label)
                    Picker("Input",selection:m.kind) { Text("Note").tag("note"); Text("CC").tag("cc"); Text("Relative CC").tag("relative") }
                    Stepper("Channel \(m.channel.wrappedValue)",value:m.channel,in:1...16)
                    Stepper("MIDI number \(m.number.wrappedValue)",value:m.number,in:0...127)
                    Picker("Send",selection: Binding(get:{m.wrappedValue.outputMode ?? "osc"},set:{m.wrappedValue.outputMode=$0})) {
                        Text("OSC").tag("osc"); Text("MIDI").tag("midi"); Text("Both").tag("both")
                    }
                    if m.wrappedValue.outputMode == "both" || m.wrappedValue.outputMode == "midi" {
                        Stepper("Output number \(m.wrappedValue.midiNumber ?? m.number.wrappedValue)",value:Binding(get:{m.wrappedValue.midiNumber ?? m.number.wrappedValue},set:{m.wrappedValue.midiNumber=$0}),in:0...127)
                        Stepper("Output channel \(m.wrappedValue.midiChannel ?? m.channel.wrappedValue)",value:Binding(get:{m.wrappedValue.midiChannel ?? m.channel.wrappedValue},set:{m.wrappedValue.midiChannel=$0}),in:1...16)
                    }
                    if m.wrappedValue.outputMode != "midi" {
                    LabeledContent("OSC address") { TextField("/address",text:m.address) }
                    if m.kind.wrappedValue != "cc" { LabeledContent(m.kind.wrappedValue == "note" ? "Release" : "Turn left") { TextField("Alternate address",text:m.alternate) } }
                    Picker("OSC argument",selection:m.format) { Text("None").tag("none"); Text("Integer").tag("int"); Text("Float").tag("float"); Text("Text").tag("string") }
                    if m.format.wrappedValue == "string" { TextField("Text argument",text:Binding(get:{m.wrappedValue.stringValue ?? ""},set:{m.wrappedValue.stringValue=$0})) }
                    if ["int","float"].contains(m.format.wrappedValue) {
                        HStack { Text("Range"); TextField("From",value:m.low,format:.number); Text("to"); TextField("To",value:m.high,format:.number) }
                    }
                    }
                }.textFieldStyle(.roundedBorder).disabled(r.armed)

            if m.wrappedValue.outputMode != "midi" {
                HStack { TextField("OSC host",text:$r.profile.host); TextField("Port",value:$r.profile.port,format:.number.grouping(.never)).frame(width:70) }.disabled(r.armed)
            }
            if r.profile.device != "X1 MK2", let id=m.wrappedValue.controlID, (0..<16).contains(id) { PadLightControls(pad:id,lights:gridLights)
                paletteEditor(id,m) }
            if r.armed {
                Stepper("Test value \(testValue)",value:$testValue,in:0...127)
                Button("Send test") { r.receive((m.kind.wrappedValue=="note" ? 0x90 : 0xb0)+m.channel.wrappedValue-1,m.number.wrappedValue,testValue) }
                Button("Release held notes") {r.releaseAll()}
            }
            Divider()
            HStack { Button("Import preset") {importing=true}.disabled(r.armed); Button("Export preset") {exporting=true} }
            Text(r.log).font(.caption.monospaced())
            if !r.issue.isEmpty {Text(r.issue).foregroundStyle(.orange)}
        }.textFieldStyle(.roundedBorder).padding(18).frame(maxWidth:.infinity,alignment:.leading)
    }
}

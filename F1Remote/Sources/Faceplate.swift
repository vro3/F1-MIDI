import SwiftUI

struct Faceplate: View {
    @ObservedObject var remote: Remote
    let labels: Bool
    private var x1: Bool { remote.profile.device == "X1 MK2" }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(.gray).frame(width:5,height:5)
                Spacer()
                Text(x1 ? "KONTROL  X1 MK2" : "KONTROL  F1")
                    .font(.caption.bold()).tracking(2)
                Spacer()
                Circle().fill(.gray).frame(width:5,height:5)
            }.padding(.bottom,5)
            if x1 {
                ForEach(0..<4) { row in
                    HStack { key(row); key(37+row,"knob"); key(41+row,"knob"); key(4+row) }
                }
                strip([8,9,10,11])
                HStack { key(46,"knob"); key(45,"knob"); key(47,"knob") }
                strip([36,35,15]); strip([34,33,32]); strip([12,13,14])
                strip([48,49])
                ForEach(0..<4) { row in
                    strip([24+row*2,25+row*2,16+row*2,17+row*2])
                }
            } else {
                HStack { ForEach(29..<33) { key($0,"knob") } }
                HStack { ForEach(33..<37) { key($0,"fader") } }
                Divider()
                HStack { key(26); key(27); key(28)
                    Text("88").font(.system(size:20,weight:.light,design:.monospaced)).foregroundStyle(.gray.opacity(0.65)).accessibilityLabel("Display illustration")
                    key(37,"knob")
                }
                strip([16,17,18,19,20])
                HStack { Spacer(); key(21).frame(width:86) }
                ForEach(0..<4) { row in HStack { ForEach(0..<4) { col in key(row*4+col,"pad") } } }
                strip([22,23,24,25])
            }
        }.padding(14).frame(maxWidth:375)
        .background(LinearGradient(colors:[Color(white:0.19),Color(white:0.085)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.15))).foregroundStyle(.white)
    }
    func strip(_ ids:[Int]) -> some View {
        HStack { ForEach(ids,id:\.self) { key($0) } }
    }
    func key(_ id:Int,_ style:String="button") -> some View {
        let index = remote.profile.routes.firstIndex { $0.controlID == id }
        let route = index.map { remote.profile.routes[$0] }
        let selected = index == remote.selection
        return Button {
            if let index { remote.selection=index }
        } label: {
            VStack(spacing:2) {
                if style == "knob" {
                    ZStack(alignment:.top) { Circle().fill(LinearGradient(colors:[.gray,Color(white:0.15)],startPoint:.topLeading,endPoint:.bottomTrailing)); Capsule().fill(.mint).frame(width:2,height:8).padding(.top,2) }.frame(width:24,height:24)
                } else if style == "fader" {
                    ZStack { Capsule().fill(.black).frame(width:4,height:46); RoundedRectangle(cornerRadius:2).fill(.gray.gradient).frame(width:29,height:11).overlay(Rectangle().fill(.white).frame(height:1)) }
                }
                Text(style == "pad" ? String(format:"%02d",id+1) : route?.label ?? "—")
                    .font(.system(size:style == "pad" ? 14 : 10,weight:.semibold)).lineLimit(2).minimumScaleFactor(0.72)
                if labels, let route { Text("\(route.kind == "note" ? "N" : "CC") \(route.number)").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary) }
            }.padding(3).frame(maxWidth:.infinity,minHeight:style == "pad" ? 41 : 24)
            .background(selected ? Color.mint.opacity(0.28) : style == "pad" ? Color.teal.opacity(0.24) : Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? Color.mint : .white.opacity(0.12),lineWidth:selected ? 2 : 1))
        }.buttonStyle(.plain).disabled(index == nil).accessibilityLabel(route?.label ?? "Unassigned")
    }
}

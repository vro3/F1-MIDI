import Foundation
import Darwin

enum RouteError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}
struct Mapping: Codable {
    var feedbackPath: String?
    var controlID: Int?
    var label, kind: String
    var number, channel: Int
    var address, alternate, format: String
    var low, high: Double
    var outputMode: String?
    var midiNumber, midiChannel: Int?
    var stringValue: String?
    func midiWord(_ status: Int, _ value: Int) -> UInt32 {
        let target = (status & 0xf0) | ((midiChannel ?? channel)-1)
        return 0x20000000 | UInt32(target)<<16 | UInt32(midiNumber ?? number)<<8 | UInt32(value)
    }
    func messages(_ status: Int, _ key: Int, _ value: Int) -> [(String, Data)] {
        let type = status >> 4
        guard status % 16 + 1 == channel, number == key else { return [] }
        guard outputMode != "midi" else { return [] }
        var path = address, repetitions = 1
        switch kind {
        case "note":
            guard [8,9].contains(type) else { return [] }
            if type == 8 || value == 0 { path = alternate }
        case "relative":
            guard type == 11, value != 0 else { return [] }
            let delta = value >= 64 ? value - 128 : value
            if delta < 0 { path = alternate }
            repetitions = abs(delta)
        default: guard type == 11 else { return [] }
        }
        guard !path.isEmpty else { return [] }
        func string(_ s: String) -> Data {
            var d = Data(s.utf8); d.append(0)
            while d.count % 4 != 0 { d.append(0) }
            return d
        }
        var packet = string(path)
        packet.append(string(format == "float" ? ",f" : format == "int" ? ",i" : format == "string" ? ",s" : ","))
        if format == "string" { packet.append(string(stringValue ?? "")) }
        if format == "float" || format == "int" {
            let scaled = low + (high-low)*Double(type == 8 ? 0 : value)/127
            var bits = (format == "float" ? Float(scaled).bitPattern : UInt32(bitPattern: Int32(scaled.rounded()))).bigEndian
            withUnsafeBytes(of: &bits) { packet.append(contentsOf: $0) }
        }
        return Array(repeating: (path,packet),count: repetitions)
    }
}
struct Profile: Codable {
    var palette: [[UInt8]]?
    var feedbackPort: Int?
    var device: String?
    var version: Int
    var host: String
    var port: Int
    var routes: [Mapping]
    func validate() throws {
        guard version == 1, !host.isEmpty, !host.contains("\0"), (1...65535).contains(port), (1...256).contains(routes.count) else { throw RouteError.invalid("Check destination, port and preset version.") }
        if let palette, palette.count != 16 || !palette.allSatisfy({$0.count == 3 && $0.allSatisfy({$0<128})}) { throw RouteError.invalid("Expected 16 RGB pad colors.") }
        if let feedbackPort, !(1...65535).contains(feedbackPort) {throw RouteError.invalid("Invalid feedback port.")}
        for m in routes {
            func validPath(_ p: String) -> Bool { p.hasPrefix("/") && !p.utf8.contains(where: {$0 <= 32}) && p.utf8.count < 1024 }
            guard validPath(m.address), m.alternate.isEmpty || validPath(m.alternate), (1...16).contains(m.channel), (0...127).contains(m.number),
                  ["cc","relative","note"].contains(m.kind), ["none","int","float","string"].contains(m.format), ["osc","midi","both"].contains(m.outputMode ?? "osc"),
                  (1...16).contains(m.midiChannel ?? m.channel), (0...127).contains(m.midiNumber ?? m.number),
                  !(m.stringValue ?? "").contains("\0"), (m.stringValue ?? "").utf8.count <= 1024,
                  [m.low,m.high].allSatisfy({$0.isFinite && abs($0) <= 2147483647}) else { throw RouteError.invalid("Invalid mapping for "+m.label) }
        }
    }
}
final class OSCOutput {
    private var fd: Int32 = -1
    init(_ profile: Profile) throws {
        try profile.validate()
        var hints = addrinfo(); hints.ai_socktype = SOCK_DGRAM; hints.ai_family = AF_UNSPEC
        var first: UnsafeMutablePointer<addrinfo>?
        let result = getaddrinfo(profile.host,String(profile.port),&hints,&first)
        guard result == 0 else { throw RouteError.invalid(String(cString:gai_strerror(result))) }
        defer { freeaddrinfo(first) }
        var current = first
        while let info = current?.pointee {
            fd = socket(info.ai_family,info.ai_socktype,info.ai_protocol)
            if fd >= 0 {
                if connect(fd,info.ai_addr,info.ai_addrlen) == 0 { return }
                close(fd); fd = -1
            }
            current = info.ai_next
        }
        throw RouteError.invalid("Could not open UDP destination.")
    }
    func write(_ data: Data) throws {
        let written = data.withUnsafeBytes { Darwin.send(fd,$0.baseAddress,data.count,0) }
        if written != data.count { throw RouteError.invalid(String(cString:strerror(errno))) }
    }
    deinit { if fd >= 0 { close(fd) } }
}

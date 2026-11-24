import Foundation
import Darwin


// AppleMIDI control and data invitations share a token. MIDI travels on the data socket.
final class RTPHost {
    private struct Peer {
        var control: sockaddr_in
        var data: sockaddr_in?
        var name: String
        var token: UInt32
        var initiated = false
        var seen = Date()
        var sequence = UInt16.random(in: 0...UInt16.max)
    }
    private let queue = DispatchQueue(label: "F1Studio.RTP")
    private var sockets = [Int32]()
    private var readers = [DispatchSourceRead]()
    private var peers = [UInt32: Peer]()
    private var service: NetService?
    private let identity = UInt32.random(in: 1...UInt32.max)
    private(set) var port = 0
    var name: String { service?.name ?? "F1 Studio" }
    var connected: [String] { queue.sync { expire(); return peers.values.filter { $0.data != nil }.map(\.name).sorted() } }

    private func bindUDP(_ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        let code = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard code == 0, fcntl(fd,F_SETFL,O_NONBLOCK) == 0 else { close(fd); return -1 }
        return fd
    }
    func start() -> Bool {
        for base in stride(from: 5004, through: 5200, by: 2) {
            let a = bindUDP(base)
            guard a >= 0 else { continue }
            let b = bindUDP(base+1)
            guard b >= 0 else { close(a); continue }
            port = base
            sockets = [a,b]
            for (index, fd) in sockets.enumerated() {
                let read = DispatchSource.makeReadSource(fileDescriptor: fd,queue:queue)
                read.setEventHandler { [weak self] in self?.receive(fd,index) }
                read.setCancelHandler { close(fd) }
                read.resume()
                readers.append(read)
            }
            let ad = NetService(domain:"local.",type:"_apple-midi._udp.",name:"F1 Studio",port:Int32(base))
            service = ad
            ad.publish()
            return true
        }
        return false
    }
    private func bytes<T: FixedWidthInteger>(_ n: T) -> [UInt8] {
        withUnsafeBytes(of: n.bigEndian) { Array($0) }
    }
    private func word(_ a: [UInt8], _ i: Int) -> UInt32 {
        a[i..<i+4].reduce(0) { $0 << 8 | UInt32($1) }
    }
    private let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }()
    private func ticks(_ time: UInt64 = 0) -> UInt64 {
        let host = time == 0 ? mach_absolute_time() : time
        return UInt64(Double(host) * Double(timebase.numer) / Double(timebase.denom) / 100_000)
    }
    @discardableResult private func transmit(_ bytes:[UInt8], _ to:sockaddr_in, _ fd:Int32) -> Bool {
        var address = to
        return withUnsafePointer(to:&address) { ptr in
            ptr.withMemoryRebound(to:sockaddr.self,capacity:1) { addr in
                bytes.withUnsafeBytes { Darwin.sendto(fd,$0.baseAddress,$0.count,0,addr,socklen_t(MemoryLayout<sockaddr_in>.size)) == $0.count }
            }
        }
    }
    private struct Invitation {
        let control:sockaddr_in
        let name:String
        let token:UInt32
        var remoteID:UInt32?
        var attempts = 0
        var index:Int { remoteID == nil ? 0 : 1 }
        var target:sockaddr_in {
            var addr=control
            if index==1 { addr.sin_port=(UInt16(bigEndian:control.sin_port)+1).bigEndian }
            return addr
        }
    }
    private var invitation:Invitation?
    private var progress=""
    var invitationStatus:String { queue.sync { progress } }
    func invite(_ address:sockaddr_in,_ name:String) {
        queue.async {
            guard self.sockets.count==2, UInt16(bigEndian:address.sin_port)<65535 else { return }
            if self.peers.values.contains(where:{ $0.control.sin_addr.s_addr==address.sin_addr.s_addr && $0.control.sin_port==address.sin_port && $0.data != nil }) {
                self.progress="Already connected to " + name; return
            }
            self.invitation=Invitation(control:address,name:name,token:UInt32.random(in:1...UInt32.max))
            self.progress="Connecting to " + name + "…"
            self.sendInvitation()
        }
    }
    private func sendInvitation() {
        guard var call=invitation else { return }
        guard call.attempts<3 else { progress="No reply from " + call.name + ". Try again."; invitation=nil; return }
        call.attempts+=1; invitation=call
        transmit([255,255,73,78]+bytes(UInt32(2))+bytes(call.token)+bytes(identity)+Array("F1 Studio".utf8)+[0],call.target,sockets[call.index])
        let token=call.token, stage=call.index
        queue.asyncAfter(deadline:.now()+1) { [weak self] in
            guard let self, self.invitation?.token==token, self.invitation?.index==stage else { return }
            self.sendInvitation()
        }
    }
    private func synchronize(_ id:UInt32,_ token:UInt32) {
        guard let peer=peers[id],peer.initiated,peer.token==token,let data=peer.data else { return }
        transmit([255,255,67,75]+bytes(identity)+[0,0,0,0]+bytes(ticks())+Array(repeating:0,count:16),data,sockets[1])
        queue.asyncAfter(deadline:.now()+5) { [weak self] in self?.expire(); self?.synchronize(id,token) }
    }
    private func expire() { peers = peers.filter { Date().timeIntervalSince($0.value.seen) < 120 } }
    private func receive(_ fd:Int32, _ index:Int) {
        var buffer = [UInt8](repeating:0,count:1536)
        for _ in 0..<64 {
            var source = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to:&source) { ptr in
                ptr.withMemoryRebound(to:sockaddr.self,capacity:1) { addr in
                    buffer.withUnsafeMutableBytes { recvfrom(fd,$0.baseAddress,$0.count,0,addr,&len) }
                }
            }
            guard n >= 0 else { break }
            guard n >= 12, buffer[0]==255, buffer[1]==255 else { continue }
            expire()
            let cmd = UInt16(buffer[2])<<8 | UInt16(buffer[3])
            if (cmd==0x4f4b || cmd==0x4e4f), n>=16, word(buffer,4)==2, var call=invitation,
               index==call.index, word(buffer,8)==call.token, source.sin_port==call.target.sin_port,
               source.sin_addr.s_addr==call.control.sin_addr.s_addr {
                if cmd==0x4e4f { progress=call.name+" declined the connection."; invitation=nil; continue }
                let id=word(buffer,12)
                if index==0 { call.remoteID=id; call.attempts=0; invitation=call; sendInvitation() }
                else if call.remoteID==id {
                    peers[id]=Peer(control:call.control,data:source,name:call.name,token:call.token,initiated:true)
                    invitation=nil; progress=""; synchronize(id,call.token)
                }
            } else if cmd == 0x494e, n>=16, word(buffer,4)==2 {
                let id = word(buffer,12), token = word(buffer,8)
                if index==0 {
                    guard peers[id]?.control.sin_addr.s_addr == source.sin_addr.s_addr || peers[id]==nil,
                          peers.count<16 || peers[id] != nil else { continue }
                    let label = String(decoding:buffer[16..<n].prefix(63).prefix(while:{$0 != 0}),as:UTF8.self)
                    if peers[id]?.token != token || peers[id]?.control.sin_port != source.sin_port {
                        peers[id] = Peer(control:source,name:label,token:token)
                    }
                } else {
                    guard peers[id]?.token==token, peers[id]?.control.sin_addr.s_addr==source.sin_addr.s_addr else { continue }
                    peers[id]?.data=source
                }
                peers[id]?.seen=Date()
                transmit([255,255,79,75]+bytes(UInt32(2))+bytes(token)+bytes(identity)+Array("F1 Studio".utf8)+[0],source,fd)
            } else if cmd==0x434b, index==1, n>=36 {
                let id=word(buffer,4)
                guard let addr=peers[id]?.data, addr.sin_port==source.sin_port,addr.sin_addr.s_addr==source.sin_addr.s_addr else {continue}
                peers[id]?.seen=Date()
                if buffer[8]==1 && peers[id]?.initiated==true {
                    transmit([255,255,67,75]+bytes(identity)+[2,0,0,0]+Array(buffer[12..<28])+bytes(ticks()),source,fd)
                } else if buffer[8]==0 {
                    transmit([255,255,67,75]+bytes(identity)+[1,0,0,0]+Array(buffer[12..<20])+bytes(ticks())+bytes(UInt64(0)),source,fd)
                }
            } else if cmd==0x4259, n>=16 {
                let id=word(buffer,12)
                guard let peer=peers[id],peer.token==word(buffer,8),
                      peer.control.sin_addr.s_addr==source.sin_addr.s_addr,
                      source.sin_port==(index==0 ? peer.control.sin_port : peer.data?.sin_port) else {continue}
                peers.removeValue(forKey:id)
            }
        }
    }
    func send(_ word:UInt32, _ time:UInt64) -> Bool {
        queue.sync {
            guard sockets.count==2 else {return false}
            let status=UInt8(truncatingIfNeeded:word>>16)
            let length=(status>>4==12 || status>>4==13) ? 2 : 3
            var midi=[status,UInt8(truncatingIfNeeded:word>>8)]
            if length==3 {midi.append(UInt8(truncatingIfNeeded:word))}
            var ok=true
            for id in Array(peers.keys) {
                guard var peer=peers[id],let data=peer.data else {continue}
                let header=[UInt8(128),97]+bytes(peer.sequence)+bytes(UInt32(truncatingIfNeeded:ticks(time)))+bytes(identity)
                ok=transmit(header+[UInt8(length)]+midi,data,sockets[1]) && ok
                peer.sequence &+= 1
                peers[id]=peer
            }
            return ok
        }
    }
    func stop() {
        service?.stop(); service=nil
        queue.sync {
            for peer in peers.values where !sockets.isEmpty {
                transmit([255,255,66,89]+bytes(UInt32(2))+bytes(peer.token)+bytes(identity),peer.control,sockets[0])
            }
            readers.forEach { $0.cancel() }
            readers=[]; sockets=[]; peers=[:]; invitation=nil; progress=""
        }
    }
}

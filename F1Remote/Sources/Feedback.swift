import Foundation
import Network
import SwiftUI

// One OSC message per UDP datagram. The address identifies a physical pad.
struct PadFeedback {
    let path: String
    let rgb: [UInt8]
    init?(_ data: Data) {
        let bytes = Array(data)
        var cursor = 0
        func field() -> String? {
            guard let end = bytes[cursor...].firstIndex(of:0) else { return nil }
            let next = (end+4) & ~3
            guard next <= bytes.count, bytes[end..<next].allSatisfy({$0==0}),
                  let text=String(bytes:bytes[cursor..<end],encoding:.utf8) else { return nil }
            cursor = next
            return text
        }
        guard !bytes.isEmpty, bytes.count <= 2048, let address=field(), address.hasPrefix("/"),
              field()==",iii", cursor+12==bytes.count else { return nil }
        var color=[UInt8]()
        for _ in 0..<3 {
            guard bytes[cursor..<cursor+3].allSatisfy({$0==0}), bytes[cursor+3]<128 else { return nil }
            color.append(bytes[cursor+3]); cursor+=4
        }
        path=address; rgb=color
    }
}
final class FeedbackReceiver {
    private let listener: NWListener
    private var peers=[ObjectIdentifier:NWConnection]()
    init(port:Int, update:@escaping (PadFeedback)->Void, status:@escaping (String)->Void) throws {
        guard (1...65535).contains(port), let port=NWEndpoint.Port(rawValue:UInt16(port)) else {throw RouteError.invalid("Invalid feedback port.")}
        listener=try NWListener(using:.udp,on:port)
        listener.stateUpdateHandler={ state in
            switch state {
            case .ready: status("Listening on UDP \(port.rawValue)")
            case .failed(let error): status(error.localizedDescription)
            default: break
            }
        }
        listener.newConnectionHandler={ [weak self] c in
            guard let self, self.peers.count<32 else { c.cancel();return }
            let id=ObjectIdentifier(c)
            self.peers[id]=c
            c.stateUpdateHandler={ [weak self] state in
                switch state { case .failed,.cancelled:self?.peers.removeValue(forKey:id);default:break }
            }
            c.start(queue:.main)
            self.read(c,update)
        }
        listener.start(queue:.main)
    }
    private func read(_ c:NWConnection,_ update:@escaping (PadFeedback)->Void) {
        c.receiveMessage { [weak self,weak c] data,_,_,error in
            guard let self,let c else {return}
            if error != nil {c.cancel();return}
            if let data,let message=PadFeedback(data) {update(message)}
            self.read(c,update)
        }
    }
    func stop(){listener.cancel(); for c in peers.values {c.cancel()};peers.removeAll()}
}

#import <CoreMIDI/CoreMIDI.h>
static inline void ForEachF1Message(const MIDIEventList *list, void (^visit)(UInt32, MIDITimeStamp)) {
    // This port requests MIDI 1.0 UMP. Skip other message types by UMP length.
    static const UInt8 lengths[16] = {1,1,1,2,2,4,1,1,2,2,2,3,3,4,4,4};
    const MIDIEventPacket *packet = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets; i++, packet = MIDIEventPacketNext(packet)) {
        for (UInt32 j = 0; j < packet->wordCount;) {
            UInt32 word = packet->words[j];
            UInt32 type = word >> 28;
            if (type == 2) visit(word, packet->timeStamp);
            j += lengths[type];
        }
    }
}
static inline OSStatus PublishF1Message(MIDIEndpointRef endpoint, UInt32 message) {
    MIDIEventList list;
    MIDIEventPacket *packet = MIDIEventListInit(&list, kMIDIProtocol_1_0);
    if (!MIDIEventListAdd(&list, sizeof(list), packet, 0, 1, &message)) return kMIDIMessageSendErr;
    return MIDIReceivedEventList(endpoint, &list);
}
static inline OSStatus F1SendColorBytes(MIDIPortRef port, MIDIEndpointRef destination,
                                         const UInt8 *bytes, UInt16 length) {
    MIDIPacketList list;
    MIDIPacket *packet = MIDIPacketListInit(&list);
    if (!MIDIPacketListAdd(&list, sizeof(list), packet, 0, length, bytes)) return kMIDIMessageSendErr;
    return MIDISend(port, destination, &list);
}
static inline void F1VisitBytes(const MIDIPacketList *list, void (^visit)(const UInt8 *, UInt16)) {
    const MIDIPacket *p = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets; ++i, p = MIDIPacketNext(p)) visit(p->data, p->length);
}

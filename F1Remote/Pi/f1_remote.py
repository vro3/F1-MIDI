"""Route a raw ALSA F1 MIDI device through the F1 Remote JSON preset."""
import argparse
import json
import math
from contextlib import ExitStack
import signal
import socket
import struct
from pathlib import Path


def events(stream):
    status = None
    data = []
    while chunk := stream.read(256):
        for byte in chunk:
            if byte >= 0xf8:
                continue
            if byte >= 0x80:
                status = byte if byte < 0xf0 else None
                data.clear()
            elif status is not None:
                data.append(byte)
                if len(data) == (1 if status >> 4 in (12, 13) else 2):
                    if status >> 4 in (8, 9, 11):
                        yield status, *data
                    data.clear()


def osc_string(value):
    data = value.encode() + bytes(1)
    return data + bytes(-len(data) % 4)


def packets(profile, status, number, value):
    for m in profile['routes']:
        if m.get('outputMode') == 'midi':
            continue
        if (m['number'], m['channel']) != (number, status % 16 + 1):
            continue
        if (m['kind'] == 'note') != (status >> 4 in (8, 9)):
            continue
        path = m['address']
        count = 1
        if m['kind'] == 'relative':
            delta = value if value < 64 else value - 128
            count = abs(delta)
            if delta < 0:
                path = m['alternate']
        elif m['kind'] == 'note' and (status >> 4 == 8 or value == 0):
            path = m['alternate']
        if not path:
            continue
        fmt = m['format']
        val = m['low'] + (m['high'] - m['low']) * (0 if status >> 4 == 8 else value) / 127
        arg = b''
        if fmt == 'int':
            arg = struct.pack('>i', int(math.copysign(math.floor(abs(val) + 0.5), val)))
        elif fmt == 'float':
            arg = struct.pack('>f', val)
        elif fmt == 'string':
            arg = osc_string(m.get('stringValue', ''))
        packet = osc_string(path) + osc_string({'none': ',', 'int': ',i', 'float': ',f', 'string': ',s'}[fmt]) + arg
        for _ in range(count):
            yield packet


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('device', help='raw ALSA input, e.g. /dev/snd/midiC1D0')
    ap.add_argument('--preset', type=Path, default=Path(__file__).resolve().parents[1] / 'Presets/Companion.json')
    ap.add_argument('--host', help='override OSC destination')
    ap.add_argument('--midi-out', help='optional separate raw ALSA output device for MIDI/both routes')
    args = ap.parse_args()
    profile = json.loads(args.preset.read_text())
    if profile['version'] != 1:
        ap.error('unsupported profile version')
    dest = socket.getaddrinfo(args.host or profile['host'], profile['port'], type=socket.SOCK_DGRAM)[0]
    held = set()
    def stop(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    needs_midi = any(m.get('outputMode') in ('midi', 'both') for m in profile['routes'])
    if needs_midi and not args.midi_out:
        ap.error('this profile requires --midi-out')
    with ExitStack() as stack:
        stream = stack.enter_context(open(args.device, 'rb', buffering=0))
        midi_out = stack.enter_context(open(args.midi_out, 'wb', buffering=0)) if needs_midi else None
        sock = stack.enter_context(socket.socket(*dest[:3]))
        sock.connect(dest[4])
        def send(s, n, v):
            for m in profile['routes']:
                if (m.get('outputMode') in ('midi','both') and m['channel'] == (s & 15)+1
                    and m['number'] == n and (m['kind'] == 'note') == (s >> 4 in (8,9))):
                    midi_out.write(bytes([(s & 0xf0) | (m.get('midiChannel',m['channel'])-1),m.get('midiNumber',n),v]))
            for packet in packets(profile, s, n, v):
                sock.send(packet)
        try:
            for s, n, v in events(stream):
                key = (s & 15, n)
                if s >> 4 == 9 and v:
                    held.add(key)
                elif s >> 4 in (8, 9):
                    held.discard(key)
                send(s, n, v)
        except KeyboardInterrupt:
            pass
        finally:
            for channel, note in held:
                send(128 + channel, note, 0)


if __name__ == '__main__':
    main()

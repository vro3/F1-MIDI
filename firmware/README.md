# F1 firmware

The public artifact is an IPS patch against the original Kontrol F1 v11 upgrade payload. The included Python tool reconstructs the exact two-way USB-MIDI/RGB image that ran on hardware. Supply your own stock payload or the Mac Device Updater executable that contains it. The tool checks both hashes and creates a new file on disk.

```sh
python3 firmware/build_image.py "/path/to/DeviceUpdater.app/Contents/MacOS/DeviceUpdater" F1-midi-rgb.bin
```

| Image | SHA-256 |
| --- | --- |
| Stock v11, 48,640 bytes | `210017e6d1879533612be6b2e950a8a106e8eee1fb3045f48c07cf8190358953` |
| Two-way MIDI and RGB, 48,640 bytes | `dea141e2c0dd1f1075b3c9bb856ed06fbc169b233cc5d55eedd180cc8e615420` |

## How the project got here

1. Extract the single-tile stock payload. Repack it offline with XMOS xTIMEcomposer 14.4.1 and compare all bytes against the original. A DFU read from an early test unit independently matched the v11 payload. This covers the upgrade image only.
2. Preserve runtime DFU while exposing USB Audio Class MIDI Streaming. Start with pad note-on/off, then translate switch transitions, knobs, faders and the relative encoder. Verify on Mac and directly on iPad.
3. Drive the grid through the stock LED wiring. Early builds lit unrelated pads when controls moved. A regression reproduced a MIDI stack overlapping LED state. Moving the stack eliminated the observed corruption.
4. Add USB MIDI OUT, a color parser and a reply on MIDI IN. Write 16 distinct RGB triples and independently read each back. Physically check hold/release brightness. The release artifact is this stage.

## Wire format and controls

The firmware uses MIDI channel 1. Pads send notes 36–51 in row order. Shift, Reverse, Type, Size, Browse and encoder push use 52–57. The Stop buttons use 60–63 and Sync, Quant and Capture use 64–66. Knobs use CC 16–19, faders CC 20–23 and encoder turns CC 24 with relative values 1 and 127.

Color messages use hexadecimal bytes below. The tag is a caller-chosen 7-bit value echoed in the reply. The pad index is 0–15, top-left first. Each color component is 0–127.

```
Read    F0 7D 46 31 01 tag 01 pad F7
Write   F0 7D 46 31 01 tag 02 pad red green blue F7
Reply   F0 7D 46 31 01 tag 03 pad red green blue F7
```

## Installation and recovery status

Installing an upgrade replaces the controller’s active upgrade image. A later unit running two-way RGB entered DFU and answered GETSTATE, then timed out before returning the first 64-byte DFU_UPLOAD block on both macOS and Linux. Reconnecting power restored normal MIDI. The faulting instruction and a reliable rollback procedure for that state remain unknown. A saved build with the same behavior cannot verify the contents of a particular unit. This release supplies an offline image builder. A general-purpose installer would need independently demonstrated backup and recovery.

## Reproduce the offline checks

Use Python 3 and a Capstone Python package with the XCore backend. From the repository root, run:

```sh
python3 firmware/verify_runtime.py F1-midi-rgb.bin
cc F1Remote/DeviceProtocol/{PadColor,ColorCheck}.c -o /tmp/f1-color-check
/tmp/f1-color-check
```

The first test executes the linked worker instructions with modeled USB/LED boundary calls. It covers split messages, 512-byte transfers, pad colors, note transitions, auxiliary buttons, analog controls and encoder direction. The second exercises the portable color protocol. Neither test exercises the physical flash or the host USB stack.

The src folder contains the input worker, USB descriptor call arguments, RGB worker logic, and the linked-layout assembly source used during development. The IPS builder reproduces the released image. These assembly files document extension points; rebuilding an arbitrary edited image also requires relocating code against the stock tile and repacking the XMOS container. Verify stack budgets and runtime DFU behavior before hardware trials.

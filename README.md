# Kontrol F1 MIDI

Use a Traktor Kontrol F1 as a USB MIDI controller on an iPad, edit its mappings on the host, or send its controls over a local network. This independent project includes two native apps, an experimental firmware patch, and a Bitfocus Companion starter configuration.

| Choose | When you want to |
| --- | --- |
| **F1 Remote** | Map a physical control to an outgoing MIDI note, CC or OSC address. Edit the 16 RGB pads and save palettes. |
| **F1 Studio** | Play the F1 or its on-screen controls and send notes and CCs to a network MIDI instrument. Edit control labels and assignments in the Edit workspace. The receiver supplies the sound. |
| **Pi router** | Route the F1 to OSC or a separate ALSA MIDI output using an exported Remote preset on Linux. |

## Run the editors

Open either Xcode project in its original folder. Keep the two source folders next to each other because Remote uses Studio’s pad-color implementation. Choose **My Mac** or your connected **iPad**, then Run. For iPad, select your development team in Signing & Capabilities and use a bundle identifier available to your team if required. Deployment targets are macOS 14 and iPadOS 17 or later.

For a prepared F1, plug one controller into the host before opening the app. The two apps can be built and explored without installing firmware. USB input requires a Core MIDI source. Color editing also requires the F1 MIDI destination and the two-way color protocol.

**MIDI and OSC editing.** In Remote, select a control or enable selection by touching the F1. Set the incoming message to match the device. Choose MIDI, OSC or Both and configure the outgoing destination. Start routing. For local MIDI, choose **F1 Remote Output** in the receiving app. Host mappings operate while Remote is running. Export the JSON preset to use it on another host. For OSC on iPad, enter the receiving computer’s LAN address. The default localhost address reaches only the same host.

**Pad lights.** Select a grid pad and set its RGB color. Remote reads the pad back after a write. A palette can cover a row, column or the grid. For incoming OSC feedback, enable the listener and set a pad’s address. Send one UDP OSC message with that address and three integers from 0 to 127. The simple Linux router handles outgoing routes only.

**RTP-MIDI.** In Studio’s Perform workspace choose **Open RTP-MIDI session**. On the same LAN, join F1 Studio from the receiving host’s network MIDI session, or choose **Connect to…** in Studio to discover an advertised peer. Allow local network access on iPad. Studio automatically selects an available IPv4 UDP pair, starting with 5004/5005. Bonjour advertises the actual control port. Select the joined session as MIDI input in the receiving instrument. The implementation has one automatic transport configuration.

**Companion and Pi.** The [starter configuration](F1Remote/Companion/F1%20Remote.companionconfig) targets Companion 5. Import page 1 and the custom variables into a rehearsal configuration. Enable the Companion OSC listener and match the host and port in Remote. The 16 pads occupy the top-left 4×4 block. Knobs and faders update variables. Assign your show actions to the starter buttons. On Linux, identify the raw MIDI port with `amidi -l` and run the following from F1Remote. Substitute your device and receiver.

```sh
python3 Pi/f1_remote.py /dev/snd/midiC1D0 --host 127.0.0.1
```

Use `--preset` to load an exported profile and `--midi-out` for routes with a MIDI destination.

## Firmware and project history

The [firmware guide](firmware/README.md) explains how to reconstruct the exact two-way RGB image from the original updater, how the controller was tested, and why firmware installation and rollback are still experimental. A stock F1 requires separate hardware preparation for direct class-compliant iPad use.

## Limits and fork ideas

- Host presets persist on the Mac or iPad. The firmware uses fixed control assignments and returns to its default pad colors after a power cycle. Persistent device presets are an open project.
- The installed build supports grid RGB. The two-digit display, Sync/Quant/Capture illumination, bottom Stop lights and device-side assignment commands remain experimental and are omitted from these editors. A fork could start with a display or LED fixture that verifies physical order and brightness independently.
- Use one F1 per editor host. Serial-specific selection and reconnect handling for multiple identical controllers would make a valuable contribution.
- The custom network host supports foreground IPv4 AppleMIDI on a trusted LAN. Test reconnects, network changes, packet loss, latency and background behavior on your own equipment. A successful UDP send does not establish that a remote show action executed.
- A physical Mac and iPad received notes and CCs during development. Physical pad-color writes and independent readbacks succeeded. The release apps compile for both platforms. On-device testing of the cleaned iPad apps, incoming OSC-to-pad feedback in a show, and physical Raspberry Pi operation remain open.
- For a firmware contribution, report the starting image hash, USB speed, exact request, observed response and whether the result came from a simulator or physical hardware. Avoid posting unit serials or private network details.

The Z2 work by AdT-Andreas Erkel provided a useful starting point for the XMOS investigation. This repository concerns the F1. [Z2-ReConnect](https://github.com/AdTurntables/Z2-ReConnect)

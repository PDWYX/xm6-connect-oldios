# XM6 Control (Legacy iOS)

[中文](README.md) | [English](README_EN.md)

A tiny iOS app that controls noise cancelling modes and ambient sound level on the Sony WH-1000XM6 from **older iOS versions**. The official Sound Connect app requires iOS 17.0, leaving older devices behind; this project talks to the headset through Sony's own ExternalAccessory control channel instead, so it neither depends on the official app nor on new system features.

> Unofficial project, not affiliated with or endorsed by Sony. Protocol details were derived from Bluetooth captures of the official app. Use at your own risk.

## Features

- Three modes: Noise Cancelling / Ambient Sound / Off
- Ambient sound level 1–20 (live preview while dragging, committed on release)
- Reads the current mode and level from the headset on launch
- Reconnects automatically after disconnection or returning from background
- Optional local TX/RX log (export / clear in one tap)
- No network access, no third-party dependencies, no telemetry

## Requirements

| Item | Requirement |
|---|---|
| iOS | 11.0 or later, 64-bit device |
| Bluetooth | Classic Bluetooth (iAP2 / RFCOMM), headset already paired |
| Installation | Jailbroken device + AppSync, or re-sign with your own certificate |

Only tested on a single iPhone XR running iOS 13.6. No older hardware was available for testing, so the actual minimum supported iOS version is unknown — the deployment target is iOS 11.0, but whether older systems accept this ExternalAccessory protocol remains unverified.

## How it works

The official app uses iAP2 over Classic Bluetooth. iOS's ExternalAccessory framework strips the iAP2 layer for the app, so what the app sees is a raw Sony MDR v2 frame:

```
3E | type(1) | seq(1) | len(4, big-endian) | payload | checksum(1) | 3C
```

- `checksum` = sum of bytes from `type` through the end of `payload`
- `seq` alternates 0/1; an ACK frame uses the inverse of the acknowledged frame's seq
- Ambient sound payload: `68 19 01 01 01 00 NN 00 00` (NN = 01–14)
- Noise cancelling: `68 19 01 01 00 00 NN 00 00`
- Off: `68 19 01 00 00 00 NN 00 00`
- Query state: `66 19`, headset replies `67 19 01 xx xx 00 NN 00 00`

No Sony proprietary code or keys are used.

## Building

Requires `xcodegen` and Xcode:

```bash
xcodegen generate
xcodebuild -project XM6Control.xcodeproj -scheme XM6Control \
  -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO
```

Pushing to `main` triggers GitHub Actions, which builds an unsigned ipa and uploads it as an artifact.

## Disclaimer

Personal research project, not affiliated with Sony Corporation. "SONY" and "WH-1000XM6" are trademarks of their respective owners and are used here only to describe compatibility.

- Provided "as is", with no warranty of availability, stability, or fitness for any device
- Communicates over an unofficial channel; firmware updates may break it
- Installing third-party signed apps on a jailbroken device carries stability risks
- You are solely responsible for any consequences of using this software

## AI Disclosure

Code, protocol reverse-engineering assistance, and documentation for this project were produced with help from the AI model DeepSeek-V4.1-Flash-1017. All protocol conclusions were verified against real devices and packet captures.

## License

[MIT License](LICENSE) © 2026 PDWYX

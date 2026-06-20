# SIROS Verifier App

A native proximity verifier application built with Flutter, implementing the
ISO 18013-5 mDL device engagement and data retrieval flow over BLE.

## Overview

The SIROS Verifier scans a QR code presented by a wallet holder to initiate an
mDL proximity presentation. It establishes a BLE connection with the wallet
device, performs the ISO 18013-5 session establishment, and retrieves the
requested credential data.

### Key Features

- **QR Code scanning** — reads the `mdoc` device engagement structure
- **BLE central role** — discovers and connects to the wallet peripheral
- **ISO 18013-5 session** — HKDF key derivation, CBOR session transcript
- **mDL data retrieval** — requests and displays driving licence attributes

## Prerequisites

- Flutter SDK ≥ 3.12
- Android SDK (API 36 / compileSdk 36)
- JDK 17

## Getting Started

```bash
flutter pub get
flutter run
```

## Testing

```bash
flutter test
flutter test --coverage
```

## Building

```bash
# Debug APK
flutter build apk --debug

# Release APK (requires signing config)
flutter build apk --release
```

## License

BSD 2-Clause — see [LICENSE](LICENSE).

# SIROS Verifier App

[![CI](https://github.com/sirosfoundation/siros-verifier-app/actions/workflows/ci.yml/badge.svg)](https://github.com/sirosfoundation/siros-verifier-app/actions/workflows/ci.yml)
[![SonarCloud](https://sonarcloud.io/api/project_badges/measure?project=sirosfoundation_siros-verifier-app&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=sirosfoundation_siros-verifier-app)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/sirosfoundation/siros-verifier-app/badge)](https://scorecard.dev/viewer/?uri=github.com/sirosfoundation/siros-verifier-app)
[![License](https://img.shields.io/badge/License-BSD_2--Clause-blue.svg)](LICENSE)

A native proximity verifier for **ISO 18013-5 mobile driving licences (mDL)**,
built with Flutter. Scans a QR code from the holder's wallet, establishes a
BLE session, and retrieves credential attributes — entirely offline.

## How it works

```
Holder wallet                        SIROS Verifier
─────────────                        ──────────────
Display QR (mdoc:…)  ──────────────▶  Scan & parse device engagement
                     ◀── BLE ───────  Advertise UUID, connect
                     ◀──────────────  Send SessionEstablishment (ECDH + AES-GCM)
Return DeviceResponse ─────────────▶  Decrypt & display credential
```

1. **QR scan** — decodes the `mdoc:` URI into a CBOR device engagement structure
2. **Key agreement** — generates an ephemeral P-256 key pair, performs ECDH with the holder's `eDeviceKey`
3. **Session keys** — derives `SKReader` and `SKDevice` via HKDF-SHA256
4. **BLE transport** — advertises the service UUID from the engagement, connects as central
5. **Credential request** — encrypts a `DeviceRequest` with AES-128-GCM and sends it
6. **Display** — decrypts the `DeviceResponse` and shows the mDL attributes

## Architecture

```
lib/
├── main.dart       # UI: SplashScreen → HomeScreen → ScanScreen → ConnectScreen → ResultScreen
├── crypto.dart     # Crypto primitives: ECDH, HKDF, AES-GCM, COSE_Key, CBOR encoding
└── protocol.dart   # ISO 18013-5 protocol: DeviceRequest, SessionEstablishment, parsing

android/app/src/main/kotlin/com/example/siros/
├── MainActivity.kt     # Flutter platform channel bridge for BLE
└── BleScanService.kt   # Foreground BLE scan service
```

## Prerequisites

- Flutter SDK ≥ 3.12
- Android SDK (API 36 / compileSdk 36)
- JDK 17

## Quick start

```bash
flutter pub get
flutter run
```

## Testing

```bash
flutter test                  # unit + widget tests
flutter test --coverage       # with lcov coverage report
```

## Building

```bash
flutter build apk --debug    # debug APK
flutter build apk --release  # release APK (requires signing config)
```

## License

BSD 2-Clause — see [LICENSE](LICENSE).

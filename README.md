# AERION – AeroSense
### Intelligent IoT Environmental & Air Quality Monitoring System

[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Tests Passing](https://img.shields.io/badge/Tests-33%2F33%20Passing-brightgreen?logo=checkmarx)](https://flutter.dev)
[![Code Quality](https://img.shields.io/badge/Analysis-0%20Issues-brightgreen)](https://dart.dev/tools/analysis)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 1. Track Chosen

**Track:** **IoT Environmental Monitoring / Hardware BLE & Cloud Telemetry System**

AERION AeroSense is a production-grade, end-to-end IoT environmental monitoring solution. It pairs an **ESP32 microcontroller** reading multi-sensor payloads (temperature, humidity, air quality/gas concentration, and 6-axis spatial orientation) with a responsive, modern **Flutter cross-platform application** over **Bluetooth Low Energy (BLE)**, local **Wi-Fi HTTP REST**, and cloud synchronization via **Firebase Realtime Database**.

---

## 2. Hardware & Sensor Setup

### Microcontroller Specification
- **Target MCU:** ESP32 Dev Module (ESP32-WROOM-32)
- **Architecture:** Xtensa® 32-bit LX6 Dual-Core @ 240 MHz
- **Wireless Interfaces:** 2.4 GHz Wi-Fi 802.11 b/g/n & Bluetooth v4.2 BR/EDR + BLE

### Sensor Bill of Materials (BOM)
1. **DHT22 / AM2302:** High-precision digital temperature and relative humidity sensor.
2. **MQ-135:** Air quality and hazardous gas sensor (detects $CO_2$, $NH_3$, $NO_x$, alcohol, benzene, smoke).
3. **MPU-6050:** 6-DoF I2C accelerometer and gyroscope (tracks device orientation, tilt, and tamper alerts).

### Wiring & Pinout Table

| Sensor | Sensor Pin | ESP32 GPIO | Description / Notes |
|---|---|---|---|
| **DHT22** | VCC | 3.3V / 5.0V | Regulated power rail |
| **DHT22** | GND | GND | Common ground |
| **DHT22** | DATA | **GPIO 4** | Bidirectional digital 1-wire line (10kΩ pull-up to 3.3V) |
| **MQ-135** | VCC | **5.0V (VIN)** | **MANDATORY**: Heater coil requires 5.0V for correct operation |
| **MQ-135** | GND | GND | Common ground |
| **MQ-135** | DOUT | *Unconnected* | Digital comparator threshold unused |
| **MQ-135** | AOUT | **GPIO 34** (ADC1_CH6) | Voltage divider (10kΩ / 20kΩ) steps 0–5V down to safe 0–3.3V |
| **MPU-6050** | VCC | 3.3V | 3.3V power rail |
| **MPU-6050** | GND | GND | Common ground |
| **MPU-6050** | SDA | **GPIO 21** | ESP32 Hardware I2C Data |
| **MPU-6050** | SCL | **GPIO 22** | ESP32 Hardware I2C Clock |
| **MPU-6050** | AD0 | GND | Sets I2C peripheral address to `0x68` |

> [!NOTE]
> GPIO 34 belongs to **ADC1**. Because ADC1 does not share hardware resources with the ESP32 Wi-Fi radio (unlike ADC2), analog air quality sampling remains continuous and jitter-free even during active Wi-Fi data transmissions.

---

## 3. BLE GATT Specification

The ESP32 acts as a GATT Server advertising the local name prefix `AQM-` (e.g., `AQM-Atchaya`).

**Primary Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

### Characteristics Table

| Characteristic | UUID | Properties | Format / Data Type | Description |
|---|---|---|---|---|
| **Temperature** | `beb5483e-36e1-4688-b7f5-ea07361b26a8` | Read, Notify | IEEE 754 float / String (`"28.4"`) | Real-time ambient temperature in °C |
| **Humidity** | `cba1d466-344c-4be3-ab3f-189f80dd7518` | Read, Notify | IEEE 754 float / String (`"62.1"`) | Relative humidity percentage (0–100%) |
| **Air Quality** | `f0de3a41-2b5e-4c6f-9d7a-1e8b3c4d5e6f` | Read, Notify | 12-bit uint16 / String (`"412"`) | Raw ADC value from MQ-135 (0–4095) |
| **Sampling Interval** | `d8e3b210-9b48-4b92-9654-e75b2b2a60a4` | Read, Write | uint16 (milliseconds, 1000–60000) | Bidirectional sensor poll rate configuration |
| **Alert Flag** | `e7f2a1b0-4a3d-4c5e-8f6b-9c1d2e3f4a5b` | Read, Write, Notify | uint8 bitmask (`0x00`=Normal, `0x01`=Warn, `0x02`=Crit) | Active hazard state and remote reset acknowledgement |
| **Motion / Orientation** | `a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d` | Read, Notify | JSON String `{"ax":..,"ay":..,"az":..}` | MPU-6050 6-DoF accelerometer & gyroscope vectors |

---

## 4. Mobile Application Architecture

The Flutter mobile application is engineered with a clean, decoupled architecture:

```
lib/
├── ble/                    # Bluetooth Low Energy manager, GATT scanner & serializers
│   ├── ble_constants.dart
│   └── ble_manager.dart
├── constants/              # Application theme, typography, color palettes
│   ├── app_colors.dart
│   └── app_theme.dart
├── models/                 # Immutable telemetry & incident models
│   ├── incident_record.dart
│   ├── sensor_data.dart
│   └── threshold_settings.dart
├── providers/              # Reactive state management
│   ├── app_state.dart
│   ├── connectivity_manager.dart
│   └── threshold_provider.dart
├── screens/                # User interface presentation layer
│   ├── alerts_screen.dart
│   ├── analytics_screen.dart
│   ├── audit_report_screen.dart
│   ├── ble_devices_screen.dart
│   ├── dashboard_screen.dart
│   ├── home_shell.dart
│   ├── settings_screen.dart
│   ├── splash_screen.dart
│   └── wifi_screen.dart
├── services/               # Cloud Firebase Realtime Database connector
│   └── firebase_service.dart
└── main.dart               # App entrypoint and global dependency injection
```

### Key UI/UX Enhancements
- **Strict 6-Tab Navigation:**
  `1. Dashboard` → `2. BLE Devices` → `3. Wi-Fi` → `4. Analytics` → `5. Alerts` → `6. Settings`
- **Centralized Google Sans Typography:** Consistent hierarchy (`AppTextStyles`) across all light and dark themes.
- **Animated Splash Screen:** Engaging startup screen featuring sensor calibration progress indicators and fade transition.
- **Live Interactive Charts:** Powered by `fl_chart` with multi-tier time ranges (1 Hour, 6 Hours, 24 Hours) and tooltip value inspection.
- **Wi-Fi Direct Connect:** Quick manual IP input field (`192.168.4.1` preset) with status pill and auto-reconnect triggers.
- **Configurable Telemetry Intervals:** Quick preset chips (`1s Fast`, `2s Normal`, `5s Eco`, `10s Battery`) plus custom 1–60 second manual input with hardware write-back.
- **Incident Audit Logging & Red Warning Styling:** High-visibility critical red badges (`#E53935`) for temperature spikes (>30°C warning, >35°C critical).
- **CSV Data Export:** Comprehensive export of telemetry readings and incident logs saved to device storage and system share sheet.
- **Manual & Pull-to-Refresh:** Dedicated refresh button on the AppBar and pull-to-refresh on telemetry pages.

---

## 5. Build and Run Instructions

### Prerequisites
- **Flutter SDK:** `^3.19.0` or higher ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Dart SDK:** `^3.3.0`
- **Java Development Kit (JDK):** Version 17
- **Android SDK:** API Level 34 (Android 14) platform and build-tools
- **Physical Device:** Android device with Bluetooth 4.2+ and Location enabled

### Step-by-Step Setup

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/atchayaravi724/AQM-Achuu.git
   cd AQM-Achuu
   ```

2. **Fetch Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run Code Verification & Tests:**
   ```bash
   # Analyze for errors and lints
   dart analyze lib test

   # Run all 33 automated unit and widget tests
   flutter test test/widget_test.dart
   ```

4. **Launch the Application in Debug Mode:**
   ```bash
   flutter run
   ```

5. **Build Release APK:**
   ```bash
   flutter build apk --release
   ```
   The compiled APK will be output to:
   `build/app/outputs/flutter-apk/app-release.apk`

---

## 6. Testing Methodology

The application underwent rigorous verification covering business logic, state management, UI rendering, and hardware integration:

### 1. Automated Widget & Unit Testing
- **Test Suite:** `test/widget_test.dart`
- **Total Test Cases:** 33 automated tests
- **Result:** **33 Passed (100% Success Rate)**
- **Coverage Areas:**
  - `SensorData` JSON serialization, deserialization, and boundary condition handling.
  - `AppState` multi-source telemetry processing (BLE stream + Firebase synchronization).
  - Incident threshold evaluation: temperature hazard flags, humidity anomalies, and gas spikes.
  - `ThresholdProvider` status color mapping (Normal green, Warning amber, Critical red).
  - UI component tests: Navigation bar 6-tab order, animated splash screen calibration state, Wi-Fi screen IP input form, settings sampling rate presets, and CSV export generation.

### 2. Static Code Analysis
- Clean static analysis with `dart analyze lib test`:
  `No issues found! (0 errors, 0 warnings, 0 hints)`

### 3. Hardware Integration Testing
- Verified live BLE advertising, GATT service discovery, and notification streaming on ESP32 hardware with `AQM-` prefix.
- Validated Firebase Realtime Database bidirectional sync at `/aerosense`.

---

## 7. Known Limitations

1. **Android 12+ Bluetooth Permissions:**
   Android 12 (API level 31) and higher mandate runtime user authorization for `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`. Location services must also be toggled on to perform BLE peripheral discovery.
2. **MQ-135 Sensor Burn-in / Pre-heating Period:**
   The MQ-135 tin dioxide ($SnO_2$) semiconductor heating element requires 24–48 hours of pre-heating for calibrated absolute PPM measurement. AERION AeroSense intentionally displays raw 12-bit ADC values (0–4095) with clear labels to maintain diagnostic honesty prior to calibration.
3. **Wi-Fi SoftAP Mode Isolation:**
   When connecting directly to the ESP32 in local Access Point mode (`192.168.4.1`), mobile OS auto-switch features ("Switch to Mobile Data") may temporarily redirect network requests unless local Wi-Fi stay-connected is confirmed.
4. **iOS BLE Background Throttling:**
   On iOS devices, background BLE scan intervals are throttled by iOS CoreBluetooth power management when the app is minimized.

---

## 8. License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

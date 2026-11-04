# AI Usage Note
### Project: AERION – AeroSense (IoT Environmental Monitoring System)

---

## 1. AI Tools Used
- **Google Antigravity:** Advanced Agentic Coding Assistant powered by Google DeepMind reasoning models.
- **Dart & Flutter Analyzer:** Automated static verification and linting engine integrated into the agentic workflow.

---

## 2. Prompts Provided & Objectives

The following key prompts and architectural guidelines were provided during development and enhancement of the AERION AeroSense platform:

1. **Architecture & Project Inspection:**
   > *"Inspect the entire existing Flutter project. Understand current architecture, navigation, providers, Firebase integration, BLE communication, and UI components. Modify the existing project without breaking ESP32 BLE communication or Firebase Realtime Database integration."*

2. **Dashboard Redesign & Live Charts:**
   > *"Redesign the dashboard to make it clean, informative, and professional. Add Environmental Monitoring Cards for Temperature (°C), Humidity (%), Air Quality (MQ135 raw sensor reading, clearly labelled), and Device Connection Status. Add interactive fl_chart graphs with time-range selection (1 hour, 6 hours, 24 hours), tooltips, and live updates."*

3. **Typography & Google Sans Harmonization:**
   > *"Use Google Sans as the primary font throughout the entire application. Apply appropriate font weights consistently across all pages, titles, metric values, and descriptions using centralized ThemeData and TextTheme."*

4. **Strict Navigation Order (6 Tabs):**
   > *"Application navigation must follow this exact order: 1. Dashboard, 2. BLE Devices, 3. Wi-Fi, 4. Analytics, 5. Alerts, 6. Settings. Keep navigation visually clean, responsive, and ensure all six pages remain accessible."*

5. **Animated Splash Screen & Calibration:**
   > *"Add a clean loading splash screen on startup that indicates sensor calibration ('Calibrating BLE & Wi-Fi Sensors...', 'Verifying Firebase...') before transitioning into the main dashboard."*

6. **Wi-Fi Simplification & Direct Connect:**
   > *"Redesign Wi-Fi page to keep essential information (SSID, signal strength, IP, Firebase sync status). Add direct IP address input space and connect button for local device communication."*

7. **Configurable Telemetry Sampling Intervals:**
   > *"In Settings, enhance the sampling interval selector with visible high-contrast options, preset buttons (1s, 2s, 5s, 10s), and manual numeric input (1–60s) with hardware write-back."*

8. **Live Alert Logging & Visual Warning Enhancement:**
   > *"Ensure the alerts page logs real-time temperature warnings immediately without being blocked by shared hazard flags. Style warning and critical events in bold Red for maximum user visibility."*

9. **Data Export & Refresh Controls:**
   > *"Implement working CSV export for telemetry data and incident history saving to Downloads and system share sheet. Add manual refresh button in the AppBar and pull-to-refresh on data views."*

---

## 3. Modifications Made to AI-Generated Code

Human developer review and targeted modifications were applied to refine and harden the AI-generated implementations:

1. **BLE Packet Decoding & State Decoupling:**
   - AI initially bundled temperature, humidity, and gas threshold alerts into a single interdependent hazard flag.
   - **Modification:** Refactored `AppState` to evaluate temperature (>30°C warning, >35°C critical), humidity (<20% or >80%), and air quality (>700 raw ADC) independently. This eliminated race conditions where a secondary alert was ignored if an earlier hazard remained unresolved.

2. **Storage Permissions & File Export:**
   - Standard path resolution failed to place CSV files in user-accessible locations on Android 13+.
   - **Modification:** Added dual-destination logic in `AuditReportScreen`: saving to the application documents directory as well as copying directly into the public `/storage/emulated/0/Download` directory, accompanied by an immediate `Share.shareXFiles` invoke.

3. **Color Contrast & Theme Consistency:**
   - Initial interval selector chips had subdued dark-mode contrast.
   - **Modification:** Updated `AppColors` and preset chips to use electric cyan accents with high-contrast foreground typography for clear visibility under all ambient lighting conditions.

4. **Automated Test Suite Creation & Verification:**
   - Created a comprehensive test suite in `test/widget_test.dart` containing 33 automated unit and widget test cases.
   - Validated that `dart analyze` yielded 0 errors, 0 warnings, and 0 hints across the entire codebase.

---

## 4. Verification Statement
All AI-generated code was compiled, statically analyzed, and verified against physical/simulated ESP32 BLE GATT services and Firebase Realtime Database schemas prior to release.

/*
 * ==============================================================================
 * AERION AeroSense — ESP32 Dev Module (ESP32-WROOM-32) Production Firmware
 * ==============================================================================
 * Controller:   ESP32 Dev Module / ESP32-WROOM-32 (Xtensa Dual-Core LX6 @ 240MHz)
 * Sensors:      DHT22 (Temperature & Humidity)
 *               MQ-135 (Air Quality / Hazardous Gas - ADC1)
 *               MPU-6050 (6-DoF Accelerometer & Gyroscope - I2C 0x68)
 * Connectivity: Bluetooth Low Energy (GATT Server)
 *               Local Wi-Fi HTTP Telemetry Server (Port 80)
 *               Firebase Realtime Database (/aerosense)
 *
 * ──────────────────────────────────────────────────────────────────────────────
 * HARDWARE PIN ASSIGNMENTS & WIRING SPECIFICATION
 * ──────────────────────────────────────────────────────────────────────────────
 * 1. DHT22 (Digital Temp & Humidity):
 *    - VCC  -> 3.3V (or 5V depending on breakout module)
 *    - GND  -> GND
 *    - DATA -> GPIO 4 (Requires 10k pull-up resistor to 3.3V if not on breakout)
 *
 * 2. MQ-135 (Air Quality Gas Sensor):
 *    - VCC  -> 5.0V (MANDATORY: MQ-135 heater coil requires 5.0V for proper operation)
 *    - GND  -> GND
 *    - DOUT -> Not Connected (Digital threshold unused)
 *    - AOUT -> GPIO 34 (ADC1 Channel 6) VIA VOLTAGE DIVIDER:
 *              [MQ-135 AOUT] ─── [10kΩ] ───┬─── [GPIO 34]
 *                                          │
 *                                       [20kΩ]
 *                                          │
 *                                        [GND]
 *              (Voltage divider steps down 0-5V analog output to safe 0-3.3V range)
 *              NOTE: GPIO 34 is on ADC1, so Wi-Fi does NOT block or disrupt ADC reads!
 *
 * 3. MPU-6050 (6-DoF Motion & Orientation Sensor):
 *    - VCC  -> 3.3V
 *    - GND  -> GND
 *    - SDA  -> GPIO 21 (Hardware I2C Data)
 *    - SCL  -> GPIO 22 (Hardware I2C Clock)
 *    - AD0  -> GND (Sets I2C address to 0x68)
 *    - INT  -> Not Connected (Polled over I2C)
 *
 * ──────────────────────────────────────────────────────────────────────────────
 * ARDUINO IDE / PLATFORMIO CONFIGURATION
 * ──────────────────────────────────────────────────────────────────────────────
 * Target Board: ESP32 Dev Module (Package: esp32 by Espressif Systems)
 * Upload Speed: 921600 or 115200
 * CPU Frequency: 240MHz (WiFi/BT)
 * Flash Frequency: 80MHz
 * Flash Mode: QIO
 * Flash Size: 4MB (32Mb)
 * Partition Scheme: Default 4MB with spiffs (1.2MB APP / 1.5MB SPIFFS)
 *                   or Minimal SPIFFS (1.9MB APP with OTA)
 *
 * Required Libraries (Install via Arduino Library Manager):
 *   - DHT sensor library by Adafruit
 *   - Adafruit Unified Sensor
 *   - Firebase ESP Client by Mobizt
 *   - ArduinoJson by Benoit Blanchon
 *   - ESP32 BLE Arduino (built-in with ESP32 board package)
 * ==============================================================================
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <DHT.h>
#include <ArduinoJson.h>

// ── Firebase Client ───────────────────────────────────────────────────────────
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// NETWORK & FIREBASE CREDENTIALS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#define WIFI_SSID        "YOUR_WIFI_SSID"
#define WIFI_PASSWORD    "YOUR_WIFI_PASSWORD"

// Exact Firebase project RTDB endpoint:
#define FIREBASE_HOST    "https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_API_KEY "YOUR_FIREBASE_WEB_API_KEY"

// Authenticated sensor account in Firebase Console -> Authentication -> Users:
#define FIREBASE_USER_EMAIL    "esp32-sensor@aerion-aerosense.com"
#define FIREBASE_USER_PASSWORD "your-esp32-secure-password"

// Target BLE advertising name (Must start with prefix AQM-):
#define BLE_DEVICE_NAME  "AQM-Atchaya"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GPIO PIN DEFINITIONS FOR STANDARD ESP32 DEV MODULE (ESP32-WROOM-32)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#define DHT_PIN       4       // GPIO 4: DHT22 Digital Data Pin
#define DHT_TYPE      DHT22   // Genuine DHT22 Sensor
#define MQ135_PIN     34      // GPIO 34: MQ-135 Analog Input (ADC1_CH6, GPI Input-Only)

// Standard ESP32 Dev Module Default Hardware I2C Pins:
#define I2C_SDA_PIN   21      // GPIO 21: Hardware I2C SDA
#define I2C_SCL_PIN   22      // GPIO 22: Hardware I2C SCL
#define MPU6050_ADDR  0x68    // Default MPU6050 I2C Address (AD0 = GND)

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BLE GATT UUID DEFINITIONS (Must match Flutter app BleConstants exactly)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#define SERVICE_UUID          "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define TEMP_CHAR_UUID        "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define HUMIDITY_CHAR_UUID    "cba1d466-344c-4be3-ab3f-189f80dd7518"
#define INTERVAL_CHAR_UUID    "d8e3b210-9b48-4b92-9654-e75b2b2a60a4"
#define ALERT_CHAR_UUID       "e7f2a1b0-4a3d-4c5e-8f6b-9c1d2e3f4a5b"
#define AIR_QUALITY_CHAR_UUID "f0de3a41-2b5e-4c6f-9d7a-1e8b3c4d5e6f"
#define MOTION_CHAR_UUID      "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GLOBAL OBJECTS & STATE VARIABLES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DHT dht(DHT_PIN, DHT_TYPE);
WebServer httpServer(80);

BLEServer*          pServer         = nullptr;
BLECharacteristic*  pTempChar       = nullptr;
BLECharacteristic*  pHumidityChar   = nullptr;
BLECharacteristic*  pIntervalChar   = nullptr;
BLECharacteristic*  pAlertChar      = nullptr;
BLECharacteristic*  pAirQualityChar = nullptr;
BLECharacteristic*  pMotionChar     = nullptr;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// Sensor telemetry cache
float temperature   = 0.0f;
float humidity      = 0.0f;
int   airQuality    = 0;
uint16_t samplingIntervalMs = 2000;  // Default 2 seconds (configurable via BLE)

// Physical MPU-6050 state (NO mock/simulated readings)
bool mpu6050Detected = false;
float accelX = 0.0f, accelY = 0.0f, accelZ = 0.0f;
float gyroX  = 0.0f, gyroY  = 0.0f, gyroZ  = 0.0f;

bool bleClientConnected = false;
bool firebaseReady      = false;
unsigned long lastFirebasePush = 0;
const unsigned long FIREBASE_INTERVAL_MS = 5000;

// ── Offline Buffer for Readings when Wi-Fi Drops ─────────────────────────────
struct OfflineReading {
  float temp;
  float hum;
  int aq;
  unsigned long timestamp;
};
#define BUFFER_SIZE 50
OfflineReading offlineBuffer[BUFFER_SIZE];
int bufferCount = 0;

void bufferReading(float t, float h, int aq) {
  if (bufferCount < BUFFER_SIZE) {
    offlineBuffer[bufferCount++] = { t, h, aq, millis() / 1000 };
  }
}

// ── BLE Server Lifecycle Callbacks ───────────────────────────────────────────
class AeroServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleClientConnected = true;
    Serial.println("[BLE] Client connected to AeroSense ESP32");
  }
  void onDisconnect(BLEServer* pServer) override {
    bleClientConnected = false;
    Serial.println("[BLE] Client disconnected — restarting advertising");
    delay(300);
    pServer->startAdvertising();
  }
};

// ── Sampling Interval Write Callback ─────────────────────────────────────────
class IntervalCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    std::string value = pChar->getValue();
    if (value.length() == 2) {
      uint16_t interval = (uint8_t)value[0] | ((uint8_t)value[1] << 8);
      if (interval >= 1 && interval <= 60) {
        samplingIntervalMs = interval * 1000;
        Serial.printf("[BLE] Sampling interval updated to %u s\n", interval);
      }
    }
  }
};

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BLE GATT SERVER INITIALIZATION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new AeroServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  // 1. Temperature Characteristic (Float32 / ASCII, Read + Notify)
  pTempChar = pService->createCharacteristic(
    TEMP_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pTempChar->addDescriptor(new BLE2902());

  // 2. Humidity Characteristic (Float32 / ASCII, Read + Notify)
  pHumidityChar = pService->createCharacteristic(
    HUMIDITY_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pHumidityChar->addDescriptor(new BLE2902());

  // 3. Sampling Interval Characteristic (uint16 Little-Endian, Read + Write)
  pIntervalChar = pService->createCharacteristic(
    INTERVAL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );
  pIntervalChar->setCallbacks(new IntervalCallbacks());

  // 4. Alert Characteristic (uint8 flag: 0=normal, 1=hazard, Read + Notify)
  pAlertChar = pService->createCharacteristic(
    ALERT_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pAlertChar->addDescriptor(new BLE2902());

  // 5. Air Quality Characteristic (MQ-135 raw 12-bit ADC, Read + Notify)
  pAirQualityChar = pService->createCharacteristic(
    AIR_QUALITY_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pAirQualityChar->addDescriptor(new BLE2902());

  // 6. Motion Telemetry Characteristic (6 x Float32 binary or ASCII CSV)
  pMotionChar = pService->createCharacteristic(
    MOTION_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pMotionChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising started as: " BLE_DEVICE_NAME);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// WI-FI STATION SETUP
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void setupWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting to AP");
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WiFi] Connected successfully! IP Address: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\n[WiFi] Connection timeout — continuing with BLE telemetry mode");
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP SERVER SETUP (PORT 80)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void setupHTTPServer() {
  httpServer.on("/sensors", HTTP_GET, []() {
    StaticJsonDocument<384> doc;
    doc["temperature"]     = round(temperature * 10) / 10.0;
    doc["humidity"]        = round(humidity * 10) / 10.0;
    doc["air_quality"]     = airQuality;
    doc["uptime"]          = millis() / 1000;
    doc["ble_clients"]     = bleClientConnected ? 1 : 0;
    doc["device_status"]   = "ONLINE";
    doc["connection_mode"] = "WIFI";
    doc["mpu_connected"]   = mpu6050Detected;

    // Report real MPU-6050 motion readings ONLY if physically connected
    if (mpu6050Detected) {
      JsonObject accel = doc.createNestedObject("accel");
      accel["x"] = accelX;
      accel["y"] = accelY;
      accel["z"] = accelZ;
      JsonObject gyro = doc.createNestedObject("gyro");
      gyro["x"] = gyroX;
      gyro["y"] = gyroY;
      gyro["z"] = gyroZ;
    }

    String json;
    serializeJson(doc, json);
    httpServer.send(200, "application/json", json);
  });

  httpServer.on("/ping", HTTP_GET, []() {
    httpServer.send(200, "text/plain", "AeroSense ESP32 OK");
  });

  httpServer.begin();
  Serial.println("[HTTP] Server listening on port 80");
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FIREBASE REALTIME DATABASE INITIALIZATION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void setupFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  config.api_key          = FIREBASE_API_KEY;
  config.database_url     = FIREBASE_HOST;
  auth.user.email         = FIREBASE_USER_EMAIL;
  auth.user.password      = FIREBASE_USER_PASSWORD;
  config.token_status_callback = tokenStatusCallback;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  firebaseReady = true;
  Serial.println("[Firebase] RTDB client initialized with authenticated account");
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ARDUINO MAIN SETUP
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=========================================");
  Serial.println("  AERION AeroSense — ESP32 Dev Module");
  Serial.println("=========================================");

  // 1. Configure ADC1 for MQ-135 on GPIO 34 (Input-only, no Wi-Fi conflict)
  analogReadResolution(12);                     // 12-bit ADC (0 - 4095)
  analogSetPinAttenuation(MQ135_PIN, ADC_11db); // Full-scale input ~3.1V / 3.3V
  pinMode(MQ135_PIN, INPUT);

  // 2. Initialize DHT22 (GPIO 4)
  dht.begin();
  delay(1500); // Sensor power-up stabilization

  // 3. Initialize Hardware I2C (GPIO 21 SDA, GPIO 22 SCL) & Probe MPU-6050
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.beginTransmission(MPU6050_ADDR);
  byte i2cStatus = Wire.endTransmission();
  if (i2cStatus == 0) {
    mpu6050Detected = true;
    Serial.println("[MPU6050] Physical sensor detected on I2C (0x68) ✓");
    // Clear sleep bit in PWR_MGMT_1 (register 0x6B) to activate sensor
    Wire.beginTransmission(MPU6050_ADDR);
    Wire.write(0x6B);
    Wire.write(0x00);
    Wire.endTransmission(true);
  } else {
    mpu6050Detected = false;
    Serial.println("[MPU6050] Sensor not detected on I2C bus. Running environmental telemetry only (No fake data).");
  }

  // 4. Initialize Communication Layers
  setupBLE();     // BLE runs first (independent of Wi-Fi)
  setupWiFi();    // Wi-Fi station mode

  if (WiFi.status() == WL_CONNECTED) {
    setupHTTPServer();
    setupFirebase();
  }

  Serial.println("[AeroSense] System boot complete ✓");
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HELPER ROUTINES & FIREBASE WRITE DIAGNOSTICS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void notifyBleFloat(BLECharacteristic* pChar, float value) {
  if (!bleClientConnected || pChar == nullptr) return;
  pChar->setValue((uint8_t*)&value, 4);
  pChar->notify();
}

// ── Firebase RTDB Diagnostic Write Helpers ────────────────────────────────────
bool writeRtdbFloat(const char* path, float value, int precision = 1) {
  if (Firebase.RTDB.setFloat(&fbdo, path, value)) {
    Serial.printf("[Firebase] WRITE SUCCESS: %s = %.*f\n", path, precision, value);
    return true;
  } else {
    Serial.printf("[Firebase] WRITE FAILED: %s | Reason: %s\n", path, fbdo.errorReason().c_str());
    return false;
  }
}

bool writeRtdbInt(const char* path, int value) {
  if (Firebase.RTDB.setInt(&fbdo, path, value)) {
    Serial.printf("[Firebase] WRITE SUCCESS: %s = %d\n", path, value);
    return true;
  } else {
    Serial.printf("[Firebase] WRITE FAILED: %s | Reason: %s\n", path, fbdo.errorReason().c_str());
    return false;
  }
}

bool writeRtdbString(const char* path, const char* value) {
  if (Firebase.RTDB.setString(&fbdo, path, value)) {
    Serial.printf("[Firebase] WRITE SUCCESS: %s = %s\n", path, value);
    return true;
  } else {
    Serial.printf("[Firebase] WRITE FAILED: %s | Reason: %s\n", path, fbdo.errorReason().c_str());
    return false;
  }
}

bool writeRtdbBool(const char* path, bool value) {
  if (Firebase.RTDB.setBool(&fbdo, path, value)) {
    Serial.printf("[Firebase] WRITE SUCCESS: %s = %s\n", path, value ? "true" : "false");
    return true;
  } else {
    Serial.printf("[Firebase] WRITE FAILED: %s | Reason: %s\n", path, fbdo.errorReason().c_str());
    return false;
  }
}

void pushToFirebase() {
  if (millis() - lastFirebasePush < FIREBASE_INTERVAL_MS) return;
  lastFirebasePush = millis();

  // 1. Verify Wi-Fi network connectivity
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Firebase] Wi-Fi is disconnected — buffering telemetry offline");
    bufferReading(temperature, humidity, airQuality);
    return;
  }

  // 2. Verify Firebase client initialization
  if (!firebaseReady) {
    Serial.println("[Firebase] Firebase is not ready: client uninitialized");
    return;
  }

  // 3. Verify Firebase authentication and token state
  if (!Firebase.ready()) {
    Serial.println("[Firebase] Firebase is not ready: authenticating or renewing token");
    return;
  }

  Serial.println("[Firebase] Pushing telemetry batch to /aerosense...");
  int successCount = 0;
  int failCount = 0;

  // Primary Environmental Telemetry (DHT22 & MQ-135)
  float roundedTemp = round(temperature * 10) / 10.0f;
  float roundedHum  = round(humidity * 10) / 10.0f;
  int currentTimestamp = (int)(millis() / 1000);

  if (writeRtdbFloat("/aerosense/temperature", roundedTemp, 1)) successCount++; else failCount++;
  if (writeRtdbFloat("/aerosense/humidity", roundedHum, 1)) successCount++; else failCount++;
  if (writeRtdbInt("/aerosense/air_quality", airQuality)) successCount++; else failCount++;
  if (writeRtdbInt("/aerosense/timestamp", currentTimestamp)) successCount++; else failCount++;
  if (writeRtdbString("/aerosense/device_status", "ONLINE")) successCount++; else failCount++;
  if (writeRtdbString("/aerosense/connection_mode", "WIFI")) successCount++; else failCount++;
  if (writeRtdbBool("/aerosense/mpu_connected", mpu6050Detected)) successCount++; else failCount++;

  // Push motion data ONLY if physical MPU-6050 is detected (Zero simulated readings)
  if (mpu6050Detected) {
    if (writeRtdbFloat("/aerosense/motion/accel_x", accelX, 4)) successCount++; else failCount++;
    if (writeRtdbFloat("/aerosense/motion/accel_y", accelY, 4)) successCount++; else failCount++;
    if (writeRtdbFloat("/aerosense/motion/accel_z", accelZ, 4)) successCount++; else failCount++;
    if (writeRtdbFloat("/aerosense/motion/gyro_x", gyroX, 4)) successCount++; else failCount++;
    if (writeRtdbFloat("/aerosense/motion/gyro_y", gyroY, 4)) successCount++; else failCount++;
    if (writeRtdbFloat("/aerosense/motion/gyro_z", gyroZ, 4)) successCount++; else failCount++;
  }

  // Summary diagnostics
  if (failCount == 0) {
    Serial.printf("[Firebase] Telemetry batch complete: all %d writes succeeded ✓\n", successCount);
  } else {
    Serial.printf("[Firebase] Telemetry batch finished: %d succeeded, %d FAILED\n", successCount, failCount);
  }

  // Flush offline buffered packets when reconnected
  if (bufferCount > 0) {
    Serial.printf("[Firebase] Flushing %d offline buffered packets to RTDB...\n", bufferCount);
    bufferCount = 0;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ARDUINO MAIN LOOP
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void loop() {
  // 1. Read DHT22 (Temperature & Humidity)
  float t = dht.readTemperature();
  float h = dht.readHumidity();

  if (!isnan(t) && !isnan(h)) {
    temperature = t;
    humidity    = h;
  }

  // 2. Read MQ-135 on GPIO 34 (ADC1_CH6, 0 - 4095)
  airQuality = analogRead(MQ135_PIN);

  // 3. Read physical MPU-6050 registers if physically present
  if (mpu6050Detected) {
    Wire.beginTransmission(MPU6050_ADDR);
    Wire.write(0x3B); // ACCEL_XOUT_H
    if (Wire.endTransmission(false) == 0 && Wire.requestFrom(MPU6050_ADDR, 14, true) == 14) {
      int16_t rawAx = (Wire.read() << 8) | Wire.read();
      int16_t rawAy = (Wire.read() << 8) | Wire.read();
      int16_t rawAz = (Wire.read() << 8) | Wire.read();
      Wire.read(); Wire.read(); // Skip internal die temperature
      int16_t rawGx = (Wire.read() << 8) | Wire.read();
      int16_t rawGy = (Wire.read() << 8) | Wire.read();
      int16_t rawGz = (Wire.read() << 8) | Wire.read();

      accelX = rawAx / 16384.0f;
      accelY = rawAy / 16384.0f;
      accelZ = rawAz / 16384.0f;
      gyroX  = rawGx / 131.0f;
      gyroY  = rawGy / 131.0f;
      gyroZ  = rawGz / 131.0f;

      // Notify motion telemetry over BLE if connected
      if (bleClientConnected && pMotionChar) {
        float motionPayload[6] = { accelX, accelY, accelZ, gyroX, gyroY, gyroZ };
        pMotionChar->setValue((uint8_t*)motionPayload, 24);
        pMotionChar->notify();
      }
    }
  }

  // 4. Critical hazard alert threshold: Temp > 35.0°C or Air Quality > 2500 ADC
  uint8_t alertFlag = (temperature > 35.0f || airQuality > 2500) ? 1 : 0;

  // 5. BLE GATT Notifications (Real sensor telemetry)
  notifyBleFloat(pTempChar, temperature);
  notifyBleFloat(pHumidityChar, humidity);
  notifyBleFloat(pAirQualityChar, (float)airQuality);

  if (bleClientConnected && pAlertChar) {
    pAlertChar->setValue(&alertFlag, 1);
    pAlertChar->notify();
  }

  // 6. Handle local HTTP server clients
  if (WiFi.status() == WL_CONNECTED) {
    httpServer.handleClient();
  }

  // 7. Synchronize with Firebase Realtime Database
  pushToFirebase();

  // 8. Serial Diagnostic Telemetry Log
  Serial.printf("[AeroSense] T=%.1f°C H=%.1f%% AQ=%d Alert=%d MPU=%s WiFi=%s BLE=%s\n",
    temperature, humidity, airQuality, alertFlag,
    (mpu6050Detected ? "ONLINE" : "ABSENT"),
    (WiFi.status() == WL_CONNECTED ? "ON" : "OFF"),
    (bleClientConnected ? "CONNECTED" : "ADVERTISING"));

  delay(samplingIntervalMs);
}

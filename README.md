AERION – AeroSense

IoT-Based Environmental Monitoring System

Smarter Monitoring. Better Awareness. A Connected Environment.

⸻

1. Project Overview

AERION – AeroSense is an IoT-based environmental monitoring system designed to monitor environmental parameters such as temperature, humidity, and air quality in real time.

The system integrates environmental sensors with an ESP32 microcontroller to collect and process sensor readings. The collected data is transmitted to a Flutter-based mobile application through Bluetooth Low Energy (BLE), while Wi-Fi connectivity enables cloud synchronization using Firebase Realtime Database.

The mobile application provides a centralized platform for monitoring live sensor readings, viewing historical data, analyzing environmental conditions, and receiving alerts based on configurable thresholds.

AERION aims to make environmental monitoring smarter, more accessible, and efficient through IoT technology.

⸻

2. Problem Statement

Environmental monitoring is important for understanding the conditions of indoor and surrounding environments.

Traditional monitoring methods may require users to check individual devices manually. They may also lack centralized monitoring, convenient historical data access, and configurable alert mechanisms.

Some of the major challenges include:

* Lack of centralized environmental monitoring.
* Difficulty in continuously tracking environmental parameters.
* Limited access to historical sensor information.
* Delayed identification of abnormal environmental conditions.
* Lack of convenient mobile-based monitoring.

To address these challenges, AERION – AeroSense provides an integrated IoT monitoring solution using sensors, wireless communication, cloud storage, and a dedicated mobile application.

⸻

3. Project Objectives

The primary objectives of AERION – AeroSense are:

1. To monitor temperature and humidity using environmental sensors.
2. To detect changes in surrounding air composition using the MQ135 sensor.
3. To collect and process sensor readings using ESP32.
4. To transmit sensor information through Bluetooth Low Energy.
5. To synchronize environmental data with Firebase Realtime Database.
6. To provide real-time monitoring through a Flutter mobile application.
7. To visualize historical sensor readings using graphs and charts.
8. To generate alerts based on configurable environmental thresholds.
9. To provide a user-friendly and responsive monitoring interface.

⸻

4. Hardware Components

The project uses the following hardware components.

4.1 ESP32 Dev Module

The ESP32 Dev Module acts as the main microcontroller of the system.

Responsibilities:

* Collects sensor readings.
* Processes environmental data.
* Converts analog sensor output into digital readings using its ADC.
* Handles Bluetooth Low Energy communication.
* Connects to Wi-Fi networks.
* Synchronizes sensor data with Firebase.

The ESP32 is selected because it provides integrated Wi-Fi and Bluetooth Low Energy capabilities.

4.2 DHT22 Temperature and Humidity Sensor

The DHT22 is a digital environmental sensor used to measure:

* Temperature in degrees Celsius (°C).
* Relative humidity in percentage (%).

Responsibilities:

* Measures surrounding temperature.
* Measures relative humidity.
* Sends digital readings to the ESP32.

4.3 MQ135 Gas Sensor

The MQ135 is a gas-sensitive sensor used to detect changes in surrounding air composition.

Responsibilities:

* Responds to various gases in the surrounding environment.
* Produces an analog output based on the sensor response.
* Provides analog readings to the ESP32.
* Helps identify changes in air conditions.

ADC Reading Explanation

The ESP32 uses a 12-bit ADC (Analog-to-Digital Converter).

The theoretical digital reading range is:

0–4095

The MQ135 analog output is converted into a digital ADC value by the ESP32.

In the current implementation, the application displays MQ135 readings as raw ADC values.

Important:

* Raw ADC values are not directly equivalent to AQI.
* Raw ADC values are not directly equivalent to CO₂ concentration.
* PPM calculations require sensor calibration, load resistance information, and gas-specific sensor characteristics.
* Thresholds used in the application are initial monitoring thresholds and must be validated for the actual sensor and environment.

⸻

5. Hardware Connection Details

5.1 ESP32 and DHT22 Connections

DHT22 Pin	ESP32 Connection
VCC	3.3V
DATA	GPIO 4
GND	GND

5.2 ESP32 and MQ135 Connections

MQ135 Pin	ESP32 Connection
VCC	5V / VIN
GND	GND
AOUT	GPIO 34 through a suitable voltage divider

Important Electrical Safety

The ESP32 GPIO pins are not 5V tolerant.

If the MQ135 analog output can exceed 3.3V, use a properly designed voltage divider before connecting it to GPIO34.

A suitable example is:

* Upper resistor: 10kΩ.
* Lower resistor: 18kΩ.

Connect the upper resistor between MQ135 AOUT and the ADC input node. Connect the lower resistor between the ADC input node and GND.

Ensure that all components share a common ground.

Verify the actual output voltage before connecting the circuit.

⸻

6. Hardware Working Principle

The system operates through the following sequence:

1. DHT22 measures the surrounding temperature and humidity.
2. MQ135 responds to changes in surrounding air composition.
3. MQ135 produces an analog output.
4. ESP32 reads the DHT22 digital data.
5. ESP32 converts the MQ135 analog output into a digital ADC reading.
6. ESP32 processes the collected sensor information.
7. Sensor readings are transmitted to the mobile application through BLE.
8. ESP32 uses Wi-Fi to synchronize sensor information with Firebase.
9. The Flutter application displays available sensor readings and environmental information.

⸻

7. Software Technologies

The project combines embedded programming, mobile application development, wireless communication, and cloud technologies.

Technology	Purpose
Embedded C++	ESP32 firmware development
Arduino IDE	ESP32 programming and uploading
Flutter	Mobile application development
Dart	Flutter application programming
Bluetooth Low Energy	Wireless communication
Wi-Fi	Internet connectivity
Firebase Realtime Database	Cloud data storage and synchronization
fl_chart	Graph and chart visualization
SharedPreferences	Local application settings
Android SDK	Android application building
Git and GitHub	Source code management

⸻

8. System Architecture

AERION follows an IoT-based architecture consisting of four major layers.

8.1 Sensor Layer

Includes:

* DHT22.
* MQ135.

This layer collects environmental information.

8.2 Processing Layer

ESP32 acts as the central processing unit.

It collects sensor readings, processes the data, and manages wireless communication.

8.3 Communication and Cloud Layer

Two communication methods are used:

Bluetooth Low Energy (BLE)

Used for direct communication between ESP32 and the mobile application.

Wi-Fi

Used to connect ESP32 to the internet and synchronize sensor information with Firebase.

8.4 Application Layer

The Flutter mobile application provides:

* Live monitoring.
* Device connectivity information.
* Environmental analytics.
* Alerts.
* Threshold configuration.

System Architecture Diagram

       DHT22 SENSOR
    (Temperature & Humidity)
              |
              |
        MQ135 SENSOR
       (Air Quality)
              |
              v
       ESP32 DEV MODULE
       (Data Processing)
              |
        +-----+-----+
        |           |
        v           v
       BLE         Wi-Fi
        |           |
        v           v
   FLUTTER APP    FIREBASE
        |           |
        |           v
        |      CLOUD STORAGE
        |
        v
     DASHBOARD
        |
   +----+-----+
   |          |
   v          v
ANALYTICS   ALERTS

⸻

9. Bluetooth Low Energy Communication

Bluetooth Low Energy is used for direct wireless communication between the ESP32 and the Flutter mobile application.

BLE Communication Process

1. ESP32 initializes its BLE functionality.
2. ESP32 advertises its Bluetooth device information.
3. The mobile application scans for nearby BLE devices.
4. The user selects the ESP32 device.
5. The mobile application establishes a BLE connection.
6. The application discovers the available BLE services.
7. It identifies the required characteristics.
8. The application reads or subscribes to the sensor data characteristics.
9. ESP32 sends updated sensor readings.
10. Flutter receives and processes the readings.
11. The Dashboard updates with the available sensor information.

Advantages of BLE

* Low power wireless communication.
* Direct device-to-mobile connectivity.
* No internet connection required for local BLE communication.
* Suitable for short-range IoT monitoring.

The existing BLE service UUIDs, characteristic UUIDs, and data format must be maintained between the ESP32 firmware and Flutter application.

⸻

10. Firebase Realtime Database Integration

Firebase Realtime Database is used as the cloud storage solution.

ESP32 connects to Wi-Fi and uploads environmental sensor readings to Firebase.

Firebase Database Path

/aerosense

Database Fields

Field	Description
temperature	Temperature reading
humidity	Relative humidity reading
air_quality	MQ135 raw ADC reading
timestamp	Sensor data timestamp
device_status	Device connection status
connection_mode	Communication mode

Firebase Working Process

1. ESP32 connects to a configured Wi-Fi network.
2. Firebase initialization is performed.
3. ESP32 establishes authenticated communication with Firebase.
4. Sensor readings are collected.
5. Sensor values are uploaded to the Realtime Database.
6. Firebase stores the latest sensor information.
7. The Flutter application accesses available cloud data through its Firebase integration.

Advantages

* Cloud-based sensor data storage.
* Real-time database synchronization.
* Centralized data access.
* Support for historical monitoring when data is retained.
* Integration with mobile applications.

Security

Firebase authentication and appropriate Realtime Database security rules should be enabled.

Never store Wi-Fi passwords, Firebase authentication passwords, or private credentials directly in public source code.

⸻

11. AERION Mobile Application

The mobile application is developed using Flutter and Dart.

It provides a centralized interface for monitoring and managing environmental sensor information.

The application contains six major modules.

11.1 Dashboard

The Dashboard is the primary monitoring interface.

It displays:

* Current temperature.
* Current humidity.
* MQ135 raw ADC reading.
* Device connection status.
* Environmental status indicators.
* Temperature trend graph.
* Humidity trend graph.
* Air-quality trend graph.
* Recent alerts.

The Dashboard provides a quick overview of the monitored environmental conditions.

11.2 BLE Devices

The BLE Devices page manages Bluetooth communication with ESP32.

Features:

* Bluetooth device scanning.
* Available device identification.
* Connect and disconnect operations.
* BLE connection status.
* Device information.

All other application pages remain accessible even when BLE is disconnected.

11.3 Wi-Fi

The Wi-Fi page provides network connectivity information.

It is designed to display:

* Wi-Fi connection status.
* Connected network SSID.
* Signal strength, when available.
* IP address, when available.
* Firebase synchronization status.
* Last successful synchronization time.

If Wi-Fi credential configuration is implemented, the page can also provide network configuration controls.

The actual ability to configure ESP32 Wi-Fi remotely depends on the communication functionality implemented in the firmware.

11.4 Analytics

The Analytics module provides graphical representations of environmental sensor data.

It uses the fl_chart package.

Visualizations include:

* Environmental status distribution.
* Temperature distribution.
* Humidity distribution.
* MQ135 raw ADC distribution.
* Sensor summary statistics.

The module can display:

* Average temperature.
* Maximum temperature.
* Minimum temperature.
* Average humidity.
* Maximum humidity.
* Minimum humidity.
* Average MQ135 raw ADC reading.
* Total recorded samples.

Analytics must be calculated using actual recorded sensor data rather than fabricated sample values.

11.5 Alerts

The Alerts module provides environmental notifications based on configured thresholds.

Alert categories:

* Normal.
* Warning.
* Critical.

The application evaluates available sensor readings against the configured threshold values.

Example:

If the temperature exceeds the configured critical threshold, the application can generate a critical temperature alert.

The Alerts module is designed to help users identify abnormal environmental conditions.

11.6 Settings

The Settings module provides user-configurable application options.

Features include:

* Light Mode.
* Dark Mode.
* Environmental alert thresholds.
* Temperature threshold configuration.
* Humidity threshold configuration.
* MQ135 raw ADC threshold configuration.
* Alert preferences.
* Sound notification preferences.
* Vibration notification preferences.
* Restore default settings.

SharedPreferences is used to retain supported local settings across application restarts.

⸻

12. Environmental Threshold Configuration

AERION provides configurable thresholds to classify environmental readings.

Thresholds can be adjusted according to the monitoring environment.

12.1 Temperature Thresholds

Example initial configuration:

Temperature	Status
Below 30°C	Normal
30°C–35°C	Warning
Above 35°C	Critical

12.2 Humidity Thresholds

Example indoor comfort-based configuration:

Relative Humidity	Status
Below 30%	Critical – Low
30%–39%	Warning – Low
40%–60%	Normal
61%–70%	Warning – High
Above 70%	Critical – High

These are example indoor comfort thresholds, not universal health or safety limits.

12.3 MQ135 ADC Thresholds

Example initial configuration:

ADC Reading	Status
0–2000	Normal
2001–2500	Warning
2501–4095	Critical

IMPORTANT:

These are initial application monitoring thresholds, not scientifically established gas concentration limits.

Actual values must be adjusted based on sensor calibration, baseline readings, operating conditions, and the intended monitoring environment.

Raw ADC readings must not be presented as calibrated AQI or PPM values.

⸻

13. Data Flow

The complete data flow of AERION is:

1. ENVIRONMENTAL DATA COLLECTION
             |
             v
2. SENSOR PROCESSING
             |
             v
3. ESP32 MICROCONTROLLER
             |
             v
4. DATA TRANSMISSION
       /           \
      /             \
     v               v
   BLE              Wi-Fi
     |               |
     v               v
 FLUTTER APP       FIREBASE
     |               |
     v               v
 DASHBOARD       CLOUD DATA
     |
     v
 ANALYTICS
     |
     v
 ALERT GENERATION

This architecture enables local wireless monitoring and cloud-based data synchronization.

⸻

14. Installation and Setup

14.1 Hardware Setup

1. Connect DHT22 to ESP32.
2. Connect MQ135 to the ESP32 through an appropriate analog voltage divider.
3. Ensure common ground connections.
4. Power the hardware.
5. Verify sensor readings.

14.2 Firmware Setup

Requirements:

* Arduino IDE.
* ESP32 board support.
* Required sensor libraries.
* Firebase library.
* BLE libraries.

Steps:

1. Open the ESP32 firmware project.
2. Configure the required sensor pins.
3. Configure Wi-Fi credentials securely.
4. Configure Firebase connection details.
5. Verify the BLE service and characteristic configuration.
6. Select the correct ESP32 board.
7. Select the correct serial port.
8. Compile and upload the firmware.
9. Open Serial Monitor to verify sensor readings and communication status.

14.3 Flutter Application Setup

Requirements:

* Flutter SDK.
* Dart SDK.
* Android SDK.
* Android Studio or Visual Studio Code.
* Firebase project configuration.

Clone the repository:

git clone <YOUR_GITHUB_REPOSITORY_URL>

Open the project directory:

cd aerion_aerosense

Install dependencies:

flutter pub get

Run static analysis:

flutter analyze

Build the Android application:

flutter build apk --release

The generated APK will be available at:

build/app/outputs/flutter-apk/app-release.apk

⸻

15. Testing and Validation

The following testing activities are relevant to the project.

Hardware Testing

* Verify ESP32 startup.
* Verify DHT22 temperature readings.
* Verify DHT22 humidity readings.
* Verify MQ135 analog readings.
* Verify ADC values.
* Verify sensor stability.

BLE Testing

* Verify Bluetooth advertising.
* Verify device scanning.
* Verify ESP32 connection.
* Verify characteristic discovery.
* Verify sensor data transmission.
* Verify disconnect and reconnect behaviour.

Firebase Testing

* Verify Wi-Fi connection.
* Verify Firebase initialization.
* Verify authentication.
* Verify database writes.
* Verify sensor field updates.
* Verify application data retrieval.

Mobile Application Testing

* Verify Dashboard readings.
* Verify navigation.
* Verify BLE device management.
* Verify Wi-Fi status.
* Verify Analytics.
* Verify Alerts.
* Verify threshold configuration.
* Verify saved settings after restart.
* Verify Light Mode and Dark Mode.
* Verify responsive layouts.

Build Testing

* Run Flutter static analysis.
* Resolve compilation errors.
* Build Android debug APK.
* Build Android release APK.

Actual hardware validation should be recorded separately from code-level verification.

⸻

16. Advantages of AERION

1. Real-time environmental monitoring.
2. Wireless sensor communication.
3. Direct BLE connectivity.
4. Cloud-based sensor data synchronization.
5. Mobile-based monitoring.
6. Historical data visualization.
7. Configurable environmental alert thresholds.
8. User-friendly interface.
9. Light and Dark theme support.
10. Expandable IoT architecture.

⸻

17. Limitations

The current implementation has the following considerations:

* MQ135 currently provides raw ADC readings rather than calibrated gas concentration values.
* Accurate PPM calculation requires additional calibration.
* BLE communication depends on Bluetooth availability and connection range.
* Firebase synchronization requires internet connectivity.
* Historical analytics depend on the availability of recorded sensor data.
* Environmental thresholds must be configured and validated for the intended environment.
* Sensor readings can be influenced by operating conditions and calibration.

⸻

18. Future Enhancements

Potential future improvements include:

1. Calibrated gas concentration measurements.
2. Additional environmental sensors.
3. Machine learning-based environmental prediction.
4. Advanced environmental risk classification.
5. Multi-device monitoring.
6. Improved cloud analytics.
7. Automated environmental reports.
8. Historical CSV and PDF data export.
9. Advanced notification mechanisms.
10. Web-based environmental monitoring dashboard.

These enhancements can expand AERION into a more comprehensive environmental monitoring platform.

⸻

19. AI Tools and Development Assistance

Artificial Intelligence tools were used as development assistants during the design, implementation, debugging, and documentation stages of AERION – AeroSense.

The following AI tools supported the development workflow:

19.1 ChatGPT – OpenAI

ChatGPT was used as an AI development assistant for:

* Understanding IoT concepts and system architecture.
* Exploring ESP32 programming concepts.
* Understanding sensor integration.
* Debugging programming errors.
* Understanding BLE communication.
* Firebase integration guidance.
* Flutter development assistance.
* UI/UX improvement suggestions.
* Technical documentation preparation.
* Project explanation and presentation preparation.

ChatGPT helped analyze technical issues and provided guidance during different stages of development.

19.2 Google Antigravity

Google Antigravity was used as an AI-assisted development environment.

Its assistance included:

* Inspecting the existing Flutter project structure.
* Supporting modifications to existing Dart files.
* Improving mobile application UI.
* Refining Dashboard components.
* Improving navigation.
* Supporting Analytics and chart implementation.
* Improving Settings and threshold configuration.
* Identifying and addressing layout issues.
* Assisting with application restructuring.

Changes generated through the AI-assisted development workflow were reviewed and validated during implementation.

19.3 Claude – Anthropic

Claude was used as an additional AI development assistant for:

* Technical problem-solving.
* Code explanation.
* Exploring implementation approaches.
* Reviewing application architecture.
* Assisting with development planning.
* Improving technical descriptions and documentation.

19.4 Responsible AI Usage

AI tools were used to support development rather than replace engineering decisions.

The project implementation involved reviewing generated suggestions, integrating suitable changes into the existing source code, testing application behaviour, and validating hardware and software functionality.

The final system is intended to operate using actual sensor readings and the implemented ESP32, BLE, Wi-Fi, Firebase, and Flutter integrations.

⸻

20. Conclusion

AERION – AeroSense demonstrates the integration of IoT hardware, environmental sensors, embedded programming, wireless communication, cloud database technology, and mobile application development.

By combining ESP32, DHT22, MQ135, Bluetooth Low Energy, Wi-Fi, Firebase Realtime Database, and Flutter, the system provides a centralized platform for environmental monitoring.

The application enables users to monitor temperature, humidity, and air-quality sensor readings, visualize available historical data, and identify abnormal conditions through configurable alerts.

AERION represents an integrated approach to smarter and more accessible environmental monitoring.

AERION – AeroSense

Designed to Monitor. Built to Connect.

⸻

21. Project Information

Category	Details
Project Name	AERION – AeroSense
Project Type	IoT-Based Environmental Monitoring System
Hardware Controller	ESP32 Dev Module
Temperature Sensor	DHT22
Humidity Sensor	DHT22
Air Quality Sensor	MQ135
Embedded Programming	C++
Mobile Framework	Flutter
Programming Language	Dart
Communication	BLE and Wi-Fi
Cloud Database	Firebase Realtime Database
Data Visualization	fl_chart
Local Storage	SharedPreferences
AI Development Tools	ChatGPT, Google Antigravity, Claude
Mobile Platform	Android

Project Tagline:

Smarter Monitoring. Better Awareness. A Connected Environment.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../connectivity/connectivity_manager.dart';
import '../wifi/wifi_sensor_service.dart';
import '../firebase/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class WiFiMonitorScreen extends StatefulWidget {
  const WiFiMonitorScreen({super.key});

  @override
  State<WiFiMonitorScreen> createState() => _WiFiMonitorScreenState();
}

class _WiFiMonitorScreenState extends State<WiFiMonitorScreen> {
  bool _isRefreshing = false;
  late final TextEditingController _ipController;
  bool _isConnecting = false;
  String? _ipError;

  @override
  void initState() {
    super.initState();
    final wifi = context.read<WiFiSensorService>();
    final currentIp = wifi.espIpAddress.isNotEmpty ? wifi.espIpAddress : '192.168.4.1';
    _ipController = TextEditingController(text: currentIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connectWifi(ConnectivityManager cm, WiFiSensorService wifi) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _ipError = 'Please enter an IP address or hostname');
      return;
    }

    setState(() {
      _isConnecting = true;
      _ipError = null;
    });
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();

    try {
      cm.connectWifi(ip);
      final reachable = await wifi.testConnection();
      if (mounted) {
        if (reachable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Connected to ESP32 Wi-Fi at $ip',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white),
              ),
              backgroundColor: AppColors.successGreen,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Polling started at $ip. Connect your phone to ESP32 Wi-Fi Access Point if data is not received.',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white),
              ),
              backgroundColor: AppColors.radiantAmber,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _ipError = 'Connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _disconnectWifi(ConnectivityManager cm) {
    HapticFeedback.lightImpact();
    cm.disconnectWifi();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Wi-Fi telemetry disconnected. Reverted to Bluetooth / Cloud.',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _refreshStatus() async {
    setState(() => _isRefreshing = true);
    HapticFeedback.lightImpact();

    try {
      final wifi = context.read<WiFiSensorService>();
      final firebase = context.read<FirebaseService>();

      if (wifi.espIpAddress.isNotEmpty) {
        await wifi.testConnection();
      }
      if (firebase.isAvailable && !firebase.isConnected) {
        firebase.startListening();
      }
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {}

    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Wi-Fi network and cloud synchronization status refreshed.',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WiFiSensorService>();
    final firebase = context.watch<FirebaseService>();
    final cm = context.watch<ConnectivityManager>();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;

    final isWifiConnected = wifi.isConnected || cm.activeMode == ConnectivityMode.wifi;
    final hasInternet = cm.hasInternetAccess;
    final isFirebaseSynced = firebase.isConnected && firebase.isAvailable;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'WI-FI & CLOUD SYNC',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: primaryColor,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh Status',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh_rounded, color: primaryColor, size: 22),
            onPressed: _isRefreshing ? null : _refreshStatus,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Wi-Fi Device Connection Form (Input Field + Connect Button)
          _buildConnectInputCard(
            cm: cm,
            wifi: wifi,
            isDark: isDark,
            primaryColor: primaryColor,
            isWifiConnected: isWifiConnected,
          ),
          const SizedBox(height: 16),

          // 2. Wi-Fi Connection Details Card
          _buildWifiCard(
            isWifiConnected: isWifiConnected,
            hasInternet: hasInternet,
            wifi: wifi,
            cm: cm,
            isDark: isDark,
            emerald: emerald,
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 16),

          // 3. Firebase Cloud Synchronization Card
          _buildFirebaseSyncCard(
            firebase: firebase,
            isFirebaseSynced: isFirebaseSynced,
            isDark: isDark,
            emerald: emerald,
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 16),

          // 4. Disconnection Guidance (shown when Wi-Fi is disconnected)
          if (!isWifiConnected)
            _buildDisconnectedNotice(isDark),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Wi-Fi Connection Input & Control Card ─────────────────────────────────

  Widget _buildConnectInputCard({
    required ConnectivityManager cm,
    required WiFiSensorService wifi,
    required bool isDark,
    required Color primaryColor,
    required bool isWifiConnected,
  }) {
    final cardBg = isDark ? const Color(0xFF131A26) : const Color(0xFFF1F5F9);
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.router_rounded, color: primaryColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  'CONNECT VIA WI-FI',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the ESP32 IP address on your local network to stream sensor telemetry over HTTP.',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),

            // IP Input Field (Enter Space)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.text,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cardBg,
                      hintText: 'e.g. 192.168.4.1',
                      hintStyle: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(Icons.lan_outlined, size: 18, color: primaryColor),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        onPressed: () => _ipController.clear(),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderCol, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: primaryColor, width: 1.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_ipError != null) ...[
              const SizedBox(height: 6),
              Text(
                _ipError!,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: AppColors.criticalRed,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Connect & Disconnect Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting
                        ? null
                        : () => _connectWifi(cm, wifi),
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.wifi_rounded, size: 18, color: Colors.black),
                    label: Text(
                      isWifiConnected ? 'RECONNECT WI-FI' : 'CONNECT WI-FI',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        fontSize: 12.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                if (isWifiConnected) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _disconnectWifi(cm),
                    icon: const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.criticalRed),
                    label: const Text(
                      'DISCONNECT',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.w800,
                        color: AppColors.criticalRed,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      side: const BorderSide(color: AppColors.criticalRed, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Quick default IP chip
            Row(
              children: [
                Text(
                  'Quick Preset: ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _ipController.text = '192.168.4.1';
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '192.168.4.1 (ESP32 AP Default)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10.5,
                        color: primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Wi-Fi Connection Details Card ──────────────────────────────────────────

  Widget _buildWifiCard({
    required bool isWifiConnected,
    required bool hasInternet,
    required WiFiSensorService wifi,
    required ConnectivityManager cm,
    required bool isDark,
    required Color emerald,
    required Color primaryColor,
  }) {
    final statusColor = isWifiConnected
        ? emerald
        : (hasInternet ? AppColors.radiantAmber : AppColors.crimsonNeon);

    final statusText = isWifiConnected
        ? 'CONNECTED'
        : (hasInternet ? 'NETWORK READY • ESP32 STANDBY' : 'DISCONNECTED');

    final ssid = wifi.connectedSsid.isNotEmpty ? wifi.connectedSsid : 'AeroSense-Network';
    final ipAddress = wifi.espIpAddress.isNotEmpty ? wifi.espIpAddress : '192.168.4.1';

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isWifiConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isWifiConnected
                            ? 'Local High-Speed IoT Telemetry Stream'
                            : 'No active local Wi-Fi telemetry packet stream',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Essential Fields
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    label: 'CONNECTED NETWORK SSID',
                    value: ssid,
                    icon: Icons.wifi_find_rounded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    label: 'IP ADDRESS',
                    value: ipAddress,
                    icon: Icons.lan_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    label: 'SIGNAL STRENGTH (RSSI)',
                    value: isWifiConnected ? '-62 dBm (Strong)' : '--',
                    icon: Icons.cell_tower_rounded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    label: 'GATEWAY STATUS',
                    value: hasInternet ? 'Online Gateway' : 'Local Only',
                    icon: Icons.public_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Firebase Synchronization Card ─────────────────────────────────────────

  Widget _buildFirebaseSyncCard({
    required FirebaseService firebase,
    required bool isFirebaseSynced,
    required bool isDark,
    required Color emerald,
    required Color primaryColor,
  }) {
    final statusColor = isFirebaseSynced ? emerald : AppColors.radiantAmber;
    final statusText = isFirebaseSynced ? 'LIVE SYNCHRONIZED' : 'BUFFER QUEUED';

    final lastSyncTime = firebase.lastPacketTime != null
        ? DateFormat('HH:mm:ss • MMM d').format(firebase.lastPacketTime!)
        : 'Awaiting First Packet';

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.cloud_sync_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'FIREBASE REALTIME SYNC',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    label: 'DATABASE TARGET',
                    value: '/aerosense',
                    icon: Icons.folder_open_rounded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    label: 'LAST SYNC TIME',
                    value: lastSyncTime,
                    icon: Icons.schedule_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _infoItem(
                    label: 'OFFLINE BUFFER',
                    value: '${firebase.pendingBufferCount} packets pending',
                    icon: Icons.storage_rounded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _infoItem(
                    label: 'CLOUD STATE',
                    value: firebase.isInitialized ? 'Connected' : 'Offline Buffer Active',
                    icon: Icons.cloud_done_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpful Disconnection Guidance ──────────────────────────────────────────

  Widget _buildDisconnectedNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.radiantAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.radiantAmber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.radiantAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wi-Fi Telemetry Stream Disconnected',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.radiantAmber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ensure your ESP32 device is powered and connected to the same local 2.4 GHz network, or switch to the BLE tab to establish a direct Bluetooth link.',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: isDark ? AppColors.textMuted : AppColors.lightTextMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
          ),
        ),
      ],
    );
  }
}

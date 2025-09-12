import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

// Background task identifier
const String batteryCheckTask = "batteryCheckTask";

// Global function for background work (must be top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case batteryCheckTask:
        await _performBatteryCheck();
        break;
    }
    return Future.value(true);
  });
}

// Background battery check function
Future<void> _performBatteryCheck() async {
  try {
    final Battery battery = Battery();
    final prefs = await SharedPreferences.getInstance();

    int batteryLevel = await battery.batteryLevel;
    BatteryState batteryState = await battery.batteryState;
    int threshold = prefs.getInt('threshold') ?? 20;
    bool isCharging = batteryState == BatteryState.charging;

    // Check if alarm should trigger
    if (batteryLevel >= threshold && isCharging) {
      // Show notification and try to play alarm
      await _showAlarmNotification(batteryLevel, threshold);
      await _playBackgroundAlarm();
    }
  } catch (e) {
    print('Background check error: $e');
  }
}

// Show notification when alarm triggers
Future<void> _showAlarmNotification(int batteryLevel, int threshold) async {
  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'battery_alarm_channel',
    'Battery Alarm',
    channelDescription: 'Notifications for battery alarm',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm'),
    ongoing: true, // Makes notification persistent
    autoCancel: false,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
  );

  await notifications.show(
    0,
    'Battery Alarm! 🔋',
    'Battery reached $batteryLevel%! Time to unplug charger.',
    notificationDetails,
  );
}

// Play alarm in background (limited functionality)
Future<void> _playBackgroundAlarm() async {
  try {
    // This has limited effectiveness in background
    // The notification sound is more reliable
    final AudioPlayer player = AudioPlayer();
    await player.play(AssetSource("sounds/alarm.mp3"));
  } catch (e) {
    print('Background audio error: $e');
  }
}

class BatteryAlarmScreen extends StatefulWidget {
  const BatteryAlarmScreen({super.key});

  @override
  State<BatteryAlarmScreen> createState() => _BatteryAlarmScreenState();
}

class _BatteryAlarmScreenState extends State<BatteryAlarmScreen>
    with WidgetsBindingObserver {
  final Battery _battery = Battery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late FlutterLocalNotificationsPlugin _notifications;

  int _batteryLevel = 100;
  int _threshold = 20;
  bool _isAlarmPlaying = false;
  bool _isCharging = false;
  Timer? _timer;
  String? _customAlarmPath;
  String _selectedAlarmName = "Default Alarm";
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  bool _backgroundMonitoringEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _initializeBackgroundWork();
    _loadSettings();
    _requestPermissions();
    _startMonitoring();
    _listenToBatteryState();
    _checkInitialState();
  }

  Future<void> _initializeNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'battery_alarm_channel',
        'Battery Alarm',
        description: 'Notifications for battery alarm',
        importance: Importance.max,
        playSound: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _initializeBackgroundWork() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  }

  void _onNotificationTapped(NotificationResponse response) {
    // When user taps notification, bring app to foreground and stop alarm
    setState(() {
      _isAlarmPlaying = false;
    });
    _audioPlayer.stop();
    _notifications.cancel(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background - start background monitoring
      _startBackgroundMonitoring();
    } else if (state == AppLifecycleState.resumed) {
      // App coming to foreground - stop background monitoring
      _stopBackgroundMonitoring();
      // Cancel any persistent notifications
      _notifications.cancel(0);
    }
  }

  Future<void> _startBackgroundMonitoring() async {
    if (_backgroundMonitoringEnabled) return;

    setState(() {
      _backgroundMonitoringEnabled = true;
    });

    // Register periodic background task (every 15 minutes minimum on Android)
    await Workmanager().registerPeriodicTask(
      "batteryCheck",
      batteryCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
  }

  Future<void> _stopBackgroundMonitoring() async {
    if (!_backgroundMonitoringEnabled) return;

    setState(() {
      _backgroundMonitoringEnabled = false;
    });

    await Workmanager().cancelByUniqueName("batteryCheck");
  }

  Future<void> _requestPermissions() async {
    // Request necessary permissions
    await Permission.audio.request();
    await Permission.storage.request();

    // For Android 13+, request notification permission
    if (Platform.isAndroid) {
      await Permission.notification.request();
      // Request to ignore battery optimizations for better background performance
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _threshold = prefs.getInt('threshold') ?? 20;
      _customAlarmPath = prefs.getString('custom_alarm_path');
      _selectedAlarmName = prefs.getString('alarm_name') ?? "Default Alarm";
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('threshold', _threshold);
    if (_customAlarmPath != null) {
      await prefs.setString('custom_alarm_path', _customAlarmPath!);
      await prefs.setString('alarm_name', _selectedAlarmName);
    }
  }

  Future<void> _checkInitialState() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      int level = await _battery.batteryLevel;
      BatteryState state = await _battery.batteryState;

      setState(() {
        _batteryLevel = level;
        _isCharging = state == BatteryState.charging;
      });

      if (level >= _threshold && _isCharging && !_isAlarmPlaying) {
        _playAlarm();
      }
    } catch (e) {
      print('Error checking initial state: $e');
    }
  }

  void _listenToBatteryState() {
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      bool wasCharging = _isCharging;
      setState(() {
        _isCharging = state == BatteryState.charging;
      });

      if (wasCharging && !_isCharging && _isAlarmPlaying) {
        _stopAlarm();
      }
    });
  }

  void _startMonitoring() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        int level = await _battery.batteryLevel;
        BatteryState state = await _battery.batteryState;

        setState(() {
          _batteryLevel = level;
          _isCharging = state == BatteryState.charging;
        });

        if (level >= _threshold && _isCharging && !_isAlarmPlaying) {
          _playAlarm();
          // Also show notification for immediate alert
          _showForegroundNotification(level);
        }
      } catch (e) {
        print('Error monitoring battery: $e');
      }
    });
  }

  Future<void> _showForegroundNotification(int batteryLevel) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'battery_alarm_channel',
      'Battery Alarm',
      channelDescription: 'Regular battery alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false, // Don't play notification sound since alarm is already playing
      ongoing: true,
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          'stop_alarm',
          'Stop Alarm',
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      0,
      'Battery Alarm Active! 🔋',
      'Battery at $batteryLevel%! Tap to stop alarm.',
      notificationDetails,
    );
  }

  Future<void> _playAlarm() async {
    if (_isAlarmPlaying) return;

    setState(() {
      _isAlarmPlaying = true;
    });

    try {
      // Set audio attributes for alarm playback
      await _audioPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));

      if (_customAlarmPath != null && File(_customAlarmPath!).existsSync()) {
        await _audioPlayer.play(DeviceFileSource(_customAlarmPath!));
      } else {
        await _audioPlayer.play(AssetSource("sounds/alarm.mp3"));
      }

      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      HapticFeedback.vibrate();

    } catch (e) {
      print('Error playing alarm: $e');
      setState(() {
        _isAlarmPlaying = false;
      });
    }
  }

  Future<void> _stopAlarm() async {
    setState(() {
      _isAlarmPlaying = false;
    });
    await _audioPlayer.stop();
    // Cancel notification when alarm stops
    await _notifications.cancel(0);
  }

  Future<void> _selectCustomAlarm() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _customAlarmPath = result.files.single.path;
          _selectedAlarmName = result.files.single.name;
        });
        await _saveSettings();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Custom alarm selected: $_selectedAlarmName')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting alarm: $e')),
      );
    }
  }

  Future<void> _testAlarm() async {
    if (_isAlarmPlaying) {
      await _stopAlarm();
    } else {
      await _playAlarm();
    }
  }

  Future<void> _checkConditionsNow() async {
    try {
      int level = await _battery.batteryLevel;
      BatteryState state = await _battery.batteryState;

      setState(() {
        _batteryLevel = level;
        _isCharging = state == BatteryState.charging;
      });

      if (level >= _threshold && _isCharging && !_isAlarmPlaying) {
        _playAlarm();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conditions met! Alarm started.')),
        );
      } else {
        String message = '';
        if (level < _threshold) message += 'Battery ($level%) below threshold ($_threshold%). ';
        if (!_isCharging) message += 'Device not charging. ';
        if (_isAlarmPlaying) message += 'Alarm already playing. ';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.isEmpty ? 'Conditions met but alarm already playing' : message)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking conditions: $e')),
      );
    }
  }

  Color _getBatteryColor() {
    if (_batteryLevel > 50) return Colors.green;
    if (_batteryLevel > 20) return Colors.orange;
    return Colors.red;
  }

  IconData _getBatteryIcon() {
    if (_isCharging) return Icons.battery_charging_full;
    if (_batteryLevel > 90) return Icons.battery_full;
    if (_batteryLevel > 60) return Icons.battery_5_bar;
    if (_batteryLevel > 30) return Icons.battery_3_bar;
    if (_batteryLevel > 15) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _batteryStateSubscription?.cancel();
    _audioPlayer.dispose();
    _stopBackgroundMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Battery Alarm"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isAlarmPlaying ? Icons.volume_off : Icons.volume_up),
            onPressed: _isAlarmPlaying ? _stopAlarm : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Background monitoring status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _backgroundMonitoringEnabled ? Colors.green[100] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _backgroundMonitoringEnabled ? Colors.green : Colors.grey,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _backgroundMonitoringEnabled ? Icons.check_circle : Icons.info,
                      color: _backgroundMonitoringEnabled ? Colors.green : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _backgroundMonitoringEnabled
                            ? "Background monitoring active - app will work when minimized"
                            : "Background monitoring inactive - keep app open for alarms",
                        style: TextStyle(
                          fontSize: 12,
                          color: _backgroundMonitoringEnabled ? Colors.green[800] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Battery Status Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getBatteryColor().withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _getBatteryColor(), width: 2),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getBatteryIcon(),
                      size: 80,
                      color: _getBatteryColor(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "$_batteryLevel%",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _getBatteryColor(),
                      ),
                    ),
                    Text(
                      _isCharging ? "Charging" : "Not Charging",
                      style: TextStyle(
                        fontSize: 16,
                        color: _isCharging ? Colors.green : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Threshold Setting Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      "Alarm Threshold: $_threshold%",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      min: 1,
                      max: 99,
                      divisions: 98,
                      value: _threshold.toDouble(),
                      onChanged: (value) {
                        setState(() {
                          _threshold = value.toInt();
                        });
                        _saveSettings();
                      },
                      activeColor: Colors.blue,
                    ),
                    Text(
                      "Alarm will trigger when battery reaches $_threshold% or higher WHILE CHARGING",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Alarm Sound Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      "Alarm Sound",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedAlarmName,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _selectCustomAlarm,
                          icon: const Icon(Icons.music_note, size: 18),
                          label: const Text("Select Audio"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _testAlarm,
                          icon: Icon(_isAlarmPlaying ? Icons.stop : Icons.play_arrow, size: 18),
                          label: Text(_isAlarmPlaying ? "Stop Test" : "Test Alarm"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isAlarmPlaying ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _checkConditionsNow,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text("Check Conditions Now"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Status and Control Section
              if (_isAlarmPlaying)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 40),
                      const SizedBox(height: 10),
                      const Text(
                        "⚠️ ALARM ACTIVE ⚠️",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        "Battery reached safe level!\nYour device is charged to the threshold.\nAlarm will only stop when you:\n• Press 'Stop Alarm' button\n• Remove charger from device\n• Tap the notification",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 15),
                      ElevatedButton.icon(
                        onPressed: _stopAlarm,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop Alarm"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Info Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      "Enhanced Background Support:\n• Uses notifications for background alerts\n• Requests battery optimization bypass\n• Periodic background checks (every 15 min)\n• Immediate foreground monitoring when app is open\n\nFor best results: Allow all permissions and disable battery optimization for this app in system settings.",
                      style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
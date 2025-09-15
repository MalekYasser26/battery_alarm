// // battery_alarm_screen.dart (Fixed version)
// import 'dart:async';
// import 'dart:developer';
// import 'dart:io';
// import 'dart:isolate';
//
// import 'package:audioplayers/audioplayers.dart';
// import 'package:battery_plus/battery_plus.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
//
// // Import your task handler
// import 'task_handler.dart';
//
// class BatteryAlarmScreen extends StatefulWidget {
//   const BatteryAlarmScreen({super.key});
//
//   @override
//   State<BatteryAlarmScreen> createState() => _BatteryAlarmScreenState();
// }
//
// class _BatteryAlarmScreenState extends State<BatteryAlarmScreen>
//     with WidgetsBindingObserver {
//   final Battery _battery = Battery();
//   final AudioPlayer _audioPlayer = AudioPlayer();
//   late FlutterLocalNotificationsPlugin _notifications;
//
//   int _batteryLevel = 100;
//   int _threshold = 20;
//   bool _isAlarmPlaying = false;
//   bool _isCharging = false;
//   Timer? _timer;
//   String? _customAlarmPath;
//   String _selectedAlarmName = "Default Alarm";
//   StreamSubscription<BatteryState>? _batteryStateSubscription;
//   bool _foregroundServiceRunning = false;
//   ReceivePort? _receivePort;
//   bool _alarmHasTriggered = false; // Track if alarm has already triggered for this charge session
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initializeNotifications();
//     _loadSettings();
//     _requestPermissions();
//     _startMonitoring();
//     _listenToBatteryState();
//     _checkInitialState();
//     _initReceivePort();
//   }
//
//   void _initReceivePort() {
//     _receivePort = ReceivePort();
//     _receivePort!.listen((data) {
//       if (data is Map) {
//         // Update UI with data from foreground service
//         setState(() {
//           _batteryLevel = data['batteryLevel'] ?? _batteryLevel;
//           _isCharging = data['isCharging'] ?? _isCharging;
//           _isAlarmPlaying = data['isAlarmPlaying'] ?? _isAlarmPlaying;
//           _alarmHasTriggered = data['alarmHasTriggered'] ?? _alarmHasTriggered;
//         });
//       }
//     });
//   }
//
//   Future<void> _initializeNotifications() async {
//     _notifications = FlutterLocalNotificationsPlugin();
//
//     const AndroidInitializationSettings androidSettings =
//     AndroidInitializationSettings('@mipmap/ic_launcher');
//
//     const InitializationSettings initSettings = InitializationSettings(
//       android: androidSettings,
//     );
//
//     await _notifications.initialize(
//       initSettings,
//       onDidReceiveNotificationResponse: _onNotificationTapped,
//     );
//   }
//
//   void _onNotificationTapped(NotificationResponse response) {
//     if (response.actionId == 'stop_alarm') {
//       _stopAlarm();
//       MyTaskHandler.stopAlarmFromOutside();
//     }
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     super.didChangeAppLifecycleState(state);
//
//     if (state == AppLifecycleState.paused ||
//         state == AppLifecycleState.inactive) {
//       // App going to background - start foreground service if charging
//       if (_isCharging) {
//         _startForegroundService();
//       }
//     } else if (state == AppLifecycleState.resumed) {
//       // App coming to foreground - we can keep foreground service running
//       // Just cancel the alarm notification since user is back in app
//       _notifications.cancel(1);
//     }
//   }
//
//   Future<void> _startForegroundService() async {
//     if (_foregroundServiceRunning) return;
//
//     try {
//       await FlutterForegroundTask.startService(
//         notificationTitle: 'Battery Monitor Active',
//         notificationText: 'Monitoring battery while charging...',
//         callback: startCallback,
//       );
//
//       setState(() {
//         _foregroundServiceRunning = true;
//       });
//
//       log("Foreground service started successfully");
//     } catch (e) {
//       log("Error starting foreground service: $e");
//     }
//   }
//
//   Future<void> _stopForegroundService() async {
//     if (!_foregroundServiceRunning) return;
//
//     await FlutterForegroundTask.stopService();
//     setState(() {
//       _foregroundServiceRunning = false;
//     });
//   }
//
//   Future<void> _requestPermissions() async {
//     await Permission.audio.request();
//     await Permission.storage.request();
//
//     if (Platform.isAndroid) {
//       await Permission.notification.request();
//       await Permission.ignoreBatteryOptimizations.request();
//       // Request foreground service permission
//       await Permission.systemAlertWindow.request();
//     }
//   }
//
//   Future<void> _loadSettings() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _threshold = prefs.getInt('threshold') ?? 20;
//       _customAlarmPath = prefs.getString('custom_alarm_path');
//       _selectedAlarmName = prefs.getString('alarm_name') ?? "Default Alarm";
//     });
//   }
//
//   Future<void> _saveSettings() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setInt('threshold', _threshold);
//     if (_customAlarmPath != null) {
//       await prefs.setString('custom_alarm_path', _customAlarmPath!);
//       await prefs.setString('alarm_name', _selectedAlarmName);
//     }
//   }
//
//   Future<void> _checkInitialState() async {
//     await Future.delayed(const Duration(milliseconds: 500));
//     try {
//       int level = await _battery.batteryLevel;
//       BatteryState state = await _battery.batteryState;
//
//       setState(() {
//         _batteryLevel = level;
//         _isCharging = state == BatteryState.charging;
//       });
//
//       // Reset alarm trigger state and check conditions immediately
//       if (_isCharging) {
//         _alarmHasTriggered = false;
//         _checkAlarmConditions(level);
//       }
//     } catch (e) {
//       print('Error checking initial state: $e');
//     }
//   }
//
//   void _listenToBatteryState() {
//     _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
//       bool wasCharging = _isCharging;
//
//       setState(() {
//         _isCharging = state == BatteryState.charging;
//       });
//
//       // Start foreground service and reset alarm state when charging begins
//       if (!wasCharging && _isCharging) {
//         _alarmHasTriggered = false; // Reset alarm trigger state for new charge session
//         await _startForegroundService();
//         // Check if we should trigger alarm immediately
//         _checkAlarmConditions(_batteryLevel);
//       }
//       // Stop alarm and optionally stop service when charging stops
//       else if (wasCharging && !_isCharging) {
//         if (_isAlarmPlaying) {
//           _stopAlarm();
//         }
//         _alarmHasTriggered = false; // Reset for next charge session
//         await _stopForegroundService();
//       }
//     });
//   }
//
//   void _startMonitoring() {
//     _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
//       try {
//         int level = await _battery.batteryLevel;
//         BatteryState state = await _battery.batteryState;
//
//         setState(() {
//           _batteryLevel = level;
//           _isCharging = state == BatteryState.charging;
//         });
//
//         // Only check alarm conditions if charging
//         if (_isCharging) {
//           _checkAlarmConditions(level);
//         }
//       } catch (e) {
//         print('Error monitoring battery: $e');
//       }
//     });
//   }
//
//   void _checkAlarmConditions(int level) {
//     // Only trigger alarm if:
//     // 1. Device is charging
//     // 2. Battery level reached or exceeded threshold
//     // 3. Alarm hasn't already been triggered for this charge session
//     // 4. Alarm is not currently playing
//     if (_isCharging && level >= _threshold && !_alarmHasTriggered && !_isAlarmPlaying) {
//       _playAlarm();
//     }
//   }
//
//   Future<void> _playAlarm() async {
//     if (_isAlarmPlaying) return;
//
//     setState(() {
//       _isAlarmPlaying = true;
//       _alarmHasTriggered = true; // Mark that alarm has triggered for this charge session
//     });
//
//     try {
//       await _audioPlayer.setAudioContext(AudioContext(
//         android: AudioContextAndroid(
//           isSpeakerphoneOn: true,
//           stayAwake: true,
//           contentType: AndroidContentType.music,
//           usageType: AndroidUsageType.alarm,
//           audioFocus: AndroidAudioFocus.gain,
//         ),
//       ));
//
//       if (_customAlarmPath != null && File(_customAlarmPath!).existsSync()) {
//         await _audioPlayer.play(DeviceFileSource(_customAlarmPath!));
//       } else {
//         await _audioPlayer.play(AssetSource("sounds/alarm.mp3"));
//       }
//
//       await _audioPlayer.setReleaseMode(ReleaseMode.loop);
//       HapticFeedback.vibrate();
//
//     } catch (e) {
//       print('Error playing alarm: $e');
//       setState(() {
//         _isAlarmPlaying = false;
//         _alarmHasTriggered = false; // Reset if there was an error
//       });
//     }
//   }
//
//   Future<void> _stopAlarm() async {
//     setState(() {
//       _isAlarmPlaying = false;
//     });
//     await _audioPlayer.stop();
//     await _notifications.cancel(1);
//     // Note: We don't reset _alarmHasTriggered here because we want to prevent
//     // the alarm from retriggering until the next charge session
//   }
//
//   Future<void> _selectCustomAlarm() async {
//     try {
//       FilePickerResult? result = await FilePicker.platform.pickFiles(
//         type: FileType.audio,
//         allowMultiple: false,
//       );
//
//       if (result != null && result.files.single.path != null) {
//         setState(() {
//           _customAlarmPath = result.files.single.path;
//           _selectedAlarmName = result.files.single.name;
//         });
//         await _saveSettings();
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Custom alarm selected: $_selectedAlarmName')),
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Error selecting alarm: $e')),
//       );
//     }
//   }
//
//   Future<void> _testAlarm() async {
//     if (_isAlarmPlaying) {
//       await _stopAlarm();
//     } else {
//       // For testing, we don't want to set _alarmHasTriggered
//       bool tempAlarmTriggered = _alarmHasTriggered;
//       await _playAlarm();
//       _alarmHasTriggered = tempAlarmTriggered; // Restore the original state
//     }
//   }
//
//   Future<void> _checkConditionsNow() async {
//     try {
//       int level = await _battery.batteryLevel;
//       BatteryState state = await _battery.batteryState;
//
//       setState(() {
//         _batteryLevel = level;
//         _isCharging = state == BatteryState.charging;
//       });
//
//       if (_isCharging && level >= _threshold) {
//         if (!_alarmHasTriggered && !_isAlarmPlaying) {
//           _playAlarm();
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Conditions met! Alarm started.')),
//           );
//         } else if (_alarmHasTriggered) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Conditions met, but alarm already triggered for this charge session.')),
//           );
//         } else {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Alarm already playing.')),
//           );
//         }
//       } else {
//         String message = '';
//         if (level < _threshold) message += 'Battery ($level%) below threshold ($_threshold%). ';
//         if (!_isCharging) message += 'Device not charging. ';
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text(message.isEmpty ? 'Unknown condition' : message)),
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Error checking conditions: $e')),
//       );
//     }
//   }
//
//   Color _getBatteryColor() {
//     if (_batteryLevel > 50) return Colors.green;
//     if (_batteryLevel > 20) return Colors.orange;
//     return Colors.red;
//   }
//
//   IconData _getBatteryIcon() {
//     if (_isCharging) return Icons.battery_charging_full;
//     if (_batteryLevel > 90) return Icons.battery_full;
//     if (_batteryLevel > 60) return Icons.battery_5_bar;
//     if (_batteryLevel > 30) return Icons.battery_3_bar;
//     if (_batteryLevel > 15) return Icons.battery_2_bar;
//     return Icons.battery_1_bar;
//   }
//
//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _timer?.cancel();
//     _batteryStateSubscription?.cancel();
//     _audioPlayer.dispose();
//     _receivePort?.close();
//     _stopForegroundService();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Battery Alarm"),
//         backgroundColor: Colors.blue,
//         foregroundColor: Colors.white,
//         actions: [
//           IconButton(
//             icon: Icon(_isAlarmPlaying ? Icons.volume_off : Icons.volume_up),
//             onPressed: _isAlarmPlaying ? _stopAlarm : null,
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: SingleChildScrollView(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               // Service status
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: _foregroundServiceRunning ? Colors.green[100] : Colors.grey[100],
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(
//                     color: _foregroundServiceRunning ? Colors.green : Colors.grey,
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     Icon(
//                       _foregroundServiceRunning ? Icons.check_circle : Icons.info,
//                       color: _foregroundServiceRunning ? Colors.green : Colors.grey[600],
//                     ),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _foregroundServiceRunning
//                             ? "Background service active - audio will play even when app is closed"
//                             : "Background service inactive - plug in charger to activate",
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: _foregroundServiceRunning ? Colors.green[800] : Colors.grey[600],
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//
//               const SizedBox(height: 20),
//
//               // Battery Status Section
//               Container(
//                 padding: const EdgeInsets.all(20),
//                 decoration: BoxDecoration(
//                   color: _getBatteryColor().withValues(alpha: 0.1),
//                   borderRadius: BorderRadius.circular(15),
//                   border: Border.all(color: _getBatteryColor(), width: 2),
//                 ),
//                 child: Column(
//                   children: [
//                     Icon(
//                       _getBatteryIcon(),
//                       size: 80,
//                       color: _getBatteryColor(),
//                     ),
//                     const SizedBox(height: 10),
//                     Text(
//                       "$_batteryLevel%",
//                       style: TextStyle(
//                         fontSize: 32,
//                         fontWeight: FontWeight.bold,
//                         color: _getBatteryColor(),
//                       ),
//                     ),
//                     Text(
//                       _isCharging ? "Charging" : "Not Charging",
//                       style: TextStyle(
//                         fontSize: 16,
//                         color: _isCharging ? Colors.green : Colors.grey[600],
//                       ),
//                     ),
//                     if (_isCharging && _alarmHasTriggered)
//                       Text(
//                         "Alarm already triggered this session",
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: Colors.orange[700],
//                           fontStyle: FontStyle.italic,
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//
//               const SizedBox(height: 30),
//
//               // Threshold Setting Section
//               Container(
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: Colors.grey[100],
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 child: Column(
//                   children: [
//                     Text(
//                       "Alarm Threshold: $_threshold%",
//                       style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
//                     ),
//                     Slider(
//                       min: 1,
//                       max: 99,
//                       divisions: 98,
//                       value: _threshold.toDouble(),
//                       onChanged: (value) {
//                         setState(() {
//                           _threshold = value.toInt();
//                         });
//                         _saveSettings();
//                       },
//                       activeColor: Colors.blue,
//                     ),
//                     Text(
//                       "Alarm will trigger when battery reaches $_threshold% while charging",
//                       style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                       textAlign: TextAlign.center,
//                     ),
//                   ],
//                 ),
//               ),
//
//               const SizedBox(height: 20),
//
//               // Alarm Sound Section
//               Container(
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: Colors.grey[100],
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 child: Column(
//                   children: [
//                     Text(
//                       "Alarm Sound",
//                       style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
//                     ),
//                     const SizedBox(height: 10),
//                     Text(
//                       _selectedAlarmName,
//                       style: TextStyle(fontSize: 14, color: Colors.grey[700]),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 10),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                       children: [
//                         ElevatedButton.icon(
//                           onPressed: _selectCustomAlarm,
//                           icon: const Icon(Icons.music_note, size: 18),
//                           label: const Text("Select Audio"),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.blue,
//                             foregroundColor: Colors.white,
//                           ),
//                         ),
//                         ElevatedButton.icon(
//                           onPressed: _testAlarm,
//                           icon: Icon(_isAlarmPlaying ? Icons.stop : Icons.play_arrow, size: 18),
//                           label: Text(_isAlarmPlaying ? "Stop Test" : "Test Alarm"),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: _isAlarmPlaying ? Colors.red : Colors.green,
//                             foregroundColor: Colors.white,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 10),
//                     ElevatedButton.icon(
//                       onPressed: _checkConditionsNow,
//                       icon: const Icon(Icons.check_circle, size: 18),
//                       label: const Text("Check Conditions Now"),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.orange,
//                         foregroundColor: Colors.white,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//
//               const SizedBox(height: 30),
//
//               // Status and Control Section
//               if (_isAlarmPlaying)
//                 Container(
//                   padding: const EdgeInsets.all(16),
//                   decoration: BoxDecoration(
//                     color: Colors.red[100],
//                     borderRadius: BorderRadius.circular(10),
//                     border: Border.all(color: Colors.red, width: 2),
//                   ),
//                   child: Column(
//                     children: [
//                       const Icon(Icons.warning, color: Colors.red, size: 40),
//                       const SizedBox(height: 10),
//                       const Text(
//                         "⚠️ ALARM ACTIVE ⚠️",
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.red,
//                         ),
//                       ),
//                       const SizedBox(height: 5),
//                       const Text(
//                         "Battery reached safe level!\nYour device is charged to the threshold.\nAlarm will only stop when you:\n• Press 'Stop Alarm' button\n• Remove charger from device\n• Tap the notification",
//                         textAlign: TextAlign.center,
//                         style: TextStyle(fontSize: 14),
//                       ),
//                       const SizedBox(height: 15),
//                       ElevatedButton.icon(
//                         onPressed: _stopAlarm,
//                         icon: const Icon(Icons.stop),
//                         label: const Text("Stop Alarm"),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.red,
//                           foregroundColor: Colors.white,
//                           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//
//               const SizedBox(height: 20),
//
//               // Info Section
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: Colors.blue[50],
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Column(
//                   children: [
//                     const Icon(Icons.info, color: Colors.blue, size: 24),
//                     const SizedBox(height: 8),
//                     Text(
//                       "Enhanced Background Support:\n• Uses notifications for background alerts\n• Requests battery optimization bypass\n• Continuous monitoring while charging\n• Alarm triggers once per charge session\n• Unplug and plug charger to reset alarm\n\nFor best results: Allow all permissions and disable battery optimization for this app in system settings.",
//                       style: TextStyle(fontSize: 12, color: Colors.blue[800]),
//                       textAlign: TextAlign.center,
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
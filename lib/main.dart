import 'package:battery_alarm/battery_alarm_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'alarm_channel',
      channelName: 'Battery Alarm',
      channelDescription: 'Battery level alarm is running',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 1000, // Task callback interval in milliseconds
      isOnceEvent: false,
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ), iosNotificationOptions: IOSNotificationOptions(),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery alarm',
      home:  BatteryAlarmScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}


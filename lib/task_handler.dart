import 'dart:async';

import 'package:battery_alarm/constants.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';
  static const String checkForThresholdCommand = 'thresholdCheck';

  final battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  int _count = 0;

  void _incrementCount() {
    _count++;
    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)',
      notificationText: 'count: $_count',
    );
    FlutterForegroundTask.sendDataToMain(_count);
  }


  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    _incrementCount();
    listenToBatteryState();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _incrementCount();
    // no need to re-subscribe each time
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('onDestroy(isTimeout: $isTimeout)');
    await _batteryStateSubscription?.cancel();
    _batteryStateSubscription = null;
  }

  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
    if (data == incrementCountCommand) {
      _incrementCount();
    }
    if (data == checkForThresholdCommand) {
      // optional: manually send current charging state
      FlutterForegroundTask.sendDataToMain(isCharging);
    }
  }
}
  // Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed: $id');
  }

  // Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    print('onNotificationPressed');
  }

  // Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    print('onNotificationDismissed');
  }


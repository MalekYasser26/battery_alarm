import 'dart:async';

import 'package:battery_alarm/constants.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';
  static const String checkForThresholdCommand = 'thresholdCheck';
  static const String requestStatusFromTaskCommand = 'task_request_status';


  // Cache of the last battery info received from the main isolate

  // void _incrementCount() {
  //   _count++;
  //   FlutterForegroundTask.updateService(
  //     notificationTitle: 'Battery Alarm Active',
  //     notificationText: 'Count: $_count',
  //   );
  //   FlutterForegroundTask.sendDataToMain({'type': 'count', 'value': _count});
  // }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
   // _incrementCount();
    // Optionally ask the main isolate to send an initial battery status
    // The main isolate should listen for this and reply with battery data.
    FlutterForegroundTask.sendDataToMain({'type': 'task_started'});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called periodically per your ForegroundTaskOptions
  //  _incrementCount();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('onDestroy(isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');

    if (data is Map) {
      if (data.containsKey('charging') && data.containsKey('level')) {
        final charging = data['charging'] as bool? ?? false;
        final rawLevel = data['level'];
        final level = rawLevel is int ? rawLevel : (rawLevel is double ? rawLevel.round() : -1);


        FlutterForegroundTask.updateService(
          notificationTitle: 'Battery Alarm',
          notificationText: 'Charging: $charging · Level: $level%',
        );

        // Only trigger alarm logic in the task handler if needed
        // The main isolate should handle the primary alarm triggering
        if (charging && level >= chargingThreshold) {
          print('⚡ TASK: Charging & threshold reached at $level%');
          // Don't trigger alarm here - let main isolate handle it
        }
        return;
      }}}}

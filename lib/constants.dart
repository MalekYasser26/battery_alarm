import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
final battery = Battery();
StreamSubscription<BatteryState>? _batteryStateSubscription;
bool isCharging = false;
double chargingThreshold = 80.0;

void listenToBatteryState() {
  _batteryStateSubscription ??= battery.onBatteryStateChanged.listen((BatteryState state) {
    final wasCharging = isCharging;
    isCharging = state == BatteryState.charging;

    if (wasCharging != isCharging) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Hello MyTaskHandler :)',
        notificationText: 'Now charging: $isCharging',
      );
      FlutterForegroundTask.sendDataToMain(isCharging);
    }
  });
}

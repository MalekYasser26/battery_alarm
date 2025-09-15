import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmManager {
  static final AlarmManager _instance = AlarmManager._internal();
  factory AlarmManager() => _instance;
  AlarmManager._internal();

  AudioPlayer? _alarmPlayer;
  bool _isAlarmActive = false;
  bool _isServiceActive = false;

  bool get isAlarmActive => _isAlarmActive;
  bool get isServiceActive => _isServiceActive;

  void setServiceActive(bool active) {
    _isServiceActive = active;
    if (!active) {
      // When service stops, stop alarm and allow retriggering
      stopAlarm();
    }
    print("Service active: $_isServiceActive");
  }

  Future<void> startAlarm() async {
    if (_isAlarmActive || !_isServiceActive) return;

    const String audioKey = 'selected_audio_path';
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(audioKey);

    if (path != null && File(path).existsSync()) {
      _alarmPlayer = AudioPlayer();
      _isAlarmActive = true;

      // Set the player to loop
      await _alarmPlayer!.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer!.play(DeviceFileSource(path));

      print("🔔 Alarm started - looping audio");
    } else {
      print("⚠️ No valid audio file found for alarm");
    }
  }

  Future<void> stopAlarm() async {
    if (!_isAlarmActive || _alarmPlayer == null) return;

    await _alarmPlayer!.stop();
    await _alarmPlayer!.dispose();
    _alarmPlayer = null;
    _isAlarmActive = false;

    print("🔕 Alarm stopped");
  }

  Future<void> dispose() async {
    await stopAlarm();
  }
}

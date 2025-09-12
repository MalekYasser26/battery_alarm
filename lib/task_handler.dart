// import 'dart:io';
// import 'dart:isolate';
//
// import 'package:audioplayers/audioplayers.dart';
// import 'package:flutter_foreground_task/flutter_foreground_task.dart';
//
// class AlarmTaskHandler extends TaskHandler {
//   final AudioPlayer _audioPlayer = AudioPlayer();
//
//   @override
//   Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
//     // Set audio attributes for alarm
//     await _audioPlayer.setAudioContext(AudioContext(
//       android: AudioContextAndroid(
//         isSpeakerphoneOn: true,
//         stayAwake: true,
//         contentType: AndroidContentType.music,
//         usageType: AndroidUsageType.alarm,
//         audioFocus: AndroidAudioFocus.gain,
//       ),
//     ));
//
//
//   @override
//   Future<void> onDestroy(bool isStopped) async {
//     await _audioPlayer.stop();
//   }
//
//   @override
//   Future<void> onButtonPressed(String id) async {
//     if (id == 'stop') {
//       await _audioPlayer.stop();
//       FlutterForegroundTask.stopService();
//     }
//   }
//
//   @override
//   Future<void> onNotificationPressed() async {
//     // Handle notification press if necessary
//   }
//
//   @override
//   Future<void> onEvent(DateTime timestamp, SendPort? sendPort) {
//     throw UnimplementedError();
//   }
// }

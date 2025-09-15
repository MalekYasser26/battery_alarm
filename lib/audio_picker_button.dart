import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

class AudioPickerButton extends StatefulWidget {
  const AudioPickerButton({Key? key}) : super(key: key);

  @override
  State<AudioPickerButton> createState() => _AudioPickerButtonState();
}

class _AudioPickerButtonState extends State<AudioPickerButton> {
  static const String _audioKey = 'selected_audio_path';
  String? _audioPath;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAudio();
  }

  Future<void> _loadSavedAudio() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _audioPath = prefs.getString(_audioKey);
    });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_audioKey, path);

      setState(() {
        _audioPath = path;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_audioPath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      await _audioPlayer.play(DeviceFileSource(_audioPath!));
      setState(() {
        _isPlaying = true;
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _audioPath != null
        ? File(_audioPath!).uri.pathSegments.last
        : "No audio selected";

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _pickAudio,
          icon: const Icon(Icons.music_note,color: Colors.green,),
          label: Text(
            "Pick Alarm Audio",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Selected Audio: $fileName",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        if (_audioPath != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _togglePlayPause,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,color: Colors.green,),
            label: Text(_isPlaying ? "Pause" : "Play", style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.green,
            ),),
          ),
        ],
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _studioBg = Color(0xFF090B12);
const _studioPanel = Color(0xFF151925);
const _studioPurple = Color(0xFF7C5CFF);
const _studioCyan = Color(0xFF39D8E8);

class MusicTrack {
  MusicTrack({required this.path, required this.kind, double gain = 0.8, bool muted = false})
      : gain = gain, muted = muted, id = DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
  final String path;
  String kind;
  double gain;
  bool muted;
  String get name => path.split(Platform.pathSeparator).last;
}

class MusicStudioPage extends StatefulWidget {
  const MusicStudioPage({super.key});
  @override
  State<MusicStudioPage> createState() => _MusicStudioPageState();
}

class _MusicStudioPageState extends State<MusicStudioPage> {
  final List<MusicTrack> tracks = [];
  bool exporting = false;
  double masterGain = 1.0;
  int bpm = 110;
  String effect = 'None';
  String status = 'Import audio, vocals, or beats to start your session.';
  String quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  void message(String value) {
    if (mounted) setState(() => status = value);
  }

  Future<void> addTracks(String kind) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      final paths = result.files.map((f) => f.path).whereType<String>()
          .where((p) => File(p).existsSync()).toList();
      if (paths.isEmpty) {
        message('No readable audio files were selected.');
        return;
      }
      setState(() {
        tracks.addAll(paths.map((p) => MusicTrack(path: p, kind: kind)));
        status = '${paths.length} ${kind.toLowerCase()} track(s) added.';
      });
    } catch (e) {
      message('Could not import audio: $e');
    }
  }

  Future<void> exportMix() async {
    if (exporting) return;
    final active = tracks.where((t) => !t.muted && t.gain > 0 && File(t.path).existsSync()).toList();
    if (active.isEmpty) {
      message('Add at least one unmuted audio track before exporting.');
      return;
    }
    setState(() { exporting = true; status = 'Mixing ${active.length} tracks…'; });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final output = '${dir.path}/NovaCut_Mix_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final inputs = <String>[];
      for (final track in active) {
        inputs.add('-i ${quote(track.path)}');
      }
      final filters = <String>[];
      for (var i = 0; i < active.length; i++) {
        filters.add('[$i:a]volume=${active[i].gain.toStringAsFixed(3)}[a$i]');
      }
      final labels = List.generate(active.length, (i) => '[a$i]').join();
      final fx = effect == 'Echo' ? ',aecho=0.8:0.75:70:0.25' : effect == 'Reverb' ? ',aecho=0.8:0.9:80|160:0.25|0.15' : effect == 'Warmth' ? ',equalizer=f=180:t=q:w=1:g=2,equalizer=f=7000:t=q:w=1:g=-1.5' : '';
      filters.add('${labels}amix=inputs=${active.length}:duration=longest:dropout_transition=0:normalize=0,volume=${masterGain.toStringAsFixed(3)}$fx[aout]');
      final command = '-y ${inputs.join(' ')} -filter_complex "${filters.join(';')}" '
          '-map "[aout]" -c:a libmp3lame -b:a 192k -ar 44100 ${quote(output)}';
      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();
      if (code == null || code.getValue() != 0 || !File(output).existsSync()) {
        throw Exception(await session.getOutput() ?? 'Audio rendering failed ($code)');
      }
      if (!mounted) return;
      setState(() => status = 'Mix exported: ${output.split(Platform.pathSeparator).last}');
      await Share.shareXFiles([XFile(output)], text: 'Music mix exported from NovaCut Music Studio');
    } catch (e) {
      message('Mix export failed: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> saveSession() async {
    try {
      final data = {
        'version': 1, 'bpm': bpm, 'masterGain': masterGain, 'effect': effect,
        'tracks': tracks.map((t) => {'path': t.path, 'kind': t.kind, 'gain': t.gain, 'muted': t.muted}).toList(),
      };
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Music Studio session', fileName: 'NovaCut_music_session.json',
        type: FileType.custom, allowedExtensions: ['json']);
      if (path == null) return;
      await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      message('Session saved. Keep your original audio files in place.');
    } catch (e) { message('Could not save session: $e'); }
  }

  Future<void> loadSession() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = picked?.files.single.path;
      if (path == null) return;
      final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final incoming = (data['tracks'] as List).map((raw) {
        final item = Map<String, dynamic>.from(raw);
        return MusicTrack(path: item['path'] as String, kind: item['kind'] as String,
          gain: (item['gain'] as num?)?.toDouble() ?? .8, muted: item['muted'] as bool? ?? false);
      }).where((t) => File(t.path).existsSync()).toList();
      setState(() {
        tracks..clear()..addAll(incoming);
        bpm = (data['bpm'] as num?)?.toInt() ?? 110;
        masterGain = (data['masterGain'] as num?)?.toDouble() ?? 1;
        effect = data['effect'] as String? ?? 'None';
        status = 'Session loaded: ${tracks.length} available tracks.';
      });
    } catch (e) { message('Could not load session: $e'); }
  }

  Widget studioButton(String label, IconData icon, VoidCallback onTap, {bool disabled = false}) {
    return FilledButton.tonalIcon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _studioBg,
      appBar: AppBar(
        title: const Text('Music Studio', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _studioBg,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_studioPurple.withValues(alpha: .28), _studioCyan.withValues(alpha: .10)]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.graphic_eq, color: _studioCyan, size: 30),
                  SizedBox(width: 10),
                  Expanded(child: Text('MULTITRACK WORKSPACE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
                ]),
                const SizedBox(height: 8),
                const Text('Build your song from vocals, drums, instrumentals and beats. Adjust each track, mute or remove layers, then export a mixed MP3.',
                  style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  studioButton('Add beat', Icons.album_outlined, () => addTracks('Beat')),
                  studioButton('Add vocals', Icons.mic_none, () => addTracks('Vocals')),
                  studioButton('Add instrument', Icons.piano, () => addTracks('Instrument')),
                  studioButton('Add audio', Icons.library_music, () => addTracks('Audio')),
                  studioButton('Load session', Icons.folder_open, loadSession),
                  studioButton('Save session', Icons.save_outlined, saveSession),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                const Text('TRACKS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const Spacer(),
                Text('${tracks.length} total', style: const TextStyle(color: Colors.white60)),
                IconButton(
                  tooltip: 'Clear all tracks',
                  onPressed: tracks.isEmpty ? null : () => setState(() { tracks.clear(); status = 'Session cleared.'; }),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ]),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.multitrack_audio, size: 64, color: _studioCyan),
                      SizedBox(height: 12),
                      Text('Your session is empty'),
                      SizedBox(height: 4),
                      Text('Add a beat or vocal track to begin.', style: TextStyle(color: Colors.white54)),
                    ]))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: tracks.length,
                      onReorder: (oldIndex, newIndex) { setState(() { if (newIndex > oldIndex) newIndex--; final item = tracks.removeAt(oldIndex); tracks.insert(newIndex, item); }); },
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return Container(
                          key: ValueKey(track.id),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _studioPanel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: track.muted ? Colors.white10 : _studioCyan.withValues(alpha: .45)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(color: _studioPurple.withValues(alpha: .22), borderRadius: BorderRadius.circular(10)),
                                child: Icon(track.kind == 'Vocals' ? Icons.mic : track.kind == 'Beat' ? Icons.album : Icons.graphic_eq, color: _studioCyan),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(track.kind.toUpperCase(), style: const TextStyle(fontSize: 10, color: _studioCyan, letterSpacing: 1)),
                              ])),
                              const Icon(Icons.drag_handle, color: Colors.white38),
                              IconButton(tooltip: track.muted ? 'Unmute track' : 'Mute track',
                                onPressed: () => setState(() => track.muted = !track.muted),
                                icon: Icon(track.muted ? Icons.volume_off : Icons.volume_up)),
                              IconButton(tooltip: 'Remove track', onPressed: () => setState(() {
                                tracks.removeAt(index);
                                status = 'Track removed.';
                              }), icon: const Icon(Icons.close)),
                            ]),
                            Row(children: [
                              const Icon(Icons.volume_down, size: 17, color: Colors.white60),
                              Expanded(child: Slider(
                                value: track.gain, min: 0, max: 1.5, divisions: 30,
                                onChanged: (v) => setState(() => track.gain = v),
                              )),
                              SizedBox(width: 46, child: Text('${(track.gain * 100).round()}%', textAlign: TextAlign.end,
                                style: const TextStyle(color: _studioCyan, fontSize: 12))),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: const BoxDecoration(color: _studioPanel, border: Border(top: BorderSide(color: Colors.white12))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (exporting) const LinearProgressIndicator(minHeight: 3),
                Row(children: [
                  const Text('BPM', style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(onPressed: bpm <= 40 ? null : () => setState(() => bpm--), icon: const Icon(Icons.remove_circle_outline)),
                  Text('$bpm', style: const TextStyle(color: _studioCyan, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: bpm >= 240 ? null : () => setState(() => bpm++), icon: const Icon(Icons.add_circle_outline)),
                  const Spacer(), const Text('Effect'), const SizedBox(width: 8),
                  DropdownButton<String>(value: effect, items: const ['None','Echo','Reverb','Warmth'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => effect = v ?? effect)),
                ]),
                Row(children: [const Icon(Icons.tune, size: 18), const SizedBox(width: 8), const Text('Master'),
                  Expanded(child: Slider(value: masterGain, min: 0, max: 1.5, divisions: 30, onChanged: (v) => setState(() => masterGain = v))),
                  Text('${(masterGain * 100).round()}%', style: const TextStyle(color: _studioCyan)),
                ]),
                Text(status, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: exporting || tracks.isEmpty ? null : exportMix,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(exporting ? 'Mixing tracks…' : 'Export mixed MP3'),
                  style: FilledButton.styleFrom(backgroundColor: _studioPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 4),
                const Text('Includes multitrack mix, gain, mute, track ordering, BPM notes, basic export effects and session save/load. Live recording, instrument synthesis and real-time playback still require a dedicated audio engine.',
                  style: TextStyle(fontSize: 10, color: Colors.white38)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

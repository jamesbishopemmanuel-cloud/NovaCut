import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

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
  MusicTrack({required this.path, required this.kind, double gain = 0.8, bool muted = false, this.kieTaskId, this.kieAudioId})
      : gain = gain, muted = muted, id = DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
  final String path;
  String kind;
  double gain;
  bool muted;
  final String? kieTaskId;
  final String? kieAudioId;
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
  bool aiBusy = false;
  bool recording = false;
  final AudioRecorder recorder = AudioRecorder();
  final AudioPlayer previewPlayer = AudioPlayer();
  String? previewingTrackId;
  final Set<int> drumSteps = <int>{0, 4, 8, 12};
  final Set<int> hatSteps = <int>{0, 2, 4, 6, 8, 10, 12, 14};
  final TextEditingController promptController = TextEditingController();
  final TextEditingController titleController = TextEditingController(text: 'My New Song');
  final TextEditingController styleController = TextEditingController(text: 'Afrobeats, Afro-pop, Nigerian Pidgin, catchy melody, punchy drums');
  bool instrumentalOnly = true;
  String? lastKieTaskId;
  String? lastKieAudioId;
  List<Map<String, dynamic>> generatedVersions = [];
  double masterGain = 1.0;
  int bpm = 110;
  String effect = 'None';
  String status = 'Import audio, vocals, or beats to start your session.';
  String quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  void message(String value) {
    if (mounted) setState(() => status = value);
  }


  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  Future<Map<String, dynamic>> _kieRequest(Map<String, dynamic> body) async {
    if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
      throw Exception('AI music is not configured. Build with SUPABASE_URL and SUPABASE_ANON_KEY, deploy supabase/functions/kie-music, and set KIE_API_KEY as a server secret.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final uri = Uri.parse('${_supabaseUrl.replaceAll(RegExp(r'/+
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

  Future<void> startRecording() async {
    try {
      if (!await recorder.hasPermission()) { message('Microphone permission is required to record vocals.'); return; }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/NovaCut_Vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 192000, sampleRate: 44100), path: path);
      if (mounted) setState(() { recording = true; status = 'Recording vocals… tap Stop recording when finished.'; });
    } catch (e) { message('Could not start microphone recording: $e'); }
  }

  Future<void> stopRecording() async {
    try {
      final path = await recorder.stop();
      if (mounted) setState(() {
        recording = false;
        if (path != null && File(path).existsSync()) tracks.add(MusicTrack(path: path, kind: 'Vocals'));
        status = path == null ? 'Recording stopped.' : 'Vocal recording added to your tracks.';
      });
    } catch (e) { message('Could not save recording: $e'); }
  }

  Future<void> previewTrack(MusicTrack track) async {
    try {
      if (previewingTrackId == track.id && previewPlayer.playing) { await previewPlayer.pause(); if (mounted) setState(() => status = 'Preview paused.'); return; }
      await previewPlayer.setFilePath(track.path);
      if (mounted) setState(() => previewingTrackId = track.id);
      await previewPlayer.play();
      if (mounted) setState(() => status = 'Preview finished/paused: ${track.name}');
    } catch (e) { message('Could not preview audio: $e'); }
  }

  Future<void> createDrumBeat() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      const sampleRate = 44100;
      final bpmValue = bpm.toDouble();
      final secondsPerBeat = 60.0 / bpmValue;
      final sampleCount = (16 * secondsPerBeat * sampleRate).round();
      final pcm = Int16List(sampleCount);
      final random = math.Random(7);
      for (var step = 0; step < 16; step++) {
        final start = (step * secondsPerBeat * sampleRate).round();
        if (step % 4 == 0) {
          final length = math.min((sampleRate * .22).round(), sampleCount - start);
          for (var j = 0; j < length; j++) {
            final t = j / sampleRate; final freq = 105 * math.exp(-t * 14) + 42;
            final mixed = pcm[start + j] + (math.sin(2 * math.pi * freq * t) * math.exp(-t * 19) * .85 * 32767).round();
            pcm[start + j] = mixed.clamp(-32768, 32767).toInt();
          }
        }
        if (drumSteps.contains(step)) {
          final length = math.min((sampleRate * .13).round(), sampleCount - start);
          for (var j = 0; j < length; j++) {
            final t = j / sampleRate;
            final mixed = pcm[start + j] + (math.sin(2 * math.pi * 185 * t) * math.exp(-t * 23) * .35 * 32767).round();
            pcm[start + j] = mixed.clamp(-32768, 32767).toInt();
          }
        }
        if (hatSteps.contains(step)) {
          final hStart = start + (sampleRate * .02).round();
          final length = math.min((sampleRate * .045).round(), sampleCount - hStart);
          if (length > 0) for (var j = 0; j < length; j++) {
            final value = (random.nextDouble() * 2 - 1) * math.exp(-(j / sampleRate) * 65) * .16;
            final mixed = pcm[hStart + j] + (value * 32767).round();
            pcm[hStart + j] = mixed.clamp(-32768, 32767).toInt();
          }
        }
      }
      final out = '${dir.path}/NovaCut_DrumLoop_${DateTime.now().millisecondsSinceEpoch}.wav';
      final bytes = BytesBuilder();
      void ascii(String value) => bytes.add(value.codeUnits);
      void u32(int value) { final d = ByteData(4)..setUint32(0, value, Endian.little); bytes.add(d.buffer.asUint8List()); }
      void u16(int value) { final d = ByteData(2)..setUint16(0, value, Endian.little); bytes.add(d.buffer.asUint8List()); }
      ascii('RIFF'); u32(36 + pcm.length * 2); ascii('WAVE'); ascii('fmt '); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16); ascii('data'); u32(pcm.length * 2);
      final pcmBytes = Uint8List(pcm.length * 2); final data = ByteData.sublistView(pcmBytes);
      for (var i = 0; i < pcm.length; i++) { data.setInt16(i * 2, pcm[i], Endian.little); }
      bytes.add(pcmBytes); await File(out).writeAsBytes(bytes.takeBytes(), flush: true);
      if (mounted) setState(() { tracks.add(MusicTrack(path: out, kind: 'Beat')); status = 'Generated a 4-bar drum loop at 110 BPM. Change the 16-step pattern to shape another loop.'; });
    } catch (e) { message('Beat maker failed: $e'); }
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
      final fx = effect == 'Echo' ? ',aecho=0.8:0.75:70:0.25' : effect == 'Reverb' ? ',aecho=0.8:0.9:80|160:0.25|0.15' : effect == 'Warmth' ? ',equalizer=f=180:t=q:w=1:g=2,equalizer=f=7000:t=q:w=1:g=-1.5' : effect == 'Bass' ? ',equalizer=f=100:t=q:w=1:g=4' : effect == 'Bright' ? ',equalizer=f=6000:t=q:w=1:g=3' : effect == 'Compressor' ? ',acompressor=threshold=0.125:ratio=3:attack=20:release=250' : effect == 'Normalize' ? ',loudnorm=I=-16:TP=-1.5:LRA=11' : '';
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
        'tracks': tracks.map((t) => {'path': t.path, 'kind': t.kind, 'gain': t.gain, 'muted': t.muted, 'kieTaskId': t.kieTaskId, 'kieAudioId': t.kieAudioId}).toList(),
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
          gain: (item['gain'] as num?)?.toDouble() ?? .8, muted: item['muted'] as bool? ?? false, kieTaskId: item['kieTaskId'] as String?, kieAudioId: item['kieAudioId'] as String?);
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
  void dispose() { recorder.dispose(); previewPlayer.dispose(); promptController.dispose(); titleController.dispose(); styleController.dispose(); super.dispose(); }

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
                  studioButton(recording ? 'Stop recording' : 'Record vocals', recording ? Icons.stop_circle : Icons.mic, recording ? stopRecording : startRecording, disabled: exporting),
                  studioButton('Make drum loop', Icons.grid_view, createDrumBeat, disabled: exporting),
                  studioButton('Cut beat', Icons.content_cut, () { if (tracks.isNotEmpty) cutTrack(tracks.last); else message('Add an audio track first.'); }),
                  studioButton('Load session', Icons.folder_open, loadSession),
                  studioButton('Save session', Icons.save_outlined, saveSession),
                ]),
              ]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _studioPanel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _studioPurple.withValues(alpha: .5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [Icon(Icons.auto_awesome, color: _studioCyan), SizedBox(width: 8), Text('KIE AI SONG CREATOR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7))]),
                const SizedBox(height: 8),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Song title', isDense: true, border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: promptController, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Describe the song or write lyrics', hintText: 'e.g. Create an original energetic Afrobeats song about chasing dreams…', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: styleController, decoration: const InputDecoration(labelText: 'Music style', border: OutlineInputBorder(), isDense: true)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Instrumental only (beat)', style: TextStyle(fontSize: 13)), value: instrumentalOnly, onChanged: aiBusy ? null : (v) => setState(() => instrumentalOnly = v)),
                FilledButton.icon(onPressed: aiBusy ? null : createAiSong, icon: const Icon(Icons.auto_awesome), label: Text(aiBusy ? 'Creating / processing…' : 'Create song with KIE AI')),
                OutlinedButton.icon(onPressed: aiBusy ? null : separateGeneratedAudio, icon: const Icon(Icons.graphic_eq), label: const Text('Extract beat / stems from generated song')),
                if (generatedVersions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('GENERATED AUDIO / EXTRACTED STEMS', style: TextStyle(fontSize: 11, color: _studioCyan, fontWeight: FontWeight.bold)),
                  ...generatedVersions.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      const Icon(Icons.audiotrack, size: 18, color: _studioCyan),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.value['title']?.toString() ?? 'Audio version', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      IconButton(tooltip: 'Add to editable tracks', onPressed: aiBusy ? null : () => addGeneratedVersion(entry.value), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  )),
                ],
                const Text('KIE generation and stem extraction use credits. You can cut any imported or generated track and keep the selected section as a separate editable track.', style: TextStyle(fontSize: 10, color: Colors.white54)),
              ]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _studioPanel, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.grid_view, color: _studioCyan), const SizedBox(width: 8), const Text('16-STEP DRUM PATTERN', style: TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('$bpm BPM', style: const TextStyle(color: _studioCyan))]),
                const SizedBox(height: 6), const Text('Kick / snare pattern', style: TextStyle(fontSize: 11, color: Colors.white60)),
                Wrap(spacing: 4, runSpacing: 4, children: List.generate(16, (i) => SizedBox(width: 30, height: 32, child: FilledButton(onPressed: () => setState(() { if (drumSteps.contains(i)) { drumSteps.remove(i); } else { drumSteps.add(i); } }), style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: drumSteps.contains(i) ? _studioPurple : Colors.white12), child: Text('${i + 1}', style: const TextStyle(fontSize: 10))))),
                const SizedBox(height: 6), const Text('Hi-hat pattern', style: TextStyle(fontSize: 11, color: Colors.white60)),
                Wrap(spacing: 4, runSpacing: 4, children: List.generate(16, (i) => SizedBox(width: 30, height: 32, child: FilledButton(onPressed: () => setState(() { if (hatSteps.contains(i)) { hatSteps.remove(i); } else { hatSteps.add(i); } }), style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: hatSteps.contains(i) ? _studioCyan.withValues(alpha: .7) : Colors.white12), child: Text('${i + 1}', style: const TextStyle(fontSize: 10))))),
                const SizedBox(height: 6), const Text('Generate a new 4-bar WAV after changing the pattern. Synthesized drum sounds are used; no sample pack is required.', style: TextStyle(fontSize: 10, color: Colors.white54)),
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
                              IconButton(tooltip: 'Preview track', onPressed: () => previewTrack(track), icon: Icon(previewingTrackId == track.id && previewPlayer.playing ? Icons.pause_circle : Icons.play_circle_outline, color: _studioCyan)),
                              const Icon(Icons.drag_handle, color: Colors.white38),
                              IconButton(tooltip: track.muted ? 'Unmute track' : 'Mute track',
                                onPressed: () => setState(() => track.muted = !track.muted),
                                icon: Icon(track.muted ? Icons.volume_off : Icons.volume_up)),
                              IconButton(tooltip: 'Cut this track', onPressed: () => cutTrack(track), icon: const Icon(Icons.content_cut)),
                              IconButton(tooltip: 'Remove track', onPressed: () => setState(() {
                                tracks.removeAt(index);
                                status = 'Track removed.';
                              }), icon: const Icon(Icons.close)),
                            ]),
                            SizedBox(height: 24, width: double.infinity, child: CustomPaint(painter: _TrackWaveformPainter(seed: track.path.hashCode, color: track.muted ? Colors.white24 : _studioCyan))),
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
                  DropdownButton<String>(value: effect, items: const ['None','Echo','Reverb','Warmth','Bass','Bright','Compressor','Normalize'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => effect = v ?? effect)),
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
                const Text('Includes mic recording, per-track preview, waveform-style lanes, a synthesized 16-step drum sequencer, beat cutting, KIE AI generation/stems, EQ-style tone shaping, compression, normalization, and MP3 mix export. The waveform is a visual guide rather than a decoded sample-accurate waveform; playback is per-track preview, not synchronized multitrack transport.',
                  style: TextStyle(fontSize: 10, color: Colors.white38)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
), '')}/functions/v1/kie-music');
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('apikey', _supabaseKey);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_supabaseKey');
      request.write(jsonEncode(body));
      final response = await request.close();
      final textBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(textBody);
      if (decoded is! Map<String, dynamic>) throw Exception('Unexpected AI server response.');
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['error'] != null) {
        throw Exception(decoded['error'] ?? decoded['message'] ?? 'AI server returned HTTP ${response.statusCode}');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _waitForKieTask(String taskId) async {
    for (var attempt = 0; attempt < 120; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final result = await _kieRequest({'action': 'status', 'taskId': taskId});
      final data = (result['data'] as Map?)?.cast<String, dynamic>() ?? result;
      final state = (data['state'] ?? data['status'] ?? '').toString().toLowerCase();
      if (state == 'success' || state == 'succeeded' || state == 'complete' || state == 'completed') return data;
      if (state == 'fail' || state == 'failed' || state == 'error') {
        throw Exception(data['failMsg'] ?? data['error'] ?? 'KIE music generation failed.');
      }
      if (mounted) message('KIE AI is creating your music… (${attempt + 1}/120)');
    }
    throw Exception('Music generation is taking too long. Check your KIE task later.');
  }

  List<Map<String, dynamic>> _extractKieVersions(Map<String, dynamic> data) {
    dynamic raw = data['resultJson'] ?? data['result_json'];
    if (raw is String) { try { raw = jsonDecode(raw); } catch (_) {} }
    final root = raw is Map ? raw : data;
    final resultObject = root is Map ? (root['resultObject'] ?? root['result_object']) : null;
    final urls = root is Map ? (root['resultUrls'] ?? root['result_urls']) : null;
    final versions = <Map<String, dynamic>>[];
    if (urls is List) {
      for (var i = 0; i < urls.length; i++) {
        final url = urls[i]?.toString() ?? '';
        if (url.startsWith('https://')) versions.add({'url': url, 'id': null, 'title': 'AI Song ${i + 1}'});
      }
    }
    if (resultObject is Map && resultObject['audioList'] is List) {
      versions.clear();
      for (final item in resultObject['audioList'] as List) {
        if (item is Map) {
          final url = (item['audioUrl'] ?? item['audio_url'] ?? item['sourceAudioUrl'] ?? '').toString();
          if (url.startsWith('https://')) versions.add({'url': url, 'id': item['id']?.toString(), 'title': item['title']?.toString() ?? 'AI Song'});
        }
      }
    }
    return versions;
  }

  Future<void> createAiSong() async {
    if (aiBusy) return;
    final prompt = promptController.text.trim();
    if (prompt.isEmpty) { message('Describe the song you want KIE AI to create first.'); return; }
    setState(() { aiBusy = true; status = 'Sending song idea to KIE AI…'; generatedVersions = []; });
    try {
      final created = await _kieRequest({'action': 'generate',
        'title': titleController.text.trim().isEmpty ? 'NovaCut Song' : titleController.text.trim(),
        'prompt': prompt, 'style': styleController.text.trim(), 'instrumental': instrumentalOnly});
      final data = (created['data'] as Map?)?.cast<String, dynamic>() ?? created;
      final taskId = (data['taskId'] ?? data['task_id'])?.toString();
      if (taskId == null || taskId.isEmpty) throw Exception('KIE did not return a task ID: ${jsonEncode(created)}');
      lastKieTaskId = taskId;
      message('KIE task started. Waiting for the generated audio…');
      final finished = await _waitForKieTask(taskId);
      final versions = _extractKieVersions(finished);
      if (versions.isEmpty) throw Exception('KIE task finished but no audio URL was found in its result.');
      if (!mounted) return;
      setState(() { generatedVersions = versions; status = 'KIE created ${versions.length} audio version(s).'; });
    } catch (e) { message('AI song creation failed: $e'); }
    finally { if (mounted) setState(() => aiBusy = false); }
  }

  Future<String> _downloadAudio(String url, String filename) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Audio download failed (HTTP ${response.statusCode}).');
      final dir = await getApplicationDocumentsDirectory();
      final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName.mp3';
      await response.pipe(File(path).openWrite());
      return path;
    } finally { client.close(force: true); }
  }

  Future<void> addGeneratedVersion(Map<String, dynamic> version) async {
    try {
      message('Downloading generated audio…');
      final path = await _downloadAudio(version['url'].toString(), version['title']?.toString() ?? 'KIE_Song');
      if (!mounted) return;
      setState(() {
        final audioId = version['id']?.toString();
        lastKieAudioId = audioId;
        tracks.add(MusicTrack(path: path, kind: 'Beat', kieTaskId: lastKieTaskId, kieAudioId: audioId));
        status = 'Generated audio added to your editable tracks.';
      });
    } catch (e) { message('Could not add generated audio: $e'); }
  }

  Future<void> separateGeneratedAudio() async {
    final taskId = lastKieTaskId;
    final audioId = lastKieAudioId ?? (tracks.isNotEmpty ? tracks.last.kieAudioId : null);
    if (taskId == null || audioId == null || audioId.isEmpty) {
      message('Add a generated KIE audio version first. The selected version must include its KIE audio ID.');
      return;
    }
    setState(() { aiBusy = true; status = 'Requesting AI stem separation…'; });
    try {
      final created = await _kieRequest({'action': 'separate', 'taskId': taskId, 'audioId': audioId, 'type': 'split_stem'});
      final data = (created['data'] as Map?)?.cast<String, dynamic>() ?? created;
      final separationId = (data['taskId'] ?? data['task_id'])?.toString();
      if (separationId == null || separationId.isEmpty) throw Exception('KIE did not return a separation task ID.');
      final finished = await _waitForKieTask(separationId);
      final stems = _extractKieVersions(finished);
      if (stems.isEmpty) throw Exception('KIE separation finished but returned no downloadable stems.');
      if (!mounted) return;
      setState(() { generatedVersions = stems.map((v) => {...v, 'title': 'Stem · ${v['title']}'}).toList(); status = 'Separated audio is ready. Add any stem to your tracks.'; });
    } catch (e) { message('Stem separation failed: $e'); }
    finally { if (mounted) setState(() => aiBusy = false); }
  }

  Future<void> cutTrack(MusicTrack track) async {
    final startController = TextEditingController(text: '0');
    final endController = TextEditingController(text: '30');
    final values = await showDialog<List<double>>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Cut audio section'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter the start and end time in seconds. The original file stays unchanged.'),
        TextField(controller: startController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Start (seconds)')),
        TextField(controller: endController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'End (seconds)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final a = double.tryParse(startController.text);
          final b = double.tryParse(endController.text);
          if (a == null || b == null || a < 0 || b <= a) return;
          Navigator.pop(ctx, [a, b]);
        }, child: const Text('Cut and add')),
      ],
    ));
    startController.dispose(); endController.dispose();
    if (values == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = '${dir.path}/NovaCut_Cut_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final duration = values[1] - values[0];
      final session = await FFmpegKit.execute('-y -ss ${values[0].toStringAsFixed(3)} -i ${quote(track.path)} -t ${duration.toStringAsFixed(3)} -vn -c:a libmp3lame -b:a 192k ${quote(out)}');
      final code = await session.getReturnCode();
      if (code == null || code.getValue() != 0 || !File(out).existsSync()) throw Exception(await session.getOutput() ?? 'Cut failed.');
      setState(() { tracks.add(MusicTrack(path: out, kind: track.kind)); status = 'Cut section added as a new track. Original preserved.'; });
    } catch (e) { message('Could not cut audio: $e'); }
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

class _TrackWaveformPainter extends CustomPainter {
  const _TrackWaveformPainter({required this.seed, required this.color});
  final int seed;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .8)..strokeWidth = 1.4..strokeCap = StrokeCap.round;
    var value = seed.abs() + 1;
    for (var x = 2.0; x < size.width; x += 4) {
      value = (value * 1103515245 + 12345) & 0x7fffffff;
      final amplitude = 2.0 + (value % (size.height.toInt().clamp(2, 22))) / 2.0;
      canvas.drawLine(Offset(x, size.height / 2 - amplitude), Offset(x, size.height / 2 + amplitude), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _TrackWaveformPainter oldDelegate) => oldDelegate.seed != seed || oldDelegate.color != color;
}

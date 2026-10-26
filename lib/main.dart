import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'music_studio.dart';

void main() => runApp(const NovaCutApp());

const ink = Color(0xFF090B12);
const panel = Color(0xFF151925);
const purple = Color(0xFF7C5CFF);
const cyan = Color(0xFF39D8E8);

class ClipItem {
  ClipItem({required this.path, required this.start, required this.end, String? id})
      : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${path.hashCode}';
  final String id;
  final String path;
  double start;
  double end;
  double get length => (end - start).clamp(0.0, double.infinity).toDouble();
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'start': start, 'end': end};
  factory ClipItem.fromJson(Map<String, dynamic> j) => ClipItem(
    id: j['id'] as String?, path: j['path'] as String,
    start: (j['start'] as num).toDouble(), end: (j['end'] as num).toDouble());
  ClipItem copy() => ClipItem(id: id, path: path, start: start, end: end);
}

enum TrackKind { video, audio, sticker, caption }

class TimelineItem {
  TimelineItem({required this.id, required this.kind, required this.label, this.path, this.start = 0, this.duration = 3, this.x = 0.5, this.y = 0.5, this.scale = 1, this.rotation = 0});
  final String id;
  final TrackKind kind;
  final String label;
  final String? path;
  double start, duration, x, y, scale, rotation;
  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'label': label, 'path': path, 'start': start, 'duration': duration, 'x': x, 'y': y, 'scale': scale, 'rotation': rotation};
  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
    id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
    kind: TrackKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => TrackKind.video),
    label: j['label'] as String? ?? 'Layer', path: j['path'] as String?,
    start: (j['start'] as num?)?.toDouble() ?? 0, duration: (j['duration'] as num?)?.toDouble() ?? 3,
    x: (j['x'] as num?)?.toDouble() ?? .5, y: (j['y'] as num?)?.toDouble() ?? .5,
    scale: (j['scale'] as num?)?.toDouble() ?? 1, rotation: (j['rotation'] as num?)?.toDouble() ?? 0);
}

class AnimationKeyframe {
  AnimationKeyframe({required this.time, required this.scale, required this.x, required this.y});
  final double time, scale, x, y;
  Map<String, dynamic> toJson() => {'time': time, 'scale': scale, 'x': x, 'y': y};
}

class NovaCutApp extends StatelessWidget {
  const NovaCutApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NovaCut', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
      useMaterial3: true), home: const EditorPage());
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final List<ClipItem> clips = [];
  final List<TimelineItem> layerItems = [];
  final List<AnimationKeyframe> keyframes = [];
  String transition = 'Cut';
  bool chromaKeyEnabled = false;
  double chromaSimilarity = .18;
  String sticker = '⭐';
  final List<List<ClipItem>> undoStack = [];
  final List<List<ClipItem>> redoStack = [];
  VideoPlayerController? player;
  String? musicPath, exportedPath;
  String overlay = '';
  String aspect = '9:16';
  String filter = 'None';
  double musicVolume = .75, originalVolume = .85, speed = 1, fadeSeconds = .35;
  double brightness = 0, contrast = 1, saturation = 1;
  bool busy = false;
  String status = 'Import videos to start editing';
  int selected = 0;

  double get total => clips.fold<double>(0.0, (v, c) => v + c.length);
  ClipItem? get active => clips.isEmpty ? null : clips[selected.clamp(0, clips.length - 1).toInt()];
  String quote(String s) => "'${s.replaceAll("'", "'\\''")}'";
  String stamp(double s) {
    final ms = (s * 1000).round().clamp(0, 1 << 31);
    return '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000 ~/ 10).toString().padLeft(2, '0')}';
  }

  void notify(String s) { if (mounted) setState(() => status = s); }
  void checkpoint() {
    undoStack.add(clips.map((c) => c.copy()).toList());
    if (undoStack.length > 30) undoStack.removeAt(0);
    redoStack.clear();
  }

  Future<void> importVideos() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
    if (pick == null) return;
    final paths = pick.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) { notify('No readable video paths were returned.'); return; }
    checkpoint();
    for (final path in paths) {
      try {
        final c = VideoPlayerController.file(File(path));
        await c.initialize();
        final duration = c.value.duration.inMilliseconds / 1000;
        await c.dispose();
        if (duration > 0) clips.add(ClipItem(path: path, start: 0, end: duration));
      } catch (e) { notify('Could not inspect a video: $e'); }
    }
    if (clips.isNotEmpty) {
      selected = clips.length - 1;
      await loadPreview(active!);
      notify('${paths.length} video(s) added to the timeline');
    }
    if (mounted) setState(() {});
  }

  Future<void> loadPreview(ClipItem clip) async {
    final old = player;
    player = null;
    await old?.dispose();
    final next = VideoPlayerController.file(File(clip.path));
    await next.initialize();
    await next.setLooping(false);
    await next.setPlaybackSpeed(speed);
    await next.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
    if (!mounted) { await next.dispose(); return; }
    setState(() => player = next);
  }

  Future<void> chooseClip(int i) async {
    if (i < 0 || i >= clips.length) return;
    setState(() => selected = i);
    await loadPreview(clips[i]);
  }

  Future<void> splitClip() async {
    final c = active;
    final p = player;
    if (c == null || p == null || !p.value.isInitialized) { notify('Import and select a clip first.'); return; }
    final cut = (p.value.position.inMilliseconds / 1000).clamp(c.start + .15, c.end - .15).toDouble();
    if (cut <= c.start || cut >= c.end) { notify('Move the preview playhead inside the selected clip before splitting.'); return; }
    checkpoint();
    final right = ClipItem(path: c.path, start: cut, end: c.end);
    c.end = cut;
    clips.insert(selected + 1, right);
    notify('Clip split at ${stamp(cut)}');
    setState(() {});
  }

  void removeClip(int i) {
    if (i < 0 || i >= clips.length) return;
    checkpoint();
    clips.removeAt(i);
    selected = clips.isEmpty ? 0 : selected.clamp(0, clips.length - 1).toInt();
    if (clips.isEmpty) { player?.dispose(); player = null; }
    else { loadPreview(clips[selected]); }
    setState(() {});
  }

  void undo() {
    if (undoStack.isEmpty) { notify('Nothing to undo.'); return; }
    redoStack.add(clips.map((c) => c.copy()).toList());
    clips..clear()..addAll(undoStack.removeLast().map((c) => c.copy()));
    selected = clips.isEmpty ? 0 : selected.clamp(0, clips.length - 1).toInt();
    if (clips.isNotEmpty) loadPreview(clips[selected]);
    setState(() {});
  }
  void redo() {
    if (redoStack.isEmpty) { notify('Nothing to redo.'); return; }
    undoStack.add(clips.map((c) => c.copy()).toList());
    clips..clear()..addAll(redoStack.removeLast().map((c) => c.copy()));
    selected = clips.isEmpty ? 0 : selected.clamp(0, clips.length - 1).toInt();
    if (clips.isNotEmpty) loadPreview(clips[selected]);
    setState(() {});
  }

  Future<void> addTimelineLayer(TrackKind kind) async {
    if (clips.isEmpty) { notify('Add a base video first.'); return; }
    String? path;
    if (kind == TrackKind.video || kind == TrackKind.audio) {
      final picked = await FilePicker.platform.pickFiles(type: kind == TrackKind.audio ? FileType.audio : FileType.media);
      path = picked?.files.single.path;
      if (path == null) return;
    }
    final item = TimelineItem(id: DateTime.now().microsecondsSinceEpoch.toString(), kind: kind,
      label: kind == TrackKind.video ? 'Overlay video' : kind == TrackKind.audio ? 'Audio layer' : kind == TrackKind.sticker ? 'Sticker $sticker' : 'Caption',
      path: path, start: (player?.value.position.inMilliseconds ?? 0) / 1000.0, duration: 3);
    setState(() => layerItems.add(item));
    notify('${kind.name} layer added; adjust its timing in the multi-track lane.');
  }

  Future<void> addKeyframe() async {
    final ctl = TextEditingController(text: (player?.value.position.inMilliseconds ?? 0) == 0 ? '0' : ((player!.value.position.inMilliseconds / 1000).toStringAsFixed(2)));
    final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add animation keyframe'),
      content: TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Timeline time (seconds)')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)), child: const Text('Add')]));
    if (result == null || result < 0) return;
    setState(() => keyframes.add(AnimationKeyframe(time: result, scale: 1.2, x: .5, y: .5)));
    notify('Keyframe saved at ${result.toStringAsFixed(2)}s. Keyframes are stored in the project.');
  }

  Future<void> chooseSticker() async {
    const choices = ['⭐','🔥','❤️','✨','⚡','😂','🎬','💥','🌈','👑'];
    final picked = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Choose sticker'),
      content: Wrap(spacing: 10, runSpacing: 10, children: choices.map((v) => InkWell(onTap: () => Navigator.pop(ctx, v), child: Padding(padding: const EdgeInsets.all(6), child: Text(v, style: const TextStyle(fontSize: 30))))).toList()),
    ));
    if (picked != null) { setState(() => sticker = picked); await addTimelineLayer(TrackKind.sticker); }
  }

  Future<void> pickMusic() async {
    final p = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = p?.files.single.path;
    if (path != null) { setState(() => musicPath = path); notify('Music track added'); }
  }

  Future<void> editCaption() async {
    final ctl = TextEditingController(text: overlay);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Text overlay / caption'),
      content: TextField(controller: ctl, maxLines: 3, maxLength: 120,
        decoration: const InputDecoration(hintText: 'Type title or caption')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Apply')]),
    ));
    if (result != null) setState(() => overlay = result.trim());
  }

  Future<Directory> projectDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/NovaCut');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> saveProject() async {
    final dir = await projectDir();
    final data = {'version': 2, 'clips': clips.map((c) => c.toJson()).toList(),
      'musicPath': musicPath, 'overlay': overlay, 'aspect': aspect, 'filter': filter,
      'musicVolume': musicVolume, 'originalVolume': originalVolume, 'speed': speed, 'fadeSeconds': fadeSeconds,
      'brightness': brightness, 'contrast': contrast, 'saturation': saturation, 'layers': layerItems.map((e) => e.toJson()).toList(), 'keyframes': keyframes.map((e) => e.toJson()).toList(), 'transition': transition, 'chromaKeyEnabled': chromaKeyEnabled, 'chromaSimilarity': chromaSimilarity, 'sticker': sticker, 'savedAt': DateTime.now().toIso8601String()};
    await File('${dir.path}/project.json').writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    notify('Project saved offline on this device');
  }

  Future<void> loadProject() async {
    try {
      final dir = await projectDir();
      final f = File('${dir.path}/project.json');
      if (!await f.exists()) { notify('No saved project found on this device.'); return; }
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      checkpoint();
      clips..clear()..addAll((data['clips'] as List).map((e) => ClipItem.fromJson(Map<String, dynamic>.from(e))));
      musicPath = data['musicPath'] as String?;
      overlay = data['overlay'] as String? ?? '';
      aspect = data['aspect'] as String? ?? '9:16';
      filter = data['filter'] as String? ?? 'None';
      musicVolume = (data['musicVolume'] as num?)?.toDouble() ?? .75;
      originalVolume = (data['originalVolume'] as num?)?.toDouble() ?? .85;
      speed = (data['speed'] as num?)?.toDouble() ?? 1;
      fadeSeconds = (data['fadeSeconds'] as num?)?.toDouble() ?? .35;
      brightness = (data['brightness'] as num?)?.toDouble() ?? 0;
      contrast = (data['contrast'] as num?)?.toDouble() ?? 1;
      saturation = (data['saturation'] as num?)?.toDouble() ?? 1;
      layerItems..clear()..addAll(((data['layers'] as List?) ?? []).map((e) => TimelineItem.fromJson(Map<String, dynamic>.from(e))));
      keyframes..clear()..addAll(((data['keyframes'] as List?) ?? []).map((e) { final j = Map<String, dynamic>.from(e); return AnimationKeyframe(time: (j['time'] as num).toDouble(), scale: (j['scale'] as num).toDouble(), x: (j['x'] as num).toDouble(), y: (j['y'] as num).toDouble()); }));
      transition = data['transition'] as String? ?? 'Cut'; chromaKeyEnabled = data['chromaKeyEnabled'] as bool? ?? false; chromaSimilarity = (data['chromaSimilarity'] as num?)?.toDouble() ?? .18; sticker = data['sticker'] as String? ?? '⭐';
      selected = 0;
      if (clips.isNotEmpty && await File(clips.first.path).exists()) {
        await loadPreview(clips.first);
      } else if (clips.isNotEmpty) {
        notify('Project loaded, but one or more original media files are missing.');
      }
      setState(() {});
      notify('Project loaded');
    } catch (e) { notify('Could not load project: $e'); }
  }


  Future<void> exportProjectFile() async {
    try {
      final data = {
        'version': 3,
        'clips': clips.map((c) => c.toJson()).toList(),
        'musicPath': musicPath,
        'overlay': overlay,
        'aspect': aspect,
        'filter': filter,
        'musicVolume': musicVolume,
        'originalVolume': originalVolume,
        'speed': speed,
        'fadeSeconds': fadeSeconds,
        'savedAt': DateTime.now().toIso8601String(),
      };
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export NovaCut project',
        fileName: 'NovaCut_project.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) { notify('Project export cancelled.'); return; }
      await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      notify('Project JSON exported. Keep the original media files with it.');
    } catch (e) { notify('Project export failed: $e'); }
  }

  Future<void> importProjectFile() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      final path = pick?.files.single.path;
      if (path == null) return;
      final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final incoming = (data['clips'] as List)
          .map((e) => ClipItem.fromJson(Map<String, dynamic>.from(e))).toList();
      if (incoming.any((c) => !File(c.path).existsSync())) {
        notify('Project opened, but source media paths are missing. Re-import the original files.');
        return;
      }
      checkpoint();
      clips..clear()..addAll(incoming);
      musicPath = data['musicPath'] as String?;
      overlay = data['overlay'] as String? ?? '';
      aspect = data['aspect'] as String? ?? '9:16';
      filter = data['filter'] as String? ?? 'None';
      musicVolume = (data['musicVolume'] as num?)?.toDouble() ?? .75;
      originalVolume = (data['originalVolume'] as num?)?.toDouble() ?? .85;
      speed = (data['speed'] as num?)?.toDouble() ?? 1;
      fadeSeconds = (data['fadeSeconds'] as num?)?.toDouble() ?? .35;
      selected = 0;
      if (clips.isNotEmpty) await loadPreview(clips.first);
      if (mounted) setState(() {});
      notify('Project imported');
    } catch (e) { notify('Could not import project: $e'); }
  }

  String videoFilter() {
    final dimensions = switch (aspect) {
      '16:9' => '1920:1080', '1:1' => '1080:1080', '4:5' => '1080:1350', _ => '1080:1920'
    };
    final bits = <String>['scale=$dimensions:force_original_aspect_ratio=decrease',
      'pad=$dimensions:(ow-iw)/2:(oh-ih)/2', 'setsar=1'];
    if (filter == 'Grayscale') bits.add('hue=s=0');
    if (filter == 'Warm') bits.add('colorbalance=rs=.08:gs=.02:bs=-.04');
    if (filter == 'Vintage') bits.add('eq=saturation=.75:contrast=1.08:brightness=.02');
    if (filter == 'Cinematic') bits.add('eq=saturation=1.15:contrast=1.18:brightness=-.02,colorbalance=rs=.04:bs=-.06');
    if (filter == 'Cool') bits.add('colorbalance=rs=-.04:bs=.08');
    if (filter == 'Invert') bits.add('negate');
    if (filter == 'Sharpen') bits.add('unsharp=5:5:0.8:3:3:0.4');
    if (filter == 'Soft blur') bits.add('gblur=sigma=1.2');
    if (chromaKeyEnabled) bits.add('chromakey=0x00FF00:${chromaSimilarity.toStringAsFixed(2)}:0.08');
    bits.add('eq=brightness=${brightness.toStringAsFixed(2)}:contrast=${contrast.toStringAsFixed(2)}:saturation=${saturation.toStringAsFixed(2)}');
    return bits.join(',');
  }

  Future<void> export() async {
    if (busy) return;
    if (clips.isEmpty) { notify('Import at least one video before exporting.'); return; }
    if (clips.any((c) => !File(c.path).existsSync() || c.length < .2)) {
      notify('A source file is missing or a clip is too short. Check the timeline.'); return;
    }
    setState(() => busy = true);
    try {
      final dir = await projectDir();
      final work = Directory('${dir.path}/render');
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);
      final segmentPaths = <String>[];
      for (var i = 0; i < clips.length; i++) {
        final c = clips[i];
        final out = '${work.path}/segment_${i.toString().padLeft(3, '0')}.mp4';
        final fd = (transition == 'Cut' ? fadeSeconds : (transition == 'Fade' ? fadeSeconds.clamp(.25, 2.0) : fadeSeconds.clamp(.25, 1.0))).clamp(0.0, c.length / 2).toDouble();
        final fades = fd <= 0 ? '' : ',fade=t=in:st=0:d=$fd,fade=t=out:st=${(c.length - fd).clamp(0.0, c.length)}:d=$fd';
        final vf = videoFilter() + fades;
        final caption = overlay.trim().isEmpty ? '' :
          ",drawtext=fontfile=/system/fonts/Roboto-Regular.ttf:text='${overlay.replaceAll('\\', '\\\\').replaceAll(':', '\\:').replaceAll("'", "\\'").replaceAll('%', '\\%').replaceAll(',', '\\,')}':fontcolor=white:fontsize=48:box=1:boxcolor=black@0.55:boxborderw=16:x=(w-text_w)/2:y=h-text_h-100";
        final baseAudio = 'atempo=${speed.clamp(.5, 2).toStringAsFixed(2)},volume=${originalVolume.toStringAsFixed(2)}';
        final audioFilters = fd <= 0 ? baseAudio :
          '$baseAudio,afade=t=in:st=0:d=${fd.toStringAsFixed(2)},afade=t=out:st=${(c.length-fd).clamp(0.0,c.length).toStringAsFixed(2)}:d=${fd.toStringAsFixed(2)}';
        final command = '-y -ss ${c.start.toStringAsFixed(3)} -i ${quote(c.path)} -t ${c.length.toStringAsFixed(3)} '
          '-vf ${quote(vf + caption)} -filter:a ${quote(audioFilters)} '
          '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 160k -ar 44100 -ac 2 '
          '-avoid_negative_ts make_zero -movflags +faststart ${quote(out)}';
        final session = await FFmpegKit.execute(command);
        final code = await session.getReturnCode();
        if (code == null || code.getValue() != 0 || !File(out).existsSync()) {
          final logs = await session.getOutput();
          throw Exception('Clip ${i + 1} render failed: ${logs ?? code}');
        }
        segmentPaths.add(out);
        if (mounted) setState(() => status = 'Rendering clip ${i + 1} of ${clips.length}…');
      }
      final listFile = File('${work.path}/concat.txt');
      await listFile.writeAsString(segmentPaths.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n'));
      final joined = '${work.path}/joined.mp4';
      final concat = await FFmpegKit.execute('-y -f concat -safe 0 -i ${quote(listFile.path)} -c copy -movflags +faststart ${quote(joined)}');
      final concatCode = await concat.getReturnCode();
      if (concatCode == null || concatCode.getValue() != 0 || !File(joined).existsSync()) {
        throw Exception('Could not join the rendered clips: ${await concat.getOutput() ?? concatCode}');
      }
      var finalPath = joined;
      if (musicPath != null && File(musicPath!).existsSync()) {
        final mixed = '${dir.path}/NovaCut_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final mix = await FFmpegKit.execute('-y -i ${quote(joined)} -stream_loop -1 -i ${quote(musicPath!)} '
          '-filter_complex "[1:a]volume=${musicVolume.toStringAsFixed(2)},atrim=duration=${total.toStringAsFixed(2)}[music]" '
          '-map 0:v:0 -map "[music]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart ${quote(mixed)}');
        final mixCode = await mix.getReturnCode();
        if (mixCode == null || mixCode.getValue() != 0 || !File(mixed).existsSync()) {
          throw Exception('Audio mix failed: ${await mix.getOutput() ?? mixCode}');
        }
        finalPath = mixed;
      } else {
        final copy = '${dir.path}/NovaCut_${DateTime.now().millisecondsSinceEpoch}.mp4';
        await File(joined).copy(copy);
        finalPath = copy;
      }
      if (!mounted) return;
      setState(() => exportedPath = finalPath);
      notify('MP4 export complete: ${finalPath.split(Platform.pathSeparator).last}');
    } catch (e) {
      notify('Export failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> shareExport() async {
    final p = exportedPath;
    if (p == null || !File(p).existsSync()) { notify('Export a video first.'); return; }
    await Share.shareXFiles([XFile(p)], text: 'Exported with NovaCut');
  }

  Widget action(String title, IconData icon, VoidCallback fn, {bool disabled = false}) =>
    FilledButton.tonalIcon(onPressed: disabled ? null : fn, icon: Icon(icon, size: 18), label: Text(title));

  @override
  void dispose() { player?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = player;
    final ready = p?.value.isInitialized == true;
    final current = active;
    return Scaffold(
      appBar: AppBar(title: const Text('NovaCut Studio', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton.icon(tooltip: 'Open Music Studio', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MusicStudioPage())), icon: const Icon(Icons.graphic_eq), label: const Text('Music Studio')), IconButton(tooltip: 'Undo', onPressed: undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Redo', onPressed: redo, icon: const Icon(Icons.redo)),
          IconButton(tooltip: 'Save project', onPressed: saveProject, icon: const Icon(Icons.save_outlined)),
          IconButton(tooltip: 'Load project', onPressed: loadProject, icon: const Icon(Icons.folder_open))]),
      body: SafeArea(child: Column(children: [
        Expanded(flex: 5, child: Container(margin: const EdgeInsets.all(12), width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
          child: Stack(alignment: Alignment.center, children: [
            if (ready) AspectRatio(aspectRatio: p!.value.aspectRatio, child: VideoPlayer(p))
            else const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.movie_creation_outlined, size: 64, color: cyan), SizedBox(height: 12), Text('Import videos to begin')]),
            if (ready && overlay.isNotEmpty) Positioned(bottom: 20, left: 12, right: 12,
              child: Container(padding: const EdgeInsets.all(8), color: Colors.black54,
                child: Text(overlay, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
            if (ready) Positioned(bottom: 8, left: 8, right: 8, child: Row(children: [
              Text(stamp(p!.value.position.inMilliseconds / 1000), style: const TextStyle(fontSize: 12)),
              Expanded(child: VideoProgressIndicator(p, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 8))),
              Text(stamp(p.value.duration.inMilliseconds / 1000), style: const TextStyle(fontSize: 12)),
              IconButton(onPressed: () async { if (p.value.isPlaying) { await p.pause(); } else { await p.play(); } setState(() {}); },
                icon: Icon(p.value.isPlaying ? Icons.pause : Icons.play_arrow))
            ]))
          ]))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          action('Import', Icons.video_library, importVideos),
          action('Split', Icons.content_cut, splitClip, disabled: current == null),
          action('Delete', Icons.delete_outline, () => removeClip(selected), disabled: current == null),
          action('Music', Icons.music_note, pickMusic),
          action('Caption', Icons.title, editCaption),
          action('Import Project', Icons.file_open, importProjectFile),
          action('Export Project', Icons.save_alt, exportProjectFile),
          action('Export MP4', Icons.ios_share, export, disabled: busy || clips.isEmpty),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Wrap(spacing: 6, runSpacing: 6, children: [
          action('Video layer', Icons.video_collection, () => addTimelineLayer(TrackKind.video)),
          action('Audio layer', Icons.graphic_eq, () => addTimelineLayer(TrackKind.audio)),
          action('Sticker', Icons.emoji_emotions_outlined, chooseSticker),
          action('Keyframe', Icons.animation, addKeyframe),
          action('Chroma key', Icons.colorize, () => setState(() { chromaKeyEnabled = !chromaKeyEnabled; notify(chromaKeyEnabled ? 'Green-screen chroma key enabled for export.' : 'Chroma key disabled.'); })),
        ])),
        if (layerItems.isNotEmpty || keyframes.isNotEmpty) Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.layers_outlined, color: cyan), const SizedBox(width: 6), const Text('MULTI-TRACK LAYERS', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('${layerItems.length} layers • ${keyframes.length} keyframes', style: const TextStyle(fontSize: 11, color: Colors.white60))]),
            const SizedBox(height: 8),
            ...layerItems.map((item) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
              SizedBox(width: 68, child: Text(item.kind.name.toUpperCase(), style: const TextStyle(fontSize: 10, color: cyan))),
              Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 86, child: Text('${item.start.toStringAsFixed(1)}s · ${item.duration.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10))),
              IconButton(tooltip: 'Remove layer', visualDensity: VisualDensity.compact, onPressed: () => setState(() => layerItems.remove(item)), icon: const Icon(Icons.close, size: 17)),
            ]))),
            Row(children: [const Text('Transition'), const SizedBox(width: 8), Expanded(child: DropdownButton<String>(isExpanded: true, value: transition, items: const ['Cut','Fade','Dissolve','Wipe left','Wipe right'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => transition = v ?? transition)))]),
            if (chromaKeyEnabled) Row(children: [const Text('Green screen tolerance'), Expanded(child: Slider(value: chromaSimilarity, min: .05, max: .5, divisions: 9, onChanged: (v) => setState(() => chromaSimilarity = v))), Text(chromaSimilarity.toStringAsFixed(2))]),
            if (keyframes.isNotEmpty) Text('Keyframe times: ${keyframes.map((k) => '${k.time.toStringAsFixed(2)}s').join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 2), child: Row(children: [
          const Text('TIMELINE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const Spacer(), Text('${clips.length} clips • ${stamp(total)}', style: const TextStyle(color: Colors.white60)),
        ])),
        SizedBox(height: 126, child: clips.isEmpty
          ? const Center(child: Text('Add multiple videos to create a sequence', style: TextStyle(color: Colors.white54)))
          : ReorderableListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(10),
              itemCount: clips.length, onReorder: (oldIndex, newIndex) {
                checkpoint(); if (newIndex > oldIndex) newIndex--;
                final item = clips.removeAt(oldIndex); clips.insert(newIndex, item);
                selected = newIndex; setState(() {});
              }, itemBuilder: (ctx, i) {
                final c = clips[i];
                return Container(key: ValueKey(c.id), width: 145, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: i == selected ? purple.withValues(alpha: .25) : panel,
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: i == selected ? cyan : Colors.white12)),
                  child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => chooseClip(i),
                    child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [const Icon(Icons.movie, size: 17, color: cyan), const SizedBox(width: 5),
                        Expanded(child: Text('Clip ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Icon(Icons.drag_handle, size: 16)]),
                      const Spacer(), Text(c.path.split(Platform.pathSeparator).last, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white60)),
                      const SizedBox(height: 4), Text('${stamp(c.start)} – ${stamp(c.end)}', style: const TextStyle(fontSize: 11, color: cyan)),
                    ]))));
              })),
        Container(color: panel, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Column(children: [
          Row(children: [const Text('Canvas'), const SizedBox(width: 8),
            DropdownButton<String>(value: aspect, items: const ['9:16','16:9','1:1','4:5'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => aspect = v ?? aspect)),
            const SizedBox(width: 16), const Text('Filter'), const SizedBox(width: 8),
            Expanded(child: DropdownButton<String>(isExpanded: true, value: filter,
              items: const ['None','Grayscale','Warm','Vintage','Cinematic','Cool','Invert','Sharpen','Soft blur'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => filter = v ?? filter))),
          ]),
          if (current != null && ready) Row(children: [
            const Icon(Icons.content_cut, size: 18), const SizedBox(width: 8), const Text('Trim'),
            Expanded(child: RangeSlider(
              min: 0,
              max: p!.value.duration.inMilliseconds / 1000,
              values: RangeValues(current.start, current.end),
              labels: RangeLabels(stamp(current.start), stamp(current.end)),
              onChangeStart: (_) => checkpoint(),
              onChanged: (v) {
                if (v.end - v.start >= .2) {
                  setState(() { current.start = v.start; current.end = v.end; });
                }
              },
              onChangeEnd: (v) => p.seekTo(Duration(milliseconds: (v.start * 1000).round())),
            )),
          ]),
          Row(children: [const Icon(Icons.speed, size: 18), const SizedBox(width: 8), const Text('Speed'),
            Expanded(child: Slider(value: speed, min: .5, max: 2, divisions: 6, label: '${speed}x',
              onChanged: (v) { setState(() => speed = v); player?.setPlaybackSpeed(v); })),
            Text('${speed}x', style: const TextStyle(color: cyan)),
          ]),
          Row(children: [const Icon(Icons.volume_up, size: 18), const SizedBox(width: 8), const Text('Original audio'),
            Expanded(child: Slider(value: originalVolume, min: 0, max: 1, onChanged: (v) => setState(() => originalVolume = v))),
            Text('${(originalVolume * 100).round()}%', style: const TextStyle(color: cyan)),
          ]),
          Row(children: [const Icon(Icons.blur_on, size: 18), const SizedBox(width: 8), const Text('Fade in/out'),
            Expanded(child: Slider(value: fadeSeconds, min: 0, max: 2, divisions: 8, label: '${fadeSeconds.toStringAsFixed(2)}s', onChanged: (v) => setState(() => fadeSeconds = v))),
            Text('${fadeSeconds.toStringAsFixed(2)}s', style: const TextStyle(color: cyan)),
          ]),
          Row(children: [const Icon(Icons.light_mode_outlined, size: 18), const SizedBox(width: 8), const Text('Brightness'),
            Expanded(child: Slider(value: brightness, min: -0.5, max: 0.5, divisions: 20, onChanged: (v) => setState(() => brightness = v))),
            Text(brightness.toStringAsFixed(2), style: const TextStyle(color: cyan)),
          ]),
          Row(children: [const Icon(Icons.tonality, size: 18), const SizedBox(width: 8), const Text('Contrast'),
            Expanded(child: Slider(value: contrast, min: 0.5, max: 1.8, divisions: 13, onChanged: (v) => setState(() => contrast = v))),
            Text(contrast.toStringAsFixed(2), style: const TextStyle(color: cyan)),
          ]),
          Row(children: [const Icon(Icons.palette_outlined, size: 18), const SizedBox(width: 8), const Text('Saturation'),
            Expanded(child: Slider(value: saturation, min: 0, max: 2, divisions: 20, onChanged: (v) => setState(() => saturation = v))),
            Text(saturation.toStringAsFixed(2), style: const TextStyle(color: cyan)),
          ]),
          if (musicPath != null) Row(children: [const Icon(Icons.graphic_eq, size: 18), const SizedBox(width: 8),
            Expanded(child: Text(musicPath!.split(Platform.pathSeparator).last, maxLines: 1, overflow: TextOverflow.ellipsis)),
            SizedBox(width: 110, child: Slider(value: musicVolume, min: 0, max: 1, onChanged: (v) => setState(() => musicVolume = v))),
          ]),
          if (busy) const LinearProgressIndicator(minHeight: 3),
          Align(alignment: Alignment.centerLeft, child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white60))),
          if (exportedPath != null) Align(alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: shareExport, icon: const Icon(Icons.share), label: const Text('Share exported MP4'))),
        ])),
      ])),
    );
  }
}

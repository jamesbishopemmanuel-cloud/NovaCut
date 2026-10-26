import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vihbsfrwnslnmheowkhy.supabase.co',
    anonKey: 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz',
  );
  runApp(const NovaCutApp());
}
const bg = Color(0xFF090B12);
const panel = Color(0xFF151925);
const purple = Color(0xFF7C5CFF);
const cyan = Color(0xFF39D8E8);

class NovaCutApp extends StatelessWidget {
  const NovaCutApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NovaCut', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
      useMaterial3: true),
    home: const EditorHome());
}

class EditorHome extends StatefulWidget {
  const EditorHome({super.key});
  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> {
  VideoPlayerController? video;
  String? videoPath, audioPath, lastExport;
  String ratio = '9:16', transition = 'Fade in/out', overlayText = '', filterPreset = 'Original';
  double trimIn = 0, trimOut = 1, musicVolume = .75, speed = 1;
  bool muted = false, busy = false;
  Duration get duration => video?.value.isInitialized == true ? video!.value.duration : Duration.zero;
  double get seconds => duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000 : 1;
  double get playhead => video?.value.isInitialized == true ? video!.value.position.inMilliseconds / 1000 : 0;

  Future<Directory> projectDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/NovaCut');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  String time(double s) {
    final n = s.isFinite && s > 0 ? s.floor() : 0;
    return '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
  }

  Future<void> importVideo() async {
    try {
      final pick = await FilePicker.platform.pickFiles(type: FileType.video);
      if (pick == null || pick.files.single.path == null) return;
      setState(() => busy = true);
      final next = VideoPlayerController.file(File(pick.files.single.path!));
      await next.initialize();
      await next.setLooping(true);
      await next.setPlaybackSpeed(speed);
      final old = video;
      old?.removeListener(tick);
      setState(() {
        video = next; videoPath = pick.files.single.path;
        trimIn = 0; trimOut = next.value.duration.inMilliseconds / 1000;
        lastExport = null; busy = false;
      });
      next.addListener(tick);
      await old?.dispose();
    } catch (e) {
      if (mounted) setState(() => busy = false);
      message('Could not open video: $e');
    }
  }

  void tick() { if (mounted) setState(() {}); }
  Future<void> seek(double s) async {
    final v = video;
    if (v != null && v.value.isInitialized) await v.seekTo(Duration(milliseconds: (s * 1000).round()));
  }

  Future<void> importAudio() async {
    try {
      final pick = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (pick != null && pick.files.single.path != null) {
        setState(() => audioPath = pick.files.single.path);
        message('Audio selected. It will be mixed into the next export.');
      }
    } catch (e) { message('Could not import audio: $e'); }
  }

  String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
  String filterEscape(String s) => s.replaceAll('\\', r'\\').replaceAll(':', r'\:')
    .replaceAll("'", r"\'").replaceAll('%', r'\%').replaceAll(',', r'\,')
    .replaceAll('[', r'\[').replaceAll(']', r'\]');

  String videoFilter(double clipSeconds) {
    final size = switch (ratio) {
      '16:9' => '1920:1080', '1:1' => '1080:1080', '4:5' => '1080:1350', _ => '1080:1920'
    };
    final bits = <String>[
      switch (filterPreset) {
        'Warm' => 'eq=saturation=1.25:contrast=1.05:brightness=0.02',
        'Black & white' => 'hue=s=0',
        'Vintage' => 'eq=saturation=0.80:contrast=1.10:brightness=0.02',
        'Cool' => 'colorbalance=rs=-0.05:bs=0.08',
        _ => 'null'
      },
      'scale=$size:force_original_aspect_ratio=increase',
      'crop=$size', 'setsar=1'
    ];
    if (transition == 'Fade in/out') {
      bits.add('fade=t=in:st=0:d=0.5');
      bits.add('fade=t=out:st=${(clipSeconds - .5).clamp(0.0, clipSeconds)}:d=0.5');
    }
    if (overlayText.trim().isNotEmpty) {
      bits.add("drawtext=fontfile=/system/fonts/Roboto-Regular.ttf:text='${filterEscape(overlayText.trim())}':fontcolor=white:fontsize=48:box=1:boxcolor=black@0.55:boxborderw=18:x=(w-text_w)/2:y=h-text_h-100");
    }
    return bits.join(',');
  }

  Future<void> exportMp4() async {
    final source = videoPath;
    if (source == null || !File(source).existsSync()) { message('Import a video before exporting.'); return; }
    if (trimOut - trimIn < .25) { message('Choose a trim range of at least 0.25 seconds.'); return; }
    if (busy) return;
    setState(() => busy = true);
    try {
      final dir = await projectDir();
      final output = '${dir.path}/NovaCut_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final clip = trimOut - trimIn;
      final vf = videoFilter(clip);
      final hasAudio = audioPath != null && File(audioPath!).existsSync();
      final cmd = StringBuffer('-y -ss ${trimIn.toStringAsFixed(3)} -i ${shellQuote(source)} ');
      if (hasAudio) {
        cmd
          ..write('-i ${shellQuote(audioPath!)} -t ${clip.toStringAsFixed(3)} ')
          ..write('-filter_complex ${shellQuote('[0:v]$vf[v];[0:a]atrim=duration=$clip,asetpts=PTS-STARTPTS[a0];[1:a]volume=$musicVolume,atrim=duration=$clip,asetpts=PTS-STARTPTS[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[a]')} ')
          ..write('-map "[v]" -map "[a]" ');
      } else {
        cmd..write('-t ${clip.toStringAsFixed(3)} -vf ${shellQuote(vf)} -map 0:v:0 -map 0:a? ');
      }
      cmd..write('-c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k -movflags +faststart ')
        ..write(shellQuote(output));
      final session = await FFmpegKit.execute(cmd.toString());
      final code = await session.getReturnCode();
      if (code != null && code.getValue() == 0 && File(output).existsSync()) {
        setState(() => lastExport = output);
        message('MP4 export finished: ${output.split(Platform.pathSeparator).last}');
      } else {
        final logs = await session.getOutput();
        message('Export failed. Check the video/audio codec and try again. ${logs ?? ''}');
      }
    } catch (e) {
      message('Export error: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> saveProject() async {
    try {
      final dir = await projectDir();
      final data = {
        'version': 1, 'videoPath': videoPath, 'audioPath': audioPath,
        'trimIn': trimIn, 'trimOut': trimOut, 'ratio': ratio,
        'transition': transition, 'overlayText': overlayText, 'filterPreset': filterPreset,
        'musicVolume': musicVolume, 'speed': speed,
        'savedAt': DateTime.now().toIso8601String()
      };
      await File('${dir.path}/project.json').writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      message('Project saved offline on this device.');
    } catch (e) { message('Could not save project: $e'); }
  }

  Future<void> loadProject() async {
    try {
      final dir = await projectDir();
      final file = File('${dir.path}/project.json');
      if (!await file.exists()) { message('No saved project found on this device.'); return; }
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final path = data['videoPath'] as String?;
      VideoPlayerController? next;
      if (path != null && File(path).existsSync()) {
        next = VideoPlayerController.file(File(path));
        await next.initialize();
        await next.setLooping(true);
      }
      final old = video;
      old?.removeListener(tick);
      setState(() {
        video = next; videoPath = next == null ? null : path;
        audioPath = data['audioPath'] as String?;
        ratio = data['ratio'] as String? ?? '9:16';
        transition = data['transition'] as String? ?? 'Fade in/out';
        overlayText = data['overlayText'] as String? ?? '';
        filterPreset = data['filterPreset'] as String? ?? 'Original';
        musicVolume = (data['musicVolume'] as num?)?.toDouble() ?? .75;
        speed = (data['speed'] as num?)?.toDouble() ?? 1;
        trimIn = (data['trimIn'] as num?)?.toDouble() ?? 0;
        trimOut = next == null ? 1 : ((data['trimOut'] as num?)?.toDouble() ?? (next.value.duration.inMilliseconds / 1000)).clamp(.25, next.value.duration.inMilliseconds / 1000).toDouble();
      });
      next?.addListener(tick);
      if (next != null) await next.setPlaybackSpeed(speed);
      await old?.dispose();
      message(next == null ? 'Project settings loaded, but the original video file is missing.' : 'Offline project loaded.');
    } catch (e) { message('Could not load project: $e'); }
  }

  Future<void> editText() async {
    final controller = TextEditingController(text: overlayText);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Text overlay'),
      content: TextField(controller: controller, maxLines: 3, maxLength: 120, decoration: const InputDecoration(hintText: 'Enter title or caption')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Apply'))
      ]));
    if (value != null) setState(() => overlayText = value);
  }

  Future<void> chooseTransition() async {
    final result = await showModalBottomSheet<String>(context: context, backgroundColor: panel,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('None'), onTap: () => Navigator.pop(context, 'None')),
        ListTile(title: const Text('Fade in/out'), subtitle: const Text('Fade the start and end of this exported clip'), onTap: () => Navigator.pop(context, 'Fade in/out'))
      ])));
    if (result != null) setState(() => transition = result);
  }

  Future<void> shareExport() async {
    final path = lastExport;
    if (path == null || !File(path).existsSync()) { message('Export an MP4 first.'); return; }
    await Share.shareXFiles([XFile(path)], text: 'Created with NovaCut');
  }

  Widget pill(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .68), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: cyan), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 11))]));

  Widget tool(String label, IconData icon, VoidCallback action) => InkWell(
    onTap: action, borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: cyan, size: 21), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70))])));

  void projectMenu() {
    showModalBottomSheet<void>(context: context, backgroundColor: panel, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.save_outlined, color: cyan), title: const Text('Save project offline'), onTap: () { Navigator.pop(context); saveProject(); }),
        ListTile(leading: const Icon(Icons.folder_open, color: cyan), title: const Text('Load saved project'), onTap: () { Navigator.pop(context); loadProject(); }),
        ListTile(leading: const Icon(Icons.info_outline, color: cyan), title: const Text('Local project storage'), subtitle: const Text('Project settings and media paths are saved in the app documents folder.'))
      ])));
  }

  @override
  void dispose() { video?.removeListener(tick); video?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final v = video;
    final ready = v?.value.isInitialized == true;
    final total = ready ? seconds : 1.0;
    final pos = playhead.clamp(0.0, total).toDouble();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: bg,
        title: const Row(children: [Icon(Icons.cut_rounded, color: cyan), SizedBox(width: 8), Text('NovaCut', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [
          IconButton(tooltip: 'AI Tools', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiToolsPage())), icon: const Icon(Icons.auto_awesome, color: cyan)),
          IconButton(tooltip: 'Project settings', onPressed: projectMenu, icon: const Icon(Icons.tune_rounded)),
          Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton.icon(onPressed: busy ? null : exportMp4, icon: const Icon(Icons.ios_share_rounded, size: 18), label: Text(busy ? 'Working…' : 'Export MP4')))
        ]),
      body: SafeArea(child: Column(children: [
        Expanded(flex: 4, child: Padding(padding: const EdgeInsets.all(12), child: Container(
          width: double.infinity, clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
          child: Stack(alignment: Alignment.center, children: [
            if (ready) Center(child: AspectRatio(aspectRatio: v!.value.aspectRatio, child: Stack(children: [
              VideoPlayer(v),
              if (overlayText.isNotEmpty) Positioned(left: 10, right: 10, bottom: 34, child: Container(color: Colors.black54, padding: const EdgeInsets.all(8), child: Text(overlayText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))))
            ]))) else const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.movie_creation_outlined, size: 58, color: cyan), SizedBox(height: 12), Text('Make every frame count'), Text('Import a video to begin', style: TextStyle(color: Colors.white60))]),
            if (busy) const CircularProgressIndicator(color: cyan),
            Positioned(left: 12, right: 12, top: 12, child: Row(children: [pill(ratio, Icons.aspect_ratio), const Spacer(), pill('$filterPreset • $transition', Icons.auto_awesome_motion)])),
            Positioned(bottom: 4, left: 6, right: 6, child: Row(children: [
              IconButton(onPressed: () { setState(() => muted = !muted); video?.setVolume(muted ? 0 : 1); }, icon: Icon(muted ? Icons.volume_off : Icons.volume_up)),
              Text(time(pos), style: const TextStyle(fontSize: 11)),
              Expanded(child: Slider(value: pos, min: 0, max: total, onChanged: ready ? seek : null)),
              Text(time(total), style: const TextStyle(fontSize: 11)),
              IconButton.filled(onPressed: () async {
                if (v == null || !v.value.isInitialized) { message('Import a video first.'); return; }
                if (v.value.isPlaying) { await v.pause(); } else { if (playhead >= trimOut) await seek(trimIn); await v.play(); }
              }, icon: Icon(v?.value.isPlaying == true ? Icons.pause : Icons.play_arrow))
            ]))
          ])))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          const Text('TIMELINE', style: TextStyle(fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(videoPath == null ? 'No clip' : '1 clip • ${time(total)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          IconButton(onPressed: importVideo, icon: const Icon(Icons.add_circle, color: cyan))
        ])),
        SizedBox(height: 62, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
          Container(width: 250, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF22233D), borderRadius: BorderRadius.circular(12), border: Border.all(color: purple)),
            child: Row(children: [const Icon(Icons.video_file, color: cyan), const SizedBox(width: 8), Expanded(child: Text(videoPath?.split(Platform.pathSeparator).last ?? 'Tap + to import a clip', maxLines: 2, overflow: TextOverflow.ellipsis))])),
          const SizedBox(width: 8),
          Container(width: 170, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [const Icon(Icons.graphic_eq, color: cyan), const SizedBox(width: 5), Expanded(child: Text(audioPath?.split(Platform.pathSeparator).last ?? 'Add audio', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))), IconButton(onPressed: importAudio, icon: const Icon(Icons.add, size: 18))]))
        ])),
        if (ready) Container(margin: const EdgeInsets.fromLTRB(14, 6, 14, 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)), child: Column(children: [
          Row(children: [const Icon(Icons.content_cut, color: cyan, size: 17), const SizedBox(width: 6), const Text('Trim range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const Spacer(), Text('${time(trimOut-trimIn)} selected', style: const TextStyle(color: cyan, fontSize: 11)), TextButton(onPressed: () => setState(() { trimIn = 0; trimOut = total; }), child: const Text('Reset'))]),
          RangeSlider(values: RangeValues(trimIn.clamp(0.0, total).toDouble(), trimOut.clamp(0.0, total).toDouble()), min: 0, max: total, labels: RangeLabels(time(trimIn), time(trimOut)), onChanged: (r) { if (r.end-r.start >= .25) setState(() { trimIn = r.start; trimOut = r.end; }); }),
          Row(children: [Text('IN ${time(trimIn)}', style: const TextStyle(fontSize: 10, color: Colors.white60)), const Spacer(), Text('OUT ${time(trimOut)}', style: const TextStyle(fontSize: 10, color: Colors.white60)), TextButton(onPressed: () => seek(trimIn), child: const Text('Go to IN')), TextButton(onPressed: () => seek(trimOut), child: const Text('Go to OUT'))])
        ])),
        Container(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), decoration: const BoxDecoration(color: panel, border: Border(top: BorderSide(color: Colors.white10))), child: Column(children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            const Text('Canvas', style: TextStyle(color: Colors.white60, fontSize: 12)),
            for (final r in ['9:16','16:9','1:1','4:5']) Padding(padding: const EdgeInsets.only(left: 4), child: ChoiceChip(label: Text(r), selected: ratio == r, onSelected: (_) => setState(() => ratio = r), visualDensity: VisualDensity.compact)),
            PopupMenuButton<double>(initialValue: speed, onSelected: (s) async { setState(() => speed = s); await video?.setPlaybackSpeed(s); }, itemBuilder: (_) => [.5,.75,1.0,1.25,1.5,2.0].map((s) => PopupMenuItem(value:s, child: Text('${s}× speed'))).toList(), child: Padding(padding: const EdgeInsets.all(8), child: Text('${speed}×', style: const TextStyle(color: cyan)))),
            PopupMenuButton<String>(initialValue: filterPreset, onSelected: (f) => setState(() { filterPreset = f; lastExport = null; }), itemBuilder: (_) => ['Original','Warm','Black & white','Vintage','Cool'].map((f) => PopupMenuItem(value: f, child: Text(f))).toList(), child: Padding(padding: const EdgeInsets.all(8), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.filter_vintage, color: cyan, size: 18), const SizedBox(width: 4), Text(filterPreset, style: const TextStyle(color: cyan))])))
          ])),
          if (audioPath != null) Row(children: [const Text('Music', style: TextStyle(fontSize: 11)), Expanded(child: Slider(value: musicVolume, min: 0, max: 1.5, divisions: 15, onChanged: (n) => setState(() => musicVolume = n))), Text('${(musicVolume*100).round()}%', style: const TextStyle(fontSize: 11))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            tool('Audio', Icons.music_note, importAudio),
            tool('Text', Icons.title, editText),
            tool('Transition', Icons.auto_awesome_motion, chooseTransition),
            tool('Save', Icons.save_outlined, saveProject),
            tool('Load', Icons.folder_open, loadProject)
          ]),
          if (lastExport != null) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: shareExport, icon: const Icon(Icons.share, size: 16), label: const Text('Share MP4')))
        ]))
      ]))
    );
  }
}


class AiToolsPage extends StatefulWidget {
  const AiToolsPage({super.key});
  @override
  State<AiToolsPage> createState() => _AiToolsPageState();
}

class _AiToolsPageState extends State<AiToolsPage> {
  final promptController = TextEditingController();
  final modelController = TextEditingController();
  final inputJsonController = TextEditingController(text: '{"prompt": ""}');
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  int selectedType = 0;
  bool creatingAccount = false, busy = false;
  List<Map<String, dynamic>> history = [];
  static const types = ['Image', 'Video', 'Music'];
  static const typeIcons = [Icons.image_outlined, Icons.movie_creation_outlined, Icons.music_note_outlined];
  SupabaseClient get client => Supabase.instance.client;

  @override
  void initState() { super.initState(); loadHistory(); }
  @override
  void dispose() {
    promptController.dispose(); modelController.dispose(); inputJsonController.dispose();
    emailController.dispose(); passwordController.dispose(); super.dispose();
  }

  Future<File> historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/NovaCut');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}/ai_generation_history.json');
  }

  Future<void> loadHistory() async {
    try {
      final file = await historyFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List;
        if (mounted) setState(() => history = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {}
  }

  Future<void> saveHistory() async {
    final file = await historyFile();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(history));
  }

  void showMessage(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> authenticate() async {
    if (emailController.text.trim().isEmpty || passwordController.text.length < 6) {
      showMessage('Enter your email and a password of at least 6 characters.'); return;
    }
    setState(() => busy = true);
    try {
      if (creatingAccount) {
        final result = await client.auth.signUp(email: emailController.text.trim(), password: passwordController.text);
        if (result.session == null) showMessage('Account request sent. Check your email to confirm, then sign in.');
        else showMessage('Signed in successfully.');
      } else {
        await client.auth.signInWithPassword(email: emailController.text.trim(), password: passwordController.text);
        showMessage('Signed in successfully.');
      }
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      showMessage(e.message);
    } catch (e) {
      showMessage('Authentication failed: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> generate() async {
    final session = client.auth.currentSession;
    if (session == null) { showMessage('Sign in or create a NovaCut account before generating.'); return; }
    final model = modelController.text.trim();
    if (model.isEmpty) { showMessage('Enter the exact KIE model ID for this tool.'); return; }
    Map<String, dynamic> input;
    try {
      input = jsonDecode(inputJsonController.text) as Map<String, dynamic>;
    } catch (_) {
      showMessage('Input parameters must be a valid JSON object.'); return;
    }
    if (promptController.text.trim().isNotEmpty) input['prompt'] = promptController.text.trim();
    setState(() => busy = true);
    try {
      final response = await client.functions.invoke('kie-ai', body: {
        'action': 'create', 'model': model, 'input': input,
      });
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw Exception('KIE request failed (HTTP ${response.status}): $data');
      }
      final payload = data['data'] is Map ? Map<String, dynamic>.from(data['data']) : Map<String, dynamic>.from(data);
      final taskId = payload['taskId']?.toString() ?? payload['task_id']?.toString() ?? '';
      final item = <String, dynamic>{
        'type': types[selectedType], 'model': model, 'prompt': promptController.text.trim(),
        'taskId': taskId, 'status': 'Submitted', 'response': data.toString(),
        'createdAt': DateTime.now().toIso8601String(),
      };
      setState(() => history.insert(0, item));
      await saveHistory();
      showMessage(taskId.isEmpty ? 'Request submitted. Check KIE response in history.' : 'Generation task submitted.');
    } on FunctionException catch (e) {
      showMessage('AI request failed: ${e.details ?? e.reasonPhrase ?? e.toString()}');
    } catch (e) {
      showMessage('AI request failed: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> checkStatus(int index) async {
    final taskId = history[index]['taskId']?.toString() ?? '';
    if (taskId.isEmpty) { showMessage('This history entry has no task ID.'); return; }
    if (client.auth.currentSession == null) { showMessage('Sign in to check task status.'); return; }
    setState(() => busy = true);
    try {
      final response = await client.functions.invoke('kie-ai', body: {'action': 'status', 'taskId': taskId});
      if (response.status < 200 || response.status >= 300) throw Exception('HTTP ${response.status}: ${response.data}');
      setState(() {
        history[index]['status'] = 'Status checked';
        history[index]['response'] = response.data.toString();
        history[index]['checkedAt'] = DateTime.now().toIso8601String();
      });
      await saveHistory();
      showMessage('Latest provider response saved to history.');
    } catch (e) {
      showMessage('Could not check status: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final session = client.auth.currentSession;
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.auto_awesome, color: cyan), SizedBox(width: 8), Text('AI Tools')])),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF25214C), Color(0xFF102A37)]),
          borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Create with AI', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            SizedBox(height: 5), Text('Generate images, videos and music with KIE. Your task history is saved on this device.', style: TextStyle(color: Colors.white70))
          ])),
        const SizedBox(height: 16),
        SegmentedButton<int>(segments: const [
          ButtonSegment(value: 0, label: Text('Image'), icon: Icon(Icons.image_outlined)),
          ButtonSegment(value: 1, label: Text('Video'), icon: Icon(Icons.movie_outlined)),
          ButtonSegment(value: 2, label: Text('Music'), icon: Icon(Icons.music_note_outlined)),
        ], selected: {selectedType}, onSelectionChanged: (v) => setState(() => selectedType = v.first)),
        const SizedBox(height: 12),
        TextField(controller: modelController, decoration: const InputDecoration(labelText: 'KIE model ID', hintText: 'Enter the exact model ID from KIE', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: promptController, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Prompt', hintText: 'Describe what you want to create', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: inputJsonController, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Model input parameters (JSON)', helperText: 'Use the exact fields required by your selected KIE model.', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (session == null) ...[
          Text('Sign in to use AI', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password (minimum 6 characters)', border: OutlineInputBorder())),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: creatingAccount, onChanged: (v) => setState(() => creatingAccount = v), title: Text(creatingAccount ? 'Create a new account' : 'I already have an account')),
          FilledButton(onPressed: busy ? null : authenticate, child: Text(busy ? 'Please wait…' : creatingAccount ? 'Create account' : 'Sign in')),
        ] else ...[
          Row(children: [const Icon(Icons.verified_user, color: cyan), const SizedBox(width: 8), Expanded(child: Text(session.user.email ?? 'Signed in')), TextButton(onPressed: () async { await client.auth.signOut(); setState(() {}); }, child: const Text('Sign out'))]),
          FilledButton.icon(onPressed: busy ? null : generate, icon: const Icon(Icons.auto_awesome), label: Text(busy ? 'Working…' : 'Generate ${types[selectedType]}'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50))),
        ],
        const SizedBox(height: 24),
        Row(children: [const Expanded(child: Text('Generation history', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), Text('${history.length} saved')]),
        const SizedBox(height: 8),
        if (history.isEmpty) Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)), child: const Column(children: [Icon(Icons.history, size: 32, color: cyan), SizedBox(height: 8), Text('Your AI requests will appear here'), Text('History is stored locally on this device.', style: TextStyle(color: Colors.white60))]))
        else ...history.asMap().entries.map((entry) {
          final i = entry.key; final item = entry.value;
          return Card(color: panel, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(item['type'] == 'Image' ? Icons.image : item['type'] == 'Video' ? Icons.movie : Icons.music_note, color: cyan), const SizedBox(width: 8), Expanded(child: Text('${item['type']} • ${item['model'] ?? 'KIE'}', style: const TextStyle(fontWeight: FontWeight.bold))), Text(item['status']?.toString() ?? 'Submitted', style: const TextStyle(color: cyan, fontSize: 11))]),
            const SizedBox(height: 6), Text(item['prompt']?.toString().isNotEmpty == true ? item['prompt'].toString() : 'No prompt text', maxLines: 3, overflow: TextOverflow.ellipsis),
            if ((item['taskId']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Task: ${item['taskId']}', style: const TextStyle(color: Colors.white54, fontSize: 11))),
            Row(children: [TextButton.icon(onPressed: busy ? null : () => checkStatus(i), icon: const Icon(Icons.refresh, size: 16), label: const Text('Check status')), const Spacer(), IconButton(onPressed: () async { setState(() => history.removeAt(i)); await saveHistory(); }, icon: const Icon(Icons.delete_outline))])
          ])));
        }),
      ])),
    );
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const NovaCutApp());

class NovaCutApp extends StatelessWidget {
  const NovaCutApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NovaCut',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090B12),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFF), brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const EditorHome(),
  );
}

class EditorHome extends StatefulWidget {
  const EditorHome({super.key});
  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> {
  VideoPlayerController? video;
  String? path;
  String ratio = '9:16';
  String tool = 'Trim';
  bool loading = false;

  Future<void> importVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
      if (result == null || result.files.single.path == null) return;
      setState(() => loading = true);
      final next = VideoPlayerController.file(File(result.files.single.path!));
      await next.initialize();
      await next.setLooping(true);
      final old = video;
      if (!mounted) { await next.dispose(); return; }
      setState(() { video = next; path = result.files.single.path; loading = false; });
      await old?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open video: $e')));
    }
  }

  @override
  void dispose() { video?.dispose(); super.dispose(); }

  String durationLabel(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final v = video;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.cut_rounded, color: Color(0xFF39D8E8)),
          SizedBox(width: 8),
          Text('NovaCut', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video export rendering is not connected in this starter build yet.')),
            ),
            icon: const Icon(Icons.file_upload_outlined), label: const Text('Export'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: Column(children: [
        Expanded(flex: 6, child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: const Color(0xFF05060A), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white12)),
            child: Stack(alignment: Alignment.center, children: [
              if (v != null && v.value.isInitialized)
                Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)))
              else
                const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.movie_creation_outlined, size: 64, color: Color(0xFF39D8E8)),
                  SizedBox(height: 14),
                  Text('Your next great edit starts here', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('Import a video to preview your project', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              if (loading) const CircularProgressIndicator(),
              Positioned(bottom: 10, left: 10, right: 10, child: Row(children: [
                _pill(ratio, Icons.aspect_ratio),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: v == null || !v.value.isInitialized ? null : () async {
                    if (v.value.isPlaying) { await v.pause(); } else { await v.play(); }
                    if (mounted) setState(() {});
                  },
                  icon: Icon(v?.value.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 6),
                _pill(v != null && v.value.isInitialized ? durationLabel(v.value.duration) : '00:00', Icons.timer_outlined),
              ])),
            ]),
          ),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          const Text('TIMELINE', style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(path == null ? 'No clips yet' : '1 clip • ' + durationLabel(v?.value.duration ?? Duration.zero),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
          IconButton(onPressed: importVideo, icon: const Icon(Icons.add_circle, color: Color(0xFF39D8E8))),
        ])),
        SizedBox(height: 102, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
          if (path == null)
            InkWell(onTap: importVideo, child: Container(width: 260, decoration: BoxDecoration(color: const Color(0xFF151925), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF7C5CFF))), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, color: Color(0xFF39D8E8), size: 25), SizedBox(height: 5), Text('Tap to add your first clip', style: TextStyle(fontSize: 12)),
            ])))
          else
            Container(width: 280, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF22233D), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF7C5CFF))), child: Row(children: [
              const Icon(Icons.video_file_outlined, color: Color(0xFF39D8E8), size: 36), const SizedBox(width: 10),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(path!.split(Platform.pathSeparator).last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4), Text(v != null && v.value.isInitialized ? durationLabel(v.value.duration) : 'Loading preview…', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              IconButton(onPressed: importVideo, icon: const Icon(Icons.swap_horiz_rounded)),
            ])),
          const SizedBox(width: 8),
          Container(width: 110, decoration: BoxDecoration(color: const Color(0xFF151925), borderRadius: BorderRadius.circular(14)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.graphic_eq_rounded, color: Colors.white38), SizedBox(height: 5), Text('Audio track', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ])),
        ])),
        Container(padding: const EdgeInsets.fromLTRB(8, 8, 8, 12), decoration: const BoxDecoration(color: Color(0xFF151925), border: Border(top: BorderSide(color: Colors.white10))), child: Column(children: [
          Row(children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Canvas', style: TextStyle(color: Colors.white60, fontSize: 12))),
            for (final r in ['9:16', '16:9', '1:1', '4:5'])
              Padding(padding: const EdgeInsets.only(right: 5), child: ChoiceChip(label: Text(r), selected: ratio == r, onSelected: (_) => setState(() => ratio = r), visualDensity: VisualDensity.compact)),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _toolButton('Trim', Icons.content_cut_rounded),
            _toolButton('Audio', Icons.music_note_rounded),
            _toolButton('Text', Icons.title_rounded),
            _toolButton('Effects', Icons.auto_awesome_rounded),
            _toolButton('Filters', Icons.tonality_rounded),
          ]),
        ])),
      ])),
    );
  }

  Widget _pill(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: const Color(0xFF39D8E8)), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
  );

  Widget _toolButton(String label, IconData icon) {
    final selected = tool == label;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: () {
      setState(() => tool = label);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(video == null ? 'Import a video first.' : '$label tools are planned; actual editing and rendering still need to be implemented.')));
    }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: selected ? const Color(0xFF39D8E8) : Colors.white70, size: 22),
      const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, color: selected ? const Color(0xFF39D8E8) : Colors.white70)),
    ])));
  }
}

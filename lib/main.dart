import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const NovaCutApp());

const _bg = Color(0xFF090B12);
const _panel = Color(0xFF151925);
const _purple = Color(0xFF7C5CFF);
const _cyan = Color(0xFF39D8E8);

class NovaCutApp extends StatelessWidget {
  const NovaCutApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NovaCut',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _purple,
            brightness: Brightness.dark,
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: _cyan,
            thumbColor: _cyan,
            overlayColor: Color(0x3339D8E8),
          ),
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
  VideoPlayerController? _video;
  String? _path;
  String _ratio = '9:16';
  String _tool = 'Trim';
  bool _loading = false;
  bool _muted = false;
  double _playbackSpeed = 1;
  double _trimStart = 0;
  double _trimEnd = 1;

  Duration get _duration =>
      _video != null && _video!.value.isInitialized
          ? _video!.value.duration
          : Duration.zero;

  double get _durationSeconds =>
      _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds / 1000.0;

  double get _playheadSeconds =>
      _video != null && _video!.value.isInitialized
          ? _video!.value.position.inMilliseconds / 1000.0
          : 0;

  Future<void> _importVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) return;

      setState(() => _loading = true);
      final next = VideoPlayerController.file(File(result.files.single.path!));
      await next.initialize();
      await next.setLooping(true);
      await next.setPlaybackSpeed(_playbackSpeed);
      await next.setVolume(_muted ? 0 : 1);

      final old = _video;
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _video = next;
        _path = result.files.single.path;
        _trimStart = 0;
        _trimEnd = next.value.duration.inMilliseconds / 1000.0;
        _loading = false;
      });
      next.addListener(_onVideoTick);
      await old?.dispose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not open video: $error');
    }
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  Future<void> _seek(double seconds) async {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    await v.seekTo(Duration(milliseconds: (seconds * 1000).round()));
  }

  Future<void> _togglePlayback() async {
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      _message('Import a video to start editing.');
      return;
    }
    if (v.value.isPlaying) {
      await v.pause();
    } else {
      if (_playheadSeconds >= _trimEnd) {
        await _seek(_trimStart);
      }
      await v.play();
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _video?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _video?.setPlaybackSpeed(speed);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    super.dispose();
  }

  String _time(double seconds) {
    final safe = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final remainder = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final initialized = v != null && v.value.isInitialized;
    final duration = initialized ? _durationSeconds : 1.0;
    final playhead = _playheadSeconds.clamp(0.0, duration);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Row(children: [
          Icon(Icons.cut_rounded, color: _cyan, size: 25),
          SizedBox(width: 8),
          Text('NovaCut', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Project settings',
            onPressed: _showProjectSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _exportNotice,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Export'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF05060A),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white12),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  if (initialized)
                    Center(
                      child: AspectRatio(
                        aspectRatio: v.value.aspectRatio,
                        child: VideoPlayer(v),
                      ),
                    )
                  else
                    const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.movie_creation_outlined, size: 60, color: _cyan),
                      SizedBox(height: 14),
                      Text('Make every frame count',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      Text('Import a video to begin your project',
                          style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ]),
                  if (_loading)
                    const CircularProgressIndicator(color: _cyan),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Row(children: [
                      _pill(_ratio, Icons.aspect_ratio),
                      const Spacer(),
                      _pill(_muted ? 'Muted' : '${_playbackSpeed}×', _muted ? Icons.volume_off : Icons.speed),
                    ]),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 10,
                    right: 10,
                    child: Row(children: [
                      IconButton(
                        tooltip: _muted ? 'Unmute preview' : 'Mute preview',
                        onPressed: initialized ? _toggleMute : null,
                        icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                      ),
                      Text(_time(playhead), style: const TextStyle(fontSize: 11, fontFeatures: [])),
                      Expanded(
                        child: Slider(
                          value: playhead,
                          min: 0,
                          max: duration,
                          onChanged: initialized ? (value) => _seek(value) : null,
                        ),
                      ),
                      Text(_time(duration), style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        onPressed: _togglePlayback,
                        icon: Icon(v?.value.isPlaying == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
            child: Row(children: [
              const Text('TIMELINE',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                _path == null ? 'No clips yet' : '1 clip • ${_time(duration)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              IconButton(
                tooltip: 'Import video',
                onPressed: _importVideo,
                icon: const Icon(Icons.add_circle, color: _cyan),
              ),
            ]),
          ),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                if (_path == null)
                  InkWell(
                    onTap: _importVideo,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _purple),
                      ),
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_rounded, color: _cyan, size: 24),
                        SizedBox(height: 4),
                        Text('Tap to add your first clip', style: TextStyle(fontSize: 12)),
                      ]),
                    ),
                  )
                else
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22233D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _purple),
                    ),
                    child: Row(children: [
                      const Icon(Icons.video_file_outlined, color: _cyan, size: 34),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_path!.split(Platform.pathSeparator).last,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${_time(_trimStart)} – ${_time(_trimEnd)}',
                              style: const TextStyle(color: _cyan, fontSize: 11)),
                        ],
                      )),
                      IconButton(
                        tooltip: 'Replace clip',
                        onPressed: _importVideo,
                        icon: const Icon(Icons.swap_horiz_rounded),
                      ),
                    ]),
                  ),
                const SizedBox(width: 8),
                Container(
                  width: 100,
                  decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.graphic_eq_rounded, color: Colors.white38),
                    SizedBox(height: 4),
                    Text('Audio track', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  ]),
                ),
              ],
            ),
          ),
          if (initialized)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.content_cut_rounded, color: _cyan, size: 17),
                  const SizedBox(width: 7),
                  const Text('Trim range', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const Spacer(),
                  Text('${_time(_trimEnd - _trimStart)} selected',
                      style: const TextStyle(color: _cyan, fontSize: 11)),
                  TextButton(
                    onPressed: () => setState(() {
                      _trimStart = 0;
                      _trimEnd = duration;
                    }),
                    child: const Text('Reset', style: TextStyle(fontSize: 11)),
                  ),
                ]),
                RangeSlider(
                  values: RangeValues(
                    _trimStart.clamp(0.0, duration),
                    _trimEnd.clamp(0.0, duration),
                  ),
                  min: 0,
                  max: duration,
                  labels: RangeLabels(_time(_trimStart), _time(_trimEnd)),
                  onChanged: (values) {
                    if (values.end - values.start < 0.25) return;
                    setState(() {
                      _trimStart = values.start;
                      _trimEnd = values.end;
                    });
                  },
                ),
                Row(children: [
                  Text('IN  ${_time(_trimStart)}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                  const Spacer(),
                  Text('OUT  ${_time(_trimEnd)}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _seek(_trimStart),
                    icon: const Icon(Icons.first_page_rounded, size: 16),
                    label: const Text('Go to IN', style: TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: () => _seek(_trimEnd),
                    icon: const Icon(Icons.last_page_rounded, size: 16),
                    label: const Text('Go to OUT', style: TextStyle(fontSize: 10)),
                  ),
                ]),
              ]),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: const BoxDecoration(
              color: _panel,
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(children: [
              Row(children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7),
                  child: Text('Canvas', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
                for (final r in ['9:16', '16:9', '1:1', '4:5'])
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: ChoiceChip(
                      label: Text(r),
                      selected: _ratio == r,
                      onSelected: (_) => setState(() => _ratio = r),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: 'Playback speed',
                  initialValue: _playbackSpeed,
                  onSelected: _setSpeed,
                  itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                      .map((s) => PopupMenuItem(value: s, child: Text('${s}× speed')))
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('${_playbackSpeed}×', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _toolButton('Trim', Icons.content_cut_rounded),
                _toolButton('Audio', Icons.music_note_rounded),
                _toolButton('Text', Icons.title_rounded),
                _toolButton('Effects', Icons.auto_awesome_rounded),
                _toolButton('Filters', Icons.tonality_rounded),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .68),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: _cyan),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _toolButton(String label, IconData icon) {
    final selected = _tool == label;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _tool = label);
        if (label != 'Trim') {
          _message(_path == null
              ? 'Import a video first. The $label editor is not implemented yet.'
              : '$label is selected. This tool still needs its editing and rendering implementation.');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? _cyan : Colors.white70, size: 21),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: selected ? _cyan : Colors.white70)),
        ]),
      ),
    );
  }

  void _showProjectSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Project settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.aspect_ratio_rounded, color: _cyan),
              title: const Text('Canvas ratio'),
              subtitle: Text('Current setting: $_ratio'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed_rounded, color: _cyan),
              title: const Text('Preview playback speed'),
              subtitle: Text('${_playbackSpeed}×'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.offline_bolt_outlined, color: _cyan),
              title: Text('Local-first editing'),
              subtitle: Text('Imported video preview runs on this device.'),
            ),
          ]),
        ),
      ),
    );
  }

  void _exportNotice() {
    _message(_path == null
        ? 'Import a video before preparing an export.'
        : 'Trim points are selectable, but MP4 rendering/export is not implemented yet. No file has been exported.');
  }
}

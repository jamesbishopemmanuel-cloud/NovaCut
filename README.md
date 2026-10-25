# NovaCut

NovaCut is an offline-first Flutter video-editor prototype.

## Included editor workflow
- Import multiple local video files into an ordered horizontal timeline.
- Reorder clips with drag and drop, split the selected clip at the preview playhead, and remove clips.
- Preview the selected source clip and adjust playback speed.
- Set export canvas to 9:16, 16:9, 1:1, or 4:5.
- Apply basic grayscale, warm, and vintage color treatments.
- Add a caption/title overlay, mix in a selected music track, and export an MP4 using FFmpeg.
- Save/load project settings and clip edit points locally; undo/redo clip-list edits.
- Share the resulting MP4 from the device.

## Build
Use the repository's Android GitHub Actions workflow to build the APK. The code depends on the packages already declared in `pubspec.yaml`.

## Current limitations
This is not a complete CapCut replacement. The timeline currently models ordered clip segments rather than independent video/audio/text tracks. Caption text is applied across rendered segments, audio mixing replaces source clip audio with the chosen music track, and transitions, keyframes, animated effects, stickers, chroma key, automatic captions, and advanced audio controls are not implemented. Export compatibility depends on the FFmpeg binaries and the source media; verify with real files on Android before release.

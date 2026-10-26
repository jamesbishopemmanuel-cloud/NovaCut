# NovaCut

NovaCut is an offline-first Flutter video-editor prototype.

## Editing tools
- Multi-video import, ordered timeline, drag reordering, split, delete, undo, and redo.
- Preview and playback-speed control.
- Export aspect ratios 9:16, 16:9, 1:1, and 4:5.
- Grayscale, warm, and vintage presets plus manual brightness, contrast, and saturation controls.
- Title/caption overlay.
- Original-audio volume control, separate music selection, and configurable video/audio fade-in/fade-out.
- MP4 export, sharing, local JSON project save/load, and project-file import/export.

## Project portability
Project JSON stores edit settings and media paths, not source media bytes. Original files must remain accessible; moving a project to another device may require re-importing media.

## QA and limitations
Test on Android with media that does and does not contain audio. FFmpeg package compatibility, font availability, codecs, memory use, and export behavior still require verification. The project currently uses an ordered clip list, not a true multi-track timeline. Animated transitions, keyframes, stickers, picture-in-picture, chroma key, automatic captions, voice recording, waveform editing, and a rich effects library are not implemented. NovaCut is not yet a complete CapCut replacement.

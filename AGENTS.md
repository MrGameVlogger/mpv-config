# MPV Configuration Notes

## System
- macOS, Apple M2 Max (Mac14,6), 3456x2234 Retina display @ 120Hz
- 12-core (8 Performance + 4 Efficiency), 64 GB RAM
- mpv via Homebrew (currently v0.41.0_9), Vulkan rendering through MoltenVK
- FFmpeg 9.0.1, libplacebo v7.360.1, MoltenVK 1.4.2
- Primary media source: Jellyfin server via jellyfin.lua script

## Backup
- Private GitHub repository: https://github.com/MrGameVlogger/mpv-config
- Excludes: `.DS_Store`, `mpv.log`, `watch_later/`, `watch_history.jsonl`

## Configuration Philosophy
- Do NOT remove or change settings without asking, even if they appear unused.
- Keep config clean but don't sacrifice functionality for minimalism.
- When making changes, explain what and why before editing.
- Prefer commenting out over deleting when disabling features.

## Known Issues & Quirks

### MoltenVK Display Timing (Critical)
- MoltenVK's VK_GOOGLE_display_timing extension is broken.
- None of the display-sync modes work reliably:
  - `display-resample` — massive frame drops (145 in 57 seconds)
  - `display-vdrop` — still drops frames (69-88 per session)
  - `display-desync` — untested but likely same issue
- **Must use `video-sync=audio`** until MoltenVK fixes their timing implementation.
- The `DS:` metric in mpv status will not appear with audio sync (this is normal).
- `interpolation=yes` requires a display-sync mode and cannot be used.

### Hardware Decoding
- `hwdec=auto-copy` is required (not zero-copy) because scripts need CPU-side frame access.
- `hwdec=videotoolbox` (zero-copy) was tested but results were inconclusive — it was tested during the display-sync debugging period, so the frame drops observed may have been caused by the broken display timing rather than the decode mode itself.
- `hwdec-codecs=all` enables hardware decoding for all codecs.
- `hwdec-threads=4` provides dedicated threads for the VideoToolbox copy-back path.
- `vd-lavc-threads=0` — auto-detect decoder thread count (was hardcoded to 8).

### FFmpeg 9.0
- Upgraded from 8.x to 9.0 via Homebrew revision bump (mpv 0.41.0_8).
- Introduced `mmco: unref short failure` errors in the H.264 decoder with VideoToolbox.
- Root cause was the broken MoltenVK display timing, not a standalone ffmpeg bug — the mmco errors were a symptom of the timing issue.

### Content-Specific Notes
- 10-bit H.264 content (BDRips like Toradora) outputs `p010` pixel format.
- 8-bit content outputs `nv12` — less GPU-intensive.
- The shader chain handles both but is more demanding on 10-bit content.
- At 3456x2234 Retina with 120Hz, the full shader chain works fine with audio sync.

## mpv.conf Structure

### Audio
- `ao=coreaudio` — macOS audio output.
- `volume-max=200` — allows volume above 100%.

### Video Output
- `vo=gpu-next` — libplacebo-based renderer (default in mpv 0.41)
- `gpu-api=vulkan` — Vulkan backend via MoltenVK
- `gpu-context=macvk` — macOS Vulkan context
- `profile=high-quality` — sets ewa_lanczossharp scaling, sigmoid upscaling, etc.
- `vulkan-async-transfer=yes` — async texture uploads through MoltenVK
- `vulkan-async-compute=yes` — async compute shaders
- `video-latency-hacks=yes` — reduces latency (safe without display-sync)

### Deband
- `deband=no` by default, toggled with `n` key at runtime.
- `deband-iterations=4`, `deband-range=24`, `deband-grain=16` are configured for when the toggle is active. Do NOT remove these.

### Cache
- `demuxer-max-bytes=8192M` — intentionally high for Jellyfin streaming over network.
- `demuxer-max-back-bytes=2048M` — allows large rewinding buffer.
- `demuxer-readahead-secs=90` — aggressive readahead for streaming.
- `demuxer-hysteresis-secs=10` — cache hysteresis threshold.
- `cache-pause=no` — don't pause when buffer is empty.

### Playback
- `video-sync=audio` — audio-driven sync (display-sync broken on MoltenVK).
- `interpolation=no` — disabled (requires display-sync mode).
- `hr-seek=absolute` — precise seeking.
- `keep-open=yes` — don't close window after playback ends.
- `save-position-on-quit=yes` — resume from last position.
- `save-watch-history=yes` — track watch history.
- `autocreate-playlist=same` — auto-add files from same directory.
- `swapchain-depth=4` — extra presentation buffer headroom.

### Screenshots
- `screenshot-format=png` — PNG format for lossless screenshots.
- `screenshot-dir="~/Pictures/mpv"` — save location.
- `screenshot-template="%F-%p-%n"` — filename format.
- `screenshot-high-bit-depth=yes` — preserve HDR color depth.

### Logging
- `log-file=~~/mpv.log` — log file location (overwritten each session).

### Window
- `fullscreen=yes` — starts in fullscreen.
- `osc=no` — disabled because modernx.lua handles the OSC.
- `border=no` — borderless window.
- `no-hidpi-window-scale` — don't auto-scale on Retina.
- `cursor-autohide=1000` — hide cursor after 1 second.
- `geometry=50%:50%` — center window (unused when fullscreen).
- `autofit=100%` — fill screen (unused when fullscreen).
- `window-maximized=no` — not maximized (unused when fullscreen).

### Subtitles
- `blend-subtitles=yes` — CPU-side subtitle compositing (not `=video` which is GPU-heavy).
- `sub-gauss=1.0` — slight subtitle blur for readability.
- `sub-ass-override=no` — don't override ASS subtitle styling.
- `sub-ass-style-overrides=playresx=1920,playresy=1080,Kerning=yes` — affects non-ASS subs only.
- `subs-with-matching-audio=no` — don't auto-select subs matching audio language.
- `demuxer-mkv-subtitle-preroll=index` — improved subtitle preroll for MKV files.
- Custom subtitle styling with Gandhi Sans font, red border, shadow.
  - `sub-font="Gandhi Sans"`, `sub-font-size=50`, `sub-color="#FFFFFF"`
  - `sub-margin-y=40`, `sub-border-size=2.4`, `sub-border-color="#FF000000"`
  - `sub-shadow-color="#A0000000"`, `sub-shadow-offset=0.75`, `sub-bold=yes`

### Languages
- Subtitle priority: enm (Middle English), eng, en (honorifics before English).
- Audio priority: ja, jp, jpn (Japanese first).
- Dub config is commented out — switch manually when needed.

### yt-dlp
- Format preference: HEVC 4K → VP9 4K → AV1 1080p → best.
- Uses aria2c as external downloader.

### Profiles (Conditional Auto-Profiles)

#### [HDR]
- Triggers when content has PQ or HLG gamma (HDR content).
- Uses bt.2446a tone mapping, perceptual gamut mapping.
- `target-peak=500` tuned for SDR display peak brightness.
- `target-colorspace-hint=yes` for proper HDR passthrough on supported displays.

#### [4K]
- Triggers when height >= 2160.
- Applies CfL_Prediction + SSimSuperRes shaders.
- Does NOT use ravu-zoom (native resolution doesn't need upscaling).

#### [1080p-1440p]
- Triggers when height >= 1080 and < 2160.
- Applies full shader chain: ravu-zoom + CfL_Prediction + SSimSuperRes.
- This is the most common profile for anime BDRips.

#### [Sub-1080p]
- Triggers when height < 1080.
- Same full shader chain as 1080p-1440p.
- ravu-zoom handles the larger upscale factor.

## Scripts

### trickplay-jf-osc.lua
- Jellyfin-styled OSC with built-in Trickplay support.
- Repo: https://github.com/iwalton3/jf-mpv-osc
- Replaces ModernX as the active OSC.
- Works with thumbfast for seekbar thumbnails.
- `osc=no` in mpv.conf disables the built-in OSC (this script replaces it).

### modernx.lua (v0.4.7) (DISABLED)
- On-screen controller replacement by zydezu.
- Repo: https://github.com/zydezu/ModernX
- Disabled by renaming to modernx.lua.disabled.
- Config: script-opts/modernx.conf
- Re-enable by renaming back to modernx.lua and disabling trickplay-jf-osc.lua.

### jellyfin.lua
- Jellyfin playback integration by EmperorPenguin18.
- Repo: https://github.com/EmperorPenguin18/mpv-jellyfin
- Launches mpv in idle mode, receives play commands via WebSocket.
- Handles playlist management, position reporting, episode navigation.
- Config: script-opts/jellyfin.conf

### sponsorblock.lua
- SponsorBlock segment skipping, zydezu's fork for modernx integration.
- Repo: https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua
- Companion files: sponsorblock_shared/main.lua, sponsorblock_shared/sponsorblock.py
- Config: script-opts/sponsorblock.conf

### thumbfast.lua
- Video thumbnail generation on seekbar hover.
- Repo: https://github.com/po5/thumbfast
- Spawns a subprocess for thumbnail generation.
- Config: script-opts/thumbfast.conf
- Local modifications:
  - Increased subprocess cache (`--demuxer-readahead-secs=600`, `--demuxer-max-bytes=2048MiB`) for better Jellyfin streaming performance.
  - Jellyfin Trickplay support merged in — fetches server-side thumbnails for Jellyfin streams instead of spawning subprocess.
  - Requires `curl` and `ffmpeg` (at `/opt/homebrew/bin/ffmpeg`) for Trickplay.
  - Upstream backup: `thumbfast-upstream.lua` (verified exact copy from GitHub).
  - Standalone release: https://github.com/MrGameVlogger/thumbfast-jellyfin

### trackselect.lua
- Track selection helper — selects non-dub audio and subtitle tracks automatically.
- Repo: https://github.com/po5/trackselect
- Config: script-opts/trackselect.conf

### autocrop.lua (DISABLED)
- Stock mpv script for automatic black bar detection and cropping.
- Currently disabled by renaming to autocrop.lua.disabled.
- Disabled because it caused p010/yuv420p10 pixel format toggling with hwdec=auto-copy.
- If re-enabled, may cause GPU pipeline thrashing with 10-bit content.

## Shaders
All shaders are in the `shaders/` directory and applied via conditional profiles.

### ravu-zoom-ar-r3.hook
- High-quality upscaling shader from the RAVU family.
- Handles both luma and chroma upscaling.
- Applied for content below native display resolution.
- Source: https://github.com/bjin/mpv-prescalers (file: ravu-zoom-ar-r3.hook in repo root)

### CfL_Prediction.glsl
- Chroma from Luma prediction by João Chrisóstomo.
- Reconstructs chroma signal from luma information for better chroma upsampling.
- Applied to all content.
- Source: https://github.com/Artoriuz/glsl-chroma-from-luma-prediction

### SSimSuperRes.glsl
- Super-resolution enhancement by Shiandow.
- Sharpens and enhances detail based on structural similarity (SSIM).
- 4 render passes (2 downscale + variance + 3x3 final).
- Has a `#define oversharp 0.5` parameter (line 151) but changing it doesn't reduce GPU load.
- Source: Originally from igv/SSimSuperRes (repo no longer available on GitHub). Commonly distributed through mpv community shader collections.

### Other Available Shaders (not in auto-profiles, toggled via keybinds)
- ArtCNN_C4F16.glsl — neural network upscaling by João Chrisóstomo & Kacper Michajłow. Source: https://github.com/Artoriuz/ArtCNN
- SSimDownscaler.glsl — high-quality downscaling by Shiandow. Source: Originally from igv/SSimDownscaler (repo no longer available). Commonly distributed through mpv community.
- adaptive-sharpen.glsl — adaptive sharpening filter by bacondither. Source: https://github.com/bacondither/Adaptive-sharpen

## Troubleshooting

### Frame Drops
1. Check `DS:` or `Dropped:` in the status line.
2. If `DS:` shows a number far from expected (5.0 for 120Hz/24fps), it's a display timing issue.
3. Verify `video-sync=audio` is active.
4. Check GPU usage — if low, the bottleneck is elsewhere (timing, not rendering).
5. Check for `mmco: unref short failure` errors in mpv.log (likely related to display timing).

### Log Locations
- mpv log: `~/.config/mpv/mpv.log` (overwritten each session)
- Jellyfin logs: `~/Library/Application Support/JellyfinMpvPlay/data/jellyfin-mpv-play-*.log`

### Key Commands for Debugging
- `i` or `I` — toggle stats overlay (shows dropped frames, sync, codec info)
- `Shift+I` — detailed stats page
- `n` — toggle deband
- `j` / `J` — cycle subtitles
- `#` — cycle audio tracks

### Custom Keybinds (input.conf)
- `Ctrl+g` — toggle RAVU ↔ ArtCNN shader stack
- `Ctrl+h` — toggle SSimDownscaler on/off
- `n` — toggle deband (changed from `b` to avoid ModernX conflict)
- `k` — toggle sub-ass-override (force/no)

## Version History
- 2025-12-21: mpv 0.41.0 released (gpu-next now default, Vulkan hwdec preferred)
- 2026-03-18: mpv 0.41.0_4 — ffmpeg 8.1 revision bump
- 2026-02-12: mpv 0.41.0_2 — libplacebo 7.360.0 revision bump
- 2026-07-20: mpv 0.41.0_6 — enabled pipewire
- 2026-07-29: mpv 0.41.0_7 — libbluray 1.5.0 revision bump
- 2026-08-11: mpv 0.41.0_8 — ffmpeg 9.0 revision bump (caused frame drops due to MoltenVK display timing)
- 2026-08-31: mpv 0.41.0_9 — ffmpeg 9.0.1 bugfix, Vapoursynth 74+ backport

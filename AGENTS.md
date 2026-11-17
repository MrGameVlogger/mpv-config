# MPV configuration notes

## System
- macOS, Apple M2 Max (Mac14,6), 3456x2234 Retina display at 120Hz
- 12-core (8 Performance + 4 Efficiency), 64 GB RAM
- mpv via Homebrew (currently v0.42.0), Vulkan rendering through MoltenVK
- FFmpeg 9.0.2, libplacebo v7.387.0, MoltenVK 1.4.2
- Primary media source: Jellyfin server via Jellyfin MPV Play (the shim spawns
  mpv and talks to jf-mpv-osc over script messages). jellyfin.lua is disabled.

## Backup
- Public GitHub repository: https://github.com/MrGameVlogger/mpv-config
- Excludes (see .gitignore): `.DS_Store`, `mpv.log`, `watch_later/`,
  `watch_history.jsonl`, `script-opts/jellyfin.conf`, `sponsorblock.txt`

## Releases and vendored-script sync
- This repo has no release cycle: the live artifact is the git clone at
  `~/.config/mpv`. Deploying means running `git -C ~/.config/mpv pull origin main`
  after a PR merges. Never edit the live tree without a PR. It must stay
  a clean clone.
- Two scripts are vendored and must stay byte-identical with their source
  repos (verify with `diff` after every sync):
  - `scripts/thumbfast.lua`, synced from
    https://github.com/MrGameVlogger/thumbfast-jellyfin releases (track the
    version pin in the Scripts section below). Needs v1.1.3 or newer on
    Jellyfin 12 servers. Older parsers read only the Trickplay shape used up
    to 10.9 and report "No Trickplay data" for every item.
  - `scripts/trickplay-jf-osc.lua`, synced from
    https://github.com/MrGameVlogger/jf-mpv-osc `main`
- Sync procedure for either: copy the file, run `diff` to confirm it is
  identical, open a PR here, merge, then run `git -C ~/.config/mpv pull`.
  Update the version pin and notes in this file in the same PR.
- All changes go through PRs, even docs (see the fork's PR workflow).

## Configuration philosophy
- Do NOT remove or change settings without asking, even if they appear unused.
- Keep config clean but don't sacrifice functionality for minimalism.
- When making changes, explain what and why before editing.
- Prefer commenting out over deleting when disabling features.

## Known issues and quirks

### MoltenVK display timing
- MoltenVK's VK_GOOGLE_display_timing extension has issues with some display-sync modes.
- `display-resample` works but has occasional missed vsyncs (100-600 per session observed).
- `interpolation=yes` requires a display-sync mode but is disabled because it causes frame drops and is bad for anime.
- `video-sync=audio` is used because all content has clean ratios on 120Hz (24fps=5:1, 30fps=4:1, 60fps=2:1).
- Display-sync only helps for non-integer ratios (for example 25fps PAL), which is not our content.

### Hardware decoding
- `hwdec=auto-copy` is required (not zero-copy) because scripts need CPU-side frame access.
- `hwdec=videotoolbox` (zero-copy) was tested but results were inconclusive. It was tested during the display-sync debugging period, so the frame drops observed may have been caused by the broken display timing rather than the decode mode itself.
- `hwdec-codecs=all` enables hardware decoding for all codecs.
- `hwdec-threads=4` provides dedicated threads for the VideoToolbox copy-back path.
- `vd-lavc-threads=0` auto-detects the decoder thread count (was hardcoded to 8).

### FFmpeg 9.0
- Upgraded from 8.x to 9.0 via Homebrew revision bump (mpv 0.41.0_8).
- Introduced `mmco: unref short failure` errors in the H.264 decoder with VideoToolbox.
- Root cause was the broken MoltenVK display timing, not a standalone ffmpeg bug. The mmco errors were a symptom of the timing issue.

### Content-specific notes
- 10-bit H.264 content (BDRips like Toradora) outputs `p010` pixel format.
- 8-bit content outputs `nv12`, which is less GPU-intensive.
- The shader chain handles both but is more demanding on 10-bit content.
- At 3456x2234 Retina with 120Hz, the full shader chain works fine with audio sync.

## mpv.conf structure

### Audio
- `ao=coreaudio` is the macOS audio output.
- `volume-max=200` allows volume above 100%.

### Video output
- `vo=gpu-next` is the libplacebo-based renderer (default in mpv 0.41)
- `gpu-api=vulkan` selects the Vulkan backend via MoltenVK
- `gpu-context=macvk` selects the macOS Vulkan context
- `profile=high-quality` sets ewa_lanczossharp scaling, sigmoid upscaling, and more
- `vulkan-async-transfer=yes` enables async texture uploads through MoltenVK
- `vulkan-async-compute=yes` enables async compute shaders
- `video-latency-hacks=yes` reduces latency (safe without display-sync)

### Deband
- `deband=no` is the default. The `n` key toggles deband at runtime.
- `deband-iterations=4`, `deband-range=24`, `deband-grain=16` are configured for when the toggle is active. Do NOT remove these.

### Cache
- `demuxer-max-bytes=8192M` is intentionally high for Jellyfin streaming over the network.
- `demuxer-max-back-bytes=2048M` allows a large rewinding buffer.
- `demuxer-readahead-secs=90` buffers 90 seconds ahead for streaming.
- `demuxer-hysteresis-secs=10` is the cache hysteresis threshold.
- `cache-pause=yes` pauses playback when the buffer is empty (prevents playback issues during streaming).

### Playback
- `video-sync=audio` is audio-driven sync (display-sync is broken on MoltenVK).
- `interpolation=no` is disabled (it requires a display-sync mode).
- `hr-seek=absolute` gives precise seeking.
- `keep-open=yes` keeps the window open after playback ends.
- `save-position-on-quit=yes` resumes from the last position.
- `save-watch-history=yes` tracks watch history.
- `autocreate-playlist=same` adds files from the same directory automatically.
- `swapchain-depth=4` adds extra presentation buffers.
- `reset-on-next-file=audio-delay,mute,pause,speed,sub-delay` resets those between files.

### Screenshots
- `screenshot-format=png` saves PNG for lossless screenshots.
- `screenshot-dir="~/Pictures/mpv"` is the save location.
- `screenshot-template="%F-%p-%n"` is the filename format.
- `screenshot-high-bit-depth=yes` preserves HDR color depth.
- `screenshot-tag-colorspace=yes` tags colorspace in screenshots.

### Logging
- `log-file=~~/mpv.log` is the log file location (overwritten each session).

### Window
- `fullscreen=yes` starts in fullscreen.
- `osc=no` disables the built-in OSC because trickplay-jf-osc.lua replaces it.
- `border=no` gives a borderless window.
- `no-hidpi-window-scale` stops auto-scaling on Retina.
- `cursor-autohide=1000` hides the cursor after 1 second.
- `geometry=50%:50%` centers the window (unused when fullscreen).
- `autofit=100%` fills the screen (unused when fullscreen).
- `window-maximized=no` leaves the window unmaximized (unused when fullscreen).
- `force-window=immediate` opens the window immediately on launch.
- `macos-fs-animation-duration=0` disables the macOS fullscreen animation.

### Subtitles
- `blend-subtitles=yes` composites subtitles on the CPU (`=video` would move it to the GPU).
- `sub-gauss=1.0` blurs subtitles slightly for readability.
- `sub-ass-override=no` keeps ASS subtitle styling intact.
- `sub-ass-style-overrides=playresx=1920,playresy=1080,Kerning=yes` affects non-ASS subs only (SRT and similar). It is never applied to ASS subtitles.
- `subs-with-matching-audio=no` skips subtitles that match the audio language.
- `demuxer-mkv-subtitle-preroll=index` improves subtitle preroll for MKV files.
- Custom subtitle styling uses the Gandhi Sans font, black border and shadow.
  - `sub-font="Gandhi Sans"`, `sub-font-size=50`, `sub-color="#FFFFFF"`
  - `sub-margin-y=40`, `sub-border-size=2.4`, `sub-border-color="#FF000000"`
  - `sub-shadow-color="#A0000000"`, `sub-shadow-offset=0.75`, `sub-bold=yes`

### Languages
- Subtitle priority: enm (Middle English), eng, en (honorifics before English).
- Audio priority: ja, jp, jpn (Japanese first).
- Dub config is commented out. Switch manually when needed.

### yt-dlp
- Format preference: HEVC 4K, then VP9 4K, then AV1 1080p, then best.
- Uses aria2c as external downloader.

### Profiles (conditional auto-profiles)

#### [HDR]
- Triggers when content has PQ or HLG gamma (HDR content).
- Uses bt.2446a tone mapping (fallback if display can't handle HDR natively).
- `target-peak=1600` is tuned for the M2 Max XDR display peak brightness.
- `target-colorspace-hint=yes` signals HDR passthrough to the display.

#### [4K]
- Triggers when height >= 2160.
- Applies CfL_Prediction and SSimSuperRes shaders.
- Does NOT use ravu-zoom (native resolution doesn't need upscaling).

#### [1080p-1440p]
- Triggers when height >= 1080 and < 2160.
- Applies the full shader chain: ravu-zoom, CfL_Prediction, and SSimSuperRes.
- This is the most common profile for anime BDRips.

#### [Sub-1080p]
- Triggers when height < 1080.
- Uses the same full shader chain as 1080p-1440p.
- ravu-zoom handles the larger upscale factor.

## Scripts

Vendored scripts keep their upstream licenses; the repo's MIT `LICENSE` covers
the configuration itself, not the files in `scripts/`. Known terms:
`trickplay-jf-osc.lua` is GPL-3.0-or-later for the jellyfin-mpv-shim-derived
parts (Material icon data Apache-2.0, mpv `osc.lua` base terms, see its repo
`LICENSE.md`); `thumbfast.lua` and `backup/thumbfast-upstream.lua` are MPL-2.0
(in-file headers).

### trickplay-jf-osc.lua
- Jellyfin-styled OSC with built-in Trickplay support.
- Maintained at https://github.com/MrGameVlogger/jf-mpv-osc (originally from
  https://github.com/iwalton3/jf-mpv-osc). Vendored here byte-identical.
  Keep the two copies in sync.
- Replaces ModernX as the active OSC.
- Works with thumbfast for seekbar thumbnails.
- `osc=no` in mpv.conf disables the built-in OSC (this script replaces it).
- With the shim it provides action sheets (subtitles, audio, settings), queue
  prev/next, favorite, skip-intro and SyncPlay. Every control also works on
  plain-mpv playback (local files) via its hostless fallbacks: back and close
  quit mpv, Screenshot and "Quit Without Saving Position" act locally, and
  the subtitle style rows edit mpv's sub-scale, sub-pos and sub-color.

### modernx.lua (v0.4.7) (disabled)
- On-screen controller replacement by zydezu.
- Repo: https://github.com/zydezu/ModernX
- Parked at `backup/modernx.lua.disabled` (out of `scripts/`, because mpv attempts to load every file there).
- Config: script-opts/modernx.conf
- Re-enable by moving it back to `scripts/modernx.lua` and disabling trickplay-jf-osc.lua.

### jellyfin.lua (disabled)
- Jellyfin playback integration by EmperorPenguin18.
- Repo: https://github.com/EmperorPenguin18/mpv-jellyfin
- Parked at `backup/jellyfin.lua.disabled` (out of `scripts/`). Jellyfin MPV Play handles
  playback via IPC now. Kept for standalone use without the macOS app.
- Config: script-opts/jellyfin.conf.example (copy to jellyfin.conf to use)

### sponsorblock.lua
- SponsorBlock segment skipping, zydezu's fork for modernx integration.
- Repo: https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua
- Companion files: sponsorblock_shared/main.lua, sponsorblock_shared/sponsorblock.py
- Config: script-opts/sponsorblock.conf

### thumbfast.lua
- Video thumbnail generation on seekbar hover.
- Fork of https://github.com/po5/thumbfast with Jellyfin Trickplay support.
  It fetches server-side thumbnails for Jellyfin streams instead of spawning
  a subprocess, and falls back to the normal thumbfast subprocess otherwise.
- Requires `curl` (via PATH) and `ffmpeg` (auto-resolved at startup from
  common paths, Homebrew first) for Trickplay.
- Config: script-opts/thumbfast.conf
- Upstream backup: `backup/thumbfast-upstream.lua` (verified exact copy from GitHub; kept out of `scripts/` because mpv attempts to load every file there).
- Synced from https://github.com/MrGameVlogger/thumbfast-jellyfin (v1.2.0),
  kept byte-identical with its `thumbfast-jellyfin.lua`. (A one-time
  `--demuxer-readahead-secs=600` and `--demuxer-max-bytes=2048MiB` worker
  patch was dropped when the byte-identical sync began; the worker's demuxer
  args are upstream's.)
- Standalone release: https://github.com/MrGameVlogger/thumbfast-jellyfin

### trackselect.lua
- Track selection helper. Selects non-dub audio and subtitle tracks automatically.
- Repo: https://github.com/po5/trackselect
- Config: script-opts/trackselect.conf

### autocrop.lua (disabled)
- Stock mpv script for automatic black bar detection and cropping.
- Currently parked at `backup/autocrop.lua.disabled` (out of `scripts/`).
- Disabled because it caused pixel format toggling between p010 and yuv420p10 with hwdec=auto-copy.
- If re-enabled, it may cause constant GPU pipeline switching with 10-bit content.

## Shaders
All shaders are in the `shaders/` directory and applied via conditional profiles.

### ravu-zoom-ar-r3.hook
- High-quality upscaling shader from the RAVU family.
- Handles both luma and chroma upscaling.
- Applied for content below native display resolution.
- Source: https://github.com/bjin/mpv-prescalers (file: ravu-zoom-ar-r3.hook in repo root)

### CfL_Prediction.glsl
- Chroma from luma prediction by João Chrisóstomo.
- Reconstructs chroma signal from luma information for better chroma upsampling.
- Applied to all content.
- Source: https://github.com/Artoriuz/glsl-chroma-from-luma-prediction

### SSimSuperRes.glsl
- Super-resolution shader by Shiandow.
- Sharpens detail based on structural similarity (SSIM).
- 4 render passes (2 downscale, variance, and a 3x3 final).
- Has a `#define oversharp 0.5` parameter (line 151) but changing it doesn't reduce GPU load.
- Source: Originally from igv/SSimSuperRes (repo no longer available on GitHub). Commonly distributed through mpv community shader collections.

### Other available shaders (not in auto-profiles, toggled via keybinds)
- ArtCNN_C4F16.glsl. Neural network upscaling by João Chrisóstomo and Kacper Michajłow. Source: https://github.com/Artoriuz/ArtCNN
- SSimDownscaler.glsl. High-quality downscaling by Shiandow. Source: Originally from igv/SSimDownscaler (repo no longer available). Commonly distributed through mpv community.
- adaptive-sharpen.glsl. Adaptive sharpening filter by bacondither. Source: https://github.com/bacondither/Adaptive-sharpen

## Troubleshooting

### Frame drops
1. Check `DS:` or `Dropped:` in the status line.
2. If `DS:` shows a number far from expected (5.0 for 120Hz/24fps), it's a display timing issue.
3. Verify `video-sync=audio` is active.
4. Check GPU usage. If it is low, the bottleneck is elsewhere (timing, not rendering).
5. Check for `mmco: unref short failure` errors in mpv.log (likely related to display timing).

### Log locations
- mpv log: `~/.config/mpv/mpv.log` (overwritten each session)
- Jellyfin logs: `~/Library/Application Support/JellyfinMpvPlay/data/jellyfin-mpv-play-*.log`

### Key commands for debugging
- `i` or `I` toggles the stats overlay (shows dropped frames, sync, codec info)
- `Shift+I` shows the detailed stats page
- `n` toggles deband
- `j` or `J` cycles subtitles
- `#` cycles audio tracks

### Custom keybinds (input.conf)
- `Ctrl+g` cycles the RAVU stack, the ArtCNN stack, and off
- `Ctrl+h` toggles SSimDownscaler on and off
- `n` toggles deband (changed from `b` to avoid a ModernX conflict)
- `k` toggles sub-ass-override (force or no)

## Version history
- 2025-12-21: mpv 0.41.0 released (gpu-next now default, Vulkan hwdec preferred)
- 2026-02-12: mpv 0.41.0_2, libplacebo 7.360.0 revision bump
- 2026-03-18: mpv 0.41.0_4, ffmpeg 8.1 revision bump
- 2026-07-20: mpv 0.41.0_6, enabled pipewire
- 2026-07-29: mpv 0.41.0_7, libbluray 1.5.0 revision bump
- 2026-08-11: mpv 0.41.0_8, ffmpeg 9.0 revision bump (caused frame drops due to MoltenVK display timing)
- 2026-08-31: mpv 0.41.0_9, ffmpeg 9.0.1 bugfix, Vapoursynth 74+ backport
- 2026-09-22: mpv 0.41.0_10, ffmpeg 9.0.2 revision bump
- 2026-11-16: mpv 0.42.0_1, new curl network backend (HTTP/2, connection reuse), context menu on right-click, libplacebo 7.387.0 (currently installed)

## Credits and inspiration
- classicjazz/mpv-config, a macOS mpv configuration guide with shader recommendations
- SoM-MPV-Config, an anime-focused mpv config with colorspace profiles and SDH filtering

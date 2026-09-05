# mpv-config

[![mpv](https://img.shields.io/badge/mpv-v0.41.0-green.svg)](https://mpv.io/)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/MrGameVlogger/mpv-config)](https://github.com/MrGameVlogger/mpv-config/commits/main)

My personal [mpv](https://mpv.io/) configuration for macOS, optimized for anime and Japanese media playback on Apple Silicon.

## Hardware

- **MacBook Pro** — Apple M2 Max (Mac14,6), 64GB RAM
- **Display** — 3456x2234 Retina @ 120Hz
- **OS** — macOS with MoltenVK for Vulkan support

## Why This Setup

This configuration is built around three priorities:

### 1. Anime-First

Most anime is in Japanese with English subtitles, but many releases include dub tracks that mpv might select by default. This setup fixes that:

- **`trackselect.lua`** automatically selects Japanese audio and English subtitles based on track titles, even when language tags are missing
- **Language priority** in `mpv.conf` puts Japanese first (`alang=ja,jp,jpn`) and Middle English before English for subtitles (`slang=enm,eng,en`) — the `enm` catches honorifics in fansubs
- **`subs-with-matching-audio=no`** prevents mpv from auto-selecting subtitles that match the audio language (which would show Japanese subs on Japanese audio)

### 2. Jellyfin Integration

I watch everything through Jellyfin, so the setup is optimized for streaming:

- **[Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play)** launches mpv from the Jellyfin web UI — no need to copy URLs or use a browser
- **[thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin)** fetches pre-generated Trickplay thumbnails from the server instead of decoding video locally — instant seekbar previews with zero CPU overhead
- **[jf-mpv-osc](https://github.com/iwalton3/jf-mpv-osc)** provides a Jellyfin-styled OSC with skip intro button, action sheets for subtitle/audio selection, and queue navigation
- **Large cache** (`demuxer-max-bytes=8192M`) buffers aggressively for smooth streaming over network

### 3. High-Quality Rendering

The M2 Max has plenty of GPU headroom, so I use shaders that make a visible difference:

- **RAVU upscaling** for arbitrary ratios (720p→4K) — less ringing than NNEDI3
- **ArtCNN** for 2x upscaling (1080p→4K) — neural network that superseded FSRCNNX
- **CfL Prediction** for chroma — reconstructs chroma from luma, sharper than bilinear
- **SSimSuperRes** for anti-ringing — sharpens without over-sharpening flat areas
- **Conditional profiles** apply the right shader stack based on content resolution

The shaders are applied via conditional profiles, so 4K content doesn't get unnecessary upscaling, and sub-1080p content gets the full treatment.

## Features

### Video Rendering

- **gpu-next** with Vulkan (via MoltenVK) — modern rendering pipeline with better color management than the legacy `gpu` VO
- **VideoToolbox hardware decoding** — `auto-copy` mode (not zero-copy) because thumbfast Trickplay needs CPU-side frame access
- **Conditional shader profiles** — different shader stacks for 4K, 1080p-1440p, and sub-1080p content

### Jellyfin Integration

- **Direct streaming** — play from Jellyfin server via [Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play), no browser needed
- **Trickplay thumbnails** — instant seekbar previews from Jellyfin's pre-generated tiles via [thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin)
- **Custom OSC** — Jellyfin-styled interface with Material icons via [jf-mpv-osc](https://github.com/iwalton3/jf-mpv-osc)

### Playback

- **SponsorBlock** — auto-skip sponsors, intros, outros via [zydezu's fork](https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua). Works with any OSC (core skipping is independent of ModernX).
- **Auto-play** — loads adjacent files in directory for binge-watching (`autocreate-playlist=same`)
- **Episode navigation** — `>` / `<` keys for next/previous episode
- **Deband toggle** — `n` key to toggle deband on/off (off by default, settings optimized for M2 Max)

## Scripts

| Script | Purpose | Why | Source |
|--------|---------|-----|--------|
| `trickplay-jf-osc.lua` | Jellyfin-styled OSC | Replaces mpv's built-in OSC with a Jellyfin-themed interface. Has skip intro button, action sheets for subtitle/audio selection, and integrates with [thumbfast](https://github.com/po5/thumbfast) for seekbar thumbnails. | [iwalton3/jf-mpv-osc](https://github.com/iwalton3/jf-mpv-osc) |
| `thumbfast.lua` | Thumbnail generation | [Modified](https://github.com/MrGameVlogger/thumbfast-jellyfin) to fetch pre-generated Trickplay tiles from Jellyfin server instead of spawning a subprocess. Falls back to normal thumbfast for local files. | [po5/thumbfast](https://github.com/po5/thumbfast) + [MrGameVlogger/thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin) |
| `sponsorblock.lua` | SponsorBlock segment skipping | [zydezu's fork](https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua) — core skipping works with any OSC, not just ModernX | [zydezu/mpvconfig](https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua) |
| `trackselect.lua` | Auto-select non-dub tracks | Automatically selects Japanese audio and English subtitles for anime. Uses track titles to identify non-dub tracks, so it works even when language tags are missing. | [po5/trackselect](https://github.com/po5/trackselect) |

### Disabled & Backup Scripts

| File | Status | Reason | Source |
|------|--------|--------|--------|
| `jellyfin.lua.disabled` | Disabled | Was the original Jellyfin client script. Now redundant with [Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play) which handles everything via IPC. Kept for standalone use without the macOS app. | [EmperorPenguin18/mpv-jellyfin](https://github.com/EmperorPenguin18/mpv-jellyfin) |
| `autocrop.lua.disabled` | Disabled | Stock mpv script for automatic black bar detection. Didn't like the behavior — kept trying to crop when I didn't want it to. | mpv built-in |
| `modernx.lua.disabled` | Disabled | Was the previous OSC. Replaced by `trickplay-jf-osc.lua` which has native Jellyfin integration. Kept in case you want to switch back to the modern mpv style. | [zydezu/ModernX](https://github.com/zydezu/ModernX) |
| `thumbfast-upstream.lua.bak` | Backup | Original upstream [thumbfast](https://github.com/po5/thumbfast) before [Jellyfin Trickplay modifications](https://github.com/MrGameVlogger/thumbfast-jellyfin). Used to sync updates from upstream. | [po5/thumbfast](https://github.com/po5/thumbfast) |

## Shaders

### Auto-Profiles (Always Active)

These shaders are applied automatically based on content resolution via conditional profiles in `mpv.conf`:

| Profile | Condition | Shaders | Why |
|---------|-----------|---------|-----|
| **4K** | height >= 2160 | CfL + SSimSuperRes | No upscaling needed, just chroma improvement and anti-ringing |
| **1080p-1440p** | 1080 <= height < 2160 | RAVU + CfL + SSimSuperRes | Full upscaling pipeline for most anime BDRips |
| **Sub-1080p** | height < 1080 | RAVU + CfL + SSimSuperRes | Same pipeline, RAVU handles larger upscale factor |
| **HDR** | PQ/HLG gamma | bt.2446a tone mapping (fallback), target-peak=1600 (XDR display), HDR passthrough |

### Keybind Stacks (Toggle Manually)

These shaders are not in auto-profiles but can be toggled via keybinds.

| Keybind | Cycles Between | What's In Each Stack | Purpose |
|---------|----------------|---------------------|---------|
| `Ctrl+g` | RAVU stack ↔ ArtCNN stack ↔ off | **RAVU stack:** `ravu-zoom-ar-r3.hook` + `CfL_Prediction.glsl` + `SSimSuperRes.glsl` + `adaptive-sharpen.glsl`<br>**ArtCNN stack:** `ArtCNN_C4F16.glsl` + `CfL_Prediction.glsl` + `SSimSuperRes.glsl` + `adaptive-sharpen.glsl` | Switch upscaling strategy — RAVU for arbitrary ratios (720p→4K), ArtCNN for 2x (1080p→4K). Third press turns off all manual shaders. |
| `Ctrl+h` | SSimDownscaler stack ↔ off | **SSimDownscaler stack:** `SSimDownscaler.glsl` + `CfL_Prediction.glsl` + `SSimSuperRes.glsl` + `adaptive-sharpen.glsl` | Toggle downscaling for 4K content on 1080p display. Hit again to turn off and return to auto-profiles. |

**How it works:**
- Auto-profiles apply shaders automatically based on content resolution
- `Ctrl+g` and `Ctrl+h` override the auto-profiles with manual shader stacks
- Both manual stacks include `adaptive-sharpen` which is NOT in auto-profiles (too much sharpening for always-on)
- Both stacks include `CfL_Prediction` (chroma) and `SSimSuperRes` (anti-ringing) as base layers

### Shader Details

| Shader | Purpose | Why | Source |
|--------|---------|-----|--------|
| `ravu-zoom-ar-r3.hook` | Arbitrary ratio upscaling | Best for non-integer scales (720p→4K). Unlike fixed-ratio shaders, handles any resolution. Part of the RAVU family which produces less ringing than NNEDI3. | [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) |
| `CfL_Prediction.glsl` | Chroma from luma prediction | Reconstructs chroma signal from luma information. Produces sharper chroma upsampling than bilinear/bicubic, especially visible on anime color gradients. | [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction) |
| `SSimSuperRes.glsl` | Super-resolution enhancement | Anti-ringing shader that sharpens while preserving detail. Uses SSIM (structural similarity) to avoid over-sharpening. 4 render passes (2 downscale + variance + 3x3 final). | Original [igv/SSimSuperRes](https://github.com/igv) repo gone, distributed through mpv community |
| `ArtCNN_C4F16.glsl` | Neural network upscaling (2x) | Best for 1080p→4K. Superseded [FSRCNNX](https://github.com/igv/FSRCNNX) with less ringing and better detail. Uses a lightweight CNN (4 layers, 16 filters). | [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN) |
| `SSimDownscaler.glsl` | High-quality downscaling | For watching 4K content on 1080p displays. Uses SSIM-based approach for sharper downscaling than bilinear. | Original [igv/SSimDownscaler](https://github.com/igv) repo gone, distributed through mpv community |
| `adaptive-sharpen.glsl` | Adaptive sharpening | Post-resize sharpening that adapts to local content. Avoids over-sharpening flat areas while enhancing edges. Applied after upscaling. | [bacondither/Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen) |

## Configuration Reference

### Video Output

| Option | Value | Why |
|--------|-------|-----|
| `vo=gpu-next` | libplacebo-based renderer | Modern rendering pipeline with better color management (default since mpv 0.41) |
| `gpu-api=vulkan` | Vulkan backend | Required for gpu-next on macOS via MoltenVK |
| `gpu-context=macvk` | macOS Vulkan context | macOS-specific Vulkan context |
| `hwdec=auto-copy` | Hardware decoding | Auto-select best HW decoder, copy frames to CPU for script compatibility |
| `hwdec-codecs=all` | All codecs | Enable hardware decoding for all codecs |
| `hwdec-threads=4` | 4 threads | Dedicated threads for VideoToolbox copy-back path |
| `vd-lavc-threads=0` | Auto | Auto-detect decoder thread count |
| `vulkan-async-transfer=yes` | Async | Async texture uploads through MoltenVK |
| `vulkan-async-compute=yes` | Async | Async compute shaders |
| `profile=high-quality` | High quality | Sets ewa_lanczossharp scaling, sigmoid upscaling, etc. |
| `video-latency-hacks=yes` | Enabled | Reduces latency |

### Deband

| Option | Value | Why |
|--------|-------|-----|
| `deband=no` | Off by default | Toggle with `n` key at runtime |
| `deband-iterations=4` | 4 passes | Higher = stronger but more GPU cost |
| `deband-range=24` | 24 pixels | How far the filter samples |
| `deband-grain=16` | 16 | Adds dynamic noise to mask residual banding |

### Dithering

| Option | Value | Why |
|--------|-------|-----|
| `dither-depth=auto` | Auto | Match display bit depth |
| `temporal-dither=yes` | Enabled | Temporal dithering for smoother gradients |
| `dither=fruit` | Fruit | Higher quality dithering algorithm |

### Colorspace

| Option | Value | Why |
|--------|-------|-----|
| `target-prim=auto` | Auto | Auto-detect display color primaries |
| `target-trc=auto` | Auto | Auto-detect display transfer function |
| `video-output-levels=full` | Full range | Full range output for accurate colors |

### Colorspace Profiles

Applied automatically based on content type:

| Profile | Condition | Settings |
|---------|-----------|----------|
| **SD NTSC** | bt.601-525 primaries | target-prim=bt.601-525, target-trc=bt.1886 |
| **SD PAL** | bt.601-625 primaries | target-prim=bt.601-625, target-trc=bt.1886 |
| **HD BT.709** | bt.709 primaries | target-prim=bt.709, target-trc=bt.1886 |
| **SDR UHD BT.2020** | bt.2020 primaries, SDR | target-prim=bt.709, gamut-mapping-mode=absolute |
| **HDR** | PQ/HLG gamma | bt.2446a tone mapping, target-peak=1600, HDR passthrough |

### Fallback Scalers

These are active when no GLSL shader handles the scaling step (unusual resolutions, non-4K displays, final RGB output pass):

| Option | Value | Why |
|--------|-------|-----|
| `scale=ewa_lanczos` | EWA Lanczos | High quality polar luma upscale fallback |
| `cscale=ewa_lanczossharp` | EWA Lanczossharp | Chroma scaling |
| `dscale=catmull_rom` | Catmull-Rom | Good quality luma downscale |
| `correct-downscaling=yes` | Enabled | Proper windowed filter for large ratio downscaling |
| `linear-downscaling=yes` | Enabled | Downscale in linear light (more correct for luminance blending) |
| `sigmoid-upscaling=yes` | Enabled | Sigmoid curve during upscaling to reduce ringing |
| `scale-antiring=0.6` | 0.6 | Anti-ringing on fallback scaler |

### Audio

| Option | Value | Why |
|--------|-------|-----|
| `ao=coreaudio` | CoreAudio | macOS audio output |
| `volume-max=200` | 200% | Allow volume above 100% |

### Subtitles

| Option | Value | Why |
|--------|-------|-----|
| `embeddedfonts=yes` | Enabled | Use fonts embedded in video files |
| `sub-fix-timing=no` | Disabled | Don't fix subtitle timing (default) |
| `blend-subtitles=yes` | Enabled | CPU-side subtitle compositing (not GPU-heavy) |
| `demuxer-mkv-subtitle-preroll=index` | Index | Improved subtitle preroll for MKV files |
| `subs-with-matching-audio=no` | Disabled | Don't auto-select subs matching audio language |
| `sub-gauss=1.0` | 1.0 | Slight subtitle blur for readability |
| `sub-ass-override=no` | Disabled | Don't override ASS subtitle styling |
| `sub-ass-style-overrides=...` | Custom | Affects non-ASS subs only (SRT, etc.) |
| `sub-filter-sdh=yes` | Enabled | Filter SDH subtitles (deaf/hard-of-hearing) |
| `sub-filter-sdh-harder=yes` | Enabled | More aggressive SDH filtering |
| `sub-font="Gandhi Sans"` | Gandhi Sans | Custom subtitle font |
| `sub-font-size=50` | 50 | Subtitle font size |
| `sub-color="#FFFFFF"` | White | Subtitle color |
| `sub-margin-y=40` | 40px | Subtitle vertical margin |
| `sub-border-size=2.4` | 2.4 | Subtitle border size |
| `sub-border-color="#FF000000"` | Black | Subtitle border color |
| `sub-shadow-color="#A0000000"` | Semi-transparent black | Subtitle shadow color |
| `sub-shadow-offset=0.75` | 0.75 | Subtitle shadow offset |
| `sub-bold=yes` | Enabled | Bold subtitles |

### Languages

| Option | Value | Why |
|--------|-------|-----|
| `slang=enm,eng,en` | Middle English, English | Subtitle priority (enm catches honorifics in fansubs) |
| `alang=ja,jp,jpn` | Japanese | Audio priority (Japanese first for anime) |

### yt-dlp

| Option | Value | Why |
|--------|-------|-----|
| `ytdl-format=...` | Custom | Prefer HEVC 4K → VP9 4K → AV1 1080p → best |
| `ytdl-raw-options-append=external-downloader=aria2c` | aria2c | Faster downloads with aria2c |

### Window

| Option | Value | Why |
|--------|-------|-----|
| `fullscreen=yes` | Enabled | Start in fullscreen |
| `geometry=50%:50%` | Center | Center window (unused when fullscreen) |
| `autofit=100%` | 100% | Fill screen (unused when fullscreen) |
| `window-maximized=no` | Disabled | Not maximized (unused when fullscreen) |
| `osc=no` | Disabled | Disabled because jf-mpv-osc handles the OSC |
| `border=no` | Disabled | Borderless window |
| `no-hidpi-window-scale` | Enabled | Don't auto-scale on Retina |
| `cursor-autohide=1000` | 1 second | Hide cursor after 1 second |
| `force-window=immediate` | Immediate | Open window immediately on launch |
| `macos-fs-animation-duration=0` | 0 | Disable macOS fullscreen animation |

### Cache

| Option | Value | Why |
|--------|-------|-----|
| `cache=yes` | Enabled | Enable demuxer cache |
| `cache-on-disk=no` | Disabled | Don't cache to disk |
| `demuxer-max-bytes=8192M` | 8GB | Large cache for Jellyfin streaming over network |
| `demuxer-max-back-bytes=2048M` | 2GB | Large rewinding buffer |
| `demuxer-readahead-secs=90` | 90 seconds | Aggressive readahead for streaming |
| `demuxer-hysteresis-secs=10` | 10 seconds | Cache hysteresis threshold |
| `cache-pause=no` | Disabled | Don't pause when buffer is empty |

### Playback

| Option | Value | Why |
|--------|-------|-----|
| `keep-open=yes` | Enabled | Don't close window after playback ends |
| `save-position-on-quit=yes` | Enabled | Resume from last position |
| `save-watch-history=yes` | Enabled | Track watch history |
| `autocreate-playlist=same` | Same directory | Auto-add files from same directory |
| `video-sync=display-resample` | Display-resample | Display-sync for smoother motion (5:1 cadence for 24fps on 120Hz) |
| `interpolation=no` | Disabled | Anime is intentionally 24fps — interpolation creates artifacts and loses aesthetic |
| `swapchain-depth=4` | 4 | Extra presentation buffer headroom |
| `hr-seek=absolute` | Absolute | Precise seeking |
| `reset-on-next-file=...` | Custom | Reset audio-delay, mute, pause, speed, sub-delay between files |

### Screenshots

| Option | Value | Why |
|--------|-------|-----|
| `screenshot-format=png` | PNG | PNG format for lossless screenshots |
| `screenshot-dir="~/Pictures/mpv"` | ~/Pictures/mpv | Save location |
| `screenshot-template="%F-%p-%n"` | Custom | Filename format |
| `screenshot-high-bit-depth=yes` | Enabled | Preserve HDR color depth |
| `screenshot-tag-colorspace=yes` | Enabled | Tag colorspace in screenshots |

### Logging

| Option | Value | Why |
|--------|-------|-----|
| `log-file=~~/mpv.log` | mpv.log | Log file location (overwritten each session) |

| File | Description |
|------|-------------|
| `mpv.conf` | Main configuration — video output, decoding, cache, subtitles |
| `input.conf` | Keybindings — custom keys for shader toggle, deband, etc. |
| `scripts/` | Lua scripts — OSC, thumbnails, Jellyfin, SponsorBlock |
| `shaders/` | GLSL shaders — upscaling, chroma, anti-ringing, sharpening |
| `script-opts/` | Script configuration — per-script settings |
| `fonts/` | Custom fonts — Fluent System Icons for OSC |

## Keybindings

| Key | Action | Why |
|-----|--------|-----|
| `Ctrl+g` | Cycle RAVU ↔ ArtCNN ↔ off | Switch upscaling strategy (see [Keybind Stacks](#keybind-stacks-toggle-manually)) |
| `Ctrl+h` | Cycle SSimDownscaler ↔ off | Toggle downscaling for 4K on 1080p (see [Keybind Stacks](#keybind-stacks-toggle-manually)) |
| `n` | Toggle deband | Off by default, toggle when banding is visible |
| `k` | Toggle sub-ass-override | Switch between styled and plain subtitles |
| `>` / `<` | Next/previous episode | Quick navigation during binge sessions |

## Installation

```bash
# Clone to mpv config directory
git clone https://github.com/MrGameVlogger/mpv-config.git ~/.config/mpv

# Or copy individual files
cp mpv.conf ~/.config/mpv/
cp -r scripts/ ~/.config/mpv/
cp -r shaders/ ~/.config/mpv/
cp -r script-opts/ ~/.config/mpv/
cp -r fonts/ ~/.config/mpv/
```

**Note:** If you want to use `jellyfin.lua` (disabled by default — Jellyfin MPV Play handles this via IPC), create `script-opts/jellyfin.conf` with your server details. See `script-opts/jellyfin.conf.example` for the format.

## Related Projects

- [Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play) — Jellyfin client that launches mpv from the web UI
- [thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin) — Modified thumbfast with Jellyfin Trickplay support

## Credits & Inspiration

- [classicjazz/mpv-config](https://github.com/classicjazz/mpv-config) — macOS mpv configuration guide with shader recommendations. Detailed write-up: [Configuring MPV for Best Video Quality](https://freetime.mikeconnelly.com/archives/5371). Shader choices, conditional profiles, and Vulkan/MoltenVK setup are based on this guide.
- [SoM-MPV-Config](https://github.com/JySzE/SoM-MPV-Config) — Anime-focused mpv config. Colorspace profiles, SDH filtering, and display-sync settings are based on this config.

## License

Configuration files are personal use. Scripts and shaders are subject to their respective licenses (MPL-2.0, GPL-3.0, MIT, Apache-2.0 — see individual files).

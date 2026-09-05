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
- **VideoToolbox hardware decoding** — `auto-copy` mode (not zero-copy) because scripts like autocrop need CPU-side frame access
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
| **HDR** | PQ/HLG gamma | bt.2446a tone mapping | Perceptual tone mapping for HDR content on SDR display |

### Keybind-Only (Toggle Manually)

These shaders are not in auto-profiles but can be toggled via keybinds:

| Shader | Keybind | Purpose | Why |
|--------|---------|---------|-----|
| `ArtCNN_C4F16.glsl` | `Ctrl+g` | Replaces RAVU in the upscaling pipeline | Better for 2x upscaling (1080p→4K), less ringing than RAVU |
| `SSimDownscaler.glsl` | `Ctrl+h` | High-quality downscaling | For watching 4K content on 1080p displays |
| `adaptive-sharpen.glsl` | Included in keybind stacks | Post-resize sharpening that adapts to local content. Part of both `Ctrl+g` and `Ctrl+h` shader stacks. | [bacondither/Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen) |

### Shader Details

| Shader | Purpose | Why | Source |
|--------|---------|-----|--------|
| `ravu-zoom-ar-r3.hook` | Arbitrary ratio upscaling | Best for non-integer scales (720p→4K). Unlike fixed-ratio shaders, handles any resolution. Part of the RAVU family which produces less ringing than NNEDI3. | [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) |
| `CfL_Prediction.glsl` | Chroma from luma prediction | Reconstructs chroma signal from luma information. Produces sharper chroma upsampling than bilinear/bicubic, especially visible on anime color gradients. | [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction) |
| `SSimSuperRes.glsl` | Super-resolution enhancement | Anti-ringing shader that sharpens while preserving detail. Uses SSIM (structural similarity) to avoid over-sharpening. 4 render passes (2 downscale + variance + 3x3 final). | Original [igv/SSimSuperRes](https://github.com/igv) repo gone, distributed through mpv community |
| `ArtCNN_C4F16.glsl` | Neural network upscaling (2x) | Best for 1080p→4K. Superseded [FSRCNNX](https://github.com/igv/FSRCNNX) with less ringing and better detail. Uses a lightweight CNN (4 layers, 16 filters). | [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN) |
| `SSimDownscaler.glsl` | High-quality downscaling | For watching 4K content on 1080p displays. Uses SSIM-based approach for sharper downscaling than bilinear. | Original [igv/SSimDownscaler](https://github.com/igv) repo gone, distributed through mpv community |
| `adaptive-sharpen.glsl` | Adaptive sharpening | Post-resize sharpening that adapts to local content. Avoids over-sharpening flat areas while enhancing edges. Applied after upscaling. | [bacondither/Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen) |

## Key Files

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
| `Ctrl+g` | Toggle RAVU ↔ ArtCNN | Switch upscaling strategy for different content |
| `Ctrl+h` | Toggle SSimDownscaler | Enable when watching 4K on 1080p display |
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

## License

Configuration files are personal use. Scripts and shaders are subject to their respective licenses (MPL-2.0, GPL-3.0, MIT, Apache-2.0 — see individual files).

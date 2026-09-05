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

1. **Anime-first** — Japanese audio with English subtitles, auto-selecting non-dub tracks
2. **Jellyfin integration** — stream directly from my Jellyfin server with full playback control
3. **High-quality rendering** — maximize the M2 Max GPU with shaders that make a visible difference

## Features

### Video Rendering

- **gpu-next** with Vulkan (via MoltenVK) — modern rendering pipeline with better color management
- **VideoToolbox hardware decoding** — `auto-copy` mode for script compatibility (autocrop needs CPU-side frames)
- **High-quality shaders** — RAVU upscaling, CfL chroma prediction, SSimSuperRes anti-ringing

### Jellyfin Integration

- **Direct streaming** — play from Jellyfin server via `jellyfin.lua`, no browser needed
- **Trickplay thumbnails** — instant seekbar previews from Jellyfin's pre-generated tiles
- **SponsorBlock** — auto-skip sponsors, intros, outros (via zydezu's fork)
- **Custom OSC** — Jellyfin-styled interface with Material icons (jf-mpv-osc)

### Playback

- **Auto-play** — loads adjacent files in directory for binge-watching
- **Episode navigation** — `>` / `<` keys for next/previous episode
- **Deband toggle** — `n` key to toggle deband on/off (off by default, settings optimized for M2 Max)

## Scripts

| Script | Purpose | Why |
|--------|---------|-----|
| `trickplay-jf-osc.lua` | Jellyfin-styled OSC | Matches Jellyfin web UI, has skip intro button, works with Trickplay |
| `thumbfast.lua` | Thumbnail generation | Modified with Jellyfin Trickplay support — fetches pre-generated tiles instead of decoding locally |
| `jellyfin.lua` | Jellyfin playback integration | Streams from Jellyfin server, handles authentication and playback control |
| `sponsorblock.lua` | SponsorBlock segment skipping | zydezu's fork integrates with ModernX OSC |
| `trackselect.lua` | Auto-select non-dub tracks | Picks Japanese audio and English subs automatically for anime |

## Shaders

| Shader | Purpose | Why |
|--------|---------|-----|
| `ravu-zoom-ar-r3.hook` | Arbitrary ratio upscaling | Best for non-integer scales (720p→4K), handles any resolution |
| `CfL_Prediction.glsl` | Chroma from luma prediction | Reconstructs chroma signal from luma — visible improvement on anime |
| `SSimSuperRes.glsl` | Super-resolution enhancement | Reduces ringing from sharp scalers, 4 render passes |
| `ArtCNN_C4F16.glsl` | Neural network upscaling (2x) | Best for 1080p→4K, superseded FSRCNNX with less ringing |
| `SSimDownscaler.glsl` | High-quality downscaling | For 4K content on 1080p displays |
| `adaptive-sharpen.glsl` | Adaptive sharpening | Post-resize sharpening that adapts to local content |

### Shader Profiles

Shaders are applied conditionally based on content resolution:

| Profile | Condition | Shaders |
|---------|-----------|---------|
| **4K** | height >= 2160 | CfL + SSimSuperRes (no upscaling needed) |
| **1080p-1440p** | 1080 <= height < 2160 | RAVU + CfL + SSimSuperRes |
| **Sub-1080p** | height < 1080 | RAVU + CfL + SSimSuperRes |
| **HDR** | PQ/HLG gamma | bt.2446a tone mapping |

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

**Note:** You'll need to create your own `script-opts/jellyfin.conf` with your Jellyfin server details. See `script-opts/jellyfin.conf.example` for the format.

## Related Projects

- [Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play) — Jellyfin client that launches mpv from the web UI
- [thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin) — Modified thumbfast with Jellyfin Trickplay support

## License

Configuration files are personal use. Scripts and shaders are subject to their respective licenses (MPL-2.0, GPL-3.0, MIT, Apache-2.0 — see individual files).

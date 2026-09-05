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

## Features

- **gpu-next** with Vulkan rendering
- **VideoToolbox** hardware decoding (auto-copy for script compatibility)
- **High-quality shaders** — RAVU upscaling, CfL chroma prediction, SSimSuperRes
- **Jellyfin integration** — stream directly from Jellyfin server
- **Trickplay thumbnails** — instant seekbar previews from Jellyfin
- **SponsorBlock** — auto-skip sponsors, intros, outros
- **Custom OSC** — Jellyfin-styled interface (jf-mpv-osc)
- **Auto-play** — loads adjacent files in directory

## Key Files

| File | Description |
|------|-------------|
| `mpv.conf` | Main configuration |
| `input.conf` | Keybindings |
| `scripts/` | Lua scripts |
| `shaders/` | GLSL shaders |
| `script-opts/` | Script configuration |

## Scripts

| Script | Purpose | Source |
|--------|---------|--------|
| `trickplay-jf-osc.lua` | Jellyfin-styled OSC | [iwalton3/jf-mpv-osc](https://github.com/iwalton3/jf-mpv-osc) |
| `thumbfast.lua` | Thumbnail generation (with Jellyfin Trickplay) | [MrGameVlogger/thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin) |
| `jellyfin.lua` | Jellyfin playback integration | [EmperorPenguin18/mpv-jellyfin](https://github.com/EmperorPenguin18/mpv-jellyfin) |
| `sponsorblock.lua` | SponsorBlock segment skipping | [zydezu/mpvconfig](https://github.com/zydezu/mpvconfig/blob/main/scripts/sponsorblock.lua) |
| `trackselect.lua` | Auto-select non-dub tracks | No known repo |

## Shaders

| Shader | Purpose | Source |
|--------|---------|--------|
| `ravu-zoom-ar-r3.hook` | Arbitrary ratio upscaling | [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) |
| `CfL_Prediction.glsl` | Chroma from luma prediction | [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction) |
| `SSimSuperRes.glsl` | Super-resolution enhancement | Original igv repo gone, distributed through mpv community |
| `ArtCNN_C4F16.glsl` | Neural network upscaling (2x) | [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN) |
| `SSimDownscaler.glsl` | High-quality downscaling | Original igv repo gone, distributed through mpv community |
| `adaptive-sharpen.glsl` | Adaptive sharpening | [bacondither/Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen) |

## Installation

```bash
# Clone to mpv config directory
git clone https://github.com/MrGameVlogger/mpv-config.git ~/.config/mpv

# Or copy individual files
cp mpv.conf ~/.config/mpv/
cp -r scripts/ ~/.config/mpv/
cp -r shaders/ ~/.config/mpv/
cp -r script-opts/ ~/.config/mpv/
```

## Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+g` | Toggle RAVU ↔ ArtCNN shader stack |
| `Ctrl+h` | Toggle SSimDownscaler |
| `n` | Toggle deband |
| `k` | Toggle sub-ass-override |
| `>` / `<` | Next/previous episode |

## Related Projects

- [Jellyfin MPV Play](https://github.com/MrGameVlogger/Jellyfin_mpv_play) — Jellyfin client for mpv
- [thumbfast-jellyfin](https://github.com/MrGameVlogger/thumbfast-jellyfin) — Trickplay thumbnails

## License

Configuration files are personal use. Scripts and shaders are subject to their respective licenses.

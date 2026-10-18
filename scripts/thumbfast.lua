-- thumbfast-jellyfin.lua
--
-- Drop-in replacement for thumbfast.lua with Jellyfin Trickplay support.
-- Fetches pre-generated thumbnails from Jellyfin server instead of spawning
-- a subprocess for local thumbnail generation.
--
-- Based on thumbfast by po5: https://github.com/po5/thumbfast
-- Trickplay support added for Jellyfin integration
--
-- Requirements:
--   - curl (system default at /usr/bin/curl)
--   - ffmpeg (must be in PATH)
--   - Jellyfin server with Trickplay enabled
--   - Any thumbfast-compatible OSC (ModernX, uosc, etc.)
--
-- Installation:
--   1. Place this file in your mpv scripts directory
--   2. Rename to thumbfast.lua (replacing the original)
--   3. Keep a backup of the original thumbfast.lua
--   4. Configure via script-opts/thumbfast.conf as usual
--
-- How it works:
--   - On file load, detects Jellyfin streams by URL pattern
--   - Fetches Trickplay tile images from the Jellyfin API
--   - Converts tiles to BGRA format using ffmpeg
--   - Displays thumbnails instantly from server-side data
--   - Falls back to normal thumbfast for non-Jellyfin content
--
-- License: MPL-2.0 (same as upstream thumbfast)

local options = {
    socket = "",
    thumbnail = "",
    max_height = 225,
    max_width = 400,
    scale_factor = 1,
    tone_mapping = "auto",
    overlay_id = 42,
    spawn_first = false,
    quit_after_inactivity = 0,
    network = false,
    audio = false,
    hwdec = false,
    direct_io = false,
    mpv_path = "mpv",
    cache_max_mb = 2048
}

mp.utils = require "mp.utils"
mp.options = require "mp.options"
mp.options.read_options(options, "thumbfast")

local properties = {}
local pre_0_30_0 = mp.command_native_async == nil
local pre_0_33_0 = mp.get_property_native("options/vo-mmcss-profile") ~= nil
local support_media_control = mp.get_property_native("media-controls") ~= nil

-- Jellyfin Trickplay support
-- Process-global on purpose: per-instance counters restart at 0 on mpv
-- recreation and collide with still-mapped files of the previous generation.
local load_generation = 0
local keep_path = nil
-- forward declaration: `info` is defined further down (fallback section) and
-- must be callable from the async callbacks below
local info
local trickplay = {
    active = false, server_url = nil, api_key = nil, item_id = nil,
    tile_width = 0, tile_height = 0, interval = 0,
    tiles_x = 0, tiles_y = 0, thumbnail_count = 0,
    tile_file = nil, cached = false, last_frame = -1, last_x = nil, last_y = nil, is_shown = false,
    scaled_w = 0, scaled_h = 0, frames_written = 0,
    loading = false,
}
local CURL = "curl"
local FFMPEG = "ffmpeg"

-- Find ffmpeg at startup (macOS Homebrew or system)
local function find_ffmpeg()
    local paths = {"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"}
    for _, p in ipairs(paths) do
        local f = io.open(p, "r")
        if f then f:close(); return p end
    end
    return "ffmpeg"  -- fallback to PATH
end
FFMPEG = find_ffmpeg()

-- Helper to run subprocesses with correct PATH on macOS
local os_name = mp.get_property("platform") or "linux"
local function run_subprocess(args, async, callback, stdin_data)
    local env = nil
    if os_name == "darwin" then
        local path = os.getenv("PATH") or ""
        env = "PATH=" .. path .. ":/opt/homebrew/bin:/usr/local/bin"
    end
    if async then
        return mp.command_native_async({name="subprocess", playback_only=true, capture_stdout=true, capture_stderr=true, args=args, env=env, stdin_data=stdin_data or ""}, callback)
    else
        return mp.command_native({name="subprocess", capture_stdout=true, capture_stderr=true, playback_only=false, args=args, env=env, stdin_data=stdin_data or ""})
    end
end

-- curl never hangs the player: bounded connect and total times. The auth
-- header travels via curl's stdin config (-K -) so the token is not visible
-- in the process list.
local function curl_config(api_key)
    local key = tostring(api_key):gsub("\\", "\\\\"):gsub('"', '\\"')
    return "header = \"Authorization: MediaBrowser Token=\\\"" .. key .. "\\\"\"\n"
end
local function curl_args(url, extra)
    local args = {CURL, "-sS", "--connect-timeout", "5", "--max-time", "60", "-L", "-K", "-"}
    for _, a in ipairs(extra or {}) do table.insert(args, a) end
    table.insert(args, url)
    return args
end

-- Cache directory
local CACHE_DIR = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/thumbfast-jellyfin-cache"
local CACHE_INDEX = CACHE_DIR .. "/index.txt"

local function ensure_cache_dir()
    -- mkdir -p is not portable to cmd.exe; use mkdir per platform, no shell
    if os_name == "windows" then
        run_subprocess({"cmd", "/c", "mkdir", CACHE_DIR})
    else
        run_subprocess({"mkdir", "-p", CACHE_DIR})
    end
end

local function get_cache_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)
    return CACHE_DIR .. "/" .. item_id .. "_" .. scaled_w .. "x" .. scaled_h .. "_" .. tiles_x .. "x" .. tiles_y .. ".bgra"
end

local function get_cache_info_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)
    return CACHE_DIR .. "/" .. item_id .. "_" .. scaled_w .. "x" .. scaled_h .. "_" .. tiles_x .. "x" .. tiles_y .. ".info"
end

local function load_from_cache(item_id, scaled_w, scaled_h, tiles_x, tiles_y)
    local cache_path = get_cache_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)
    local info_path = get_cache_info_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)

    local f = io.open(cache_path, "rb")
    if not f then return nil, 0 end
    local size = f:seek("end")
    f:close()

    local info_f = io.open(info_path, "r")
    if not info_f then return nil, 0 end
    local frames = tonumber(info_f:read("*l")) or 0
    info_f:close()

    -- Validate against the mmap contract: a short file means mpv would SIGBUS
    -- while seeking the strip. Discard partial/stale pairs instead.
    if frames > 0 and size == frames * scaled_w * scaled_h * 4 then
        return cache_path, frames
    end
    os.remove(cache_path)
    os.remove(info_path)
    return nil, 0
end

-- Keep the cache bounded: a two-hour movie is ~250MB of BGRA at 400x225.
local function enforce_cache_limit()
    local max_bytes = (tonumber(options.cache_max_mb) or 2048) * 1024 * 1024
    local idx = io.open(CACHE_INDEX, "r")
    if not idx then return end
    local entries = {}
    for line in idx:lines() do
        local path, size, ts = line:match("^(.*)\t(%d+)\t(%d+)$")
        if path then table.insert(entries, {path=path, size=tonumber(size), ts=tonumber(ts)}) end
    end
    idx:close()
    local total = 0
    for _, e in ipairs(entries) do total = total + e.size end
    local out, i = {}, 1
    while i <= #entries do
        local e = entries[i]
        if total > max_bytes and e.path ~= keep_path then
            os.remove(e.path)
            os.remove((e.path:gsub("%.bgra$", ".info")))
            total = total - e.size
        else
            table.insert(out, e)
        end
        i = i + 1
    end
    local f = io.open(CACHE_INDEX, "w")
    if not f then return end
    for _, e in ipairs(out) do
        f:write(e.path .. "\t" .. e.size .. "\t" .. e.ts .. "\n")
    end
    f:close()
end

local function save_to_cache(item_id, scaled_w, scaled_h, tiles_x, tiles_y, bgra_path, frames)
    ensure_cache_dir()
    local cache_path = get_cache_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)
    local info_path = get_cache_info_path(item_id, scaled_w, scaled_h, tiles_x, tiles_y)

    -- os.rename fails across devices; keep the temp file in that case instead
    -- of pointing tile_file at a path that was never written.
    local renamed = os.rename(bgra_path, cache_path)
    if not renamed then
        return bgra_path, false
    end

    local info_f = io.open(info_path, "w")
    if info_f then
        info_f:write(tostring(frames) .. "\n")
        info_f:close()
    end

    local idx = io.open(CACHE_INDEX, "a")
    if idx then
        idx:write(cache_path .. "\t" .. (frames * scaled_w * scaled_h * 4) .. "\t" .. os.time() .. "\n")
        idx:close()
    end
    keep_path = cache_path
    enforce_cache_limit()
    keep_path = nil

    return cache_path, true
end

local function extract_jellyfin_info(path)
    -- Everything before /Videos/ is the server base: works for root-hosted
    -- (http://host:8096/Videos/...) and subpath (http://host/jellyfin/Videos/...)
    local server = path:match("^(https?://.-)/Videos/") or path:match("^(https?://[^/]+)")
    local item_id = path:match("/Videos/([a-fA-F0-9-]+)/stream")
    local api_key = path:match("ApiKey=([^&]+)") or path:match("api_key=([^&]+)")
    if server and item_id and api_key then return server, item_id, api_key end
    return nil, nil, nil
end

local function get_user_id_async(server, api_key, callback)
    local cfg = curl_config(api_key)
    run_subprocess(curl_args(server.."/Users/Me"), true, function(_, result)
        if result and result.status == 0 and result.stdout then
            local me = mp.utils.parse_json(result.stdout)
            if me and me.Id then return callback(me.Id) end
        end
        -- older servers without /Users/Me
        run_subprocess(curl_args(server.."/Users"), true, function(_, r2)
            if r2 and r2.status == 0 and r2.stdout then
                local users = mp.utils.parse_json(r2.stdout)
                if users and users[1] and users[1].Id then return callback(users[1].Id) end
            end
            callback(nil)
        end, cfg)
    end, cfg)
end

local function get_trickplay_info_async(server, item_id, api_key, user_id, callback)
    local url = string.format("%s/Users/%s/Items/%s", server, user_id, item_id)
    run_subprocess(curl_args(url), true, function(_, result)
        local json = result and result.status == 0 and result.stdout and mp.utils.parse_json(result.stdout)
        if not (json and json.Trickplay) then return callback(nil) end
        -- Two server shapes exist:
        --   Jellyfin <=10.9: { width: [info, ...] }
        --   Jellyfin 12:     { itemId: { width: info } }
        -- Deterministic width pick: smallest that covers the display width,
        -- else the largest available. (pairs() order is unstable.)
        local candidates = {}
        local function add_entry(w, info)
            w = tonumber(w)
            if w and type(info) == "table" then
                if info[1] then info = info[1] end  -- legacy: list per width
                table.insert(candidates, {key = w, info = info})
            end
        end
        for ws, wd in pairs(json.Trickplay) do
            if tonumber(ws) then
                add_entry(ws, wd)               -- legacy shape
            elseif type(wd) == "table" then
                for ws2, info2 in pairs(wd) do  -- Jellyfin 12 shape
                    add_entry(ws2, info2)
                end
            end
        end
        table.sort(candidates, function(a, b) return a.key < b.key end)
        local chosen = candidates[#candidates]
        for _, c in ipairs(candidates) do
            if c.key >= options.max_width then chosen = c break end
        end
        if not chosen then return callback(nil) end
        local ti = chosen.info
        local w = ti.Width or chosen.key
        local h = ti.Height or 180
        if not (w > 0 and h > 0) then return callback(nil) end
        callback({width=w, height=h, interval=ti.Interval or 10000,
            tiles_x=ti.TileWidth or 10, tiles_y=ti.TileHeight or 10, thumbnail_count=ti.ThumbnailCount or 0})
    end, curl_config(api_key))
end

local function download_trickplay_tile_async(server, item_id, api_key, width, index, callback)
    local url = string.format("%s/Videos/%s/Trickplay/%d/%d.jpg", server, item_id, width, index)
    local tmpfile = os.tmpname()..".jpg"
    run_subprocess(curl_args(url, {"-o", tmpfile}), true, function(_, result)
        if result and result.status == 0 then
            local f = io.open(tmpfile, "rb")
            if f then local sz = f:seek("end"); f:close(); if sz and sz > 0 then return callback(tmpfile) end end
        end
        os.remove(tmpfile)
        callback(nil)
    end, curl_config(api_key))
end

local function cleanup_trickplay()
    load_generation = load_generation + 1  -- cancel in-flight loads
    if trickplay.tile_file and not trickplay.cached then
        os.remove(trickplay.tile_file)
    end
    trickplay.tile_file = nil
    trickplay.cached = false
    trickplay.active = false
    trickplay.last_frame = -1
    trickplay.loading = false
end

local function load_trickplay_async(server, item_id, api_key, tp, scaled_w, scaled_h)
    local gen = load_generation
    trickplay.loading = true

    local tiles_per_image = tp.tiles_x * tp.tiles_y
    local num_tiles = math.ceil(tp.thumbnail_count / tiles_per_image)

    -- Fresh file per generation: never rewrite a file mpv may have mapped.
    local final_bgra = os.tmpname() .. ".bgra"
    local out = io.open(final_bgra, "wb")
    if not out then mp.msg.warn("[thumbfast] Failed to create output file"); trickplay.loading = false; return end

    local frames_written = 0
    local frame_size = scaled_w * scaled_h * 4
    local out_closed = false
    local function discard_out()
        -- idempotent: several cancel paths can fire for one generation
        if not out_closed then out:close(); out_closed = true end
        os.remove(final_bgra)
    end

    local function finish()
        out:close()
        out_closed = true
        if gen ~= load_generation then os.remove(final_bgra); return end
        if frames_written == 0 then
            os.remove(final_bgra)
            mp.msg.warn("[thumbfast] No frames written")
            trickplay.loading = false
            return
        end
        local cached_path, was_cached = save_to_cache(item_id, scaled_w, scaled_h, tp.tiles_x, tp.tiles_y, final_bgra, frames_written)
        trickplay.tile_file = cached_path
        trickplay.frames_written = frames_written
        trickplay.active = true
        trickplay.cached = was_cached
        trickplay.loading = false
        mp.msg.info("[thumbfast] Trickplay loaded: "..tp.width.."x"..tp.height.." -> "..scaled_w.."x"..scaled_h..", "..tp.tiles_x.."x"..tp.tiles_y.." tiles, "..frames_written.." frames")
        info(effective_w, effective_h)  -- re-report dims once Trickplay owns the overlay
    end

    local function step(i)
        if gen ~= load_generation then discard_out(); return end
        if i >= num_tiles then finish(); return end
        download_trickplay_tile_async(server, item_id, api_key, tp.width, i, function(jpg)
            if gen ~= load_generation then
                if jpg then os.remove(jpg) end
                discard_out()
                return
            end
            if not jpg then
                mp.msg.warn("[thumbfast] Failed to download Trickplay tile " .. i)
                finish()
                return
            end
            local tile_bgra = jpg:gsub("%.jpg$", ".bgra")
            run_subprocess({FFMPEG, "-y", "-i", jpg, "-vf",
                string.format("scale=%d:%d", scaled_w * tp.tiles_x, scaled_h * tp.tiles_y),
                "-pix_fmt", "bgra", "-f", "rawvideo", tile_bgra}, true, function(_, result)
                os.remove(jpg)
                if gen ~= load_generation then
                    os.remove(tile_bgra)
                    discard_out()
                    return
                end
                if result and result.status == 0 then
                    local tile_file = io.open(tile_bgra, "rb")
                    local tile_data = tile_file and tile_file:read("*a")
                    if tile_file then tile_file:close() end
                    if tile_data then
                        local tile_stride = scaled_w * tp.tiles_x * 4
                        local tile_frames = tiles_per_image
                        if i == num_tiles - 1 then
                            tile_frames = tp.thumbnail_count - (i * tiles_per_image)
                        end
                        for f = 0, tile_frames - 1 do
                            local gx = f % tp.tiles_x
                            local gy = math.floor(f / tp.tiles_x)
                            local frame_x = gx * scaled_w
                            local frame_y = gy * scaled_h
                            for row = 0, scaled_h - 1 do
                                local src_offset = (frame_y + row) * tile_stride + frame_x * 4
                                out:write(tile_data:sub(src_offset + 1, src_offset + scaled_w * 4))
                            end
                            frames_written = frames_written + 1
                        end
                    end
                end
                os.remove(tile_bgra)
                step(i + 1)
            end)
        end)
    end
    step(0)
end

local function init_trickplay()
    local path = mp.get_property("path")
    if not path then return false end
    local server, item_id, api_key = extract_jellyfin_info(path)
    if not server or not item_id or not api_key then return false end
    trickplay.server_url = server; trickplay.item_id = item_id; trickplay.api_key = api_key
    trickplay.loading = true  -- keep thumb() from spawning the decode worker meanwhile
    local gen = load_generation
    get_user_id_async(server, api_key, function(uid)
        if gen ~= load_generation then return end
        if not uid then trickplay.loading = false; mp.msg.warn("[thumbfast] Failed to get Jellyfin user ID"); return end
        get_trickplay_info_async(server, item_id, api_key, uid, function(tp)
            if gen ~= load_generation then return end
            if not tp then trickplay.loading = false; mp.msg.info("[thumbfast] No Trickplay data for this item"); return end
            trickplay.tile_width = tp.width; trickplay.tile_height = tp.height
            trickplay.interval = tp.interval; trickplay.tiles_x = tp.tiles_x
            trickplay.tiles_y = tp.tiles_y; trickplay.thumbnail_count = tp.thumbnail_count

            -- Scaled dimensions preserving aspect ratio, with HiDPI scaling
            local scale = properties["display-hidpi-scale"] or 1
            local aspect = tp.width / tp.height
            local scaled_w, scaled_h
            local max_w = options.max_width * scale
            local max_h = options.max_height * scale
            if max_w / max_h > aspect then
                scaled_h = math.floor(max_h + 0.5)
                scaled_w = math.floor(scaled_h * aspect + 0.5)
            else
                scaled_w = math.floor(max_w + 0.5)
                scaled_h = math.floor(scaled_w / aspect + 0.5)
            end
            trickplay.scaled_w = scaled_w
            trickplay.scaled_h = scaled_h

            local cached_path, cached_frames = load_from_cache(item_id, scaled_w, scaled_h, tp.tiles_x, tp.tiles_y)
            if cached_path and cached_frames > 0 then
                trickplay.tile_file = cached_path
                trickplay.frames_written = cached_frames
                trickplay.active = true
                trickplay.cached = true
                trickplay.loading = false
                mp.msg.info("[thumbfast] Trickplay loaded from cache: "..scaled_w.."x"..scaled_h..", "..cached_frames.." frames")
                info(effective_w, effective_h)  -- re-report dims once Trickplay owns the overlay
                return
            end
            load_trickplay_async(server, item_id, api_key, tp, scaled_w, scaled_h)
        end)
    end)
    return true
end

local function trickplay_thumb(time, x, y)
    if not trickplay.active or not trickplay.tile_file or not x or not y then return end
    local frame = math.floor(time / (trickplay.interval / 1000))
    if frame < 0 then frame = 0 end
    if frame >= trickplay.frames_written then frame = trickplay.frames_written - 1 end
    -- Sequential layout: each frame is scaled_w * scaled_h * 4 bytes
    local frame_size = trickplay.scaled_w * trickplay.scaled_h * 4
    local off = frame * frame_size
    local stride = trickplay.scaled_w * 4
    if frame ~= trickplay.last_frame or x ~= trickplay.last_x or y ~= trickplay.last_y then
        trickplay.last_frame = frame; trickplay.last_x = x; trickplay.last_y = y
        trickplay.is_shown = true
        mp.commandv("overlay-add", options.overlay_id, x, y, trickplay.tile_file, off, "bgra", trickplay.scaled_w, trickplay.scaled_h, stride)
    end
end

local function trickplay_clear()
    if trickplay.is_shown then
        mp.commandv("overlay-remove", options.overlay_id)
        trickplay.is_shown = false; trickplay.last_frame = -1; trickplay.last_x = nil; trickplay.last_y = nil
    end
end
-- End Jellyfin Trickplay support

function subprocess(args, async, callback)
    callback = callback or function() end

    if not pre_0_30_0 then
        local env = nil
        if os_name == "darwin" then
            local path = os.getenv("PATH") or ""
            env = "PATH=" .. path .. ":/opt/homebrew/bin:/usr/local/bin"
        end
        if async then
            return mp.command_native_async({name = "subprocess", playback_only = true, args = args, env = env}, callback)
        else
            return mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = args, env = env})
        end
    else
        if async then
            return mp.utils.subprocess_detached({args = args}, callback)
        else
            return mp.utils.subprocess({args = args})
        end
    end
end

local winapi = {}
if options.direct_io then
    local ffi_loaded, ffi = pcall(require, "ffi")
    if ffi_loaded then
        winapi = {
            ffi = ffi,
            C = ffi.C,
            bit = require("bit"),
            socket_wc = "",
            CP_UTF8 = 65001,
            GENERIC_WRITE = 0x40000000,
            OPEN_EXISTING = 3,
            FILE_FLAG_WRITE_THROUGH = 0x80000000,
            FILE_FLAG_NO_BUFFERING = 0x20000000,
            PIPE_NOWAIT = ffi.new("unsigned long[1]", 0x00000001),
            INVALID_HANDLE_VALUE = ffi.cast("void*", -1),
            _lpNumberOfBytesWritten = ffi.new("unsigned long[1]"),
        }
        winapi._createfile_pipe_flags = winapi.bit.bor(winapi.FILE_FLAG_WRITE_THROUGH, winapi.FILE_FLAG_NO_BUFFERING)

        ffi.cdef[[
            void* __stdcall CreateFileW(const wchar_t *lpFileName, unsigned long dwDesiredAccess, unsigned long dwShareMode, void *lpSecurityAttributes, unsigned long dwCreationDisposition, unsigned long dwFlagsAndAttributes, void *hTemplateFile);
            bool __stdcall WriteFile(void *hFile, const void *lpBuffer, unsigned long nNumberOfBytesToWrite, unsigned long *lpNumberOfBytesWritten, void *lpOverlapped);
            bool __stdcall CloseHandle(void *hObject);
            bool __stdcall SetNamedPipeHandleState(void *hNamedPipe, unsigned long *lpMode, unsigned long *lpMaxCollectionCount, unsigned long *lpCollectDataTimeout);
            int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr, int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
        ]]

        winapi.MultiByteToWideChar = function(MultiByteStr)
            if MultiByteStr then
                local utf16_len = winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, MultiByteStr, -1, nil, 0)
                if utf16_len > 0 then
                    local utf16_str = winapi.ffi.new("wchar_t[?]", utf16_len)
                    if winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, MultiByteStr, -1, utf16_str, utf16_len) > 0 then
                        return utf16_str
                    end
                end
            end
            return ""
        end
    else
        options.direct_io = false
    end
end

local file
local file_bytes = 0
local spawned = false
local disabled = false
local force_disabled = false
local spawn_waiting = false
local spawn_working = false
local script_written = false

local dirty = false

local x, y
local last_x, last_y

local last_seek_time

local effective_w, effective_h = options.max_width, options.max_height
local real_w, real_h
local last_real_w, last_real_h

local script_name

local show_thumbnail = false

local filters_reset = {["lavfi-crop"]=true, ["crop"]=true}
local filters_runtime = {["hflip"]=true, ["vflip"]=true}
local filters_all = {["hflip"]=true, ["vflip"]=true, ["lavfi-crop"]=true, ["crop"]=true}

local tone_mappings = {["none"]=true, ["clip"]=true, ["linear"]=true, ["gamma"]=true, ["reinhard"]=true, ["hable"]=true, ["mobius"]=true}
local last_tone_mapping

local last_vf_reset = ""
local last_vf_runtime = ""

local last_rotate = 0

local par = ""
local last_par = ""

local last_crop = nil

local last_has_vid = 0
local has_vid = 0

local file_timer
local file_check_period = 1/60

local allow_fast_seek = true

local client_script = [=[
#!/usr/bin/env bash
MPV_IPC_FD=0; MPV_IPC_PATH="%s"
trap "kill 0" EXIT
while [[ $# -ne 0 ]]; do case $1 in --mpv-ipc-fd=*) MPV_IPC_FD=${1/--mpv-ipc-fd=/} ;; esac; shift; done
if echo "print-text thumbfast" >&"$MPV_IPC_FD"; then echo -n > "$MPV_IPC_PATH"; tail -f "$MPV_IPC_PATH" >&"$MPV_IPC_FD" & while read -r -u "$MPV_IPC_FD" 2>/dev/null; do :; done; fi
]=]

local function get_os()
    local raw_os_name = ""

    if jit and jit.os and jit.arch then
        raw_os_name = jit.os
    else
        if package.config:sub(1,1) == "\\" then
            local env_OS = os.getenv("OS")
            if env_OS then
                raw_os_name = env_OS
            end
        else
            raw_os_name = subprocess({"uname", "-s"}).stdout
        end
    end

    raw_os_name = (raw_os_name):lower()

    local os_patterns = {
        ["windows"] = "windows",
        ["linux"]   = "linux",
        ["osx"]     = "darwin",
        ["mac"]     = "darwin",
        ["darwin"]  = "darwin",
        ["^mingw"]  = "windows",
        ["^cygwin"] = "windows",
        ["bsd$"]    = "darwin",
        ["sunos"]   = "darwin"
    }

    local str_os_name = "linux"

    for pattern, name in pairs(os_patterns) do
        if raw_os_name:match(pattern) then
            str_os_name = name
            break
        end
    end

    return str_os_name
end

os_name = mp.get_property("platform") or get_os()

local path_separator = os_name == "windows" and "\\" or "/"

if options.socket == "" then
    if os_name == "windows" then
        options.socket = "thumbfast"
    else
        options.socket = "/tmp/thumbfast"
    end
end

if options.thumbnail == "" then
    if os_name == "windows" then
        options.thumbnail = os.getenv("TEMP").."\\thumbfast.out"
    else
        options.thumbnail = "/tmp/thumbfast.out"
    end
end

local unique = mp.utils.getpid()

options.socket = options.socket .. unique
options.thumbnail = options.thumbnail .. unique

if options.direct_io then
    if os_name == "windows" then
        winapi.socket_wc = winapi.MultiByteToWideChar("\\\\.\\pipe\\" .. options.socket)
    end

    if winapi.socket_wc == "" then
        options.direct_io = false
    end
end

options.scale_factor = math.floor(options.scale_factor)

local mpv_path = options.mpv_path
local frontend_path

if mpv_path == "mpv" and os_name == "windows" then
    frontend_path = mp.get_property_native("user-data/frontend/process-path")
    mpv_path = frontend_path or mpv_path
end

if mpv_path == "mpv" and os_name == "darwin" and unique then
    mpv_path = string.gsub(subprocess({"ps", "-o", "comm=", "-p", tostring(unique)}).stdout, "[\n\r]", "")
    if mpv_path ~= "mpv" then
        mpv_path = string.gsub(mpv_path, "/mpv%-bundle$", "/mpv")
        local mpv_bin = mp.utils.file_info("/usr/local/mpv")
        if mpv_bin and mpv_bin.is_file then
            mpv_path = "/usr/local/mpv"
        else
            local mpv_app = mp.utils.file_info("/Applications/mpv.app/Contents/MacOS/mpv")
            if mpv_app and mpv_app.is_file then
                mp.msg.warn("symlink mpv to fix Dock icons: `sudo ln -s /Applications/mpv.app/Contents/MacOS/mpv /usr/local/mpv`")
            else
                mp.msg.warn("drag to your Applications folder and symlink mpv to fix Dock icons: `sudo ln -s /Applications/mpv.app/Contents/MacOS/mpv /usr/local/mpv`")
            end
        end
    end
end

local function vo_tone_mapping()
    local passes = mp.get_property_native("vo-passes")
    if passes and passes["fresh"] then
        for k, v in pairs(passes["fresh"]) do
            for k2, v2 in pairs(v) do
                if k2 == "desc" and v2 then
                    local tone_mapping = string.match(v2, "([0-9a-z.-]+) tone map")
                    if tone_mapping then
                        return tone_mapping
                    end
                end
            end
        end
    end
end

local function vf_string(filters, full)
    local vf = ""
    local vf_table = properties["vf"]

    if (properties["video-crop"] or "") ~= "" then
        vf = "lavfi-crop="..string.gsub(properties["video-crop"], "(%d*)x?(%d*)%+(%d+)%+(%d+)", "w=%1:h=%2:x=%3:y=%4")..","
        local width = properties["video-out-params"] and properties["video-out-params"]["dw"]
        local height = properties["video-out-params"] and properties["video-out-params"]["dh"]
        if width and height then
            vf = string.gsub(vf, "w=:h=:", "w="..width..":h="..height..":")
        end
    end

    if vf_table and #vf_table > 0 then
        for i = #vf_table, 1, -1 do
            if filters[vf_table[i].name] then
                local args = ""
                for key, value in pairs(vf_table[i].params) do
                    if args ~= "" then
                        args = args .. ":"
                    end
                    args = args .. key .. "=" .. value
                end
                vf = vf .. vf_table[i].name .. "=" .. args .. ","
            end
        end
    end

    if (full and options.tone_mapping ~= "no") or options.tone_mapping == "auto" then
        if properties["video-params"] and properties["video-params"]["primaries"] == "bt.2020" then
            local tone_mapping = options.tone_mapping
            if tone_mapping == "auto" then
                tone_mapping = last_tone_mapping or properties["tone-mapping"]
                if tone_mapping == "auto" and properties["current-vo"] == "gpu-next" then
                    tone_mapping = vo_tone_mapping()
                end
            end
            if not tone_mappings[tone_mapping] then
                tone_mapping = "hable"
            end
            last_tone_mapping = tone_mapping
            vf = vf .. "zscale=transfer=linear,format=gbrpf32le,tonemap="..tone_mapping..",zscale=transfer=bt709,"
        end
    end

    if full then
        vf = vf.."scale=w="..effective_w..":h="..effective_h..par..",pad=w="..effective_w..":h="..effective_h..":x=-1:y=-1,format=bgra"
    end

    return vf
end

local function calc_dimensions()
    local width = properties["video-out-params"] and properties["video-out-params"]["dw"]
    local height = properties["video-out-params"] and properties["video-out-params"]["dh"]
    if not width or not height then return end

    local scale = properties["display-hidpi-scale"] or 1

    if width / height > options.max_width / options.max_height then
        effective_w = math.floor(options.max_width * scale + 0.5)
        effective_h = math.floor(height / width * effective_w + 0.5)
    else
        effective_h = math.floor(options.max_height * scale + 0.5)
        effective_w = math.floor(width / height * effective_h + 0.5)
    end

    local v_par = properties["video-out-params"] and properties["video-out-params"]["par"] or 1
    if v_par == 1 then
        par = ":force_original_aspect_ratio=decrease"
    else
        par = ""
    end
end

local info_timer = nil

info = function(w, h)
    local rotate = properties["video-params"] and properties["video-params"]["rotate"]
    local image = properties["current-tracks/video"] and properties["current-tracks/video"]["image"]
    local albumart = image and properties["current-tracks/video"]["albumart"]

    disabled = (w or 0) == 0 or (h or 0) == 0 or
        has_vid == 0 or
        (properties["demuxer-via-network"] and not options.network) or
        (albumart and not options.audio) or
        (image and not albumart) or
        force_disabled

    if info_timer then
        info_timer:kill()
        info_timer = nil
    elseif has_vid == 0 or (rotate == nil and not disabled) then
        info_timer = mp.add_timeout(0.05, function() info(w, h) end)
    end

    -- Use Trickplay dimensions if active
    local report_w, report_h = w, h
    if trickplay.active then
        report_w = trickplay.scaled_w
        report_h = trickplay.scaled_h
    end

    local json, err = mp.utils.format_json({width=report_w * options.scale_factor, height=report_h * options.scale_factor, scale_factor=options.scale_factor, disabled=disabled, available=true, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
    if pre_0_30_0 then
        mp.command_native({"script-message", "thumbfast-info", json})
    else
        mp.command_native_async({"script-message", "thumbfast-info", json}, function() end)
    end
end

local function remove_thumbnail_files()
    if file then
        file:close()
        file = nil
        file_bytes = 0
    end
    os.remove(options.thumbnail)
    os.remove(options.thumbnail..".bgra")
end

local activity_timer

local function spawn(time)
    if disabled then return end

    local path = properties["path"]
    if path == nil then return end

    if options.quit_after_inactivity > 0 then
        if show_thumbnail or activity_timer:is_enabled() then
            activity_timer:kill()
        end
        activity_timer:resume()
    end

    local open_filename = properties["stream-open-filename"]
    local ytdl = open_filename and properties["demuxer-via-network"] and path ~= open_filename
    if ytdl then
        path = open_filename
    end

    remove_thumbnail_files()

    local vid = properties["vid"]
    has_vid = vid or 0

    local args = {
        mpv_path, "--no-config", "--msg-level=all=no", "--idle", "--pause", "--keep-open=always", "--really-quiet", "--no-terminal",
        "--load-scripts=no", "--osc=no", "--ytdl=no", "--load-stats-overlay=no", "--load-osd-console=no", "--load-auto-profiles=no",
        "--edition="..(properties["edition"] or "auto"), "--vid="..(vid or "auto"), "--no-sub", "--no-audio",
        "--start="..time, allow_fast_seek and "--hr-seek=no" or "--hr-seek=yes",
        "--ytdl-format=worst", "--demuxer-readahead-secs=0", "--demuxer-max-bytes=128KiB",
        "--vd-lavc-skiploopfilter=all", "--vd-lavc-software-fallback=1", "--vd-lavc-fast", "--vd-lavc-threads=2", "--hwdec="..(options.hwdec and "auto" or "no"),
        "--vf="..vf_string(filters_all, true),
        "--sws-scaler=fast-bilinear",
        "--video-rotate="..last_rotate,
        "--ovc=rawvideo", "--of=image2", "--ofopts=update=1", "--o="..options.thumbnail
    }

    if not pre_0_30_0 then
        table.insert(args, "--sws-allow-zimg=no")
    end

    if support_media_control then
        table.insert(args, "--media-controls=no")
    end

    if os_name == "darwin" and properties["macos-app-activation-policy"] then
        table.insert(args, "--macos-app-activation-policy=accessory")
    end

    if os_name == "windows" or pre_0_33_0 then
        table.insert(args, "--input-ipc-server="..options.socket)
    elseif not script_written then
        local client_script_path = options.socket..".run"
        local script = io.open(client_script_path, "w+")
        if script == nil then
            mp.msg.error("client script write failed")
            return
        else
            script_written = true
            script:write(string.format(client_script, options.socket))
            script:close()
            subprocess({"chmod", "+x", client_script_path}, true)
            table.insert(args, "--scripts="..client_script_path)
        end
    else
        local client_script_path = options.socket..".run"
        table.insert(args, "--scripts="..client_script_path)
    end

    table.insert(args, "--")
    table.insert(args, path)

    spawned = true
    spawn_waiting = true

    subprocess(args, true,
        function(success, result)
            if spawn_waiting and (success == false or (result.status ~= 0 and result.status ~= -2)) then
                spawned = false
                spawn_waiting = false
                options.tone_mapping = "no"
                mp.msg.error("mpv subprocess create failed")
                if not spawn_working then
                    if options.mpv_path == "mpv" then
                        if properties["current-vo"] == "libmpv" then
                            if options.mpv_path == mpv_path then
                                mpv_path = "ImPlay"
                                spawn(time)
                            else
                                if os_name ~= "darwin" then
                                    force_disabled = true
                                    info(real_w or effective_w, real_h or effective_h)
                                end
                                mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                                mp.commandv("script-message-to", "implay", "show-message", "thumbfast initial setup", "Set mpv_path=PATH_TO_ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                            end
                        else
                            mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                            if os_name == "windows" and frontend_path == nil then
                                mp.commandv("script-message-to", "mpvnet", "show-text", "thumbfast: ERROR! install standalone mpv, see README", 5000, 20)
                                mp.commandv("script-message", "mpv.net", "show-text", "thumbfast: ERROR! install standalone mpv, see README", 5000, 20)
                            end
                        end
                    else
                        mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                        mp.commandv("script-message-to", "implay", "show-message", "thumbfast", "Set mpv_path=PATH_TO_ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                    end
                end
            elseif success == true and (result.status == 0 or result.status == -2) then
                if not spawn_working and properties["current-vo"] == "libmpv" and options.mpv_path ~= mpv_path then
                    mp.commandv("script-message-to", "implay", "show-message", "thumbfast initial setup", "Set mpv_path=ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                end
                spawn_working = true
                spawn_waiting = false
            end
        end
    )
end

local function run(command)
    if not spawned then return end

    if options.direct_io then
        local hPipe = winapi.C.CreateFileW(winapi.socket_wc, winapi.GENERIC_WRITE, 0, nil, winapi.OPEN_EXISTING, winapi._createfile_pipe_flags, nil)
        if hPipe ~= winapi.INVALID_HANDLE_VALUE then
            local buf = command .. "\n"
            winapi.C.SetNamedPipeHandleState(hPipe, winapi.PIPE_NOWAIT, nil, nil)
            winapi.C.WriteFile(hPipe, buf, #buf + 1, winapi._lpNumberOfBytesWritten, nil)
            winapi.C.CloseHandle(hPipe)
        end

        return
    end

    local command_n = command.."\n"

    if os_name == "windows" then
        if file and file_bytes + #command_n >= 4096 then
            file:close()
            file = nil
            file_bytes = 0
        end
        if not file then
            file = io.open("\\\\.\\pipe\\"..options.socket, "r+b")
        end
    elseif pre_0_33_0 then
        subprocess({"/usr/bin/env", "sh", "-c", "echo '" .. command .. "' | socat - " .. options.socket})
        return
    elseif not file then
        file = io.open(options.socket, "r+")
    end
    if file then
        file_bytes = file:seek("end")
        file:write(command_n)
        file:flush()
    end
end

local function draw(w, h, script)
    if not w or not show_thumbnail then return end
    if x ~= nil then
        local scale_w, scale_h = options.scale_factor ~= 1 and (w * options.scale_factor) or nil, options.scale_factor ~= 1 and (h * options.scale_factor) or nil
        if pre_0_30_0 then
            mp.command_native({"overlay-add", options.overlay_id, x, y, options.thumbnail..".bgra", 0, "bgra", w, h, (4*w), scale_w, scale_h})
        else
            mp.command_native_async({"overlay-add", options.overlay_id, x, y, options.thumbnail..".bgra", 0, "bgra", w, h, (4*w), scale_w, scale_h}, function() end)
        end
    elseif script then
        local json, err = mp.utils.format_json({width=w, height=h, scale_factor=options.scale_factor, x=x, y=y, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
        mp.commandv("script-message-to", script, "thumbfast-render", json)
    end
end

local function real_res(req_w, req_h, filesize)
    local count = filesize / 4
    local diff = (req_w * req_h) - count

    if (properties["video-params"] and properties["video-params"]["rotate"] or 0) % 180 == 90 then
        req_w, req_h = req_h, req_w
    end

    if diff == 0 then
        return req_w, req_h
    else
        local threshold = 5
        local long_side, short_side = req_w, req_h
        if req_h > req_w then
            long_side, short_side = req_h, req_w
        end
        for a = short_side, short_side - threshold, -1 do
            if count % a == 0 then
                local b = count / a
                if long_side - b < threshold then
                    if req_h < req_w then return b, a else return a, b end
                end
            end
        end
        return nil
    end
end

local function move_file(from, to)
    if os_name == "windows" then
        os.remove(to)
    end
    os.rename(from, to)
end

local function seek(fast)
    if last_seek_time then
        run("async seek " .. last_seek_time .. (fast and " absolute+keyframes" or " absolute+exact"))
    end
end

local seek_period = 3/60
local seek_period_counter = 0
local seek_timer
seek_timer = mp.add_periodic_timer(seek_period, function()
    if seek_period_counter == 0 then
        seek(allow_fast_seek)
        seek_period_counter = 1
    else
        if seek_period_counter == 2 then
            if allow_fast_seek then
                seek_timer:kill()
                seek()
            end
        else seek_period_counter = seek_period_counter + 1 end
    end
end)
seek_timer:kill()

local function request_seek()
    if seek_timer:is_enabled() then
        seek_period_counter = 0
    else
        seek_timer:resume()
        seek(allow_fast_seek)
        seek_period_counter = 1
    end
end

local function check_new_thumb()
    local tmp = options.thumbnail..".tmp"
    move_file(options.thumbnail, tmp)
    local finfo = mp.utils.file_info(tmp)
    if not finfo then return false end
    spawn_waiting = false
    local w, h = real_res(effective_w, effective_h, finfo.size)
    if w then
        move_file(tmp, options.thumbnail..".bgra")

        real_w, real_h = w, h
        if real_w and (real_w ~= last_real_w or real_h ~= last_real_h) then
            last_real_w, last_real_h = real_w, real_h
            info(real_w, real_h)
        end
        if not show_thumbnail then
            file_timer:kill()
        end
        return true
    end

    return false
end

file_timer = mp.add_periodic_timer(file_check_period, function()
    if check_new_thumb() then
        draw(real_w, real_h, script_name)
    end
end)
file_timer:kill()

local function clear()
    -- Use Trickplay if active
    if trickplay.active then
        trickplay_clear()
        return
    end

    file_timer:kill()
    seek_timer:kill()
    if options.quit_after_inactivity > 0 then
        if show_thumbnail or activity_timer:is_enabled() then
            activity_timer:kill()
        end
        activity_timer:resume()
    end
    last_seek_time = nil
    show_thumbnail = false
    last_x = nil
    last_y = nil
    if script_name then return end
    if pre_0_30_0 then
        mp.command_native({"overlay-remove", options.overlay_id})
    else
        mp.command_native_async({"overlay-remove", options.overlay_id}, function() end)
    end
end

local function quit()
    activity_timer:kill()
    if show_thumbnail then
        activity_timer:resume()
        return
    end
    run("quit")
    spawned = false
    real_w, real_h = nil, nil
    clear()
end

activity_timer = mp.add_timeout(options.quit_after_inactivity, quit)
activity_timer:kill()

local function thumb(time, r_x, r_y, script)
    -- Use Trickplay if active
    if trickplay.active then
        local tx, ty
        if r_x ~= "" and r_y ~= "" then
            tx, ty = math.floor(r_x + 0.5), math.floor(r_y + 0.5)
        end
        trickplay_thumb(tonumber(time) or 0, tx, ty)
        return
    end
    if trickplay.loading then return end

    if disabled then return end

    time = tonumber(time)
    if time == nil then return end

    if r_x == "" or r_y == "" then
        x, y = nil, nil
    else
        x, y = math.floor(r_x + 0.5), math.floor(r_y + 0.5)
    end

    script_name = script
    if last_x ~= x or last_y ~= y or not show_thumbnail then
        show_thumbnail = true
        last_x, last_y = x, y
        draw(real_w, real_h, script)
    end

    if options.quit_after_inactivity > 0 then
        if show_thumbnail or activity_timer:is_enabled() then
            activity_timer:kill()
        end
        activity_timer:resume()
    end

    if time == last_seek_time then return end
    last_seek_time = time
    if not spawned and not trickplay.active then spawn(time) end
    request_seek()
    if not file_timer:is_enabled() then file_timer:resume() end
end

local function watch_changes()
    if not dirty or not properties["video-out-params"] then return end
    dirty = false

    local old_w = effective_w
    local old_h = effective_h

    calc_dimensions()

    local vf_reset = vf_string(filters_reset)
    local rotate = properties["video-rotate"] or 0

    local resized = old_w ~= effective_w or
        old_h ~= effective_h or
        last_vf_reset ~= vf_reset or
        (last_rotate % 180) ~= (rotate % 180) or
        par ~= last_par or last_crop ~= properties["video-crop"]

    if resized then
        last_rotate = rotate
        info(effective_w, effective_h)
    elseif last_has_vid ~= has_vid and has_vid ~= 0 then
        info(effective_w, effective_h)
    end

    if spawned then
        if resized then
            local seek_time = last_seek_time
            run("quit")
            clear()
            spawned = false
            if not trickplay.active then
                spawn(seek_time or mp.get_property_number("time-pos", 0))
            end
            file_timer:resume()
        else
            if rotate ~= last_rotate then
                run("set video-rotate "..rotate)
            end
            local vf_runtime = vf_string(filters_runtime)
            if vf_runtime ~= last_vf_runtime then
                run("vf set "..vf_string(filters_all, true))
                last_vf_runtime = vf_runtime
            end
        end
    else
        last_vf_runtime = vf_string(filters_runtime)
    end

    last_vf_reset = vf_reset
    last_rotate = rotate
    last_par = par
    last_crop = properties["video-crop"]
    last_has_vid = has_vid

    if not spawned and not disabled and not trickplay.active and not trickplay.loading and options.spawn_first and resized then
        spawn(mp.get_property_number("time-pos", 0))
        file_timer:resume()
    end
end

local function update_property(name, value)
    properties[name] = value
end

local function update_property_dirty(name, value)
    properties[name] = value
    dirty = true
    if name == "tone-mapping" then
        last_tone_mapping = nil
    end
end

local function update_tracklist(name, value)
    for _, track in ipairs(value) do
        if track.type == "video" and track.selected then
            properties["current-tracks/video"] = track
            return
        end
    end
end

local function sync_changes(prop, val)
    update_property(prop, val)
    if val == nil then return end

    if type(val) == "boolean" then
        if prop == "vid" then
            has_vid = 0
            last_has_vid = 0
            info(effective_w, effective_h)
            clear()
            return
        end
        val = val and "yes" or "no"
    end

    if prop == "vid" then
        has_vid = 1
    end

    if not spawned then return end

    run("set " .. prop .. " \"" .. tostring(val):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\"")
    dirty = true
end

local function file_load()
    -- overlay-remove first: never unlink a file mpv may still have mapped
    clear()
    cleanup_trickplay()
    spawned = false
    real_w, real_h = nil, nil
    last_real_w, last_real_h = nil, nil
    last_tone_mapping = nil
    last_seek_time = nil
    if info_timer then
        info_timer:kill()
        info_timer = nil
    end

    -- Try to load Trickplay for Jellyfin streams
    init_trickplay()

    calc_dimensions()
    info(effective_w, effective_h)
end

local function shutdown()
    trickplay_clear()
    cleanup_trickplay()
    run("quit")
    remove_thumbnail_files()
    if os_name ~= "windows" then
        os.remove(options.socket)
        os.remove(options.socket..".run")
    end
end

local function on_duration(prop, val)
    allow_fast_seek = (val or 30) >= 30
end

mp.observe_property("current-tracks/video", "native", function(name, value)
    if pre_0_33_0 then
        mp.unobserve_property(update_tracklist)
        pre_0_33_0 = false
    end
    update_property(name, value)
end)

mp.observe_property("track-list", "native", update_tracklist)
mp.observe_property("display-hidpi-scale", "native", update_property_dirty)
mp.observe_property("video-out-params", "native", update_property_dirty)
mp.observe_property("video-params", "native", update_property_dirty)
mp.observe_property("vf", "native", update_property_dirty)
mp.observe_property("tone-mapping", "native", update_property_dirty)
mp.observe_property("demuxer-via-network", "native", update_property)
mp.observe_property("stream-open-filename", "native", update_property)
mp.observe_property("macos-app-activation-policy", "native", update_property)
mp.observe_property("current-vo", "native", update_property)
mp.observe_property("video-rotate", "native", update_property)
mp.observe_property("video-crop", "native", update_property)
mp.observe_property("path", "native", update_property)
mp.observe_property("vid", "native", sync_changes)
mp.observe_property("edition", "native", sync_changes)
mp.observe_property("duration", "native", on_duration)

mp.register_script_message("thumb", thumb)
mp.register_script_message("clear", clear)

mp.register_event("file-loaded", file_load)
mp.register_event("shutdown", shutdown)

mp.register_idle(watch_changes)

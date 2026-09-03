-- jellyfin-trickplay.lua
-- Fetches Trickplay thumbnails from Jellyfin server for seekbar previews.
-- Works alongside ModernX (which sends thumb/clear messages via thumbfast API).
-- Falls back to thumbfast for non-Jellyfin content.

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local options = {
    enabled = true,
    width = 320,
    overlay_id = 47,  -- Different from thumbfast (42) to avoid conflicts
}

local state = {
    active = false,
    server_url = nil,
    api_key = nil,
    item_id = nil,
    tile_width = 0,
    tile_height = 0,
    interval = 0,
    tiles_x = 0,
    tiles_y = 0,
    thumbnail_count = 0,
    tile_file = nil,
    last_frame = -1,
    last_x = nil,
    last_y = nil,
    is_shown = false,
}

local function send_thumbfast_info()
    local json = utils.format_json({
        width = state.tile_width,
        height = state.tile_height,
        scale_factor = 1,
        disabled = not state.active,
        available = state.active,
        overlay_id = options.overlay_id,
    })
    mp.commandv("script-message", "thumbfast-info", json)
end

local function extract_jellyfin_info(path)
    -- URL pattern: https://host/jellyfin/Videos/{itemId}/stream?static=true&api_key={key}
    -- or: https://host/Videos/{itemId}/stream?...&api_key={key}
    local server = path:match("^(https?://[^/]+/[^/]+)")
    if not server then
        server = path:match("^(https?://[^/]+)")
    end
    local item_id = path:match("/Videos/([a-f0-9]+)/stream")
    local api_key = path:match("api_key=([^&]+)")

    if server and item_id and api_key then
        return server, item_id, api_key
    end
    return nil, nil, nil
end

local function download_trickplay_tile(server, item_id, api_key, width, index)
    local url = string.format("%s/Videos/%s/Trickplay/%d/%d.jpg", server, item_id, width, index)
    local tmpfile = os.tmpname() .. ".jpg"

    local result = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
        args = {
            "curl", "-sS", "-L",
            "-H", "Authorization: MediaBrowser Token=\"" .. api_key .. "\"",
            "-o", tmpfile,
            url
        }
    })

    if result and result.status == 0 then
        -- Verify the file exists and has content
        local f = io.open(tmpfile, "rb")
        if f then
            local size = f:seek("end")
            f:close()
            if size and size > 0 then
                return tmpfile
            end
        end
    end
    os.remove(tmpfile)
    return nil
end

local function get_user_id(server, api_key)
    local result = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
        args = {
            "curl", "-sS",
            "-H", "Authorization: MediaBrowser Token=\"" .. api_key .. "\"",
            server .. "/Users"
        }
    })

    if result and result.status == 0 and result.stdout then
        local users = utils.parse_json(result.stdout)
        if users and users[1] and users[1].Id then
            return users[1].Id
        end
    end
    return nil
end

local function get_trickplay_info(server, item_id, api_key, user_id)
    local url = string.format("%s/Users/%s/Items/%s", server, user_id, item_id)
    local result = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
        args = {
            "curl", "-sS",
            "-H", "Authorization: MediaBrowser Token=\"" .. api_key .. "\"",
            url
        }
    })

    if result and result.status == 0 and result.stdout then
        local json = utils.parse_json(result.stdout)
        if json and json.Trickplay then
            -- Trickplay structure: {itemId: {width: {Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval}}}
            for _, width_data in pairs(json.Trickplay) do
                for width_str, info in pairs(width_data) do
                    local width = tonumber(width_str)
                    if width and info then
                        return {
                            width = info.Width or width,
                            height = info.Height or 180,
                            interval = info.Interval or 10000,
                            tiles_x = info.TileWidth or 10,
                            tiles_y = info.TileHeight or 10,
                            thumbnail_count = info.ThumbnailCount or 0,
                        }
                    end
                end
            end
        end
    end
    return nil
end

local function convert_to_bgra(jpg_path, width, height)
    local bgra_path = jpg_path:gsub("%.jpg$", ".bgra")
    local result = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
        args = {
            "ffmpeg", "-y", "-i", jpg_path,
            "-vf", string.format("scale=%d:%d", width, height),
            "-pix_fmt", "bgra",
            "-f", "rawvideo",
            bgra_path
        }
    })

    if result and result.status == 0 then
        os.remove(jpg_path)
        return bgra_path
    end
    os.remove(jpg_path)
    os.remove(bgra_path)
    return nil
end

local function cleanup_tiles()
    if state.tile_file then
        os.remove(state.tile_file)
        state.tile_file = nil
    end
    state.last_frame = -1
end

local function handle_thumb(offset_seconds, x, y)
    if not state.active or not state.tile_file then
        return
    end

    local frame = math.floor(offset_seconds / (state.interval / 1000))
    if frame < 0 then frame = 0 end
    if frame >= state.thumbnail_count then frame = state.thumbnail_count - 1 end

    -- Calculate position within the tile grid
    local tile_index = math.floor(frame / (state.tiles_x * state.tiles_y))
    local frame_in_tile = frame % (state.tiles_x * state.tiles_y)
    local grid_x = frame_in_tile % state.tiles_x
    local grid_y = math.floor(frame_in_tile / state.tiles_x)

    -- Calculate byte offset in the BGRA file
    -- Each tile image is (tile_width * tiles_x) x (tile_height * tiles_y)
    local image_width = state.tile_width * state.tiles_x
    local pixel_offset = (grid_y * state.tile_height * image_width + grid_x * state.tile_width) * 4

    if frame ~= state.last_frame or x ~= state.last_x or y ~= state.last_y then
        state.last_frame = frame
        state.last_x = x
        state.last_y = y
        state.is_shown = true
        mp.commandv("overlay-add", options.overlay_id, x, y, state.tile_file, pixel_offset, "bgra", state.tile_width, state.tile_height, image_width * 4)
    end
end

local function handle_clear()
    if state.is_shown then
        mp.commandv("overlay-remove", options.overlay_id)
        state.is_shown = false
        state.last_frame = -1
        state.last_x = nil
        state.last_y = nil
    end
end

local function init_trickplay()
    local path = mp.get_property("path")
    if not path then return end

    local server, item_id, api_key = extract_jellyfin_info(path)
    if not server or not item_id or not api_key then
        state.active = false
        return
    end

    state.server_url = server
    state.item_id = item_id
    state.api_key = api_key

    -- Get user ID
    local user_id = get_user_id(server, api_key)
    if not user_id then
        msg.warn("Failed to get Jellyfin user ID")
        state.active = false
        send_thumbfast_info()
        return
    end

    -- Get Trickplay info
    local info = get_trickplay_info(server, item_id, api_key, user_id)
    if not info then
        msg.info("No Trickplay data available for this item")
        state.active = false
        send_thumbfast_info()
        return
    end

    state.tile_width = info.width
    state.tile_height = info.height
    state.interval = info.interval
    state.tiles_x = info.tiles_x
    state.tiles_y = info.tiles_y
    state.thumbnail_count = info.thumbnail_count

    -- Download first tile image
    local jpg_path = download_trickplay_tile(server, item_id, api_key, info.width, 0)
    if not jpg_path then
        msg.warn("Failed to download Trickplay tile")
        state.active = false
        send_thumbfast_info()
        return
    end

    -- Convert to BGRA
    local bgra_path = convert_to_bgra(jpg_path, info.width * info.tiles_x, info.height * info.tiles_y)
    if not bgra_path then
        msg.warn("Failed to convert Trickplay tile to BGRA")
        state.active = false
        send_thumbfast_info()
        return
    end

    state.tile_file = bgra_path
    state.active = true
    msg.info("Trickplay loaded: " .. info.width .. "x" .. info.height .. ", interval=" .. info.interval .. "ms, tiles=" .. info.tiles_x .. "x" .. info.tiles_y)
    send_thumbfast_info()

    -- Tell thumbfast to delegate to us
    mp.commandv("script-message-to", "thumbfast", "set-jellyfin-trickplay", "true")
end

-- Register message handlers (compatible with thumbfast API)
-- ModernX sends messages to "thumbfast", so we need to handle them
mp.register_script_message("thumbfast-thumb", function(_, offset_seconds, x, y)
    if state.active then
        handle_thumb(tonumber(offset_seconds), tonumber(x), tonumber(y))
    end
end)

mp.register_script_message("thumbfast-clear", function()
    handle_clear()
end)

-- Also register as "thumb" and "clear" for direct messages
mp.register_script_message("thumb", function(_, offset_seconds, x, y)
    if state.active then
        handle_thumb(tonumber(offset_seconds), tonumber(x), tonumber(y))
    end
end)

mp.register_script_message("clear", function()
    handle_clear()
end)

-- Initialize when a file is loaded
mp.register_event("file-loaded", function()
    cleanup_tiles()
    state.active = false

    -- Tell thumbfast to stop delegating to us
    mp.commandv("script-message-to", "thumbfast", "set-jellyfin-trickplay", "false")

    if options.enabled then
        init_trickplay()
    end
end)

-- Cleanup on shutdown
mp.register_event("shutdown", function()
    cleanup_tiles()
end)

msg.info("jellyfin-trickplay.lua loaded")

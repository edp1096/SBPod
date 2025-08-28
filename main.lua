local is_debug = false
-- local is_debug = true
local function dprint(msg)
    if is_debug then
        print("[SBPod] " .. msg .. "\n")
    end
end


local audio = require("audio")
local sound = nil
local is_music_stop = false
local is_music_delayed_start = false
local manual_music_stop = false

local default_volume = 0.1
local current_volume = default_volume
-- local max_volume = 0.2
local max_volume = 1.0

local music_dir = "C:/Music"
local music_files = {}

local f = io.open("ue4ss/Mods/SBPod/sbpod_settings.txt", "r")
if f then
    local first_line = f:read("*line")
    local second_line = f:read("*line")
    local third_line = f:read("*line")

    if first_line then music_dir = first_line end

    if second_line then
        local volume_pct = tonumber(second_line)
        if volume_pct then
            if volume_pct > 100 then volume_pct = 100 end
            current_volume = volume_pct * max_volume / 100
        end
    end

    if third_line then
        if third_line == "debug" then
            is_debug = true
        end
    end

    f:close()
end

function GetMusicFiles()
    if not audio.dirExists(music_dir) then
        dprint("Music directory not found: " .. music_dir)
        return {}
    end

    local files = audio.scanMusicFiles(music_dir)
    if files then
        for i, filename in ipairs(files) do
            dprint("Found music file: " .. filename)
        end
    end

    dprint("Total music files found: " .. #files)
    return files
end

local function playMusic(music_file)
    sound = audio.load(music_file)
    if not sound then
        dprint("Failed to load " .. music_file)
        return
    end

    dprint("Loaded " .. music_file)

    sound:setVolume(current_volume)
    sound:play()

    while sound:isPlaying() do
        if is_music_stop then break end
        audio.msleep(180)
    end


    local time_delay = 10
    -- if is_music_delayed_start then time_delay = 2800 end
    if is_music_delayed_start then time_delay = 4800 end

    ExecuteWithDelay(time_delay, function()
        is_music_stop = false

        local fadeout_volume = current_volume
        local volume_down_step = current_volume / 25
        -- local volume_down_step = current_volume / 100

        while fadeout_volume > 0.0 do
            fadeout_volume = fadeout_volume - volume_down_step
            if fadeout_volume < 0.0 then fadeout_volume = 0.0 end
            sound:setVolume(fadeout_volume)
            audio.msleep(50)
        end

        sound:stop()
        sound:setVolume(current_volume)
    end)
    audio.msleep(time_delay + 100)

    dprint("Finished playing " .. music_file)
end

local previous_music_index = 0
local current_music_index = 0
local function playShuffle()
    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        current_music_index = math.random(#music_files)
        if #music_files == 0 or current_music_index ~= previous_music_index then
            return
        end
    end

    local music_file = music_files[math.random(#music_files)]
    music_file = music_file:gsub("/", "\\")
    playMusic(music_file)
end

function GetMapName()
    local map_name = "Unknown Map"

    local eve = FindFirstOf("CH_P_EVE_01_Blueprint_C")
    if eve and eve:IsValid() then
        map_name = eve:GetFullName()
    end

    return map_name
end

RegisterKeyBind(0xBD, function()
    dprint("Minus key pressed")
    current_volume = current_volume - 0.005
    if current_volume < 0.0 then current_volume = 0.0 end
    sound:setVolume(current_volume)
    dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
    audio.beep(400, 50)
end)
RegisterKeyBind(0xBB, function()
    dprint("Equal key pressed")
    current_volume = current_volume + 0.005
    if current_volume > max_volume then current_volume = max_volume end
    sound:setVolume(current_volume)
    dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
    audio.beep(800, 50)
end)
RegisterKeyBind(Key.DEL, function()
    dprint("Del key pressed")

    if sound:isPlaying() then
        manual_music_stop = true
        is_music_stop = true
    else
        manual_music_stop = false
    end
end)


RegisterHook("/Script/Engine.PlayerController:ClientSetHUD", function(ctx)
    dprint("ClientSetHUD") -- 이건 ClientRestart 보다 먼저 떠버리노
end)
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(ctx)
    dprint("Restarting music")

    local mapName = GetMapName()
    dprint("Target map name: " .. mapName)

    is_music_delayed_start = false
    -- if not string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Lobby/Lobby.LOBBY") then
    if string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Art/BG/WorldMap/") then
        dprint("Move to Stage")
        is_music_delayed_start = true
    end
    is_music_stop = true
end)

local function setupMod()
    audio.init()
    music_files = GetMusicFiles()

    audio.msleep(500)
    playShuffle()

    LoopAsync(500, function()
        if not manual_music_stop then
            playShuffle()
        end
        return false
    end)
end

print("[SBPod] is loaded\n")

audio.msleep(1000)
setupMod()

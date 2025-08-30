local is_debug = false
-- local is_debug = true
local function dprint(msg)
    if is_debug then
        print("[SBPod] " .. msg .. "\n")
    end
end


local audio = require("audio")
local ini = require("ini")

local sound = nil

local default_volume = 0.1
local current_volume = default_volume
-- local max_volume = 0.2
local max_volume = 1.0

local music_dir = "C:/Music"
local music_files = {}

local previous_music_index = 0
local current_music_index = 0


local cfg, err = ini:Read("ue4ss/Mods/SBPod/config.ini")
if not cfg then
    dprint("Error:" .. tostring(err))
end
if cfg == nil then return end

if cfg.WorkingMode == "debug" then is_debug = true end
music_dir = cfg.MusicPath.Default
current_volume = cfg.VolumePercent * max_volume / 100
if current_volume > max_volume then current_volume = max_volume end


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
    -- audio.init()
    sound = audio.load(music_file)
    if not sound then
        dprint("Failed to load " .. music_file)
        return
    end

    dprint("Loaded " .. music_file)

    sound:setVolume(current_volume)
    sound:play()
end

local function stopMusic()
    if not sound then return false end
    -- sound:stop()

    local fadeout_volume = current_volume
    local volume_down_step = current_volume / 50

    while fadeout_volume > 0.0 do
        fadeout_volume = fadeout_volume - volume_down_step
        if fadeout_volume < 0.0 then fadeout_volume = 0.0 end
        sound:setVolume(fadeout_volume)
        audio.msleep(25)
    end

    sound:stop()
    sound = nil
    -- audio.shutdown()

    dprint("Music is stopped " .. music_files[current_music_index])
end


local function playShuffle()
    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        if #music_files == 0 then return end
        current_music_index = math.random(#music_files)
    end
    previous_music_index = current_music_index

    dprint("Music index: " .. current_music_index)

    local music_file = music_files[current_music_index]
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
    ExecuteAsync(function()
        dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
        sound:setVolume(current_volume)
        audio.beep(400, 50)
    end)
end)
RegisterKeyBind(0xBB, function()
    dprint("Equal key pressed")
    current_volume = current_volume + 0.005
    if current_volume > max_volume then current_volume = max_volume end
    ExecuteAsync(function()
        dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
        sound:setVolume(current_volume)
        audio.beep(800, 50)
    end)
end)
RegisterKeyBind(Key.DEL, function()
    dprint("Del key pressed")

    if sound and sound:isPlaying() then
        ExecuteAsync(function() stopMusic() end)
    else
        ExecuteAsync(function() playShuffle() end)
    end
end)


local pkgs = {
    "/Game/Art/Character/Monster/CH_M_NA_39/Blueprints/CH_M_NA_39_Seq_BP",
    "/Game/Art/Character/Monster/CH_M_NA_07/Blueprints/CH_M_NA_07_02_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_05/Blueprints/CH_M_NA_05_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_43/Blueprints/CH_M_NA_43_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_05/Blueprints/CH_M_NA_05_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_13/BluePrints/CH_M_NA_13_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_15/Animation/event/ME05_02_EliteNative_Entrance_NA15_01",
    "/Game/Art/Character/Monster/CH_M_NA_21/Animation/event/ME06_01_Tachy_Entrance_NA_21_05",
    "/Game/Art/Character/Monster/CH_M_NA_13/BluePrints/CH_M_NA_13_TypeB_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_39/Blueprints/CH_M_NA_39_TypeB_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_46/BluePrints/CH_M_NA_46_Var01_BluePrint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_07/Blueprints/CH_M_NA_07_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_31/Blueprints/CH_M_NA_31_Blueprint_seq",
    "/Game/Art/Character/Monster/CH_M_NA_26/Blueprints/CH_M_NA_26_Seq_BP",
    "/Game/Art/Character/Monster/CH_M_NA_22/BluePrints/CH_M_NA_22_Blueprint_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_42/Blueprints/CH_M_NA_42_Blueprint",
    "/Game/Art/Character/Monster/CH_M_NA_53/Blueprints/CH_M_NA_53_Blueprint",
    "/Game/Art/Character/Monster/CH_M_NA_54/Blueprints/CH_M_NA_54_Blueprint",
    "/Game/Art/Character/Monster/CH_M_NA_56/Blueprints/CH_M_NA_56_BP_Seq",
    "/Game/Art/Character/Monster/CH_M_NA_901/Blueprints/CH_M_NA_901_Blueprint",
    "/Game/DLC_2/Art/Character/Monster/CH_M_NA_961/Blueprints/CH_M_NA_961_Blueprint",
}

local function checkPackage()
    -- Abaddon
    -- local pkg = StaticFindObject(
    --     "/Game/Art/Character/Monster/CH_M_NA_39/Blueprints/CH_M_NA_39_Seq_BP.CH_M_NA_39_Seq_BP_C")
    -- local pkg = StaticFindObject(
    --     "/Game/GameDesign/Level/Theater/DrownedEidosDistrict/DED01/LevelSeq/MV_DED01_Parkinglot_AfterBattle_QTE_Success.SequenceDirector_C")
    local pkg = StaticFindObject(
        "/Game/Art/Character/Monster/CH_M_NA_05/Blueprints/CH_M_NA_05_Blueprint_Seq.CH_M_NA_05_Blueprint_Seq_C")

    if not pkg or not pkg:IsValid() then
        -- dprint("Package not found")
        ExecuteWithDelay(1500, checkPackage)
        return false
    end

    dprint("Package found: " .. pkg:GetFullName())
    return true
end


RegisterHook("/Script/Engine.PlayerController:ClientSetHUD", function(ctx)
    dprint("ClientSetHUD") -- 이건 ClientRestart 보다 먼저 떠버리노
end)
ExecuteWithDelay(5000, function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(ctx)
        dprint("Restarting music " .. ctx:get():GetFullName())

        local mapName = GetMapName()
        dprint("Target map name: " .. mapName)

        is_music_delayed_start = false
        -- if not string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Lobby/Lobby.LOBBY") then
        if string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Art/BG/WorldMap/") then
            dprint("Move to Stage")
            is_music_delayed_start = true
        end

        ExecuteAsync(function()
            stopMusic()
            audio.msleep(2000)
            playShuffle()

            checkPackage()
        end)
    end)
end)


local function setupMod()
    audio.init()
    music_files = GetMusicFiles()
    ExecuteWithDelay(180, function() playShuffle() end)
end

print("[SBPod] is loaded\n")

setupMod()

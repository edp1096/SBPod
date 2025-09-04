local is_debug = false

local function dprint(msg)
    if is_debug then
        print("[SBPod] " .. msg .. "\n")

        local log_file = io.open("ue4ss/Mods/SBPod/debug.log", "a")
        if not log_file then return end
        -- print time instead of SBPod
        log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        log_file:close()
    end
end


local audio = require("audio")
-- local audio_boss = require("audio")
local ini = require("ini")
local text = require("text")

local sound = nil
local manual_stop = false

-- Music control state management to prevent race conditions
local music_state = {
    is_stopping = false,
    is_playing_new = false,
    is_transitioning = false,
    pending_files = nil
}

local default_volume = 0.1
local current_volume = default_volume
-- local max_volume = 0.2
local max_volume = 1.0

local music_dirs = {}
local music_files = {}
local music_files_boss = {}
local previous_music_files = {}
local current_music_files = {}

local previous_music_index = 0
local current_music_index = 0

local use_boss_bgm = true
local is_boss_bgm_triggered = false
local boss_bgm_components = {}


local worldmap_names = {
    Lobby = "/Game/Lobby/Lobby.LOBBY",
    G03 = "/Game/Art/BG/WorldMap/Level_P/G03.G03",
    Eidos7 = "/Game/Art/BG/WorldMap/Level_P/F02.F02",
    Xion = "/Game/Art/BG/WorldMap/Level_P/E04.E04",
    Wasteland = "/Game/Art/BG/WorldMap/E03_WasteLand_P/E03_WasteLand_P.E03_WasteLand_P",
    AltesseLevoir = "/Game/Art/BG/WorldMap/Dungeon_P/AltesLab_P.AltesLab_P",
    Matrix11 = "/Game/Art/BG/WorldMap/Dungeon_P/Matrix_XI.Matrix_XI",
    GreatDesert = "/Game/Art/BG/WorldMap/E05_GreatDesert_P/E05_GreatDesert_P.E05_GreatDesert_P",
    AbyssLevoir = "/Game/Art/BG/WorldMap/Dungeon_P/AbyssLab_P.AbyssLab_P",
    Eidos9 = "/Game/Art/BG/WorldMap/Level_P/F01.F01",
    Spire4 = "/Game/Art/BG/WorldMap/Level_P/B07.B07",
    Nest = "/Game/Art/BG/WorldMap/Level_P/C05.C05",
    Epilog = "/Game/Art/BG/WorldMap/Dungeon_P/Epilogue_P.Epilogue_P",
    EpilogColony = "/Game/Art/BG/WorldMap/Dungeon_P/Ending_P.Ending_P"
}
local boss_bgm_names = {
    Abaddon = "BGM/F02/BGM_DED_BOSS_Abaddon",
    Corrupter = "BGM/F02/BGM_DED_BOSS_Grubshooter",
    Gigas = "BGM/F02/BGM_DED_BOSS_Gigas",
    Brute = "BGM/E03/BGM_WASTELAND_BOSS_BRUTE",
    GigasWasteland = "BGM/E03/BGM_WASTELAND_BOSS_GIGAS",
    Stalker = "BGM/Matrix_XI/BGM_ME_BOSS_Sawshark",
    Juggernaut = "BGM/Matrix_XI/BGM_ME_BOSS_JUGGERNAUT",
    Tachy = "BGM/Matrix_XI/BGM_ME_BOSS_Tachy",
    Tachy_P2 = "BGM/Matrix_XI/BGM_ME_BOSS_TACHY",
    StalkerGreatDesert = "BGM/Matrix_XI/BGM_ME_BOSS_STALKER",
    StalkerGreatDesert_P2 = "BGM/E05/BGM_E05_BOSS_Sawshark",
    Behemoth = "BGM/E05/BGM_E03_BOSS_Behemoth",
    Belial = "BGM/B07/BossBattle/BGM_SE_BOSS_Belial_Cue",
    Karakuri = "BGM/B07/BossBattle/BGM_SE_BOSS_Karakuri",
    Democrawler = "BGM/B07/BossBattle/BGM_SE_BOSS_Crawler",
    RavenBeast = "BGM/E04/BGM_XION_BOSS_RavenBeast",
    Raven = "BGM/E03/BGM_NEST_BOSS_RAVEN",
    MotherSphereLilySave = "BGM/Nest/BGM_NEST_BOSS_LILY_END_MS_SAVE",
    MotherSphereLilyDead = "BGM/Nest/BGM_NEST_BOSS_LILY_END_A",
    Providence = "BGM/Nest/BGM_NEST_BOSS_LILY_P",
    Elder = "BGM/Nest/BGM_NEST_BOSS_ELDER_P",
    ElderEnd = "BGM/Nest/BGM_NEST_BOSS_ELDER_END",
    Mann = "BGM/Nikke/BGM_D2_BOSS_MANN",
    Scarlet = "BGM/Nikke/BGM_BOSS_SCARLET"
}


local cfg, err = ini:Read("ue4ss/Mods/SBPod/config.ini")
if not cfg then
    dprint("Error:" .. tostring(err))
end
if cfg == nil then return end

for k, v in pairs(cfg.MusicPath) do
    music_dirs[k] = v
end
for k, v in pairs(cfg.Boss) do
    music_files_boss[k] = v
end

current_volume = cfg.VolumePercent * max_volume / 100
if current_volume > max_volume then
    current_volume = max_volume
end
if cfg.WorkingMode == "debug" then
    is_debug = true

    local log_file = io.open("ue4ss/Mods/SBPod/debug.log", "w")
    if log_file then log_file:close() end
end


function GetMusicFiles(music_dir)
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
    -- Check if we're in a valid state to play music (but allow during transition)
    if music_state.is_stopping then
        dprint("Cannot play music - currently stopping")
        return false
    end

    sound = audio.load(music_file)
    if not sound then
        dprint("Failed to load " .. music_file)
        return false
    end

    dprint("Loaded " .. music_file)

    sound:setVolume(current_volume)
    sound:play()
    return true
end

local function stopMusic()
    if not sound or music_state.is_stopping then
        return false
    end

    music_state.is_stopping = true

    local fadeout_volume = current_volume
    local volume_down_step = current_volume / 50

    -- Fadeout effect
    while fadeout_volume > 0.0 and sound do
        fadeout_volume = fadeout_volume - volume_down_step
        if fadeout_volume < 0.0 then fadeout_volume = 0.0 end
        sound:setVolume(fadeout_volume)
        audio.msleep(25)
    end

    if sound then
        sound:stop()
        sound = nil
    end

    music_state.is_stopping = false
    dprint("Music is stopped.")
    return true
end

local function playShuffle(music_files)
    -- Prevent multiple simultaneous shuffle calls, but allow if not transitioning
    if music_state.is_playing_new or music_state.is_stopping then
        dprint("Cannot start shuffle - music system busy (playing:" ..
            tostring(music_state.is_playing_new) .. ", stopping:" .. tostring(music_state.is_stopping) .. ")")
        return false
    end

    music_state.is_playing_new = true

    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        if #music_files == 0 then
            music_state.is_playing_new = false
            dprint("No music files to shuffle")
            return false
        end
        current_music_index = math.random(#music_files)
        if #music_files == 1 then break end
    end
    previous_music_index = current_music_index

    dprint("Music index: " .. current_music_index)

    local music_file = music_files[current_music_index]
    music_file = music_file:gsub("/", "\\")

    local success = playMusic(music_file)
    music_state.is_playing_new = false

    return success
end

-- Safe music transition function to prevent race conditions
local function safeMusicTransition(new_music_files, delay)
    if music_state.is_transitioning then
        dprint("Music transition already in progress")
        return
    end

    dprint("Starting music transition with " .. #new_music_files .. " files")
    music_state.is_transitioning = true

    ExecuteAsync(function()
        manual_stop = true

        if delay and delay > 0 then
            dprint("Waiting " .. delay .. "ms before transition")
            audio.msleep(delay)
        end

        -- Stop current music if playing
        if sound then
            dprint("Stopping current music")
            stopMusic()
        end

        -- Wait a bit to ensure complete stop
        audio.msleep(100)

        -- Reset states before playing new music
        music_state.is_stopping = false
        music_state.is_playing_new = false

        -- Play new music if we have files
        if new_music_files and #new_music_files > 0 then
            dprint("Playing new music from transition")
            current_music_files = new_music_files

            -- Direct music playing without state checks in transition
            while previous_music_index == current_music_index do
                if #new_music_files == 0 then break end
                current_music_index = math.random(#new_music_files)
                if #new_music_files == 1 then break end
            end
            previous_music_index = current_music_index

            local music_file = new_music_files[current_music_index]
            music_file = music_file:gsub("/", "\\")

            dprint("Transition playing: " .. music_file)
            playMusic(music_file)
        else
            dprint("No music files to play in transition")
        end

        manual_stop = false
        music_state.is_transitioning = false

        dprint("Music transition completed")
    end)
end

local function togglePlay()
    if sound and sound:isPlaying() then
        dprint("Stop music")
        manual_stop = true
        ExecuteAsync(function()
            stopMusic()
        end)
    else
        dprint("Play music")
        manual_stop = false
        ExecuteAsync(function()
            playShuffle(current_music_files)
        end)
    end
end

local function onMusicEnded()
    dprint("Music ended callback triggered")

    if not manual_stop and #current_music_files > 0 and not music_state.is_transitioning then
        ExecuteAsync(function()
            audio.msleep(500)
            if not manual_stop and not music_state.is_transitioning then
                playShuffle(current_music_files)
            end
        end)
    end
end

function GetMapName()
    local map_name = "Unknown Map"

    local eve = FindFirstOf("CH_P_EVE_01_Blueprint_C")
    if eve and eve:IsValid() then
        map_name = eve:GetFullName()
    end

    return map_name
end

-- Key bindings for volume control and playback
RegisterKeyBind(0xBD, function() -- Minus key
    dprint("Minus key pressed")
    current_volume = current_volume - 0.005
    if current_volume < 0.0 then current_volume = 0.0 end
    ExecuteAsync(function()
        dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
        if sound then sound:setVolume(current_volume) end
        audio.beep(400, 50)
    end)
end)

RegisterKeyBind(0xBB, function() -- Equal key (Plus)
    dprint("Equal key pressed")
    current_volume = current_volume + 0.005
    if current_volume > max_volume then current_volume = max_volume end
    ExecuteAsync(function()
        dprint("Volume: " .. math.floor(current_volume / max_volume * 100) .. "% / " .. current_volume)
        if sound then sound:setVolume(current_volume) end
        audio.beep(800, 50)
    end)
end)

RegisterKeyBind(Key.DEL, function()
    dprint("Del key pressed")
    togglePlay()
end)


local function controlBossBGM(ctx)
    if not ctx.Sound then return end

    local cname = ctx:GetFullName()
    if not string.find(cname, ":AudioComponent_") then return end

    -- audio_component: component_name, cue_name, wave_name, boss_name_key, is_playing
    local audio_component = {}
    local polling_interval = 1250 -- ms
    -- local polling_interval = 450 -- ms
    -- local polling_interval = 2500 -- ms

    LoopAsync(polling_interval, function()
        if not ctx or not ctx:IsValid() then return true end

        if ctx:IsPlaying() then
            audio_component["context"] = ctx
            audio_component["component_name"] = ctx:GetFullName()
            audio_component["cue_name"] = ctx.Sound and
                ctx.Sound:GetClass():GetFullName() and
                ctx.Sound:GetFullName() or
                "Unknown Cue"
            local sound_wave = ctx.Sound.FirstNode and
                ctx.Sound.FirstNode.SoundWave or
                nil
            audio_component["wave_name"] = sound_wave and sound_wave:GetFullName() or "Unknown SoundWave"

            -- Todo: Hard coding. remove and move to table var.
            -- Check if this is system music (exclude from boss BGM detection)
            local is_system_music = string.find(audio_component["cue_name"], "BGM_SYS_EPILOGUE_CUE")
            -- local is_elder_intro_music = string.find(audio_component["cue_name"], "BGM/Nest/BGM_NEST_BOSS_ELDER_P1_INTRO")
            -- local is_elder_intro_music = string.find(audio_component["wave_name"], "BGM/Nest/BGM_NEST_BOSS_ELDER_P1_INTRO")
            local is_intro_music = string.find(audio_component["cue_name"], "BGM/Nest/BGM_") and
                string.find(audio_component["wave_name"], "_INTRO")
            if is_system_music or is_intro_music then return true end

            if audio_component["wave_name"] ~= "Unknown SoundWave" then
                -- Single SoundWave
                for k, boss_bgm_name in pairs(boss_bgm_names) do
                    if string.find(audio_component["wave_name"], boss_bgm_name) then
                        audio_component["boss_name_key"] = text:Split(k, "_")[1]
                        -- audio_component["boss_name_key"] = k
                        break
                    end
                end
            else
                -- Multiple SoundWaves or VendingMachine or SoundNodeSwitch or Mixer or others
                for k, boss_bgm_name in pairs(boss_bgm_names) do
                    if string.find(audio_component["cue_name"], boss_bgm_name) then
                        audio_component["boss_name_key"] = text:Split(k, "_")[1]
                        -- audio_component["boss_name_key"] = k
                        break
                    end
                end
            end

            if audio_component["boss_name_key"] then
                audio_component["is_playing"] = ctx:IsPlaying()
                -- audio_component["boss_name"] = string.gsub(audio_component["boss_name_key"], "_", " ")
                audio_component["boss_name"] = audio_component["boss_name_key"]

                dprint("SoundWave: " .. audio_component["wave_name"])
                dprint("Wav/Cue: " .. audio_component["cue_name"])
                dprint("- AudioComponent: " .. audio_component["component_name"])
                dprint("- Boss name: " .. audio_component["boss_name"])
                -- dprint("- Boss name key: " .. audio_component["boss_name_key"])

                dprint("is_boss_bgm_triggered: " .. tostring(is_boss_bgm_triggered))

                -- table.insert(boss_bgm_components, audio_component)
                local already_added = false
                for i = 1, #boss_bgm_components do
                    if boss_bgm_components[i]["component_name"] == audio_component["component_name"] then
                        already_added = true
                        break
                    end
                end
                if not already_added then
                    table.insert(boss_bgm_components, audio_component)
                end

                if not is_boss_bgm_triggered then
                    local fname = text:TrimSpace(music_files_boss[audio_component["boss_name"]])
                    dprint("Current music fname: " .. tostring(fname))

                    local boss_files = {}
                    if fname ~= "" then
                        boss_files = { music_dirs["Boss"] .. "/" .. fname }
                        dprint("Current music files: " .. #boss_files)
                        for i = 1, #boss_files do
                            dprint("#" .. i .. ": " .. boss_files[i])
                        end
                    elseif #music_files["Boss"] > 0 then
                        dprint("Boss music: random")
                        boss_files = music_files["Boss"]
                    else
                        dprint("No boss music")
                        return true
                    end

                    is_boss_bgm_triggered = true
                    current_music_files = boss_files

                    -- Use safe transition instead of direct async call
                    safeMusicTransition(boss_files, 50)

                    return false
                end
            end
        end

        if is_boss_bgm_triggered and not ctx:IsPlaying() then
            dprint("isActive:" .. tostring(ctx:IsActive()) .. ", is_playing:" .. tostring(ctx:IsPlaying()))

            -- Loop forever for Fusion ending (actually until PlayerController:ClientRestart)
            if string.find(audio_component["boss_name"], "MotherSphereLily") then
                dprint("Fusion ending. Loop until ending finish")
                return false
            end

            local component_name = ctx:GetFullName()
            dprint("component_name: " .. component_name)

            for i = #boss_bgm_components, 1, -1 do
                if boss_bgm_components[i]["component_name"] == component_name then
                    -- dprint("Removing stopped component: " .. i .. ": " .. boss_bgm_components[i]["component_name"])
                    table.remove(boss_bgm_components, i)
                    break
                end
            end

            for i = #boss_bgm_components, 1, -1 do
                if not boss_bgm_components[i]["context"]:IsPlaying() then
                    -- dprint("Removing dead component: " .. i .. ": " .. boss_bgm_components[i]["component_name"])
                    table.remove(boss_bgm_components, i)
                end
            end

            dprint("#boss_bgm_components: " .. #boss_bgm_components)
            for i = 1, #boss_bgm_components do
                dprint("#" .. i .. ": " .. boss_bgm_components[i]["wave_name"])
                dprint("#" .. i .. ": " .. boss_bgm_components[i]["cue_name"])
                dprint("#" .. i .. ": " .. boss_bgm_components[i]["component_name"])
                dprint("#" .. i .. ": " .. boss_bgm_components[i]["boss_name_key"])
            end

            if #boss_bgm_components > 0 then return false end

            is_boss_bgm_triggered = false
            current_music_files = previous_music_files
            boss_bgm_components = {}

            -- Use safe transition instead of direct async call
            safeMusicTransition(current_music_files, 50)
        end

        if #boss_bgm_components == 0 then return true end
        return false
    end)
end

if use_boss_bgm then
    NotifyOnNewObject("/Script/Engine.AudioComponent", function(ctx)
        controlBossBGM(ctx)
    end)
end

ExecuteWithDelay(5000, function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(ctx)
        if manual_stop then return end

        dprint("Engine.PlayerController:ClientRestart")

        current_music_files = music_files["Default"]
        boss_bgm_components = {}

        local mapName = ctx:get():GetFullName()
        dprint("Current map name: " .. mapName)

        local stage_time_append = 3800
        if string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Lobby/Lobby.LOBBY") then
            dprint("Move to Lobby")
            stage_time_append = 180
        elseif string.find(mapName, "SBNetworkPlayerController /Game/Art/BG/WorldMap/") then
            dprint("Move to WorldMap")
        else
            dprint("Unknown map. retry")
            mapName = GetMapName()
            dprint("Retried map name: " .. mapName)
        end

        local music_files_default = GetMusicFiles(music_dirs["Default"])
        if #music_files_default > 0 then current_music_files = music_files_default end

        for k, v in pairs(worldmap_names) do
            dprint("Worldmap key and name: " .. k .. ", " .. v)
            if string.find(mapName, v) then
                local music_files_worldmap = GetMusicFiles(music_dirs[k])
                if #music_files_worldmap > 0 then current_music_files = music_files_worldmap end
                break
            end
        end

        previous_music_files = current_music_files

        -- Use safe transition instead of direct async call
        safeMusicTransition(current_music_files, stage_time_append)
    end)
end)


local function setupMod()
    audio.init()
    -- audio_boss.init()
    audio.setEndCallback(onMusicEnded)
    music_files["Default"] = GetMusicFiles(music_dirs["Default"])
    music_files["Lobby"] = GetMusicFiles(music_dirs["Lobby"])
    music_files["Boss"] = GetMusicFiles(music_dirs["Boss"])

    ExecuteWithDelay(180, function()
        if #music_files["Lobby"] > 0 then
            dprint("Starting initial music playback")
            current_music_files = music_files["Lobby"]
            playShuffle(current_music_files)
        elseif #music_files["Default"] > 0 then
            dprint("Starting initial music playback")
            current_music_files = music_files["Default"]
            playShuffle(current_music_files)
        else
            dprint("No music files found in " .. music_dirs["Default"])
        end
    end)
end

print("[SBPod] is loaded\n")
dprint("Begin to write log")

setupMod()

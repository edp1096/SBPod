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
local audio_boss = require("audio")
local ini = require("ini")
local text = require("text")

local sound = nil
local manual_stop = false
-- local music_stopping = false

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
    G03 = "/Game/Art/BG/WorldMap/Level_P/G03.G03",
    Eidos7 = "/Game/Art/BG/WorldMap/Level_P/F02.F02",
    Xion = "/Game/Art/BG/WorldMap/Level_P/E04.E04",
    Wasteland = "/Game/Art/BG/WorldMap/E03_WasteLand_P/E03_WasteLand_P.E03_WasteLand_P",
    GreatDesert = "/Game/Art/BG/WorldMap/E05_GreatDesert_P/E05_GreatDesert_P.E05_GreatDesert_P",
    Nest = "/Game/Art/BG/WorldMap/Level_P/C05.C05",
    Epilog = "/Game/Art/BG/WorldMap/Dungeon_P/Epilogue_P.Epilogue_P"
}
local boss_bgm_names = {
    Abaddon = "BGM/F02/BGM_DED_BOSS_Abaddon",
    -- Abaddon = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Abaddon",
    -- Abaddon_Finish = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Abaddon_FINISH.BGM_DED_BOSS_Abaddon_FINISH",
    -- Corrupter = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Grubshooter.BGM_DED_BOSS_Grubshooter", -- There is no Corrupter_Finish
    Corrupter = "BGM/F02/BGM_DED_BOSS_Grubshooter",
    Gigas = "BGM/F02/BGM_DED_BOSS_Gigas",
    -- Gigas = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Gigas_Cue.BGM_DED_BOSS_Gigas_Cue",
    -- Gigas_Finish = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_GIGAS_FINISH.BGM_DED_BOSS_GIGAS_FINISH",
    -- Gigas_ChallengeDone = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_GIGAS_FINISH.BGM_DED_BOSS_GIGAS_FINISH",
    -- Brute = "/Game/Sound/World/BGM/E03/BGM_WASTELAND_BOSS_BRUTE_P1.BGM_WASTELAND_BOSS_BRUTE_P1",
    -- Brute_P2 = "/Game/Sound/World/BGM/E03/BGM_WASTELAND_BOSS_BRUTE_P2.BGM_WASTELAND_BOSS_BRUTE_P2",
    Brute = "BGM/E03/BGM_WASTELAND_BOSS_BRUTE",
    -- Gigas_Wasteland = "/Game/Sound/World/BGM/E03/BGM_WASTELAND_BOSS_GIGAS_Cue.BGM_WASTELAND_BOSS_GIGAS_Cue",
    -- Gigas_Wasteland_Finish = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_GIGAS_FINISH.BGM_DED_BOSS_GIGAS_FINISH",
    Gigas_Wasteland = "BGM/E03/BGM_WASTELAND_BOSS_GIGAS",
    -- Stalker = "/Game/Sound/World/BGM/Matrix_XI/BGM_ME_BOSS_Sawshark_Cue.BGM_ME_BOSS_Sawshark_Cue",
    -- Stalker_Finish = "/Game/Sound/World/BGM/BGMEndSound/BGM_ENDSound_STALKER.BGM_ENDSound_STALKER",
    Stalker = "BGM/Matrix_XI/BGM_ME_BOSS_Sawshark",
    -- Juggernaut = "/Game/Sound/World/BGM/Matrix_XI/BGM_ME_BOSS_JUGGERNAUT_BELIAL_P1.BGM_ME_BOSS_JUGGERNAUT_BELIAL_P1",
    -- Juggernaut_Finish = "/Game/Sound/World/BGM/Matrix_XI/BGM_ME_BOSS_JUGGERNAUT_FINISH.BGM_ME_BOSS_JUGGERNAUT_FINISH",
    Juggernaut = "BGM/Matrix_XI/BGM_ME_BOSS_JUGGERNAUT",
    -- Tachy = "/Game/Sound/World/BGM/Matrix_XI/BGM_ME_BOSS_Tachy_P1_Cue.BGM_ME_BOSS_Tachy_P1_Cue",
    -- Tachy_Finish = "/Game/Sound/World/BGM/Matrix_XI/BGM_BOSS_TACHY_FINISH.BGM_BOSS_TACHY_FINISH",
    Tachy = "BGM/Matrix_XI/BGM_ME_BOSS_Tachy",
    -- Stalker_GreatDesert =
    -- "/Game/Sound/World/BGM/Matrix_XI/BGM_ME_BOSS_STALKER_P1_LOOP_170.BGM_ME_BOSS_STALKER_P1_LOOP_170",
    -- Stalker_GreatDesert_Finish = "/Game/Sound/World/BGM/E05/BGM_E05_BOSS_Sawshark_P2_Cue", -- Actually Phase 2
    Stalker_GreatDesert = "BGM/Matrix_XI/BGM_ME_BOSS_STALKER",
    -- Abaddon_GreatDesert = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Abaddon.BGM_DED_BOSS_Abaddon", -- Same as Abaddon
    -- Behemoth = "/Game/Sound/World/BGM/E05/BGM_E03_BOSS_Behemoth.BGM_E03_BOSS_Behemoth",
    -- Behemoth_Finish = "/Game/Sound/World/BGM/BGMEndSound/BGM_ENDSound_BEHEMOTH.BGM_ENDSound_BEHEMOTH",
    Behemoth = "BGM/E05/BGM_E03_BOSS_Behemoth",
    -- Corrupter_Eidos9 = "/Game/Sound/World/BGM/F02/BGM_DED_BOSS_Grubshooter.BGM_DED_BOSS_Grubshooter", -- Same as Corrupter
    -- Belial = "/Game/Sound/World/BGM/B07/BossBattle/BGM_SE_BOSS_Belial_Cue.BGM_SE_BOSS_Belial_Cue", -- There's no BGMEndSound for Belial
    -- Karakuri = "/Game/Sound/World/BGM/B07/BossBattle/BGM_SE_BOSS_Karakuri_Cue.BGM_SE_BOSS_Karakuri_Cue",
    -- Karakuri_Finish = "/Game/Sound/World/BGM/BGMEndSound/BGM_ENDSound_Karakuri.BGM_ENDSound_Karakuri",
    Karakuri = "BGM/B07/BossBattle/BGM_SE_BOSS_Karakuri",
    -- Democrawler = "/Game/Sound/World/BGM/B07/BossBattle/BGM_SE_BOSS_Crawler_P1_Cue.BGM_SE_BOSS_Crawler_P1_Cue",
    -- Democrawler_Finish = "/Game/Sound/World/BGM/BGMEndSound/EVE_SE_BGMEndSound_2.EVE_SE_BGMEndSound_2", -- Actually DemoGorgon
    Democrawler = "BGM/B07/BossBattle/BGM_SE_BOSS_Crawler",
    -- RavenBeast = "/Game/Sound/World/BGM/E04/BGM_XION_BOSS_RavenBeast_P1_Cue.BGM_XION_BOSS_RavenBeast_P1_Cue",
    -- RavenBeast_Finish = "/Game/Sound/World/BGM/E04/BGM_XION_BOSS_RAVENBEAST_FINISH.BGM_XION_BOSS_RAVENBEAST_FINISH",
    RavenBeast = "BGM/E04/BGM_XION_BOSS_RavenBeast",
    -- Raven = "/Game/Sound/World/BGM/E03/BGM_NEST_BOSS_RAVEN_P1_Cue.BGM_NEST_BOSS_RAVEN_P1_Cue",
    -- Raven_Finish = "/Game/Sound/World/BGM/E03/BGM_NEST_BOSS_RAVEN_FINISH.BGM_NEST_BOSS_RAVEN_FINISH",
    Raven = "BGM/E03/BGM_NEST_BOSS_RAVEN",
    -- Providence = "/Game/Sound/World/BGM/Nest/BGM_NEST_BOSS_LILY_P1_CUE.BGM_NEST_BOSS_LILY_P1_CUE",
    -- Providence_Lily = "/Game/Sound/World/BGM/Nest/BGM_NEST_LILY_P3_SAVE_BATTLE_143.BGM_NEST_LILY_P3_SAVE_BATTLE_143",
    -- Providence_Li_ly = "/Game/Sound/World/BGM/Nest/BGM_NEST_BOSS_LILY_P3_DIE.BGM_NEST_BOSS_LILY_P3_DIE",
    Providence = "BGM/Nest/BGM_NEST_BOSS_LILY",
    -- Elder = "/Game/Sound/World/BGM/Nest/BGM_NEST_BOSS_ELDER_P2_CUE.BGM_NEST_BOSS_ELDER_P2_CUE",
    -- Elder_01_Finish = "/Game/Sound/World/BGM/Nest/BGM_NEST_BOSS_ELDER_ENDING_01.BGM_NEST_BOSS_ELDER_ENDING_01",
    -- Elder_02_Finish = "/Game/Sound/World/BGM/Nest/BGM_NEST_BOSS_ELDER_ENDING_02.BGM_NEST_BOSS_ELDER_ENDING_02",
    Elder = "BGM/Nest/BGM_NEST_BOSS_ELDER",
    -- Mann = "/Game/Sound/World/BGM/Nikke/BGM_D2_BOSS_MANN_LOOP.BGM_D2_BOSS_MANN_LOOP",
    -- Scarlet = "/Game/Sound/World/BGM/Nikke/BGM_BOSS_SCARLET_P1_Cue.BGM_BOSS_SCARLET_P1_Cue",
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
    -- if not sound or not music_stopping then return false end
    -- music_stopping = true

    local fadeout_volume = current_volume
    local volume_down_step = current_volume / 50

    -- Fadeout effect
    while fadeout_volume > 0.0 do
        fadeout_volume = fadeout_volume - volume_down_step
        if fadeout_volume < 0.0 then fadeout_volume = 0.0 end
        sound:setVolume(fadeout_volume)
        audio.msleep(25)
    end

    sound:stop()
    -- sound = nil

    -- music_stopping = false

    -- dprint("Music is stopped." .. current_music_files[current_music_index])
    dprint("Music is stopped.")
end

local function playShuffle(music_files)
    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        if #music_files == 0 then return end
        current_music_index = math.random(#music_files)
        if #music_files == 1 then break end
    end
    previous_music_index = current_music_index

    dprint("Music index: " .. current_music_index)

    local music_file = music_files[current_music_index]
    music_file = music_file:gsub("/", "\\")
    playMusic(music_file)
end

local function playShuffleBoss(music_files)
    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        if #music_files == 0 then return end
        current_music_index = math.random(#music_files)
        if #music_files == 1 then break end
    end
    previous_music_index = current_music_index

    dprint("Music index: " .. current_music_index)

    local music_file = music_files[current_music_index]
    music_file = music_file:gsub("/", "\\")
    playMusic(music_file)
end

local function togglePlay()
    if sound and sound:isPlaying() then
        dprint("Stop music")
        manual_stop = true
        -- while music_stopping do audio.msleep(100) end
        ExecuteAsync(function() stopMusic() end)
    else
        dprint("Play music")
        manual_stop = false
        ExecuteAsync(function() playShuffle(current_music_files) end)
    end
end

local function onMusicEnded()
    dprint("Music ended callback triggered")

    if not manual_stop and #current_music_files > 0 then
        ExecuteAsync(function()
            audio.msleep(500)
            playShuffle(current_music_files)
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

            if audio_component["wave_name"] ~= "Unknown SoundWave" then
                -- Single SoundWave
                for k, boss_bgm_name in pairs(boss_bgm_names) do
                    if string.find(audio_component["wave_name"], boss_bgm_name) then
                        audio_component["boss_name_key"] = text:Split(k, "_")[1]
                        break
                    end
                end
            else
                -- Multiple SoundWaves or VendingMachine or SoundNodeSwitch or Mixer or others
                for k, boss_bgm_name in pairs(boss_bgm_names) do
                    if string.find(audio_component["cue_name"], boss_bgm_name) then
                        audio_component["boss_name_key"] = text:Split(k, "_")[1]
                        break
                    end
                end
            end

            if audio_component["boss_name_key"] then
                audio_component["is_playing"] = ctx:IsPlaying()
                audio_component["boss_name"] = string.gsub(audio_component["boss_name_key"], "_", " ")

                dprint("SoundWave: " .. audio_component["wave_name"])
                dprint("Wav/Cue: " .. audio_component["cue_name"])
                dprint("- AudioComponent: " .. audio_component["component_name"])
                dprint("- Boss name: " .. audio_component["boss_name"])
                dprint("- Boss name key: " .. audio_component["boss_name_key"])

                dprint("is_boss_bgm_triggered: " .. tostring(is_boss_bgm_triggered))

                table.insert(boss_bgm_components, audio_component)

                if not is_boss_bgm_triggered then
                    local fname = text:TrimSpace(music_files_boss[audio_component["boss_name"]])
                    dprint("Current music fname: " .. tostring(fname))
                    if fname ~= "" then
                        current_music_files = { music_dirs["Boss"] .. "/" .. fname }

                        dprint("Current music files: " .. #current_music_files)
                        for i = 1, #current_music_files do
                            dprint("#" .. i .. ": " .. current_music_files[i])
                        end
                    elseif #music_files["Boss"] > 0 then
                        dprint("Boss music: random")
                        current_music_files = music_files["Boss"]
                    else
                        dprint("No boss music")
                        return true
                    end

                    is_boss_bgm_triggered = true

                    ExecuteAsync(function()
                        manual_stop = true
                        -- while music_stopping do audio.msleep(100) end
                        if sound then stopMusic() end
                        playShuffleBoss(current_music_files)
                        manual_stop = false
                    end)

                    return false
                end
            end
        end

        if is_boss_bgm_triggered and not ctx:IsPlaying() then
            dprint("isActive:" .. tostring(ctx:IsActive()) .. ", is_playing:" .. tostring(ctx:IsPlaying()))

            local component_name = ctx:GetFullName()
            dprint("component_name: " .. component_name)

            for i = #boss_bgm_components, 1, -1 do
                if boss_bgm_components[i]["component_name"] == component_name then
                    dprint("Removing stopped component: " .. i .. ": " .. boss_bgm_components[i]["component_name"])
                    table.remove(boss_bgm_components, i)
                    break
                end
            end

            for i = #boss_bgm_components, 1, -1 do
                if not boss_bgm_components[i]["context"]:IsPlaying() then
                    dprint("Removing dead component: " .. i .. ": " .. boss_bgm_components[i]["component_name"])
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

            ExecuteAsync(function()
                manual_stop = true
                -- while music_stopping do audio.msleep(100) end
                if sound then stopMusic() end
                playShuffle(current_music_files)
                manual_stop = false
            end)
        end

        if #boss_bgm_components == 0 then return true end
        -- return true
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

        -- local mapName = GetMapName()
        local mapName = ctx:get():GetFullName()
        dprint("Current map name: " .. mapName)

        local stage_time_append = 3800
        if string.find(mapName, "CH_P_EVE_01_Blueprint_C /Game/Lobby/Lobby.LOBBY") then
            dprint("Move to Lobby")
            stage_time_append = 180
        elseif string.find(mapName, "SBNetworkPlayerController /Game/Art/BG/WorldMap/") then
            dprint("Move to WorldMap")

            local music_files_default = GetMusicFiles(music_dirs["Default"])
            if #music_files_default > 0 then current_music_files = music_files_default end

            for k, v in pairs(worldmap_names) do
                if string.find(mapName, v) then
                    local music_files_worldmap = GetMusicFiles(music_dirs[k])
                    if #music_files_worldmap > 0 then current_music_files = music_files_worldmap end
                    break
                end
            end
        else
            dprint("Unknown map")
        end

        previous_music_files = current_music_files

        ExecuteAsync(function()
            manual_stop = true
            audio.msleep(stage_time_append)
            -- while music_stopping do audio.msleep(100) end
            if sound then stopMusic() end
            playShuffle(current_music_files)
            manual_stop = false
        end)
    end)
end)


local function setupMod()
    audio.init()
    audio_boss.init()
    audio.setEndCallback(onMusicEnded)
    music_files["Default"] = GetMusicFiles(music_dirs["Default"])
    music_files["Boss"] = GetMusicFiles(music_dirs["Boss"])

    ExecuteWithDelay(180, function()
        if #music_files["Default"] > 0 then
            playShuffle(music_files["Default"])
        else
            dprint("No music files found in " .. music_dirs["Default"])
        end
    end)
end

print("[SBPod] is loaded\n")
dprint("Begin to write log")

setupMod()

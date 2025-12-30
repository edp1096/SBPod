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
local ini = require("ini")
local text = require("text")

local sound = nil
local current_sound_uid = 0  -- Unique ID for current music session
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

local play_shuffle = false

local music_dirs = {}
local music_files = {}
local music_files_boss = {}
local previous_music_files = {}
local current_music_files = {}

local previous_music_index = 0
local current_music_index = 0

local client_restart_triggered = false
local pending_map_transition = false
local pending_transition_files = nil
local pending_transition_delay = 0

local current_map = ""  -- Current map name
local current_map_is_lobby = true  -- Track if current map is Lobby (game starts in Lobby)

local use_boss_bgm = true
local current_boss_name = ""
local is_boss_bgm_triggered = false
local boss_bgm_components = {}
local pending_audio_components = {}  -- Queue for audio components to check
local pending_boss_transition = false  -- Boss BGM transition pending
local pending_boss_files = nil

local boss_notification_registered = false
local boss_bgm_notification_active = false


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
    Brute = "BGM/G03/BGM_PROLOGUE_BOSS_BRUTE_P1",
    BruteFinish = "BGM/G03/BGM_G03_EVENT_BossFinish",
    Abaddon = "BGM/F02/BGM_DED_BOSS_Abaddon.BGM_DED_BOSS_Abaddon",
    AbaddonFinish = "BGM/F02/BGM_DED_ZONE_01_DEFAULT.BGM_DED_ZONE_01_DEFAULT",
    -- Corrupter = "BGM/F02/BGM_DED_BOSS_Grubshooter.BGM_DED_BOSS_Grubshooter",
    Gigas = "BGM/F02/BGM_DED_BOSS_Gigas_Cue.BGM_DED_BOSS_Gigas_Cue",
    GigasFinish = "BGM/F02/BGM_DED_BOSS_GIGAS_FINISH.BGM_DED_BOSS_GIGAS_FINISH",
    Quiel = "BGM/E03/BGM_WASTELAND_BOSS_QUIEL",
    QuielFinish = "BGM/E03/BGM_WASTELAND_ZONE01C_Default_Cue",
    MaelstromAltess = "BGM/LAB1/BGM_LAB_BOSS_Melstrom_Cue.BGM_LAB_BOSS_Melstrom_Cue",
    MaelstromAltessFinish = "BGM/LAB1/BGM_LAB1_ZONE_02_DEFAULT_110.BGM_LAB1_ZONE_02_DEFAULT_110",
    BruteWasteland = "BGM/E03/BGM_WASTELAND_BOSS_BRUTE",
    BruteWastelandFinish = "BGM/E03/BGM_WASTELAND_AMB",
    GigasWasteland = "BGM/E03/BGM_WASTELAND_BOSS_GIGAS_Cue.BGM_WASTELAND_BOSS_GIGAS_Cue",
    GigasWastelandFinish = "BGM/E03/BGM_WASTELAND_AMB",
    Stalker = "BGM/Matrix_XI/BGM_ME_BOSS_Sawshark",
    StalkerFinish = "BGM/Matrix_XI/BGM_ME_Zone_03_Default.BGM_ME_Zone_03_Default",
    Juggernaut = "BGM/Matrix_XI/BGM_ME_BOSS_JUGGERNAUT",
    JuggernautFinish = "BGM/Matrix_XI/BGM_ME_Zone_04_Default.BGM_ME_Zone_04_Default",
    Tachy = "BGM/Matrix_XI/BGM_ME_BOSS_Tachy",
    TachyFinish = "BGM/Matrix_XI/BGM_EVENT_Mute_Cue.BGM_EVENT_Mute_Cue",
    -- TachyFinish = "BGM/Matrix_XI/BGM_BOSS_TACHY_FINISH.BGM_BOSS_TACHY_FINISH",
    StalkerGreatDesert = "BGM/Matrix_XI/BGM_ME_BOSS_STALKER_P1_LOOP_170.BGM_ME_BOSS_STALKER_P1_LOOP_170",
    StalkerGreatDesertFinish = "BGM/E05/BGM_DESERT_FIELD_01",
    Shael = "BGM/E05/BGM_DESERT_BOSS_SHAEL",
    ShaelFinish = "BGM/E05/BGM_DESERT_FIELD_01",
    MaelstromAbyss = "BGM/LAB1/BGM_LAB_BOSS_Maelstrom2_",
    MaelstromAbyssFinish = "BGM/LAB1/BGM_LAB2_ZONE_02_DEFAULT_110.BGM_LAB1_ZONE_02_DEFAULT_110",
    Behemoth = "BGM/E05/BGM_E03_BOSS_Behemoth",
    BehemothFinish = "BGM/E05/BGM_DESERT_FIELD_01",
    Belial = "BGM/B07/BossBattle/BGM_SE_BOSS_Belial_Cue",
    BelialFinish = "Ambient/Amb_Default_wind_02.Amb_Default_wind_02",
    Karakuri = "BGM/B07/BossBattle/BGM_SE_BOSS_Karakuri",
    KarakuriFinish = "BGM/B07/BGM_SE_ZONE_08_Default.BGM_SE_ZONE_08_Default",
    Democrawler = "BGM/B07/BossBattle/BGM_SE_BOSS_Crawler",
    DemocrawlerFinish = "BGM/B07/BossBattle/BGM_SE_EVENT_Crawler_Finish.BGM_SE_EVENT_Crawler_Finish",
    -- Demogorgon = "BGM/B07/BossBattle/BGM_SE_EVENT_Demogorgon_Intro.BGM_SE_EVENT_Demogorgon_Intro",
    -- -- Demogorgon = "BGM/B07/BossBattle/BGM_SE_BOSS_Demogorgon_Cue.BGM_SE_BOSS_Demogorgon_Cue",
    -- DemogorgonFinish = "BGM/B07/BossBattle/BGM_SE_EVENT_Demogorgon_Finish.BGM_SE_EVENT_Demogorgon_Finish",
    -- -- DemogorgonFinish = "BGM/B07/BGM_SE_EVENT_EXOLANDING_PIANO.BGM_SE_EVENT_EXOLANDING_PIANO",
    RavenBeast = "BGM/E04/BGM_XION_BOSS_RavenBeast_P1_Cue.BGM_XION_BOSS_RavenBeast_P1_Cue",
    RavenBeastFinish = "BGM/E04/BGM_XION_Cinematic_RAVEN_END_Cue.BGM_XION_Cinematic_RAVEN_END_Cue",
    Raven = "BGM/E03/BGM_NEST_BOSS_RAVEN_P1",
    RavenFinish = "BGM/E03/BGM_NEST_Enterance.BGM_NEST_Enterance",
    MotherSphereLilySave = "BGM/Nest/BGM_NEST_BOSS_LILY_END_MS_SAVE",
    MotherSphereLilyDead = "BGM/Nest/BGM_NEST_BOSS_LILY_END_A",
    -- MotherSphereLilyDead = "BGM/Nest/BGM_NEST_BOSS_LILY_END_CUE",
    -- MotherSphereLilyDead = "Ambient/E03/AMB_E03_Default_Cue.AMB_E03_Default_Cue",
    Providence = "BGM/Nest/BGM_NEST_BOSS_LILY_P",
    Elder = "BGM/Nest/BGM_NEST_BOSS_ELDER_P",
    ElderEnd = "BGM/Nest/BGM_NEST_BOSS_ELDER_END",
    Mann = "BGM/Nikke/BGM_D2_BOSS_MANN",
    Scarlet = "BGM/Nikke/BGM_BOSS_SCARLET_P1",
    ScarletFinish = "BGM/Nikke/CAMP/BGM_CAMP_NIKKE_08_ON"
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

play_shuffle = cfg.Shuffle == "true"
use_boss_bgm = cfg.UseBossBGM == "true"

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

    -- Generate new UID for this music session
    current_sound_uid = current_sound_uid + 1
    local this_uid = current_sound_uid
    dprint("Starting music session UID: " .. this_uid)

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
    if not sound or music_state.is_stopping then return false end

    music_state.is_stopping = true

    local fadeout_volume = current_volume
    local volume_down_step = current_volume / 50

    dprint("Stopping music")

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

local function SelectAndPlayMusicFile(flist)
    -- Prevent multiple simultaneous SelectAndPlayMusicFile calls, but allow if not transitioning
    if music_state.is_playing_new or music_state.is_stopping then
        dprint("Cannot start SelectAndPlayMusicFile - music system busy (playing:" ..
            tostring(music_state.is_playing_new) .. ", stopping:" .. tostring(music_state.is_stopping) .. ")")
        return false
    end

    music_state.is_playing_new = true

    dprint("Shuffling music")

    while previous_music_index == current_music_index do
        if #flist == 0 then
            music_state.is_playing_new = false
            dprint("No music files to shuffle")
            return false
        end

        if play_shuffle then
            current_music_index = math.random(#flist)
        else
            current_music_index = current_music_index % #flist + 1
        end

        if #flist == 1 then break end
    end
    previous_music_index = current_music_index

    dprint("Shuffle mode: " .. tostring(play_shuffle) .. "/" .. tostring(cfg.Shuffle))
    dprint("Music count: " .. tostring(#flist))
    dprint("Music index: " .. current_music_index)

    local music_file = flist[current_music_index]
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

    manual_stop = true

    if delay and delay > 0 then
        dprint("Waiting " .. delay .. "ms before transition")
        audio.msleep(delay)
    end

    -- Stop current music if playing
    if sound and sound:isPlaying() then
        dprint("Stopping current music")
        stopMusic()
        audio.msleep(100)
    end

    -- Reset states before playing new music
    music_state.is_stopping = false
    music_state.is_playing_new = false

    -- Play new music if we have files
    if new_music_files and #new_music_files > 0 then
        dprint("Playing new music from transition")
        current_music_files = new_music_files

        -- Direct music playing without state checks in transition
        dprint("previous, current indexs: " .. previous_music_index .. ", " .. current_music_index)
        while previous_music_index == current_music_index do
            if #new_music_files == 0 then break end

            if play_shuffle then
                current_music_index = math.random(#new_music_files)
            else
                current_music_index = current_music_index % #new_music_files + 1
            end
            dprint("Shuffle mode: " .. tostring(play_shuffle) .. "/" .. tostring(cfg.Shuffle))
            dprint("Music count: " .. tostring(#new_music_files))
            dprint("Current music index: " .. current_music_index)

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
    return true
end

local function togglePlay()
    if sound and sound:isPlaying() then
        dprint("Stop music")
        manual_stop = true
        stopMusic()
    else
        dprint("Play music")
        manual_stop = false
        SelectAndPlayMusicFile(current_music_files)
    end
end

local function controlBossBGM(ctx)
    -- Just add to queue for processing, don't create LoopAsync per component
    if not ctx then
        return
    end

    -- Safely check if valid
    local is_valid_success, is_valid = pcall(function() return ctx:IsValid() end)
    if not is_valid_success or not is_valid then
        return
    end

    -- Don't process Boss BGM in Lobby
    if current_map_is_lobby then
        return
    end

    -- Quick filter: only process AudioComponent objects - SAFELY
    local cname_success, cname = pcall(function() return ctx:GetFullName() end)
    if not cname_success or not cname or type(cname) ~= "string" then
        return  -- Failed to get name or not a string
    end

    if not string.find(cname, ":AudioComponent_") then
        return
    end

    -- Prevent duplicates - check if already in queue
    for i = 1, #pending_audio_components do
        if pending_audio_components[i] == ctx then
            return  -- Already in queue
        end
    end

    -- Limit queue size to prevent memory issues
    if #pending_audio_components > 100 then
        dprint("WARNING: AudioComponent queue full, skipping")
        return
    end

    -- Add to pending queue for global loop to process
    table.insert(pending_audio_components, ctx)
    -- dprint("Added AudioComponent to queue. Queue size: " .. #pending_audio_components)
end

-- Process boss BGM audio component (called from MASTER LOOP)
local function processBossAudioComponent(ctx)
    -- Wrap ENTIRE function in pcall to prevent any crashes
    local process_ok, process_err = pcall(function()
        -- Quick validation
        if not ctx then return end
        if not ctx:IsValid() then return end
        if not ctx.Sound then return end
        if not ctx:IsPlaying() then return end

        -- Process this component
        local audio_component = {}
        audio_component["context"] = ctx
        audio_component["component_name"] = ctx:GetFullName()

        if not audio_component["component_name"] then return end
        dprint("Component name: " .. tostring(audio_component["component_name"]))

        -- Get cue name - simplified
        audio_component["cue_name"] = "Unknown Cue"
        if ctx.Sound then
            local ok, fullname = pcall(function()
                return ctx.Sound:GetFullName()
            end)
            if ok and fullname and type(fullname) == "string" then
                audio_component["cue_name"] = fullname
            end
        end
        dprint("Cue name: " .. tostring(audio_component["cue_name"]))

        -- Get wave name - simplified
        audio_component["wave_name"] = "Unknown SoundWave"
        if ctx.Sound and ctx.Sound.FirstNode and ctx.Sound.FirstNode.SoundWave then
            local ok, wave_name = pcall(function()
                return ctx.Sound.FirstNode.SoundWave:GetFullName()
            end)
            if ok and wave_name and type(wave_name) == "string" then
                audio_component["wave_name"] = wave_name
            end
        end
        dprint("Wave name: " .. tostring(audio_component["wave_name"]))

        -- Check if this is system music (exclude from boss BGM detection)
        local is_system_music = string.find(audio_component["cue_name"], "BGM_SYS_EPILOGUE_CUE")
        local is_intro_music = string.find(audio_component["cue_name"], "BGM/Nest/BGM_") and
            string.find(audio_component["wave_name"], "_INTRO")
        if is_system_music or is_intro_music then return end

        dprint("current_boss_name: " .. tostring(current_boss_name))

        -- Single SoundWave
        local sound_name_key = "wave_name"
        if audio_component["wave_name"] == "Unknown SoundWave" then
            sound_name_key = "cue_name"
        end

        -- Match boss BGM name
        for k, boss_bgm_name in pairs(boss_bgm_names) do
            local sound_name_value = audio_component[sound_name_key]
            if sound_name_value and type(sound_name_value) == "string" and string.find(sound_name_value, boss_bgm_name) then
                -- Split boss name key
                local parts = {}
                for part in string.gmatch(k, "[^_]+") do
                    table.insert(parts, part)
                end
                if parts[1] then
                    local boss_prefix = parts[1]
                    if current_boss_name == "" or boss_prefix == current_boss_name or
                       (current_boss_name and boss_prefix == current_boss_name .. "Finish") then
                        audio_component["boss_name_key"] = k
                        break
                    end
                end
            end
        end

        if not audio_component["boss_name_key"] then
            dprint("boss_name_key: nil")
            return
        end

        if audio_component["boss_name_key"] == "" then
            dprint("boss_name_key is empty")
            return
        end

        dprint("boss_name_key: " .. tostring(audio_component["boss_name_key"]))

        audio_component["boss_name"] = string.gsub(audio_component["boss_name_key"], "_", " ")

        dprint("SoundWave: " .. tostring(audio_component["wave_name"]))
        dprint("Wav/Cue: " .. tostring(audio_component["cue_name"]))
        dprint("- Boss name: " .. tostring(audio_component["boss_name"]))
        dprint("is_boss_bgm_triggered: " .. tostring(is_boss_bgm_triggered))

        if not is_boss_bgm_triggered then
            -- Play boss music
            if string.find(audio_component["boss_name"], "Finish") then
                dprint("Boss music: finish")
                return
            end

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

            local fname = text:TrimSpace(music_files_boss[audio_component["boss_name"]])
            dprint("Current music fname: " .. tostring(fname))

            local boss_files = {}
            if fname ~= "" then
                boss_files = { music_dirs["Boss"] .. "/" .. fname }
                dprint("Current music files: " .. #boss_files)
            elseif #music_files["Boss"] > 0 then
                dprint("Boss music: random")
                boss_files = music_files["Boss"]
            else
                dprint("No boss music")
                return
            end

            is_boss_bgm_triggered = true
            current_music_files = boss_files
            current_boss_name = audio_component["boss_name"]
            dprint("Current boss name: " .. current_boss_name)

            -- Set pending transition
            pending_boss_transition = true
            pending_boss_files = boss_files
            dprint("Boss BGM transition pending")
        else
            if not current_boss_name or current_boss_name == "" then return end
            dprint("Playing boss music: " .. current_boss_name)

            -- Stop music by stage xxxFinish
            if audio_component["boss_name"] == current_boss_name .. "Finish" then
                dprint("Stop boss music: " .. current_boss_name)

                is_boss_bgm_triggered = false
                current_music_files = previous_music_files
                boss_bgm_components = {}
                current_boss_name = ""

                -- Set pending transition
                pending_boss_transition = true
                pending_boss_files = current_music_files
                dprint("Boss BGM finish transition pending")
            end
        end
    end)  -- End of pcall

    if not process_ok then
        dprint("ERROR processBossAudioComponent: " .. tostring(process_err))
    end
end

-- Boss BGM: Dynamic registration function with auto-unregister
local function registerBossNotification()
    if boss_notification_registered then
        dprint("Boss notification already registered, skipping")
        return
    end

    NotifyOnNewObject("/Script/Engine.AudioComponent", function(ctx)
        -- Check if should unregister (비활성화 또는 Lobby면 해제)
        if not boss_bgm_notification_active or current_map_is_lobby then
            boss_notification_registered = false
            dprint("Boss BGM NotifyOnNewObject UNREGISTERED (inactive or lobby)")
            return true  -- ← Unregister this callback
        end

        -- Process (wrapped in pcall to prevent crashes)
        pcall(function()
            -- Fast validation
            if not ctx or type(ctx) ~= "userdata" then return end
            if manual_stop or client_restart_triggered then return end

            -- Minimal validation - if any fails, just return silently
            local is_valid = pcall(function() return ctx:IsValid() end)
            if not is_valid then return end

            local ok, name = pcall(function() return ctx:GetFullName() end)
            if not ok or not name or type(name) ~= "string" then return end
            if not string.find(name, ":AudioComponent_") then return end

            -- Check queue limit
            if #pending_audio_components >= 100 then return end

            -- Check duplicate
            for i = 1, #pending_audio_components do
                if pending_audio_components[i] == ctx then return end
            end

            -- Add to queue
            table.insert(pending_audio_components, ctx)
        end)

        return false  -- Keep listening
    end)

    boss_notification_registered = true
    dprint("Boss BGM NotifyOnNewObject REGISTERED")
end

-- MASTER LOOP: All async operations in one place to prevent conflicts
local last_music_playing = false
local last_checked_uid = 0
local loop_counter = 0
local map_transition_cooldown = 0  -- Cooldown after map transition

LoopAsync(200, function()
    local loop_success, loop_error = pcall(function()
        loop_counter = loop_counter + 1

        -- Debug: Log every 10 cycles (2 seconds)
        if loop_counter % 10 == 0 then
            dprint("MASTER LOOP alive - cycle " .. loop_counter)
        end

        -- Decrease cooldown timer
        if map_transition_cooldown > 0 then
            map_transition_cooldown = map_transition_cooldown - 1
        end

        -- Task 1: Map transition (highest priority)
    if pending_map_transition and not music_state.is_transitioning then
        pending_map_transition = false
        pending_boss_transition = false  -- Cancel boss transition if map transition occurs
        map_transition_cooldown = 20  -- 10 second cooldown (50 cycles * 200ms)
        boss_bgm_notification_active = false  -- Deactivate Boss BGM notifications during transition
        dprint("Boss BGM notifications DEACTIVATED (map transition)")

        local files = pending_transition_files
        local delay = pending_transition_delay
        pending_transition_files = nil
        pending_transition_delay = 0

        -- Stop current music with fadeout
        if sound and sound:isPlaying() then
            stopMusic()
        end
        audio.msleep(50)

        local success, err = pcall(function()
            safeMusicTransition(files, delay)
        end)
        if not success then
            dprint("ERROR in pending transition: " .. tostring(err))
        end
        client_restart_triggered = false
        return false  -- Skip other tasks this cycle
    end

    -- Task 1.5: Boss BGM transition (if pending and no other transition)
    if pending_boss_transition and not music_state.is_transitioning and not pending_map_transition then
        dprint("Task 1.5: Starting Boss BGM transition")
        pending_boss_transition = false
        local files = pending_boss_files
        pending_boss_files = nil

        if files and #files > 0 then
            dprint("Task 1.5: Transitioning to " .. #files .. " files")
            local success, err = pcall(function()
                safeMusicTransition(files, 0)
            end)
            if not success then
                dprint("ERROR Task 1.5 boss transition failed: " .. tostring(err))
            else
                dprint("Task 1.5: Boss transition completed successfully")
            end
        else
            dprint("Task 1.5: No files to transition")
        end
        return false  -- Skip other tasks this cycle
    end

    -- Task 1.6: Boss BGM notification registration (after cooldown expires)
    if use_boss_bgm and not boss_notification_registered and map_transition_cooldown == 0 and not current_map_is_lobby then
        boss_bgm_notification_active = true
        registerBossNotification()  -- Register with auto-unregister capability
        dprint("Boss BGM notifications ACTIVATED (cooldown expired, not in Lobby)")
    end

    -- Task 2: Music end detection (every 2-3 cycles - ~500ms)
    if loop_counter % 3 == 0 then
        if not music_state.is_transitioning and not music_state.is_stopping and not music_state.is_playing_new and sound then
            local current_uid = current_sound_uid
            if last_checked_uid ~= 0 and last_checked_uid ~= current_uid then
                last_music_playing = false
                last_checked_uid = current_uid
            else
                last_checked_uid = current_uid
                local is_playing = false

                -- Defensive check: ensure sound is valid and has isPlaying method
                if sound and type(sound) == "userdata" then
                    local success, result = pcall(function() return sound:isPlaying() end)
                    if success and type(result) == "boolean" then
                        is_playing = result
                    else
                        dprint("ERROR Task 2: isPlaying() failed - " .. tostring(result))
                        sound = nil  -- Invalid sound object, clear it
                        return false
                    end
                elseif sound then
                    dprint("ERROR Task 2: sound is not userdata, type=" .. tostring(type(sound)))
                    sound = nil
                    return false
                end

                if last_music_playing and not is_playing and current_sound_uid == current_uid then
                    if not manual_stop and #current_music_files > 0 and not music_state.is_transitioning then
                        -- Safe function calls with validation
                        if audio and type(audio.msleep) == "function" then
                            local sleep_success, sleep_err = pcall(function() audio.msleep(300) end)
                            if not sleep_success then
                                dprint("ERROR Task 2: audio.msleep failed - " .. tostring(sleep_err))
                            end
                        else
                            dprint("ERROR Task 2: audio.msleep is not a function")
                        end

                        if current_sound_uid == current_uid and not manual_stop and not music_state.is_transitioning then
                            if type(SelectAndPlayMusicFile) == "function" then
                                local play_success, play_err = pcall(function()
                                    SelectAndPlayMusicFile(current_music_files)
                                end)
                                if not play_success then
                                    dprint("ERROR Task 2: SelectAndPlayMusicFile failed - " .. tostring(play_err))
                                end
                            else
                                dprint("ERROR Task 2: SelectAndPlayMusicFile is not a function, type=" .. tostring(type(SelectAndPlayMusicFile)))
                            end
                        end
                    end
                end
                last_music_playing = is_playing
            end
        else
            last_music_playing = false
        end
    end

    -- Task 3: Boss BGM component processing (every 5 cycles - ~1000ms, up to 5 components per cycle)
    -- DISABLED in Lobby and during cooldown period
    if use_boss_bgm and not current_map_is_lobby and loop_counter % 5 == 0 and map_transition_cooldown == 0 then
        local task3_success, task3_err = pcall(function()
            -- Clean invalid components from queue
            local valid_components = {}
            for i = 1, #pending_audio_components do
                local comp = pending_audio_components[i]
                if comp and type(comp) == "userdata" then
                    local is_valid_success, is_valid_result = pcall(function() return comp:IsValid() end)
                    if is_valid_success and is_valid_result then
                        table.insert(valid_components, comp)
                    end
                end
            end
            pending_audio_components = valid_components

            -- Process UP TO 5 components per cycle for faster Boss detection
            local process_count = math.min(5, #pending_audio_components)
            for i = 1, process_count do
                if #pending_audio_components > 0 then
                    local ctx = table.remove(pending_audio_components, 1)
                    if ctx and type(ctx) == "userdata" then
                        local is_ctx_valid_success, is_ctx_valid = pcall(function() return ctx:IsValid() end)
                        if is_ctx_valid_success and is_ctx_valid then
                            local process_success, process_err = pcall(function()
                                processBossAudioComponent(ctx)
                            end)
                            if not process_success then
                                dprint("ERROR processing boss BGM component: " .. tostring(process_err))
                            end
                        end
                    end
                end
            end
        end)
        if not task3_success then
            dprint("ERROR Task 3 failed: " .. tostring(task3_err))
        end
    end
    end)  -- End of MASTER LOOP pcall

    if not loop_success then
        dprint("CRITICAL ERROR: MASTER LOOP crashed - " .. tostring(loop_error))
        print("[SBPod] CRITICAL ERROR: MASTER LOOP crashed - " .. tostring(loop_error))
    end

    return false
end)

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
    ExecuteAsync(function()
        togglePlay()
    end)
end)

-- Map transitions now handled by MASTER LOOP above

-- ExecuteWithDelay(250, function()
ExecuteWithDelay(8250, function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(ctx)
        local hook_success, hook_error = pcall(function()
            if manual_stop then return end

            dprint("Engine.PlayerController:ClientRestart")
        client_restart_triggered = true

        -- Clear boss BGM state and queue
        boss_bgm_notification_active = false  -- Deactivate on every map transition
        pending_audio_components = {}
        boss_bgm_components = {}
        current_boss_name = ""
        is_boss_bgm_triggered = false
        dprint("Cleared boss BGM queue and state, notification deactivated")

        current_music_files = music_files["Default"]

        current_map = ctx:get():GetFullName()
        -- current_map = GetMapName()
        dprint("Current map name: " .. current_map)

        -- local stage_time_append = 1800
        local stage_time_append = 180
        if string.find(current_map, "CH_P_EVE_01_Blueprint_C /Game/Lobby/Lobby.LOBBY") then
            dprint("Move to Lobby")
            current_map_is_lobby = true  -- Disable Boss BGM in Lobby
            boss_bgm_notification_active = false  -- Ensure deactivated in Lobby
            stage_time_append = 180
        elseif string.find(current_map, "SBNetworkPlayerController /Game/Art/BG/WorldMap/") then
            dprint("Move to WorldMap: " .. current_map)
            current_map_is_lobby = false  -- Enable Boss BGM in WorldMap
        else
            dprint("Unknown map. retry")
            current_map = GetMapName()
            -- current_map = ctx:get():GetFullName()
            dprint("Retried map name: " .. current_map)
            current_map_is_lobby = false  -- Default: enable Boss BGM
        end

        local music_files_default = GetMusicFiles(music_dirs["Default"])
        if #music_files_default > 0 then current_music_files = music_files_default end

        dprint("Checking worldmap names for map: " .. current_map)
        for k, v in pairs(worldmap_names) do
            dprint("Worldmap key and name: " .. k .. ", " .. v)
            if string.find(current_map, v) then
                dprint("Found matching worldmap: " .. k)
                local music_files_worldmap = GetMusicFiles(music_dirs[k])
                if #music_files_worldmap > 0 then
                    current_music_files = music_files_worldmap
                    dprint("Set current_music_files to " .. k .. " with " .. #current_music_files .. " files")
                end
                break
            end
        end

        dprint("Finished worldmap check. Total files: " .. #current_music_files)
        previous_music_files = current_music_files
        previous_music_index = 0
        current_music_index = 0

        current_boss_name = ""
        is_boss_bgm_triggered = false

        -- Use safe transition instead of direct async call
        dprint("Attempting to start music transition via ExecuteAsync")

        if not ExecuteAsync then
            dprint("ERROR: ExecuteAsync is not available!")
            client_restart_triggered = false
            return
        end

        -- Set pending transition instead of using ExecuteWithDelay
        dprint("Setting pending map transition")
        pending_map_transition = true
        pending_transition_files = current_music_files
        pending_transition_delay = stage_time_append
        end)  -- End of pcall

        if not hook_success then
            dprint("ERROR ClientRestart hook failed: " .. tostring(hook_error))
        end
    end)
end)


local function setupMod()
    audio.init()
    -- Note: Using LoopAsync for music end detection instead of callback
    music_files["Default"] = GetMusicFiles(music_dirs["Default"])
    music_files["Lobby"] = GetMusicFiles(music_dirs["Lobby"])
    music_files["Boss"] = GetMusicFiles(music_dirs["Boss"])

    -- ExecuteWithDelay(1180, function()
    ExecuteWithDelay(2180, function()
        if #music_files["Lobby"] > 0 then
            dprint("Starting initial music playback")
            current_music_files = music_files["Lobby"]
            SelectAndPlayMusicFile(current_music_files)
        elseif #music_files["Default"] > 0 then
            dprint("Starting initial music playback")
            current_music_files = music_files["Default"]
            SelectAndPlayMusicFile(current_music_files)
        else
            dprint("No music files found in " .. music_dirs["Default"])
        end
    end)
end

print("[SBPod] is loaded\n")
dprint("Begin to write log")

setupMod()

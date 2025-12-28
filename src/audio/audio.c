/*
 * lua_audio.c - Lua Audio Wrapper DLL with Callback Support
 *
 * Compile: gcc -shared -o lua_audio.dll lua_audio.c .\stb_vorbis.c -I"lua/include" -L"lua/lib" -llua54 -lwinmm -lole32
 *
 * Lua Usage:
 * local audio = require("lua_audio")
 * audio.init()
 * audio.setEndCallback(function() print("Music ended!") end)
 * local sound = audio.load("guitar.ogg")
 * sound:play()
 */

#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MA_HAS_VORBIS
#define MA_ENABLE_VORBIS
#define MINIAUDIO_IMPLEMENTATION
#include <stdio.h>
#include <stdlib.h>

#include "lauxlib.h"
#include "lua.h"
#include "miniaudio.h"

// External function declarations from util.c
extern int l_sleep(lua_State* L);
extern int l_msleep(lua_State* L);
extern int l_kbhit(lua_State* L);
extern int l_getch(lua_State* L);
extern int l_cls(lua_State* L);
extern int l_beep(lua_State* L);
extern int l_tick(lua_State* L);
extern int l_yield(lua_State* L);
extern void create_key_constants(lua_State* L);

// Filesystem functions
extern int l_scan_music_files(lua_State* L);
extern int l_file_exists(lua_State* L);
extern int l_dir_exists(lua_State* L);

// Global audio engine
static ma_engine* g_engine = NULL;
static int g_initialized = 0;

// Global Lua state and callback reference for end callback
static lua_State* g_lua_state = NULL;
static int g_end_callback_ref = LUA_NOREF;

// Sound handle structure for Lua userdata
typedef struct {
    ma_sound* sound;
    int is_valid;
    lua_State* L;  // Store Lua state for callback
} LuaSound;

// Sound end callback function - called when sound finishes playing
static void sound_end_callback(void* pUserData, ma_sound* pSound) {
    (void)pUserData;  // Unused parameter
    (void)pSound;     // Unused parameter

    // Safety check: ensure Lua state is valid
    if (!g_lua_state || g_end_callback_ref == LUA_NOREF) {
        return;
    }

    // Save stack position for cleanup
    int top = lua_gettop(g_lua_state);

    // Get the callback function from registry
    lua_rawgeti(g_lua_state, LUA_REGISTRYINDEX, g_end_callback_ref);

    // Strict type check: must be a Lua function (not C function, not userdata)
    int callback_type = lua_type(g_lua_state, -1);
    if (callback_type != LUA_TFUNCTION) {
        printf("Audio callback warning: callback type is %d (expected %d for function)\n",
               callback_type, LUA_TFUNCTION);
        lua_settop(g_lua_state, top);  // Restore stack
        return;
    }

    // Call the Lua callback function with protected call
    if (lua_pcall(g_lua_state, 0, 0, 0) != LUA_OK) {
        // If there's an error, print it but don't crash
        const char* error = lua_tostring(g_lua_state, -1);
        if (error) {
            printf("Audio callback error: %s\n", error);
        } else {
            printf("Audio callback error: unknown error\n");
        }
        lua_settop(g_lua_state, top);  // Restore stack
    }
}

// Initialize audio system
static int l_audio_init(lua_State* L) {
    if (g_initialized) {
        lua_pushboolean(L, 1);
        return 1;
    }

    g_engine = malloc(sizeof(ma_engine));
    if (!g_engine) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "Memory allocation failed");
        return 2;
    }

    if (ma_engine_init(NULL, g_engine) != MA_SUCCESS) {
        free(g_engine);
        g_engine = NULL;
        lua_pushboolean(L, 0);
        lua_pushstring(L, "Audio engine init failed");
        return 2;
    }

    // Store Lua state for callbacks
    g_lua_state = L;
    g_initialized = 1;
    lua_pushboolean(L, 1);
    return 1;
}

// Shutdown audio system
static int l_audio_shutdown(lua_State* L) {
    if (g_initialized && g_engine) {
        ma_engine_uninit(g_engine);
        free(g_engine);
        g_engine = NULL;
        g_initialized = 0;
    }

    // Clear callback reference
    if (g_end_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_end_callback_ref);
        g_end_callback_ref = LUA_NOREF;
    }
    g_lua_state = NULL;

    return 0;
}

// Set end callback function - called when any sound finishes
static int l_audio_set_end_callback(lua_State* L) {
    // Check if parameter is a function
    if (!lua_isfunction(L, 1)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "Parameter must be a function");
        return 2;
    }

    // Clear previous callback if exists
    if (g_end_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_end_callback_ref);
    }

    // Store new callback in registry
    lua_pushvalue(L, 1);  // Copy function to top of stack
    g_end_callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_pushboolean(L, 1);
    return 1;
}

// Clear end callback
static int l_audio_clear_end_callback(lua_State* L) {
    if (g_end_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_end_callback_ref);
        g_end_callback_ref = LUA_NOREF;
    }
    lua_pushboolean(L, 1);
    return 1;
}

// Load music file
static int l_audio_load(lua_State* L) {
    const char* filename = luaL_checkstring(L, 1);

    if (!g_initialized) {
        lua_pushnil(L);
        lua_pushstring(L, "Audio system not initialized");
        return 2;
    }

    // Create LuaSound userdata
    LuaSound* lua_sound = (LuaSound*)lua_newuserdata(L, sizeof(LuaSound));
    lua_sound->sound = NULL;
    lua_sound->is_valid = 0;
    lua_sound->L = L;

    // Set metatable
    luaL_getmetatable(L, "LuaSound");
    lua_setmetatable(L, -2);

    // Create ma_sound
    lua_sound->sound = malloc(sizeof(ma_sound));
    if (!lua_sound->sound) {
        lua_pushnil(L);
        lua_pushstring(L, "Memory allocation failed");
        return 2;
    }

    // Load file with end callback
    if (ma_sound_init_from_file(g_engine, filename, 0, NULL, NULL, lua_sound->sound) != MA_SUCCESS) {
        free(lua_sound->sound);
        lua_sound->sound = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "Failed to load: %s", filename);
        return 2;
    }

    // Set end callback for this sound
    ma_sound_set_end_callback(lua_sound->sound, sound_end_callback, NULL);

    lua_sound->is_valid = 1;
    return 1;
}

// Simple file playback (one-shot)
static int l_audio_play_file(lua_State* L) {
    const char* filename = luaL_checkstring(L, 1);

    if (!g_initialized) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "Audio system not initialized");
        return 2;
    }

    ma_result result = ma_engine_play_sound(g_engine, filename, NULL);
    lua_pushboolean(L, result == MA_SUCCESS);
    return 1;
}

// Play sound
static int l_sound_play(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    ma_result result = ma_sound_start(lua_sound->sound);
    lua_pushboolean(L, result == MA_SUCCESS);
    return 1;
}

// Stop sound
static int l_sound_stop(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    // Check if already stopped - if so, just return success
    // This prevents crashes from multiple stop calls
    ma_bool32 is_playing = ma_sound_is_playing(lua_sound->sound);
    if (!is_playing) {
        // Already stopped, return success without doing anything
        lua_pushboolean(L, 1);
        return 1;
    }

    // Stop the sound
    ma_result result = ma_sound_stop(lua_sound->sound);

    // Small delay to ensure callbacks complete
    ma_sleep(10);

    lua_pushboolean(L, result == MA_SUCCESS);
    return 1;
}

// Set volume
static int l_sound_set_volume(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");
    float volume = (float)luaL_checknumber(L, 2);

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;

    ma_sound_set_volume(lua_sound->sound, volume);
    lua_pushboolean(L, 1);
    return 1;
}

// Check if sound is playing
static int l_sound_is_playing(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    ma_bool32 is_playing = ma_sound_is_playing(lua_sound->sound);
    lua_pushboolean(L, is_playing);
    return 1;
}

// Set looping
static int l_sound_set_looping(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");
    int loop = lua_toboolean(L, 2);

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    ma_sound_set_looping(lua_sound->sound, loop ? MA_TRUE : MA_FALSE);
    lua_pushboolean(L, 1);
    return 1;
}

// Get sound length in seconds
static int l_sound_get_length(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushnumber(L, 0);
        return 1;
    }

    float length_in_seconds;
    if (ma_sound_get_length_in_seconds(lua_sound->sound, &length_in_seconds) != MA_SUCCESS) {
        lua_pushnumber(L, 0);
        return 1;
    }

    lua_pushnumber(L, (double)length_in_seconds);
    return 1;
}

// Get current playback position in seconds
static int l_sound_get_position(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushnumber(L, 0);
        return 1;
    }

    float position_in_seconds;
    if (ma_sound_get_cursor_in_seconds(lua_sound->sound, &position_in_seconds) != MA_SUCCESS) {
        lua_pushnumber(L, 0);
        return 1;
    }

    lua_pushnumber(L, (double)position_in_seconds);
    return 1;
}

// LuaSound garbage collection
static int l_sound_gc(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (lua_sound->is_valid && lua_sound->sound) {
        // Stop the sound first if it's still playing
        ma_bool32 is_playing = ma_sound_is_playing(lua_sound->sound);
        if (is_playing) {
            ma_sound_stop(lua_sound->sound);
            // Small delay to allow any pending callbacks to complete
            ma_sleep(10);
        }

        // Now safe to uninitialize
        ma_sound_uninit(lua_sound->sound);
        free(lua_sound->sound);
        lua_sound->sound = NULL;
        lua_sound->is_valid = 0;
    }

    return 0;
}

// LuaSound tostring
static int l_sound_tostring(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (lua_sound->is_valid) {
        lua_pushstring(L, "LuaSound(valid)");
    } else {
        lua_pushstring(L, "LuaSound(invalid)");
    }
    return 1;
}

// Audio module functions (includes both audio and util functions)
static const luaL_Reg audiolib[] = {
    // Audio functions
    {"init", l_audio_init},
    {"shutdown", l_audio_shutdown},
    {"load", l_audio_load},
    {"playFile", l_audio_play_file},
    {"setEndCallback", l_audio_set_end_callback},
    {"clearEndCallback", l_audio_clear_end_callback},

    // Util functions (from util.c)
    {"sleep", l_sleep},
    {"msleep", l_msleep},
    {"kbhit", l_kbhit},
    {"getch", l_getch},
    {"cls", l_cls},
    {"beep", l_beep},
    {"tick", l_tick},
    {"yield", l_yield},

    // Filesystem functions
    {"scanMusicFiles", l_scan_music_files},
    {"fileExists", l_file_exists},
    {"dirExists", l_dir_exists},

    {NULL, NULL}};

// LuaSound metamethods
static const luaL_Reg sound_meta[] = {
    {"play", l_sound_play},
    {"stop", l_sound_stop},
    {"setVolume", l_sound_set_volume},
    {"isPlaying", l_sound_is_playing},
    {"setLooping", l_sound_set_looping},
    {"getLength", l_sound_get_length},
    {"getPosition", l_sound_get_position},
    {"__gc", l_sound_gc},
    {"__tostring", l_sound_tostring},
    {NULL, NULL}};

// Module initialization function
#if defined(_WIN32)
#if defined(_MSC_VER) || defined(__MINGW64__)
__declspec(dllexport)
#endif
#endif
int
luaopen_audio(lua_State* L) {
    // Create LuaSound metatable
    luaL_newmetatable(L, "LuaSound");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");  // Set metatable as its own __index
    luaL_setfuncs(L, sound_meta, 0);
    lua_pop(L, 1);

    // Create audio module table (includes util functions)
    luaL_newlib(L, audiolib);

    // Add key constants (from util.c)
    create_key_constants(L);

    // Version information
    lua_pushstring(L, "1.1");
    lua_setfield(L, -2, "version");

    return 1;
}
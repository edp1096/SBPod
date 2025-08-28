/*
 * lua_audio.c - Lua용 오디오 래퍼 DLL
 *
 * 컴파일: gcc -shared -o lua_audio.dll lua_audio.c .\stb_vorbis.c -I"lua/include" -L"lua/lib" -llua54 -lwinmm -lole32
 *
 * Lua 사용법:
 * local audio = require("lua_audio")
 * audio.init()
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

// util.c 함수들 extern 선언
extern int l_sleep(lua_State* L);
extern int l_msleep(lua_State* L);
extern int l_kbhit(lua_State* L);
extern int l_getch(lua_State* L);
extern int l_cls(lua_State* L);
extern int l_beep(lua_State* L);
extern int l_tick(lua_State* L);
extern int l_yield(lua_State* L);
extern void create_key_constants(lua_State* L);

// 파일시스템 함수들
extern int l_scan_music_files(lua_State* L);
extern int l_file_exists(lua_State* L);
extern int l_dir_exists(lua_State* L);

// 전역 오디오 엔진
static ma_engine* g_engine = NULL;
static int g_initialized = 0;

// 사운드 핸들 구조체 (Lua userdata용)
typedef struct {
    ma_sound* sound;
    int is_valid;
} LuaSound;

// 오디오 시스템 초기화
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

    g_initialized = 1;
    lua_pushboolean(L, 1);
    return 1;
}

// 오디오 시스템 종료
static int l_audio_shutdown(lua_State* L) {
    if (g_initialized && g_engine) {
        ma_engine_uninit(g_engine);
        free(g_engine);
        g_engine = NULL;
        g_initialized = 0;
    }
    return 0;
}

// 음악 파일 로드
static int l_audio_load(lua_State* L) {
    const char* filename = luaL_checkstring(L, 1);

    if (!g_initialized) {
        lua_pushnil(L);
        lua_pushstring(L, "Audio system not initialized");
        return 2;
    }

    // LuaSound userdata 생성
    LuaSound* lua_sound = (LuaSound*)lua_newuserdata(L, sizeof(LuaSound));
    lua_sound->sound = NULL;
    lua_sound->is_valid = 0;

    // 메타테이블 설정
    luaL_getmetatable(L, "LuaSound");
    lua_setmetatable(L, -2);

    // ma_sound 생성
    lua_sound->sound = malloc(sizeof(ma_sound));
    if (!lua_sound->sound) {
        lua_pushnil(L);
        lua_pushstring(L, "Memory allocation failed");
        return 2;
    }

    // 파일 로드
    if (ma_sound_init_from_file(g_engine, filename, 0, NULL, NULL, lua_sound->sound) != MA_SUCCESS) {
        free(lua_sound->sound);
        lua_sound->sound = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "Failed to load: %s", filename);
        return 2;
    }

    lua_sound->is_valid = 1;
    return 1;
}

// 간단한 파일 재생 (원샷)
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

// 사운드 재생
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

// 사운드 정지
static int l_sound_stop(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (!lua_sound->is_valid || !lua_sound->sound) {
        lua_pushboolean(L, 0);
        return 1;
    }

    ma_sound_stop(lua_sound->sound);
    lua_pushboolean(L, 1);
    return 1;
}

// 볼륨 설정
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

// 재생 상태 확인
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

// 루프 설정
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

// LuaSound 가비지 컬렉션
static int l_sound_gc(lua_State* L) {
    LuaSound* lua_sound = (LuaSound*)luaL_checkudata(L, 1, "LuaSound");

    if (lua_sound->is_valid && lua_sound->sound) {
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

// 오디오 모듈 함수들 (audio와 util 함수 모두 포함)
static const luaL_Reg audiolib[] = {
    // Audio 함수들
    {"init", l_audio_init},
    {"shutdown", l_audio_shutdown},
    {"load", l_audio_load},
    {"playFile", l_audio_play_file},

    // Util 함수들 (util.c에서 가져옴)
    {"sleep", l_sleep},
    {"msleep", l_msleep},
    {"kbhit", l_kbhit},
    {"getch", l_getch},
    {"cls", l_cls},
    {"beep", l_beep},
    {"tick", l_tick},
    {"yield", l_yield},

    // 파일시스템 함수들
    {"scanMusicFiles", l_scan_music_files},  // 음악 파일 스캔
    {"fileExists", l_file_exists},           // 파일 존재 확인
    {"dirExists", l_dir_exists},             // 디렉토리 존재 확인

    {NULL, NULL}};

// LuaSound 메타메서드들
static const luaL_Reg sound_meta[] = {
    {"play", l_sound_play},
    {"stop", l_sound_stop},
    {"setVolume", l_sound_set_volume},
    {"isPlaying", l_sound_is_playing},
    {"setLooping", l_sound_set_looping},
    {"__gc", l_sound_gc},
    {"__tostring", l_sound_tostring},
    {NULL, NULL}};

// 모듈 초기화 함수
#if defined(_WIN32)
#if defined(_MSC_VER) || defined(__MINGW64__)
__declspec(dllexport)
#endif
#endif
int
luaopen_audio(lua_State* L) {
    // LuaSound 메타테이블 생성
    luaL_newmetatable(L, "LuaSound");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");  // 메타테이블을 자기 자신의 __index로 설정
    luaL_setfuncs(L, sound_meta, 0);
    lua_pop(L, 1);

    // 오디오 모듈 테이블 생성 (util 함수들도 포함)
    luaL_newlib(L, audiolib);

    // 키 상수 추가 (util.c에서 가져옴)
    create_key_constants(L);

    // 버전 정보
    lua_pushstring(L, "1.0");
    lua_setfield(L, -2, "version");

    return 1;
}
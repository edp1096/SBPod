/*
 * util.c - 시스템 유틸리티 함수들 (audio 모듈에서 사용)
 * 
 * 기능:
 * - sleep(seconds)
 * - msleep(milliseconds) 
 * - kbhit() - 키 입력 감지
 * - getch() - 키 입력 받기
 * - cls() - 화면 지우기
 * - beep() - 비프음
 * - scanMusicFiles() - 음악 파일 스캔
 * - fileExists() - 파일 존재 확인
 * - dirExists() - 디렉토리 존재 확인
 */

#include "lua.h"
#include "lauxlib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <conio.h>
#include <io.h>
#include <fcntl.h>
#else
#include <unistd.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/select.h>
#include <time.h>      // clock_gettime용
#include <sched.h>     // sched_yield용
#include <dirent.h>
#include <sys/stat.h>
#include <strings.h>   // strcasecmp용
#endif

// 크로스플랫폼 대소문자 무관 문자열 비교
static int stricmp_cross(const char* s1, const char* s2) {
#ifdef _WIN32
    return _stricmp(s1, s2);
#else
    return strcasecmp(s1, s2);
#endif
}

// 파일 확장자 확인 함수
static int has_music_extension(const char* filename) {
    const char* ext = strrchr(filename, '.');
    if (!ext) return 0;
    
    return (stricmp_cross(ext, ".mp3") == 0 ||
            stricmp_cross(ext, ".wav") == 0 ||
            stricmp_cross(ext, ".ogg") == 0 ||
            stricmp_cross(ext, ".flac") == 0);
            // stricmp_cross(ext, ".m4a") == 0 ||
            // stricmp_cross(ext, ".aac") == 0);
}

#ifdef _WIN32
// UTF-16을 UTF-8로 변환하는 함수
static char* utf16_to_utf8(const wchar_t* wstr) {
    if (!wstr) return NULL;
    
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (len <= 0) return NULL;
    
    char* utf8str = malloc(len);
    if (!utf8str) return NULL;
    
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, utf8str, len, NULL, NULL);
    return utf8str;
}

// UTF-8을 UTF-16으로 변환하는 함수  
static wchar_t* utf8_to_utf16(const char* str) {
    if (!str) return NULL;
    
    int len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
    if (len <= 0) return NULL;
    
    wchar_t* wstr = malloc(len * sizeof(wchar_t));
    if (!wstr) return NULL;
    
    MultiByteToWideChar(CP_UTF8, 0, str, -1, wstr, len);
    return wstr;
}
#endif

// 초 단위 sleep
int l_sleep(lua_State* L) {
    double seconds = luaL_checknumber(L, 1);
    
#ifdef _WIN32
    Sleep((DWORD)(seconds * 1000));
#else
    usleep((useconds_t)(seconds * 1000000));
#endif
    
    return 0;
}

// 밀리초 단위 sleep
int l_msleep(lua_State* L) {
    int milliseconds = luaL_checkinteger(L, 1);
    
#ifdef _WIN32
    Sleep((DWORD)milliseconds);
#else
    usleep((useconds_t)(milliseconds * 1000));
#endif
    
    return 0;
}

// 키 입력 감지 (non-blocking)
int l_kbhit(lua_State* L) {
#ifdef _WIN32
    lua_pushboolean(L, _kbhit());
#else
    struct termios oldt, newt;
    int ch;
    int oldf;
    
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
    oldf = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, oldf | O_NONBLOCK);
    
    ch = getchar();
    
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    fcntl(STDIN_FILENO, F_SETFL, oldf);
    
    if(ch != EOF) {
        ungetc(ch, stdin);
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
#endif
    
    return 1;
}

// 키 입력 받기 (extended key 지원)
int l_getch(lua_State* L) {
#ifdef _WIN32
    int ch = _getch();
    
    // Extended key 체크 (화살표, Page Up/Down, Function keys 등)
    if (ch == 0 || ch == 224) {
        int extended = _getch();  // 실제 키코드 받기
        
        // Extended key는 1000번대로 변환하여 구분
        lua_pushinteger(L, 1000 + extended);
    } else {
        lua_pushinteger(L, ch);
    }
#else
    struct termios oldt, newt;
    int ch;
    
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
    
    ch = getchar();
    
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    
    if (ch == 27) {  // ESC 시퀀스 확인
        fd_set fds;
        struct timeval tv;
        
        FD_ZERO(&fds);
        FD_SET(STDIN_FILENO, &fds);
        tv.tv_sec = 0;
        tv.tv_usec = 100000;  // 100ms timeout
        
        if (select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0) {
            int ch2 = getchar();
            if (ch2 == '[') {
                int ch3 = getchar();
                // 화살표 키 등을 1000번대로 변환
                switch (ch3) {
                    case 'A': lua_pushinteger(L, 1072); break;  // Up
                    case 'B': lua_pushinteger(L, 1080); break;  // Down  
                    case 'C': lua_pushinteger(L, 1077); break;  // Right
                    case 'D': lua_pushinteger(L, 1075); break;  // Left
                    default: lua_pushinteger(L, ch); break;
                }
            } else {
                lua_pushinteger(L, ch);
            }
        } else {
            lua_pushinteger(L, ch);
        }
    } else {
        lua_pushinteger(L, ch);
    }
#endif
    return 1;
}

// 화면 지우기
int l_cls(lua_State* L) {
#ifdef _WIN32
    int ret = system("cls");
    (void)ret;  // 반환값 사용하지 않음을 명시
#else
    int ret = system("clear");
    (void)ret;  // 반환값 사용하지 않음을 명시
#endif
    return 0;
}

// 비프음
int l_beep(lua_State* L) {
    int frequency = luaL_optinteger(L, 1, 800);    // 기본 800Hz
    int duration = luaL_optinteger(L, 2, 200);     // 기본 200ms
    
#ifdef _WIN32
    Beep(frequency, duration);
#else
    // Linux에서는 단순히 시스템 벨 사용 (frequency, duration 무시)
    (void)frequency;  // 경고 방지
    (void)duration;   // 경고 방지
    printf("\a");     // 시스템 벨
    fflush(stdout);
#endif
    
    return 0;
}

// 현재 시간 (밀리초)
int l_tick(lua_State* L) {
#ifdef _WIN32
    lua_pushinteger(L, GetTickCount());
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        long long ms = (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
        lua_pushinteger(L, ms);
    } else {
        lua_pushinteger(L, 0);
    }
#endif
    return 1;
}

// CPU 사용량 최소화 대기
int l_yield(lua_State* L) {
#ifdef _WIN32
    Sleep(0);  // 다른 스레드에게 시간 양보
#else
    sched_yield();
#endif
    return 0;
}

// 디렉토리에서 음악 파일 목록을 가져와서 Lua 테이블로 반환
int l_scan_music_files(lua_State* L) {
    const char* directory = luaL_checkstring(L, 1);
    
    lua_newtable(L);  // 결과 테이블 생성
    int index = 1;
    
#ifdef _WIN32
    // 윈도우: FindFirstFile/FindNextFile 사용
    WIN32_FIND_DATAW findData;
    HANDLE hFind;
    
    // 검색 패턴 생성 (directory\*.*)
    size_t pathLen = strlen(directory);
    char* searchPath = malloc(pathLen + 10);
    if (!searchPath) {
        lua_pushnil(L);
        lua_pushstring(L, "Memory allocation failed");
        return 2;
    }
    sprintf(searchPath, "%s\\*.*", directory);
    
    // UTF-8을 UTF-16으로 변환
    wchar_t* wSearchPath = utf8_to_utf16(searchPath);
    free(searchPath);
    
    if (!wSearchPath) {
        lua_pushnil(L);
        lua_pushstring(L, "Path encoding conversion failed");
        return 2;
    }
    
    hFind = FindFirstFileW(wSearchPath, &findData);
    free(wSearchPath);
    
    if (hFind == INVALID_HANDLE_VALUE) {
        lua_pushnil(L);
        lua_pushstring(L, "Directory not found or access denied");
        return 2;
    }
    
    do {
        // 디렉토리는 건너뛰기
        if (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            continue;
        }
        
        // UTF-16을 UTF-8로 변환
        char* filename = utf16_to_utf8(findData.cFileName);
        if (!filename) continue;
        
        // 음악 파일 확장자 확인
        if (has_music_extension(filename)) {
            // 전체 경로 생성
            size_t fullPathLen = strlen(directory) + strlen(filename) + 2;
            char* fullPath = malloc(fullPathLen);
            if (fullPath) {
                sprintf(fullPath, "%s\\%s", directory, filename);
                
                // Lua 테이블에 추가
                lua_pushstring(L, fullPath);
                lua_rawseti(L, -2, index++);
                
                free(fullPath);
            }
        }
        
        free(filename);
    } while (FindNextFileW(hFind, &findData));
    
    FindClose(hFind);
    
#else
    // 리눅스/Unix: opendir/readdir 사용
    DIR* dir = opendir(directory);
    if (!dir) {
        lua_pushnil(L);
        lua_pushstring(L, "Directory not found or access denied");
        return 2;
    }
    
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        // 숨김 파일과 디렉토리 건너뛰기
        if (entry->d_name[0] == '.') continue;
        
        // 전체 경로로 stat 확인
        char fullPath[1024];
        snprintf(fullPath, sizeof(fullPath), "%s/%s", directory, entry->d_name);
        
        struct stat statbuf;
        if (stat(fullPath, &statbuf) != 0) continue;
        
        // 디렉토리는 건너뛰기
        if (S_ISDIR(statbuf.st_mode)) continue;
        
        // 음악 파일 확인
        if (has_music_extension(entry->d_name)) {
            lua_pushstring(L, fullPath);
            lua_rawseti(L, -2, index++);
        }
    }
    
    closedir(dir);
#endif
    
    return 1;  // 테이블 반환
}

// 단일 파일 존재 확인
int l_file_exists(lua_State* L) {
    const char* filename = luaL_checkstring(L, 1);
    
#ifdef _WIN32
    wchar_t* wFilename = utf8_to_utf16(filename);
    if (!wFilename) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    DWORD attrs = GetFileAttributesW(wFilename);
    free(wFilename);
    
    lua_pushboolean(L, attrs != INVALID_FILE_ATTRIBUTES && 
                       !(attrs & FILE_ATTRIBUTE_DIRECTORY));
#else
    struct stat statbuf;
    int exists = (stat(filename, &statbuf) == 0 && S_ISREG(statbuf.st_mode));
    lua_pushboolean(L, exists);
#endif
    
    return 1;
}

// 디렉토리 존재 확인
int l_dir_exists(lua_State* L) {
    const char* dirname = luaL_checkstring(L, 1);
    
#ifdef _WIN32
    wchar_t* wDirname = utf8_to_utf16(dirname);
    if (!wDirname) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    DWORD attrs = GetFileAttributesW(wDirname);
    free(wDirname);
    
    lua_pushboolean(L, attrs != INVALID_FILE_ATTRIBUTES && 
                       (attrs & FILE_ATTRIBUTE_DIRECTORY));
#else
    struct stat statbuf;
    int exists = (stat(dirname, &statbuf) == 0 && S_ISDIR(statbuf.st_mode));
    lua_pushboolean(L, exists);
#endif
    
    return 1;
}

// 키 코드 상수 테이블
void create_key_constants(lua_State* L) {
    lua_newtable(L);
    
    // 일반적인 키 코드들
    lua_pushinteger(L, 13); lua_setfield(L, -2, "ENTER");
    lua_pushinteger(L, 27); lua_setfield(L, -2, "ESC");
    lua_pushinteger(L, 32); lua_setfield(L, -2, "SPACE");
    lua_pushinteger(L, 8);  lua_setfield(L, -2, "BACKSPACE");
    lua_pushinteger(L, 9);  lua_setfield(L, -2, "TAB");
    lua_pushinteger(L, 45);  lua_setfield(L, -2, "MINUS");
    lua_pushinteger(L, 61);  lua_setfield(L, -2, "EQUAL");
    
    lua_setfield(L, -2, "KEY");
}
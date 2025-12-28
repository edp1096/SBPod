.PHONY: build clean test help

SHELL = cmd.exe
.SHELLFLAGS = /c

CC = gcc
LOADER_LIBS = -lm

EXT = .dll
EXT_BIN = .exe
RM = del /Q
CFLAGS = -shared -O2 -Wall
LUA_INCLUDE = -I../../lua/include
LUA_LIB = -L../../lua/lib -llua
AUDIO_LIBS = -lwinmm -lole32

AUDIO_TARGET = audio$(EXT)

build: $(AUDIO_TARGET)

$(AUDIO_TARGET): src/audio/audio.c src/audio/stb_vorbis.c src/audio/util.c
	$(CC) $(CFLAGS) $(LUA_INCLUDE) -o $(AUDIO_TARGET) src/audio/audio.c src/audio/stb_vorbis.c src/audio/util.c $(LUA_LIB) $(AUDIO_LIBS)

dist: build
	@mkdir dist
	@mkdir dist\SBPod
	@mkdir dist\SBPod\scripts

	@copy $(AUDIO_TARGET) dist\SBPod\scripts
	@copy src\main.lua dist\SBPod\scripts
	@copy src\ini.lua dist\SBPod\scripts
	@copy src\text.lua dist\SBPod\scripts
	@copy config.ini dist\SBPod
	@copy enabled.txt dist\SBPod
	@echo Build complete: dist\SBPod

clean:
ifeq ($(OS),Windows_NT)
	@-if exist dist rmdir /s /q dist
	@-if exist audio.dll del /q audio.dll
endif

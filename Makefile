.PHONY: build clean test help

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

$(AUDIO_TARGET): audio/audio.c audio/stb_vorbis.c audio/util.c
	$(CC) $(CFLAGS) $(LUA_INCLUDE) -o $(AUDIO_TARGET) audio/audio.c audio/stb_vorbis.c audio/util.c $(LUA_LIB) $(AUDIO_LIBS)

dist: build
	mkdir dist
ifeq ($(OS),Windows_NT)
	copy $(AUDIO_TARGET) dist
	copy main.lua dist
else
	cp $(AUDIO_TARGET) dist
	cp main.lua dist
endif

clean:
ifeq ($(OS),Windows_NT)
	-$(RM) *.dll 2>nul
	-$(RM) dist 2>nul
	rmdir dist 2>nul
endif

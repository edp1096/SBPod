mingw32-make dist

@REM force copy main.lua
copy dist\audio.dll %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\scripts\ /y
copy dist\main.lua %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\scripts\ /y

mingw32-make clean

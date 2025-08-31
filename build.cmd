mingw32-make clean
mingw32-make dist

type nul > dist\SBPod\debug.log


@REM force copy main.lua
@REM copy dist\audio.dll %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\scripts\ /y
@REM copy dist\ini.lua %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\scripts\ /y
@REM copy dist\main.lua %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\scripts\ /y
@REM copy config.ini %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\ /y

xcopy dist\SBPod %USERPROFILE%\Desktop\mo2\mods\SBPod\SB\Binaries\Win64\ue4ss\Mods\SBPod\ /e /h /k /y

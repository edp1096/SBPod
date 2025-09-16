# BGM Playing mod for Stellar Blade

https://www.nexusmods.com/stellarblade/mods/1857


## Prequisites

Instead of below, you can try [VSCode working set for Lua](https://github.com/edp1096/my-lua-set).

* Lua >= 5.4.8
* MinGW - https://github.com/brechtsanders/winlibs_mingw


## Compile audio.dll
```powershell
make
# or
mingw32-make
# or
make dist
# or
mingw32-make dist
```


## Clean
```powershell
make clean
# or
mingw32-make clean
```


## Note
* Build.cmd - Compile then copy files to the mod folder in `Mod Organizer 2`.

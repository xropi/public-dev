@echo off
rem Configures a Visual Studio tree beside the Ninja one, so both can coexist:
rem the .sh scripts own build\, this owns +build-vs2022\ (gitignored via **/+*).
rem Then open +build-vs2022\ini-output-rule.sln and build Debug, Release, Debug again --
rem the same scenario the .sh scripts run, which is what O1/O2 are waiting on.
cd /d "%~dp0"
cmake -G "Visual Studio 17 2022" -B +build-vs2022 -S .

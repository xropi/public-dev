@echo off
cd /d "%~dp0"
cmake -G "Visual Studio 17 2022" -B +build-vs2022 -S .

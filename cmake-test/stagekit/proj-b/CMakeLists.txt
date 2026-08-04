# A second subproject, sharing proj-a's staging target without either knowing
# about the other, and staging into a subdirectory of the binary root to show
# that stagekit creates the destination directory. Also standalone-buildable.
#
# It is additionally the directory-staging example: ad/ and ar/ are staged whole
# (D13) by a stage_file() call that differs from the single-file one above it
# only in what it passes for del_stale (D16).
cmake_minimum_required(VERSION 3.26)
project(proj-b CXX)

set(CMAKE_CXX_STANDARD 20)

include(${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake)

add_executable(app-b src/main.cpp)

stage_file(app-b
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/cd.txt,${CMAKE_CURRENT_SOURCE_DIR}/src/cr.txt>"
    "${CMAKE_BINARY_DIR}/data/cfg.txt"
    OFF)

# The same call with a directory source: the contents of ad/ or ar/ -- including
# nested/ -- become the contents of build/assets/, one level down from the file
# above. Nothing but the trailing del_stale distinguishes the two cases.
#
# del_stale ON because build/assets/ is meant to be exactly one of the two source
# trees: without it, a file present in ad/ but not ar/ would linger through the
# switch to Release and the app would see a mixture. The call above passes OFF,
# which is all a single-file destination can mean (D16).
stage_file(app-b
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/ad,${CMAKE_CURRENT_SOURCE_DIR}/src/ar>"
    "${CMAKE_BINARY_DIR}/assets"
    ON)

target_compile_definitions(app-b PRIVATE
    INI_PATH="${CMAKE_BINARY_DIR}/data/cfg.txt"
    ASSET_DIR="${CMAKE_BINARY_DIR}/assets")

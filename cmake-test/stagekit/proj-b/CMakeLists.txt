# A second subproject, sharing proj-a's staging target without either knowing
# about the other, and staging into a subdirectory of the binary root to show
# that stagekit creates the destination directory. Also standalone-buildable.
cmake_minimum_required(VERSION 3.21)
project(proj-b CXX)

set(CMAKE_CXX_STANDARD 20)

include(${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake)

add_executable(app-b src/main.cpp)

stage_file(app-b
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/cd.txt,${CMAKE_CURRENT_SOURCE_DIR}/src/cr.txt>"
    "${CMAKE_BINARY_DIR}/data/cfg.txt")

target_compile_definitions(app-b PRIVATE INI_PATH="${CMAKE_BINARY_DIR}/data/cfg.txt")

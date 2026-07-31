# Buildable two ways: pulled in by ../CMakeLists.txt, or configured directly
# (cmake -B build -S .) as its own top level. Nothing below is conditional on
# which -- that is the point of the self-finalizing stagekit.
cmake_minimum_required(VERSION 3.21)
project(proj-a CXX)

set(CMAKE_CXX_STANDARD 20)

# Included by relative path rather than through CMAKE_MODULE_PATH, so a
# standalone configure needs no setup from a parent that is not there.
# include_guard(GLOBAL) makes the second include a no-op in an umbrella build.
include(${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake)

add_executable(app-a src/main.cpp)

# The only staging line. CMAKE_BINARY_DIR is the umbrella build root when built
# from above and proj-a/build when built standalone -- correct either way.
stage_file(app-a
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/xd.ini,${CMAKE_CURRENT_SOURCE_DIR}/src/xr.ini>"
    "${CMAKE_BINARY_DIR}/x.ini")

target_compile_definitions(app-a PRIVATE INI_PATH="${CMAKE_BINARY_DIR}/x.ini")

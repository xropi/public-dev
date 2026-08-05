# Buildable two ways: pulled in by ../CMakeLists.txt, or configured directly
# (cmake -B build -S .) as its own top level. Nothing below is conditional on
# which -- that is the point of the self-finalizing stagekit.
cmake_minimum_required(VERSION 3.26)
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
    "${CMAKE_BINARY_DIR}/x.ini"
    OFF)

target_compile_definitions(app-a PRIVATE INI_PATH="${CMAKE_BINARY_DIR}/x.ini")

# Debugging from the IDE starts app-a one directory above its .vcxproj instead
# of in it. $(ProjectDir) is an MSBuild macro -- VS expands it, CMake passes it
# through untouched (CMake's own syntax is $<...>), and it carries a trailing
# backslash, so the ".." appends cleanly. It points at the *binary* directory
# holding the project file, which is +build-vs2022/proj-a/ in an umbrella build
# and proj-a/build/ standalone; the parent is therefore the build root in the
# first case and proj-a/ itself in the second. For a fixed directory regardless
# of generator layout, write a CMake path such as
# "${CMAKE_CURRENT_SOURCE_DIR}/.." instead.
#
# No generator guard: every non-VS generator ignores the property. It is written
# into app-a.vcxproj.user and only affects F5, never a build -- nothing in this
# harness reads a relative path (INI_PATH above is absolute), so the setting is
# here as the worked example, not because staging needs it. (D17)
set_target_properties(app-a PROPERTIES
    VS_DEBUGGER_WORKING_DIRECTORY "$(ProjectDir)..")

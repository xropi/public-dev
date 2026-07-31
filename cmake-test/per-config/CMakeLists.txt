cmake_minimum_required(VERSION 3.20)
project(ini-per-config-dir CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(app src/main.cpp)

# Both multi-config generators already default to this layout (build/Debug/app,
# build/Release/app), but say it explicitly: the staging path below has to land
# in the same directory as the executable, and relying on an unstated default
# for that is how the two silently drift apart.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>")

# The destination itself carries $<CONFIG>, so no two configs ever write the
# same file. That is the whole difference from output-rule/: cross-config
# staleness stops being a scheduling problem the generator has to get right and
# becomes structurally impossible. Debug and Release stay independently
# runnable, with no rebuild needed between them.
set(ini_dst "${CMAKE_BINARY_DIR}/$<CONFIG>/x.ini")

# Which ini this config wants. The else-branch is what makes RelWithDebInfo and
# MinSizeRel land on the release ini instead of getting nothing.
set(ini_src "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/xd.ini,${CMAKE_CURRENT_SOURCE_DIR}/src/xr.ini>")

# An OUTPUT rule is safe again here — unlike in output-rule/, each config
# owns its own output path, so no generator's per-config up-to-date tracking can
# be confused by what another config did to the file. Being a real dependency
# edge is what makes editing an ini restage it on the next build; a POST_BUILD
# step would only fire when the executable relinks, which editing an ini does
# not cause.
#
# $<CONFIG> in a custom command OUTPUT requires CMake 3.20 (the minimum above).
add_custom_command(
    OUTPUT "${ini_dst}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ini_src}" "${ini_dst}"
    DEPENDS "${ini_src}"
    COMMENT "staging x.ini for $<CONFIG>"
    VERBATIM)

# Putting the output in app's source list is what makes the rule run. .ini is
# not a compilable language, so it adds a dependency edge and nothing else.
target_sources(app PRIVATE "${ini_dst}")

# No INI_PATH define: the path now contains $<CONFIG>, which a configure-time
# compile definition cannot carry. The app resolves it at runtime instead.

cmake_minimum_required(VERSION 3.20)
project(ini-always-run CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(app src/main.cpp)

# The ini lives at the binary root, shared by every config — same destination as
# the parent sample. What changes is how the copy is scheduled.
set(ini_dst "${CMAKE_BINARY_DIR}/x.ini")

# Which ini this config wants. $<CONFIG:Debug> matches case-insensitively and is
# evaluated per config, never at configure time. The else-branch is what makes
# RelWithDebInfo and MinSizeRel land on the release ini instead of getting
# nothing.
set(ini_src "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/xd.ini,${CMAKE_CURRENT_SOURCE_DIR}/src/xr.ini>")

# A custom TARGET, not a custom command with an OUTPUT. That distinction is the
# whole point of this variant: a target has no up-to-date check, so its command
# runs on every build in every generator.
#
# The parent sample's OUTPUT rule only re-copies when the generator notices the
# rule is dirty. Ninja Multi-Config notices because its single shared .ninja_log
# is keyed by output path and records the command line, so switching config is a
# command change. MSBuild's tracking is per-config .tlog files compared by
# timestamp, so after Debug -> Release -> Debug it sees x.ini newer than xd.ini,
# same command as its last Debug build, and skips — leaving the release ini in
# place under the debug binary. Running unconditionally sidesteps the entire
# question of whose up-to-date logic is in play.
#
# copy_if_different keeps the unconditional run cheap (compare, write only on a
# real difference) and still gives the property the OUTPUT rule was chosen for:
# edit an ini, the next build restages it. Cost is one cmake -E process per
# build.
add_custom_target(stage_ini ALL
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ini_src}" "${ini_dst}"
    COMMENT "staging x.ini for $<CONFIG>"
    VERBATIM)

# Ordering only — without this the copy could race the link. app does not
# consume the ini at build time, so a dependency edge is all that is needed.
add_dependencies(app stage_ini)

# The binary root is a configure-time constant, so the app can just be told.
target_compile_definitions(app PRIVATE INI_PATH="${ini_dst}")

cmake_minimum_required(VERSION 3.20)
project(ini-per-config CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(app src/main.cpp)

# The ini lives at the binary root, shared by every config.
set(ini_dst "${CMAKE_BINARY_DIR}/x.ini")

# Which ini this config wants. $<CONFIG:Debug> matches case-insensitively and is
# evaluated per config, never at configure time — that is the whole trick.
# The $<NOT:...> branch is what makes RelWithDebInfo and MinSizeRel land on the
# release ini instead of silently getting nothing.
set(ini_src "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/xd.ini,${CMAKE_CURRENT_SOURCE_DIR}/src/xr.ini>")

# A build-time copy is the only mechanism that works here: the destination has
# no $<CONFIG> in it, so only one config may write it, and only a build step
# knows which config that is. file(GENERATE) cannot do this — it runs for ALL
# configs at once and CMake rejects the two branches as conflicting commands.
#
# OUTPUT rule rather than POST_BUILD, so the ini is a real dependency: editing
# it re-copies on the next build. POST_BUILD would only fire when the
# executable itself relinks, which editing an ini does not cause.
add_custom_command(
    OUTPUT "${ini_dst}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ini_src}" "${ini_dst}"
    DEPENDS "${ini_src}"
    COMMENT "staging x.ini for $<CONFIG>"
    VERBATIM)

# Putting the output in app's source list is what makes the rule run. .ini is
# not a compilable language, so it adds a dependency edge and nothing else.
target_sources(app PRIVATE "${ini_dst}")

# The binary root is a configure-time constant, so the app can just be told.
target_compile_definitions(app PRIVATE INI_PATH="${ini_dst}")

# One staging target per build tree, assembled without ceremony.
#
# Usage, in any CMakeLists.txt at any depth:
#
#     include(${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake)
#     add_executable(app-a src/main.cpp)
#     stage_file(app-a "<src, may contain $<CONFIG> genexes>" "<dst>")
#
# That is the whole interface. There is no init call to place before the
# add_subdirectory list and no finalize call to place after it, so there is no
# ordering rule for a later add_subdirectory to violate -- which was the one
# silent failure mode of the earlier init/finalize form.
#
# Why the pieces are what they are:
#
# - include_guard(GLOBAL): every subproject includes this file unconditionally,
#   including when it is built standalone as its own top level. Only the first
#   include does anything.
#
# - The target is created lazily, on the first stage_file() call, rather than by
#   an explicit init. Nothing has to exist before the subprojects are read.
#
# - Registration goes through a GLOBAL property. A plain variable cannot escape
#   add_subdirectory (the append is silently lost in the parent), and
#   add_custom_command(TARGET ...) can only append to a target created in the
#   same directory, so neither works across a tree.
#
# - stage_finalize is deferred onto CMAKE_SOURCE_DIR, which is always the root
#   of whatever configure is currently running: the tree root for an umbrella
#   build, the subproject itself for a standalone one. The same code is correct
#   in both modes with no PROJECT_IS_TOP_LEVEL guard anywhere.
#
# - One `cmake -P` runs per build regardless of file count, because the copies
#   are emitted into a generated per-config script rather than spliced into the
#   target as one COMMAND per file.

include_guard(GLOBAL)

# Creates the staging target and arranges for the script to be written. Runs at
# most once per configure; every stage_file() call goes through it.
function(_stage_ensure)
    get_property(ready GLOBAL PROPERTY stage_ready)
    if(ready)
        return()
    endif()
    set_property(GLOBAL PROPERTY stage_ready TRUE)
    set_property(GLOBAL PROPERTY stage_lines "")

    # The command is fixed, so the target does not care that the script's
    # contents are decided later. It lands in whichever directory called
    # stage_file() first; that is invisible, since ALL propagates to the root
    # and add_dependencies works across directories.
    add_custom_target(stage_files ALL
        COMMAND ${CMAKE_COMMAND} -P "${CMAKE_BINARY_DIR}/stage-$<CONFIG>.cmake"
        COMMENT "staging data files for $<CONFIG>"
        VERBATIM)

    # Runs once the top-level directory has finished being processed, i.e. after
    # every add_subdirectory and so after every stage_file() call.
    cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL stage_finalize)
endfunction()

# Register one file to stage, and make <target> wait for the staging.
#
# The add_dependencies is not optional: ALL only puts stage_files in the default
# build, so `cmake --build . --target app-a` -- and VS's "only build startup
# project and dependencies on Run" -- would otherwise skip staging entirely and
# launch the app against a stale or missing file.
function(stage_file target src dst)
    _stage_ensure()

    set_property(GLOBAL APPEND PROPERTY stage_lines
        "get_filename_component(d [[${dst}]] DIRECTORY)"
        "file(MAKE_DIRECTORY \"\${d}\")"
        "file(COPY_FILE [[${src}]] [[${dst}]] ONLY_IF_DIFFERENT)")

    add_dependencies(${target} stage_files)
endfunction()

# Called automatically via cmake_language(DEFER); not part of the interface.
# file(GENERATE) evaluates the generator expressions per config and writes one
# script per config -- which is what it is good at, unlike doing the copying
# itself (it runs for all configs at once, so it cannot pick one source).
function(stage_finalize)
    get_property(lines GLOBAL PROPERTY stage_lines)
    list(JOIN lines "\n" content)
    file(GENERATE
        OUTPUT "${CMAKE_BINARY_DIR}/stage-$<CONFIG>.cmake"
        CONTENT "${content}\n")
endfunction()

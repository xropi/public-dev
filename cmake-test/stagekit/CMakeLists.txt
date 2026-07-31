# Variant 3: ONE staging target for a whole multi-project tree.
#
# always-run/ solves the config-switch staleness with a custom target per
# project. That does not scale to a large tree: a copy target littered next to
# every subproject, and one `cmake -E` process per file on every build.
#
# Here the tree has a single stage_files target. Subprojects create no targets
# and append no commands -- they only register (source, destination) pairs by
# calling stage_file(). See cmake/stagekit.cmake for why registration goes
# through a global property rather than a variable or an appended custom
# command; both of those alternatives fail across directory boundaries, one of
# them silently.
cmake_minimum_required(VERSION 3.21)  # file(COPY_FILE ... ONLY_IF_DIFFERENT)
project(ini-stagekit CXX)

set(CMAKE_CXX_STANDARD 20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(stagekit)

# Before the subprojects: creates the target, so they can depend on it.
stage_init()

add_subdirectory(proj-a)
add_subdirectory(proj-b)

# After them: every stage_file() call has run, so the script can be written.
stage_finalize()

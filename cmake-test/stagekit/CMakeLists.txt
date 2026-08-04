# Variant 3: ONE staging target for a whole multi-project tree.
#
# always-run/ solves the config-switch staleness with a custom target per
# project. That does not scale to a large tree: a copy target next to every
# subproject, and one `cmake -E` process per file on every build. Here the tree
# has a single stage_files target, and subprojects create no targets and append
# no commands -- they only call stage_file().
#
# Note what is NOT in this file: no include, no init, no finalize. The staging
# mechanism imposes nothing on the top level, so an add_subdirectory added below
# can never end up on the wrong side of a finalize call. See cmake/stagekit.cmake.
#
# Each subproject is also configurable on its own (cmake -B build -S proj-a),
# which is the normal mode for this monorepo's C++ projects, where every project
# is its own top level and pulls siblings in via add_subdirectory.
cmake_minimum_required(VERSION 3.26)  # -E copy_directory_if_different (D14)
project(ini-stagekit CXX)

set(CMAKE_CXX_STANDARD 20)

add_subdirectory(proj-a)
add_subdirectory(proj-b)

# A subproject stages a per-config ini into the binary root, exactly like
# output-rule/ -- but creates no target of its own to do it.
add_executable(app-a src/main.cpp)

set(dst "${CMAKE_BINARY_DIR}/x.ini")

# The only staging-related line a subproject writes. src carries the $<CONFIG>
# choice; stagekit defers evaluating it to generate time.
stage_file(
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/xd.ini,${CMAKE_CURRENT_SOURCE_DIR}/src/xr.ini>"
    "${dst}")

# Ordering only, so the copy cannot race the link. Unlike add_custom_command,
# add_dependencies works on a target created in another directory -- which is
# what lets one top-level staging target serve the whole tree.
add_dependencies(app-a stage_files)

target_compile_definitions(app-a PRIVATE INI_PATH="${dst}")

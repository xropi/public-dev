# A second subproject, staging a differently-named file into a subdirectory of
# the binary root -- the point being that it shares proj-a's staging target
# without either knowing about the other, and that stagekit creates the
# destination directory.
add_executable(app-b src/main.cpp)

set(dst "${CMAKE_BINARY_DIR}/data/cfg.txt")

stage_file(
    "$<IF:$<CONFIG:Debug>,${CMAKE_CURRENT_SOURCE_DIR}/src/cd.txt,${CMAKE_CURRENT_SOURCE_DIR}/src/cr.txt>"
    "${dst}")

add_dependencies(app-b stage_files)

target_compile_definitions(app-b PRIVATE INI_PATH="${dst}")

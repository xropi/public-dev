# One staging target for the whole tree.
#
# add_custom_command(TARGET ...) can only append to a target created in the SAME
# directory, so subprojects cannot add commands to a top-level target. The list
# of copies is therefore collected in a global property and materialised once,
# as a generated per-config script.
#
# That also fixes the cost problem: the naive form spawns one `cmake -E` process
# per file per build. Here every build runs exactly one `cmake -P`, whatever the
# file count.

include_guard(GLOBAL)

# Call once, at the top level, BEFORE add_subdirectory. The target must already
# exist when subprojects add_dependencies() onto it. Its command is fixed, so it
# does not care that the script's contents are decided later.
function(stage_init)
    set_property(GLOBAL PROPERTY stage_lines "")
    add_custom_target(stage_files ALL
        COMMAND ${CMAKE_COMMAND} -P "${CMAKE_BINARY_DIR}/stage-$<CONFIG>.cmake"
        COMMENT "staging data files for $<CONFIG>"
        VERBATIM)
endfunction()

# Call from anywhere, any directory. src may contain generator expressions
# (that is how a per-config source is selected); dst may too.
function(stage_file src dst)
    set_property(GLOBAL APPEND PROPERTY stage_lines
        "get_filename_component(d [[${dst}]] DIRECTORY)"
        "file(MAKE_DIRECTORY \"\${d}\")"
        "file(COPY_FILE [[${src}]] [[${dst}]] ONLY_IF_DIFFERENT)")
endfunction()

# Call once, at the top level, AFTER every add_subdirectory. file(GENERATE)
# evaluates the generator expressions per config and writes one script per
# config -- exactly the job it is good at, unlike copying the files itself.
function(stage_finalize)
    get_property(lines GLOBAL PROPERTY stage_lines)
    list(JOIN lines "\n" content)
    file(GENERATE
        OUTPUT "${CMAKE_BINARY_DIR}/stage-$<CONFIG>.cmake"
        CONTENT "${content}\n")
endfunction()

#[[[ @module ipxact
#]]

#[[[
# Provides the following function:
#
#   sv_to_ipxact(
#       TARGET      <target-name>          # name of the custom target created
#       SV_FILE     <path/to/module.sv>    # input SystemVerilog file
#       OUTDIR  <path/to/output/dir>   # where the .xml is written
#       VENDOR      <vendor-string>        # VLNV vendor
#       LIBRARY     <library-string>       # VLNV library
#       [VERSION    <version-string>]      # VLNV version (default: "1.0")
#   )
#
# The output file is named <module-name>.xml, where <module-name> is derived
# from the SV filename stem (the actual parsed module name is set by the script
# itself inside the XML).
#]]

set(_SV2IPXACT_DEFAULT_SCRIPT
    "${CMAKE_CURRENT_LIST_DIR}/sv2ipxact.py"
    CACHE FILEPATH "Default path to sv2ipxact.py"
)

function(sv2ipxact)
    cmake_parse_arguments(ARG "" "SV_FILE;OUTDIR;VENDOR;LIBRARY;VERSION" "" ${ARGN})

    foreach(_req SV_FILE VENDOR LIBRARY)
        if(NOT DEFINED ARG_${_req})
            message(FATAL_ERROR "sv_to_ipxact: missing required argument ${_req}")
        endif()
    endforeach()

    # Defaults
    if(NOT DEFINED ARG_VERSION)
        set(ARG_VERSION "1.0")
    endif()

    if(NOT ARG_OUTDIR)
        set(ARG_OUTDIR ${PROJECT_BINARY_DIR}/ipxact)
    endif()

    get_filename_component(_sv_abs   "${ARG_SV_FILE}"               ABSOLUTE)
    get_filename_component(_sv_stem  "${ARG_SV_FILE}"               NAME_WE)
    get_filename_component(_out_abs  "${ARG_OUTDIR}"                ABSOLUTE)
    get_filename_component(_tool_abs "${_SV2IPXACT_DEFAULT_SCRIPT}" ABSOLUTE)

    set(_xml_output "${_out_abs}/${_sv_stem}.xml")

    # Sanity checks
    if(NOT EXISTS "${_sv_abs}")
        message(FATAL_ERROR
            "sv_to_ipxact: SV_FILE not found:\n  ${_sv_abs}")
    endif()

    if(NOT EXISTS "${_tool_abs}")
        message(FATAL_ERROR "sv_to_ipxact: sv2ipxact.py not found at:\n  ${_tool_abs}\n")
    endif()

    file(MAKE_DIRECTORY "${_out_abs}")

    add_custom_command(
        OUTPUT  "${_xml_output}"
        COMMAND "${Python3_EXECUTABLE}"
                    "${_tool_abs}"
                    --input   "${_sv_abs}"
                    --output  "${_xml_output}"
                    --vendor  "${ARG_VENDOR}"
                    --library "${ARG_LIBRARY}"
                    --version "${ARG_VERSION}"
        DEPENDS
            "${_sv_abs}"
            "${_tool_abs}"
        COMMENT
            "[sv2ipxact] ${_sv_stem}.sv → ${_sv_stem}.xml  (${ARG_VENDOR}:${ARG_LIBRARY}:${_sv_stem}:${ARG_VERSION})"
        VERBATIM
    )

    add_custom_target("${ARG_VENDOR}_${ARG_LIBRARY}_${_sv_stem}_sv2ipxact" ALL
        DEPENDS "${_xml_output}"
    )

    set(SV2IPXACT_OUTPUT_FILE "${_xml_output}" PARENT_SCOPE)

    message(STATUS
        "[sv2ipxact] Registered target '${ARG_VENDOR}_${ARG_LIBRARY}_${_sv_stem}_sv2ipxact': "
        "${_sv_stem}.sv → ${_sv_stem}.xml")
endfunction()

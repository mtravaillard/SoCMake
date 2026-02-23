#[[[ @module vhier
#]]

#[[[
# This function use vhier, it is used to return all files in a verilog hierarchy using Verilog::Netlist.
# It creates a Makefile target to run vhier command.
#
# More information on vhier can be found on vhier man page.
#
# :param IP_LIB: target IP library.
# :type IP_LIB: string
#
# **Keyword Arguments**
#
# :keyword TOP_MODULE: if set, add --top-module ${IP_NAME} flags, that will start looking at the hierarchy by starting at the given top modules.
# :type TOP_MODULE: bool
# :keyword XML: if set, add --xml flags, that creates an output in xml format.
# :type XML: bool
# :keyword FILES: if set, add --module-files flags, that shows all module filenames, in a top-down order.
# :type FILES: bool
# :keyword MODULES: if set, add --modules flag, that shows all module names.
# :type MODULES: bool
# :keyword FOREST: if set, add --forest flags, that shows an "ASCII-art" hierarchy tree of all cells.
# :type FOREST: bool
#]]
function(vhier IP_LIB)
    cmake_parse_arguments(ARG "XML;FILES;MODULES;FOREST" "TOP_MODULE" "" ${ARGN})
    if(ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION} passed unrecognized argument " "${ARG_UNPARSED_ARGUMENTS}")
    endif()

    include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../hwip.cmake")
    alias_dereference(IP_LIB ${IP_LIB})

    get_target_property(IP_NAME ${IP_LIB} IP_NAME)

    get_ip_sources(RTL_SOURCES ${IP_LIB} SYSTEMVERILOG VERILOG)
    get_ip_include_directories(INCDIRS ${IP_LIB} SYSTEMVERILOG VERILOG)
    foreach(_i ${INCDIRS})
        set(INCDIR_ARG ${INCDIR_ARG} -y ${_i})
    endforeach()

    get_ip_compile_definitions(COMP_DEFS ${IP_LIB} SYSTEMVERILOG VERILOG)
    foreach(_d ${COMP_DEFS})
        set(COMPDEF_ARG ${COMPDEF_ARG} -D${_d})
    endforeach()

    find_program(VHIER_EXECUTABLE vhier)
    set(__CMD ${VHIER_EXECUTABLE}
        --top-module $<IF:$<BOOL:${ARG_TOP_MODULE}>,${ARG_TOP_MODULE},${IP_NAME}>
        ${RTL_SOURCES}
        ${INCDIR_ARG}
        ${COMPDEF_ARG}
        $<$<BOOL:${ARG_XML}>:--xml>
        $<$<BOOL:${ARG_FILES}>:--module-files>
        $<$<BOOL:${ARG_MODULES}>:--modules>
        $<$<BOOL:${ARG_FOREST}>:--forest>
    )

    set(DESCRIPTION "Extract verilog hierarchy of ${IP_LIB} with ${CMAKE_CURRENT_FUNCTION}")

    set(OUT_FILE ${CMAKE_BINARY_DIR}/${IP_LIB}_${CMAKE_CURRENT_FUNCTION}.$<IF:$<BOOL:${ARG_XML}>,xml,txt>)
    set(STAMP_FILE "${CMAKE_BINARY_DIR}/${IP_LIB}_${CMAKE_CURRENT_FUNCTION}.stamp")
    add_custom_command(
        OUTPUT ${STAMP_FILE} ${OUT_FILE}
        COMMAND touch ${STAMP_FILE}
        COMMAND ${__CMD} | tee ${OUT_FILE}
        DEPENDS ${RTL_SOURCES} ${IP_LIB}
        COMMENT ${DESCRIPTION}
    )

    add_custom_target(
        ${IP_LIB}_${CMAKE_CURRENT_FUNCTION}
        DEPENDS ${IP_LIB} ${STAMP_FILE} ${OUT_FILE}
    )

    set_property(TARGET ${IP_LIB}_${CMAKE_CURRENT_FUNCTION} PROPERTY DESCRIPTION ${DESCRIPTION})
endfunction()


#[[[ @module sed_wor
#]]

#[[[
# This function replace "wor" with "wire" in all Verilog/SystemVerilog files given. 
#
# This is a workaround for a Verilator not supporting "wor" and similar keywords.
#
# It will create a list called ``SED_WOR_SOURCES``, avaialble in the parent scope, that contains all the files, with the ones that needed to be modified.
#
# :param IP_LIB: target IP library.
# :type IP_LIB: string
# :param BINARY_DIR: Path were this function will generate the outputs file, in ${BINARY_DIR}/sed_wor.
# :type BINARY_DIR: string
# :param SOURCES: list of the sources, any file can be given, only the .v/.sv files will be copied and modified.
# :type SOURCES: list
#]]
function(sed_wor IP_LIB BINARY_DIR SOURCES)
    file(MAKE_DIRECTORY ${BINARY_DIR}/sed_wor)
    set(MODIFIED_SOURCES "")

    foreach(source ${SOURCES})
        get_filename_component(source_name ${source} NAME)
        if(source_name MATCHES "\\.(v|sv)$")
            set(output_file "${BINARY_DIR}/sed_wor/${source_name}")
            list(APPEND MODIFIED_SOURCES ${output_file}) 

            add_custom_command(
                OUTPUT ${output_file}
                # space after wor is important to avoid replacing words like "word"!
                COMMAND sed "s/wor /wire /g" ${source} > ${output_file}
                DEPENDS ${source}
                COMMENT "Replacing wor with wire in ${source_name}."
            )
        else()
            list(APPEND MODIFIED_SOURCES ${source})
        endif()
    endforeach()

    # Create stamp file for sed command
    set(STAMP_FILE "${BINARY_DIR}/sed_wor/${IP_LIB}_sed_wor.stamp")

    add_custom_command(
        OUTPUT ${STAMP_FILE}
        COMMAND /bin/sh -c date > ${STAMP_FILE}
        DEPENDS ${MODIFIED_SOURCES}
        COMMENT "Generating stamp file after sed commands."
    )

    if(NOT TARGET ${IP_LIB}_sed_wor)
        add_custom_target(
            ${IP_LIB}_sed_wor  
            DEPENDS ${STAMP_FILE}
        )

        add_dependencies(${IP_LIB}_sed_wor ${IP_LIB})

    endif()

    # Return modified sources
    set(SED_WOR_SOURCES ${MODIFIED_SOURCES} PARENT_SCOPE)
endfunction()

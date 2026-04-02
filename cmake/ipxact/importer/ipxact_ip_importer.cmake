#[[[ @module ipxact
#]]

#[[[
# This function import an IP-XACT .xml file and convert it to an SoCMake HWIP.
#
# ``xmlstarlet`` or ``xsltproc`` will be used, depending on the one found on your system,
# to extract the data coming from the .xml file.
#
# It will find the differents IPs, find the corresponding file and do the corresponding linking,
# everything will be stored in a Config.cmake file.
#
# :param COMP_XML: Path to the ipxact .xml file.
# :type COMP_XML: string
#
# **Keyword Arguments**
#
# :keyword IPXACT_STANDARD: Version of the IP-XACT standard used by the input file.
#     Supported values: ``2009``, ``2014``, ``2022``. Defaults to ``2022``.
#     If the standard is older than 2022, the Accellera migration XSLT scripts will
#     be applied to up-convert the file to 2022 before processing.
# :type IPXACT_STANDARD: string
# :keyword GENERATE_ONLY: If set, no Config.cmake file is generated, but the HWIP is still created and can be referenced in a parent scope (similar to a call to add_ip(), the IP variable is set to the parent scope).
# :type GENERATE_ONLY: bool
# :keyword IPXACT_SOURCE_DIR: path to be set has ${ip_vendor}__${ip_library}__${ip_name}__${ip_version}_IPXACT_SOURCE_DIR, if this argument is used.
# :type IPXACT_SOURCE_DIR: string
#]]
function(add_ip_from_ipxact COMP_XML)
    cmake_parse_arguments(ARG "GENERATE_ONLY" "IPXACT_SOURCE_DIR;IPXACT_STANDARD" "" ${ARGN})
    if(ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION} passed unrecognized argument " "${ARG_UNPARSED_ARGUMENTS}")
    endif()

    # Default standard is 2022
    if(NOT DEFINED ARG_IPXACT_STANDARD)
        set(ARG_IPXACT_STANDARD "2022")
    endif()

    if(NOT ARG_IPXACT_STANDARD STREQUAL "2009" AND
       NOT ARG_IPXACT_STANDARD STREQUAL "2014" AND
       NOT ARG_IPXACT_STANDARD STREQUAL "2022")
        message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: unsupported IPXACT_STANDARD value "
            "'${ARG_IPXACT_STANDARD}'. Supported values are: 2009, 2014, 2022.")
    endif()

    convert_paths_to_absolute(COMP_XML ${COMP_XML})

    find_program(xmlstarlet_EXECUTABLE xmlstarlet)
    if(xmlstarlet_EXECUTABLE)
        set(xml_command ${xmlstarlet_EXECUTABLE} tr)
    else()
        find_program(xsltproc_EXECUTABLE xsltproc REQUIRED)
        set(xml_command ${xsltproc_EXECUTABLE})
    endif()

    cmake_path(GET COMP_XML PARENT_PATH ip_source_dir)
    cmake_path(GET COMP_XML FILENAME file_name)
    cmake_path(GET COMP_XML STEM file_stem)

    # Up-convert the file to 2022 using Accellera migration scripts if needed
    set(XSLT_2009_TO_2014 "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/from1685_2009_to_1685_2014.xsl")
    set(XSLT_2014_TO_2022 "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/from1685_2014_to_1685_2022.xsl")

    # Work with a copy so we never modify the original file
    set(WORKING_XML "${COMP_XML}")

    if(ARG_IPXACT_STANDARD STREQUAL "2009")
        message(STATUS "IP-XACT: up-converting ${file_name} from 2009 → 2014 → 2022")

        # 2009 → 2014 (temp file)
        set(TMP_2014 "${CMAKE_CURRENT_BINARY_DIR}/${file_stem}_2014.xml")
        execute_process(
            COMMAND ${xml_command} "${XSLT_2009_TO_2014}" "${WORKING_XML}"
            OUTPUT_FILE "${TMP_2014}"
            RESULT_VARIABLE conv_result
        )
        if(NOT conv_result EQUAL 0)
            message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: conversion 2009→2014 failed for ${WORKING_XML}")
        endif()

        # 2014 → 2022
        set(CONVERTED_XML "${CMAKE_CURRENT_BINARY_DIR}/${file_stem}_2022.xml")
        execute_process(
            COMMAND ${xml_command} "${XSLT_2014_TO_2022}" "${TMP_2014}"
            OUTPUT_FILE "${CONVERTED_XML}"
            RESULT_VARIABLE conv_result
        )
        if(NOT conv_result EQUAL 0)
            message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: conversion 2014→2022 failed for ${TMP_2014}")
        endif()

        set(WORKING_XML "${CONVERTED_XML}")

    elseif(ARG_IPXACT_STANDARD STREQUAL "2014")
        message(STATUS "IP-XACT: up-converting ${file_name} from 2014 → 2022")

        set(CONVERTED_XML "${CMAKE_CURRENT_BINARY_DIR}/${file_stem}_2022.xml")
        execute_process(
            COMMAND ${xml_command} "${XSLT_2014_TO_2022}" "${WORKING_XML}"
            OUTPUT_FILE "${CONVERTED_XML}"
            RESULT_VARIABLE conv_result
        )
        if(NOT conv_result EQUAL 0)
            message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: conversion 2014→2022 failed for ${WORKING_XML}")
        endif()

        set(WORKING_XML "${CONVERTED_XML}")

    endif()

    execute_process(
        COMMAND ${xml_command} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/get_vlnv.xslt" "${WORKING_XML}"
        OUTPUT_VARIABLE vlnv_list)
    list(GET vlnv_list 0 ip_vendor)
    list(GET vlnv_list 1 ip_library)
    list(GET vlnv_list 2 ip_name)
    list(GET vlnv_list 3 ip_version)

    set(output_cmake_file ${ip_source_dir}/${ip_vendor}__${ip_library}__${ip_name}Config.cmake)


    execute_process(COMMAND ${xml_command} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/get_find_ips.xslt" ${WORKING_XML}
                    OUTPUT_VARIABLE find_ips
                )
    execute_process(COMMAND ${xml_command} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/ip_lib_with_filetype_modifier.xslt" ${WORKING_XML}
                OUTPUT_VARIABLE file_lists
            )

    execute_process(COMMAND ${xml_command} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/get_ip_links.xslt" ${WORKING_XML}
                OUTPUT_VARIABLE ip_links
            )

    # Always reference the *original* file_name in the generated cmake, not the temp file
    set(file_lists "${file_lists}\nip_sources(\${IP} IPXACT\n    \${CMAKE_CURRENT_LIST_DIR}/${file_name})\n\n")
    write_file(${output_cmake_file} ${find_ips} ${file_lists} ${ip_links})

    if(DEFINED ARG_IPXACT_SOURCE_DIR)
        set(${ip_vendor}__${ip_library}__${ip_name}__${ip_version}_IPXACT_SOURCE_DIR ${ARG_IPXACT_SOURCE_DIR})
    endif()
    if(NOT ARG_GENERATE_ONLY)
        include("${output_cmake_file}")
    endif()

    set(IP ${IP} PARENT_SCOPE)
endfunction()

#[[[ @module build_scripts
#]]

#[[[
# Build and install the SystemC library.
# It might not build a new SystemC library, if one is found using find_package() cmake function.
#
# **Keyword Arguments**
#
# :keyword VERSION: Version of the SystemC library that need to be built.
# :type VERSION: string
# :keyword EXACT_VERSION: If EXACT_VERSION is set, if a SystemC library is already built but not in this version, it will build a new one.
# :type EXACT_VERSION: bool
# :keyword INSTALL_DIR: Path to the location where the library will be installed, by default it's set to ${PROJECT_BINARY_DIR}/systemc, unless if FETCHCONTENT_BASE_DIR is set.
#]]
function(systemc_build)
    cmake_parse_arguments(ARG "EXACT_VERSION" "VERSION;INSTALL_DIR" "" ${ARGN})
    if(ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION} passed unrecognized argument " "${ARG_UNPARSED_ARGUMENTS}")
    endif()

    include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../utils/colours.cmake")

    unset(CMAKE_ARG_VERSION)
    if(ARG_VERSION)
        set(CMAKE_ARG_VERSION "-DVERSION=${ARG_VERSION}")
    endif()

    if(CMAKE_CXX_STANDARD)
        set(CMAKE_CXX_STANDARD_ARG "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}")
    endif()

    if(NOT ARG_INSTALL_DIR)
        if(FETCHCONTENT_BASE_DIR)
            set(ARG_INSTALL_DIR ${FETCHCONTENT_BASE_DIR}/systemc)
        else()
            set(ARG_INSTALL_DIR ${PROJECT_BINARY_DIR}/systemc)
        endif()
    endif()

    find_package(SystemCLanguage ${ARG_VERSION} CONFIG
        HINTS ${SYSTEMC_HOME} $ENV{SYSTEMC_HOME} ${ARG_INSTALL_DIR} 
        )

    if(ARG_EXACT_VERSION)
        if(NOT "${SystemCLanguage_VERSION_MAJOR}.${SystemCLanguage_VERSION_MINOR}.${SystemCLanguage_VERSION_PATCH}" STREQUAL ${ARG_VERSION})
            set(SystemCLanguage_FOUND FALSE)
        endif()
    endif()

    if(NOT SystemCLanguage_FOUND)
        message(STATUS "${Magenta}[SystemC Not Found]${ColourReset}")
        message(STATUS "${Magenta}[Building SystemC]${ColourReset}")
        execute_process(COMMAND ${CMAKE_COMMAND}
            -S ${CMAKE_CURRENT_FUNCTION_LIST_DIR}
            -B ${CMAKE_BINARY_DIR}/systemc-build 
            ${CMAKE_ARG_VERSION}
            ${CMAKE_CXX_STANDARD_ARG}
            -DCMAKE_INSTALL_PREFIX=${ARG_INSTALL_DIR}
            -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
            COMMAND_ECHO STDOUT
            )

        execute_process(COMMAND ${CMAKE_COMMAND}
                --build ${CMAKE_BINARY_DIR}/systemc-build
                --parallel
            )
    endif()

    find_package(SystemCLanguage ${ARG_VERSION} CONFIG REQUIRED
        HINTS ${ARG_INSTALL_DIR}
        )

    message(STATUS "${Green}[Found SystemC]${ColourReset}: ${SystemCLanguage_VERSION} in ${SystemCLanguage_DIR}")

endfunction()

#[[[ @module build_scripts
#]]

#[[[
# Build and install the UVM-SystemC library.
# It might not build a new SystemC library, if one is found using find_package() cmake function.
#
# **Keyword Arguments**
#
# :keyword VERSION: Version of the UVM-SystemC library that need to be built.
# :type VERSION: string
# :keyword EXACT_VERSION: If EXACT_VERSION is set, if a UVM-SystemC library is already built but not in this version, it will build a new one.
# :type EXACT_VERSION: bool
# :keyword INSTALL_DIR: Path to the location where the library will be installed, by default it's set to ${PROJECT_BINARY_DIR}/uvm-systemc, unless if FETCHCONTENT_BASE_DIR is set.
#]]
function(uvm_systemc_build)
    cmake_parse_arguments(ARG "EXACT_VERSION" "VERSION;INSTALL_DIR" "" ${ARGN})
    if(ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION} passed unrecognized argument " "${ARG_UNPARSED_ARGUMENTS}")
    endif()

    include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../utils/colours.cmake")

    unset(CMAKE_ARG_VERSION)
    if(ARG_VERSION)
        set(CMAKE_ARG_VERSION "-DVERSION=${ARG_VERSION}")
    endif()

    if(NOT ARG_INSTALL_DIR)
        if(FETCHCONTENT_BASE_DIR)
            set(ARG_INSTALL_DIR ${FETCHCONTENT_BASE_DIR}/uvm-systemc)
        else()
            set(ARG_INSTALL_DIR ${PROJECT_BINARY_DIR}/uvm-systemc)
        endif()
    endif()

    # TODO ARG_VERSION cannot be used as its not following major.minor.patch
    find_package(UVM-SystemC CONFIG
        HINTS ${UVM_SYSTEMC_HOME} $ENV{UVM_SYSTEMC_HOME} ${ARG_INSTALL_DIR}
    )
    get_target_property(SYSTEMC_INC_DIR SystemC::systemc INTERFACE_INCLUDE_DIRECTORIES)
    set(SYSTEMC_HOME "${SYSTEMC_INC_DIR}/../")

    if(NOT SystemCLanguage_DIR)
        message(FATAL_ERROR "Please provide SystemC library using \"systemc_build()\" or \"find_package()\" ")
    endif()

    if(NOT UVM-SystemC_FOUND)
        message(STATUS "${Magenta}[UVM-SystemC Not Found]${ColourReset}")
        message(STATUS "${Magenta}[Building UVM-SystemC]${ColourReset}")
        execute_process(COMMAND ${CMAKE_COMMAND}
            -S ${CMAKE_CURRENT_FUNCTION_LIST_DIR}
            -B ${CMAKE_BINARY_DIR}/uvm-systemc-build
            ${CMAKE_ARG_VERSION}
            -DSYSTEMC_HOME=${SYSTEMC_HOME}
            -DCMAKE_INSTALL_PREFIX=${ARG_INSTALL_DIR}
            COMMAND_ECHO STDOUT
            )

        execute_process(COMMAND ${CMAKE_COMMAND}
                --build ${CMAKE_BINARY_DIR}/uvm-systemc-build
                --parallel ${CMAKE_BUILD_PARALLEL_LEVEL}
                --target install
            )
    endif()

    find_package(UVM-SystemC CONFIG REQUIRED
        HINTS ${ARG_INSTALL_DIR}
        )

    message(STATUS "${Green}[Found UVM-SystemC]${ColourReset}: ${UVM-SystemC_VERSION} in ${UVM-SystemC_DIR}")

endfunction()

cmake_minimum_required(VERSION 3.28)
project(example CXX C)

include("../../SoCMakeConfig.cmake")

add_subdirectory(adder)

verilator_build(VERSION 5.012 EXACT_VERSION)

verilator(adder TRACE)

add_executable(testbench main.cpp)

target_link_libraries(testbench adder)

help(PRINT_ON_CONF)

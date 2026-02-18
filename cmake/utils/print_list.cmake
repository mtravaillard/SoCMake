#[[[ @module print_list
#]]

include_guard(GLOBAL)

#[[[
# To Update
#]]
macro(print_list LIST)
    foreach(item ${LIST})
        message(${item})
    endforeach()
endmacro()

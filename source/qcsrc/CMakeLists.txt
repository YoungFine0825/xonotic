# ============================================================================
# QuakeC 游戏代码模块（Windows / Linux）
# 目标 gamecode 生成 source/csprogs.dat、source/menu.dat、source/progs.dat
#（与现有 qcsrc/Makefile 的 PROGS_OUT=.. 默认输出一致）。
# 构建方式：cmake --build <构建目录> --target gamecode
#   - Windows：tools/qcc.ps1（gcc 预处理，回退 MSVC cl /E）
#   - Linux：调用仓库自带 qcsrc/Makefile（tools/qcc.sh，需要 make/bash/gcc）
# ============================================================================

project(xonotic-qcsrc LANGUAGES C)

if(NOT XONOTIC_BUILD_GMQCC OR NOT TARGET gmqcc)
    message(STATUS "qcsrc：需要先启用并构建 gmqcc，跳过 gamecode 目标")
    return()
endif()

# 版本水印（对应 Makefile 的 QCCFLAGS_WATERMARK；仓库无 tag 时回退到短提交号）
execute_process(
    COMMAND git describe --tags --dirty=~
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    RESULT_VARIABLE _wm_res
    OUTPUT_VARIABLE QCSRC_WATERMARK
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(NOT _wm_res EQUAL 0 OR QCSRC_WATERMARK STREQUAL "")
    execute_process(
        COMMAND git rev-parse --short HEAD
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        RESULT_VARIABLE _wm_res2
        OUTPUT_VARIABLE QCSRC_WATERMARK
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
endif()
if(NOT _wm_res2 EQUAL 0 OR QCSRC_WATERMARK STREQUAL "")
    set(QCSRC_WATERMARK "-")
endif()

set(QCSRC_OUT "${CMAKE_SOURCE_DIR}/source")

if(WIN32)
    # ---- Windows：PowerShell 预处理脚本 + gmqcc -----------------------------
    find_program(POWERSHELL_EXE NAMES powershell pwsh)
    if(NOT POWERSHELL_EXE)
        message(STATUS "qcsrc：未找到 PowerShell，跳过 gamecode 目标")
        return()
    endif()

    # 全部 QC 源文件作为依赖（unity 构建，任一文件变化即重编）
    file(GLOB_RECURSE QCSRC_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/*.qc"
        "${CMAKE_CURRENT_SOURCE_DIR}/*.qh"
        "${CMAKE_CURRENT_SOURCE_DIR}/*.inc")

    set(QCC_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/tools/qcc.ps1")

    # 游戏代码预处理优先使用 GCC 风格的预处理器（与上游 qcc.sh 完全一致，
    # 可正确处理宏参数内的条件指令、反斜杠续行等）；找不到时回退到 MSVC cl /E。
    find_program(XONOTIC_QC_CPP NAMES gcc cc clang)
    if(XONOTIC_QC_CPP)
        set(_qc_cpp "${XONOTIC_QC_CPP}")
    else()
        set(_qc_cpp "${CMAKE_C_COMPILER}")
    endif()

    foreach(_unit client menu server)
        if(_unit STREQUAL "client")
            set(_mode client)
            set(_inc client/progs.inc)
            set(_dat csprogs.dat)
        elseif(_unit STREQUAL "menu")
            set(_mode menu)
            set(_inc menu/progs.inc)
            set(_dat menu.dat)
        else()
            set(_mode server)
            set(_inc server/progs.inc)
            set(_dat progs.dat)
        endif()

        add_custom_command(
            OUTPUT "${QCSRC_OUT}/${_dat}"
            COMMAND ${POWERSHELL_EXE} -NoProfile -ExecutionPolicy Bypass
                -File "${QCC_SCRIPT}"
                -Cpp "${_qc_cpp}"
                -Qcc "$<TARGET_FILE:gmqcc>"
                -Mode ${_mode}
                -In "${CMAKE_CURRENT_SOURCE_DIR}/${_inc}"
                -Out "${QCSRC_OUT}/${_dat}"
                -WorkDir "${CMAKE_CURRENT_BINARY_DIR}/.tmp"
                -Include "${CMAKE_CURRENT_SOURCE_DIR}"
                -Watermark "${QCSRC_WATERMARK}"
            DEPENDS ${QCSRC_SOURCES} gmqcc
            COMMENT "编译 QuakeC ${_mode} 代码 -> source/${_dat}"
            VERBATIM)
    endforeach()
    unset(_unit)
    unset(_mode)
    unset(_inc)
    unset(_dat)

    add_custom_target(gamecode
        DEPENDS
            "${QCSRC_OUT}/csprogs.dat"
            "${QCSRC_OUT}/menu.dat"
            "${QCSRC_OUT}/progs.dat")
else()
    # ---- Linux/类 Unix：调用仓库自带 qcsrc/Makefile（tools/qcc.sh）---------
    find_program(XONOTIC_MAKE NAMES make gmake)
    find_program(XONOTIC_BASH NAMES bash)
    if(NOT XONOTIC_MAKE OR NOT XONOTIC_BASH)
        message(STATUS "qcsrc：构建 gamecode 需要 make 与 bash，跳过")
        return()
    endif()

    add_custom_target(gamecode
        COMMAND ${XONOTIC_MAKE} -C "${CMAKE_CURRENT_SOURCE_DIR}" qc
            QCC="$<TARGET_FILE:gmqcc>"
            PROGS_OUT=${QCSRC_OUT}
            QCCFLAGS_WATERMARK=${QCSRC_WATERMARK}
        DEPENDS gmqcc
        COMMENT "编译 QuakeC 游戏代码 -> source/*.dat（qcsrc/Makefile）")
endif()

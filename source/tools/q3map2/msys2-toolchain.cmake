# ============================================================================
# MSYS2 / MinGW64 工具链（Windows 上编译 q3map2 等工具用）
#
# 由 CMakePresets.json 的 "msys2" 预设通过 CMAKE_TOOLCHAIN_FILE 引用。
# 所有路径均来自环境变量 MSYS2_ROOT（不写死绝对路径）。
# ============================================================================

if(NOT DEFINED ENV{MSYS2_ROOT} OR "$ENV{MSYS2_ROOT}" STREQUAL "")
    message(FATAL_ERROR
        "MSYS2 工具链需要设置环境变量 MSYS2_ROOT"
        "（PowerShell: $env:MSYS2_ROOT='D:\\msys64'）")
endif()

set(_msys2_root "$ENV{MSYS2_ROOT}")
string(REPLACE "\\" "/" _msys2_root "${_msys2_root}")

set(CMAKE_SYSTEM_NAME Windows)

set(CMAKE_C_COMPILER "${_msys2_root}/mingw64/bin/gcc.exe")
set(CMAKE_CXX_COMPILER "${_msys2_root}/mingw64/bin/g++.exe")
# 生成器读取 CMAKE_MAKE_PROGRAM 时需要 cache 变量
set(CMAKE_MAKE_PROGRAM "${_msys2_root}/mingw64/bin/mingw32-make.exe"
    CACHE FILEPATH "MSYS2 make" FORCE)
set(PKG_CONFIG_EXECUTABLE "${_msys2_root}/mingw64/bin/pkgconf.exe"
    CACHE FILEPATH "MSYS2 pkgconf" FORCE)

# configure 阶段让 MSYS2 工具可用（gcc 依赖的 DLL 在 mingw64/bin）；
# 构建阶段（cmake --build）由调用方终端提供 PATH（见 BUILDING.md）。
set(ENV{PATH} "${_msys2_root}/mingw64/bin;$ENV{PATH}")

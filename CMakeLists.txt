# ============================================================================
# Xonotic 模块化 CMake 构建体系
#
# 目标平台：Windows（默认 MSVC）+ vcpkg（依赖声明见 vcpkg.json；
# vcpkg 根目录由环境变量 VCPKG_ROOT 指定，不写死绝对路径）
# 产物布局：
#   - 可执行文件与项目自身 DLL  -> 仓库根目录
#   - 第三方 vcpkg DLL          -> 根目录 bin32 / bin64（按目标架构）
#
# 快速开始（x64 Release）：
#   cmake --preset msvc-x64
#   cmake --build --preset msvc-x64
#   cmake --build build/msvc-x64 --target gamecode   # 可选：编译 QuakeC 游戏代码
# ============================================================================

cmake_minimum_required(VERSION 3.21)

# --- vcpkg 工具链（未显式指定时自动探测） ------------------------------------
if(WIN32 AND NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    if(DEFINED ENV{VCPKG_ROOT} AND NOT "$ENV{VCPKG_ROOT}" STREQUAL "")
        set(_vcpkg_root "$ENV{VCPKG_ROOT}")
        if(EXISTS "${_vcpkg_root}/scripts/buildsystems/vcpkg.cmake")
            set(CMAKE_TOOLCHAIN_FILE
                "${_vcpkg_root}/scripts/buildsystems/vcpkg.cmake"
                CACHE FILEPATH "vcpkg 工具链（来自 VCPKG_ROOT 环境变量）")
        endif()
        unset(_vcpkg_root)
    else()
        message(WARNING
            "未设置 VCPKG_ROOT 环境变量，未自动加载 vcpkg 工具链。"
            "请先设置（PowerShell: $env:VCPKG_ROOT='<vcpkg路径>'）"
            "或显式指定 -DCMAKE_TOOLCHAIN_FILE=...")
    endif()
endif()

project(xonotic LANGUAGES C CXX)

# --- 模块开关 -----------------------------------------------------------------
option(XONOTIC_BUILD_ENGINE        "构建 DarkPlaces 引擎（SDL 客户端 + 专用服务器）" ON)
option(XONOTIC_BUILD_GMQCC         "构建 gmqcc QuakeC 编译器" ON)
option(XONOTIC_BUILD_D0_BLIND_ID   "构建 d0_blind_id 加密库（引擎运行时加载）" ON)
option(XONOTIC_BUILD_GAMECODE      "提供 QuakeC 游戏代码构建目标（需 gmqcc 与 PowerShell）" ON)

option(XONOTIC_COPY_THIRDPARTY_DLLS "将 vcpkg 的第三方 DLL 复制到根目录 bin32/bin64" ON)
option(XONOTIC_COPY_ALL_VCPKG_DLLS
    "复制 vcpkg 三元组 bin 目录中的全部 DLL（默认 OFF：只复制并按引擎查找名重命名所需 DLL，对齐官方发布版）" OFF)

# --- 引擎特性 -----------------------------------------------------------------
option(XONOTIC_ENGINE_CD            "CD 音频支持 (CONFIG_CD)" ON)
option(XONOTIC_ENGINE_VIDEO_CAPTURE "视频捕获支持 (CONFIG_VIDEO_CAPTURE)" ON)
option(XONOTIC_ENGINE_ZLIB_SHARED   "直接链接 zlib（默认关闭：运行时 dlopen zlib1.dll）" OFF)
option(XONOTIC_ENGINE_JPEG_SHARED   "直接链接 libjpeg（默认关闭：运行时 dlopen libjpeg.dll）" OFF)
option(XONOTIC_ENGINE_CRYPTO_SHARED "直接链接 d0_blind_id（默认关闭：运行时 dlopen）" OFF)

set(XONOTIC_D0_BIGNUM_BACKEND "auto"
    CACHE STRING "d0_blind_id 大数后端：auto|gmp|tommath|openssl")
set_property(CACHE XONOTIC_D0_BIGNUM_BACKEND PROPERTY STRINGS auto gmp tommath openssl)

# --- 平台约束 -----------------------------------------------------------------
if(WIN32 AND NOT MSVC)
    message(WARNING
        "Windows 平台默认应使用 MSVC 编译（Visual Studio 生成器）。"
        "当前编译器：${CMAKE_C_COMPILER_ID}")
endif()

# --- 输出目录布局 ---------------------------------------------------------------
# 可执行文件与项目自身 DLL 输出到仓库根目录；中间产物留在构建目录。
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_PDB_OUTPUT_DIRECTORY     "${CMAKE_BINARY_DIR}/pdb")
foreach(_cfg DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${_cfg} "${CMAKE_SOURCE_DIR}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${_cfg} "${CMAKE_BINARY_DIR}/lib")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${_cfg} "${CMAKE_BINARY_DIR}/lib")
    set(CMAKE_PDB_OUTPUT_DIRECTORY_${_cfg}     "${CMAKE_BINARY_DIR}/pdb")
endforeach()
unset(_cfg)

# --- 工具链细节 -------------------------------------------------------------------
# MSVC 统一使用动态 CRT（/MD、/MDd），与 vcpkg 预编译库保持一致。
set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "MSVC 运行时库（保持与 vcpkg 一致）")

# --- 子模块 -------------------------------------------------------------------------
if(XONOTIC_BUILD_D0_BLIND_ID)
    add_subdirectory(source/d0_blind_id)
endif()

if(XONOTIC_BUILD_ENGINE)
    add_subdirectory(source/darkplaces)
endif()

if(XONOTIC_BUILD_GMQCC)
    add_subdirectory(source/gmqcc)
endif()

if(XONOTIC_BUILD_GAMECODE)
    add_subdirectory(source/qcsrc)
endif()

# q3map2 —— Xonotic 标准地图编译工具（bsp/vis/light/minimap）
# 源文件清单与 NetRadiant-YF/tools/quake3/CMakeLists.txt 的 radiant_tool(q3map2 ...) 一致。

set(Q3MAP2_COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../common")
set(Q3MAP2_LIBS_DIR   "${CMAKE_CURRENT_SOURCE_DIR}/../libs")
set(Q3MAP2_VERSION "2.5.17n")

# ---- Windows 工具链选择 ------------------------------------------------------
# auto：MSVC 构建用 MSVC（vcpkg 依赖），其余（MSYS2/MinGW、Linux）用 pkg-config
# msvc：强制 MSVC + vcpkg；msys2：强制 MSYS2/MinGW + pkg-config
set(XONOTIC_Q3MAP2_TOOLCHAIN "auto" CACHE STRING
    "Windows 平台 q3map2 工具链：auto | msvc | msys2（MSYS2 根目录由环境变量 MSYS2_ROOT 指定）")
set_property(CACHE XONOTIC_Q3MAP2_TOOLCHAIN PROPERTY STRINGS auto msvc msys2)

if(XONOTIC_Q3MAP2_TOOLCHAIN STREQUAL "auto")
    if(MSVC)
        set(_q3map2_toolchain "msvc")
    else()
        set(_q3map2_toolchain "msys2")
    endif()
else()
    set(_q3map2_toolchain "${XONOTIC_Q3MAP2_TOOLCHAIN}")
endif()

# ---- 系统依赖 -----------------------------------------------------------------
if(_q3map2_toolchain STREQUAL "msvc")
    # Windows（vcpkg）：优先使用 vcpkg 提供的 CMake config 包
    find_package(JPEG REQUIRED)
    find_package(PNG REQUIRED)
    find_package(LibXml2 REQUIRED)
    find_package(WebP CONFIG REQUIRED)
    # minizip：优先新版 config 包，回退旧版 unofficial-minizip
    find_package(minizip CONFIG QUIET)
    if(minizip_FOUND)
        if(TARGET MINIZIP::minizip)
            set(Q3MAP2_MINIZIP_TARGET "MINIZIP::minizip")
        else()
            set(Q3MAP2_MINIZIP_TARGET "MINIZIP::minizipstatic")
        endif()
    else()
        find_package(unofficial-minizip CONFIG REQUIRED)
        set(Q3MAP2_MINIZIP_TARGET "unofficial::minizip::minizip")
    endif()
    # GLib 无官方 config，走 pkg-config（vcpkg 提供 pkgconf 端口）
    if(DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
        find_program(PKG_CONFIG_EXECUTABLE NAMES pkg-config pkgconf
            HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/tools/pkgconf")
    endif()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(Q3MAP2_GLIB REQUIRED IMPORTED_TARGET glib-2.0)
else()
    # MSYS2/MinGW 或 Linux：pkg-config（MSYS2 用 mingw64 的包，Linux 用系统包）
    if(WIN32)
        # MSYS2 根目录来自环境变量 MSYS2_ROOT（不写死绝对路径）
        if(NOT DEFINED ENV{MSYS2_ROOT} OR "$ENV{MSYS2_ROOT}" STREQUAL "")
            message(FATAL_ERROR
                "XONOTIC_Q3MAP2_TOOLCHAIN=msys2 需要设置环境变量 MSYS2_ROOT"
                "（如 $env:MSYS2_ROOT='D:\\msys64'）")
        endif()
        set(_msys2_root "$ENV{MSYS2_ROOT}")
        string(REPLACE "\\" "/" _msys2_root "${_msys2_root}")
        find_program(PKG_CONFIG_EXECUTABLE NAMES pkg-config pkgconf
            HINTS "${_msys2_root}/mingw64/bin")
        set(ENV{PKG_CONFIG_PATH} "${_msys2_root}/mingw64/lib/pkgconfig")
    endif()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(Q3MAP2_GLIB REQUIRED IMPORTED_TARGET glib-2.0)
    pkg_check_modules(Q3MAP2_WEBP REQUIRED IMPORTED_TARGET libwebp)
    pkg_check_modules(Q3MAP2_MINIZIP REQUIRED IMPORTED_TARGET minizip)
    pkg_check_modules(Q3MAP2_JPEG REQUIRED IMPORTED_TARGET libjpeg)
    pkg_check_modules(Q3MAP2_PNG REQUIRED IMPORTED_TARGET libpng16)
    pkg_check_modules(Q3MAP2_XML REQUIRED IMPORTED_TARGET libxml-2.0)
endif()

# ---- 源文件 -------------------------------------------------------------------
set(Q3MAP2_SOURCES
    "${Q3MAP2_COMMON_DIR}/cmdlib.c"
    "${Q3MAP2_COMMON_DIR}/imagelib.c"
    "${Q3MAP2_COMMON_DIR}/inout.c"
    "${Q3MAP2_COMMON_DIR}/jpeg.c"
    "${Q3MAP2_COMMON_DIR}/md4.c"
    "${Q3MAP2_COMMON_DIR}/mutex.c"
    "${Q3MAP2_COMMON_DIR}/polylib.c"
    "${Q3MAP2_COMMON_DIR}/scriplib.c"
    "${Q3MAP2_COMMON_DIR}/threads.c"
    "${Q3MAP2_COMMON_DIR}/vfs.c"
    brush.c brush_primit.c bsp.c bsp_analyze.c bsp_info.c bsp_scale.c
    bspfile_abstract.c bspfile_ibsp.c bspfile_rbsp.c convert_ase.c
    convert_bsp.c convert_gltf.c convert_map.c convert_obj.c decals.c exportents.c
    facebsp.c fixaas.c fog.c help.c image.c leakfile.c light.c
    light_bounce.c light_trace.c light_ydnar.c lightmaps_ydnar.c main.c
    map.c mesh.c minimap.c model.c patch.c path_init.c portals.c prtfile.c
    shaders.c surface.c surface_extra.c surface_foliage.c surface_fur.c
    surface_meta.c tjunction.c tree.c vis.c visflow.c writebsp.c)

add_executable(q3map2 ${Q3MAP2_SOURCES})

target_include_directories(q3map2 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${Q3MAP2_COMMON_DIR}"
    "${Q3MAP2_LIBS_DIR}"
    "${Q3MAP2_LIBS_DIR}/cgltf"
    "${Q3MAP2_LIBS_DIR}/crnrgba"
    ${Q3MAP2_GLIB_INCLUDE_DIRS}
    ${Q3MAP2_WEBP_INCLUDE_DIRS}
    ${Q3MAP2_MINIZIP_INCLUDE_DIRS})

# 新版 vfs.c 使用 <minizip/unzip.h>（带前缀），需要 include 根的父目录
if(Q3MAP2_MINIZIP_INCLUDE_DIRS)
    get_filename_component(_minizip_parent "${Q3MAP2_MINIZIP_INCLUDE_DIRS}" DIRECTORY)
    target_include_directories(q3map2 PRIVATE "${_minizip_parent}")
endif()

target_compile_definitions(q3map2 PRIVATE
    RADIANT_NAME="NetRadiant"
    RADIANT_VERSION="1.5.0"
    Q3MAP_VERSION="${Q3MAP2_VERSION}")

target_link_libraries(q3map2 PRIVATE
    q3map2_mathlib
    q3map2_ddslib
    q3map2_crnrgba
    q3map2_etclib
    q3map2_filematch
    q3map2_l_net
    q3map2_picomodel)

if(_q3map2_toolchain STREQUAL "msvc")
    target_sources(q3map2 PRIVATE q3map2.rc)
    target_link_libraries(q3map2 PRIVATE
        JPEG::JPEG
        PNG::PNG
        LibXml2::LibXml2
        WebP::webp
        ${Q3MAP2_MINIZIP_TARGET}
        PkgConfig::Q3MAP2_GLIB
        ws2_32)
else()
    target_link_libraries(q3map2 PRIVATE
        PkgConfig::Q3MAP2_JPEG
        PkgConfig::Q3MAP2_PNG
        PkgConfig::Q3MAP2_XML
        PkgConfig::Q3MAP2_GLIB
        PkgConfig::Q3MAP2_WEBP
        PkgConfig::Q3MAP2_MINIZIP)
    if(WIN32)
        # MSYS2/MinGW 是 Windows 目标：winsock 与运行时库
        target_link_libraries(q3map2 PRIVATE ws2_32)
    else()
        target_link_libraries(q3map2 PRIVATE m pthread)
    endif()
endif()

message(STATUS "q3map2：地图编译工具（bsp/vis/light）版本 ${Q3MAP2_VERSION}（工具链 ${_q3map2_toolchain}）")

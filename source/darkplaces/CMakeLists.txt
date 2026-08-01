# ============================================================================
# DarkPlaces 引擎模块（Windows / Linux）
# 源文件清单与 makefile.inc 保持一致：
#   - SDL 客户端：OBJ_SDL（sys_sdl / vid_sdl / snd_sdl / cd_sdl / 菜单 / 视频捕获）
#   - 专用服务器：OBJ_SV（sys_linux / vid_null / thread_null / snd_null）
# Windows 使用 MSVC + vcpkg；Linux 使用系统包（SDL2 通过 pkg-config 查找）。
# 其他平台请继续使用仓库自带 Makefile。
# ============================================================================

if(WIN32)
    include("${CMAKE_SOURCE_DIR}/cmake/XonoticThirdPartyDlls.cmake")
    find_package(SDL2 CONFIG REQUIRED)
elseif(UNIX AND NOT APPLE)
    message(STATUS "darkplaces：Linux 构建（SDL 客户端 + 专用服务器，系统包管理）")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(DP_SDL2 REQUIRED IMPORTED_TARGET sdl2)
else()
    message(STATUS
        "darkplaces：此平台请使用 source/darkplaces/Makefile 构建")
    return()
endif()

set(DP_SRC "${CMAKE_CURRENT_SOURCE_DIR}")

# ---- 公共源文件（对应 makefile.inc 的 OBJ_COMMON）-------------------------
set(DP_COMMON_SOURCES
    bih.c crypto.c cl_collision.c cl_demo.c cl_dyntexture.c cl_input.c
    cl_main.c cl_parse.c cl_particles.c cl_screen.c cl_video.c clvm_cmds.c
    cmd.c collision.c common.c console.c csprogs.c curves.c cvar.c
    dpsoftrast.c dpvsimpledecode.c filematch.c fractalnoise.c fs.c ft2.c
    utf8lib.c gl_backend.c gl_draw.c gl_rmain.c gl_rsurf.c gl_textures.c
    hmac.c host.c host_cmd.c image.c image_png.c jpeg.c keys.c lhnet.c
    libcurl.c mathlib.c matrixlib.c mdfour.c meshqueue.c
    mod_skeletal_animatevertices_sse.c mod_skeletal_animatevertices_generic.c
    model_alias.c model_brush.c model_shared.c model_sprite.c netconn.c
    palette.c polygon.c portals.c protocol.c prvm_cmds.c prvm_edict.c
    prvm_exec.c r_explosion.c r_lerpanim.c r_lightning.c r_modules.c
    r_shadow.c r_sky.c r_sprites.c sbar.c sv_demo.c sv_main.c sv_move.c
    sv_phys.c sv_user.c svbsp.c svvm_cmds.c sys_shared.c vid_shared.c view.c
    wad.c world.c zone.c)
list(TRANSFORM DP_COMMON_SOURCES PREPEND "${DP_SRC}/")

# ---- 平台公共定义 -----------------------------------------------------------
set(DP_PLATFORM_DEFS
    _FILE_OFFSET_BITS=64
    __KERNEL_STRICT_NAMES)
if(WIN32)
    list(APPEND DP_PLATFORM_DEFS
        WIN32
        $<$<EQUAL:${CMAKE_SIZEOF_VOID_P},8>:WIN64>
        _CRT_SECURE_NO_WARNINGS)
endif()

# 客户端特性定义（对应 Makefile 的 CFLAGS_CLIENT；服务器目标不携带）
set(DP_CLIENT_FEATURE_DEFS
    CONFIG_MENU
    $<$<BOOL:${XONOTIC_ENGINE_CD}>:CONFIG_CD>
    $<$<BOOL:${XONOTIC_ENGINE_VIDEO_CAPTURE}>:CONFIG_VIDEO_CAPTURE>)

# 与上游 Makefile 一致：客户端与服务器分别编译整套公共对象，
# 因为 netconn.c / prvm_exec.c 等文件的行为依赖 CONFIG_MENU 等定义。
add_library(dp_engine_common_client OBJECT ${DP_COMMON_SOURCES})
add_library(dp_engine_common_server  OBJECT ${DP_COMMON_SOURCES})
foreach(_lib dp_engine_common_client dp_engine_common_server)
    target_include_directories(${_lib} PRIVATE "${DP_SRC}")
    target_compile_definitions(${_lib} PRIVATE ${DP_PLATFORM_DEFS})
endforeach()
unset(_lib)
target_compile_definitions(dp_engine_common_client PRIVATE ${DP_CLIENT_FEATURE_DEFS})

# 上游 OPTIM_RELEASE 含 -fno-strict-aliasing（GCC/Clang）
if(NOT MSVC)
    target_compile_options(dp_engine_common_client PRIVATE -fno-strict-aliasing)
    target_compile_options(dp_engine_common_server  PRIVATE -fno-strict-aliasing)
endif()

# ---- 可选链接的第三方库（默认运行时 dlopen）--------------------------------
set(DP_EXTRA_LIBS)

if(XONOTIC_ENGINE_ZLIB_SHARED)
    target_compile_definitions(dp_engine_common_client PRIVATE LINK_TO_ZLIB)
    target_compile_definitions(dp_engine_common_server  PRIVATE LINK_TO_ZLIB)
    find_library(DP_ZLIB_LIBRARY NAMES zlib z
        HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
    if(DP_ZLIB_LIBRARY)
        list(APPEND DP_EXTRA_LIBS "${DP_ZLIB_LIBRARY}")
    else()
        message(WARNING "XONOTIC_ENGINE_ZLIB_SHARED=ON 但未找到 zlib 库")
    endif()
endif()

if(XONOTIC_ENGINE_JPEG_SHARED)
    target_compile_definitions(dp_engine_common_client PRIVATE LINK_TO_LIBJPEG)
    target_compile_definitions(dp_engine_common_server  PRIVATE LINK_TO_LIBJPEG)
    find_library(DP_JPEG_LIBRARY NAMES jpeg libjpeg jpeg62
        HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
    if(DP_JPEG_LIBRARY)
        list(APPEND DP_EXTRA_LIBS "${DP_JPEG_LIBRARY}")
    else()
        message(WARNING "XONOTIC_ENGINE_JPEG_SHARED=ON 但未找到 libjpeg 库")
    endif()
endif()

if(XONOTIC_ENGINE_CRYPTO_SHARED)
    target_compile_definitions(dp_engine_common_client PRIVATE
        LINK_TO_CRYPTO LINK_TO_CRYPTO_RIJNDAEL)
    target_compile_definitions(dp_engine_common_server PRIVATE
        LINK_TO_CRYPTO LINK_TO_CRYPTO_RIJNDAEL)
    target_include_directories(dp_engine_common_client PRIVATE "${CMAKE_SOURCE_DIR}/source")
    target_include_directories(dp_engine_common_server  PRIVATE "${CMAKE_SOURCE_DIR}/source")
    if(TARGET d0_blind_id AND TARGET d0_rijndael)
        list(APPEND DP_EXTRA_LIBS d0_blind_id d0_rijndael)
    else()
        message(WARNING "XONOTIC_ENGINE_CRYPTO_SHARED=ON 但 d0_blind_id 未构建")
    endif()
endif()

# ---- 版本戳（builddate.c 使用，与 Makefile 的 SVNREVISION/BUILDTYPE 对应）----
execute_process(
    COMMAND git describe --always
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    RESULT_VARIABLE _git_res
    OUTPUT_VARIABLE _git_rev
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(NOT _git_res EQUAL 0 OR _git_rev STREQUAL "")
    set(_git_rev "-")
endif()

set(DP_BUILDDATE_DEFS SVNREVISION=${_git_rev} BUILDTYPE=release)

# ---- SDL 客户端（对应 OBJ_SDL）-----------------------------------------------
set(DP_CLIENT_SOURCES
    builddate.c sys_sdl.c vid_sdl.c thread_sdl.c
    menu.c mvm_cmds.c
    snd_main.c snd_mem.c snd_mix.c snd_ogg.c snd_wav.c snd_sdl.c
    cd_shared.c cd_sdl.c
    cap_avi.c cap_ogg.c)
list(TRANSFORM DP_CLIENT_SOURCES PREPEND "${DP_SRC}/")

set(DP_CLIENT_EXTRA)
if(WIN32)
    list(APPEND DP_CLIENT_EXTRA "${DP_SRC}/darkplaces.rc")
endif()

add_executable(xonotic-local-sdl
    ${DP_CLIENT_SOURCES} ${DP_CLIENT_EXTRA}
    $<TARGET_OBJECTS:dp_engine_common_client>)
target_compile_definitions(xonotic-local-sdl PRIVATE
    ${DP_PLATFORM_DEFS}
    ${DP_CLIENT_FEATURE_DEFS}
    ${DP_BUILDDATE_DEFS})

if(WIN32)
    set_target_properties(xonotic-local-sdl PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_libraries(xonotic-local-sdl PRIVATE
        SDL2::SDL2 ${DP_EXTRA_LIBS} winmm ws2_32
        kernel32 user32 gdi32 winspool comdlg32 advapi32
        shell32 ole32 oleaut32 uuid)
    # SDL2main 由 sys_sdl.c 的 #pragma comment 引用，vcpkg 将其放在 lib/manual-link
    if(DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
        set(_dp_sdl2_manual_link
            "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib/manual-link")
        if(EXISTS "${_dp_sdl2_manual_link}")
            target_link_directories(xonotic-local-sdl PRIVATE "${_dp_sdl2_manual_link}")
        endif()
    endif()
    xonotic_copy_thirdparty_dlls(xonotic-local-sdl)
else()
    target_link_libraries(xonotic-local-sdl PRIVATE
        PkgConfig::DP_SDL2 ${DP_EXTRA_LIBS} m dl rt pthread)
endif()

# ---- 专用服务器（对应 OBJ_SV）--------------------------------------------------
set(DP_SERVER_SOURCES
    builddate.c sys_linux.c vid_null.c thread_null.c snd_null.c)
list(TRANSFORM DP_SERVER_SOURCES PREPEND "${DP_SRC}/")

add_executable(xonotic-local-dedicated
    ${DP_SERVER_SOURCES} $<TARGET_OBJECTS:dp_engine_common_server>)
target_compile_definitions(xonotic-local-dedicated PRIVATE
    ${DP_PLATFORM_DEFS} ${DP_BUILDDATE_DEFS})

if(WIN32)
    target_link_libraries(xonotic-local-dedicated PRIVATE
        ${DP_EXTRA_LIBS} winmm ws2_32
        kernel32 user32 gdi32 winspool comdlg32 advapi32
        shell32 ole32 oleaut32 uuid)
    xonotic_copy_thirdparty_dlls(xonotic-local-dedicated)
else()
    target_link_libraries(xonotic-local-dedicated PRIVATE
        ${DP_EXTRA_LIBS} m dl rt pthread)
endif()

# 上游 OPTIM_RELEASE 对全部文件启用 -fno-strict-aliasing（GCC/Clang）
if(NOT MSVC)
    target_compile_options(xonotic-local-sdl PRIVATE -fno-strict-aliasing)
    target_compile_options(xonotic-local-dedicated PRIVATE -fno-strict-aliasing)
endif()

message(STATUS "darkplaces：SDL 客户端 -> xonotic-local-sdl，服务器 -> xonotic-local-dedicated")

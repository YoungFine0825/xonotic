# 将 vcpkg 提供的第三方 DLL 复制到仓库根目录的 bin32 / bin64（按目标架构）。
# 用法：xonotic_copy_thirdparty_dlls(<目标名>)
#
# 默认（XONOTIC_COPY_ALL_VCPKG_DLLS=OFF）只复制引擎实际需要的 DLL，
# 并按引擎运行时查找名（Sys_LoadLibrary）重命名，以对齐官方发布版：
#   jpeg62.dll    -> libjpeg.dll       （引擎查找 libjpeg.dll）
#   freetype.dll  -> libfreetype-6.dll （引擎查找 libfreetype-6.dll）
# 设置 XONOTIC_COPY_ALL_VCPKG_DLLS=ON 可改为全量复制 vcpkg bin 目录。
function(xonotic_copy_thirdparty_dlls target)
    if(NOT XONOTIC_COPY_THIRDPARTY_DLLS OR NOT WIN32)
        return()
    endif()

    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(_dll_dest "${CMAKE_SOURCE_DIR}/bin64")
    else()
        set(_dll_dest "${CMAKE_SOURCE_DIR}/bin32")
    endif()

    set(_vcpkg_bin "")
    if(DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
        set(_vcpkg_bin "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/bin")
    endif()
    if(NOT _vcpkg_bin OR NOT EXISTS "${_vcpkg_bin}")
        message(STATUS
            "[${target}] 未检测到 vcpkg 安装目录（${_vcpkg_bin}），跳过第三方 DLL 复制")
        return()
    endif()

    if(XONOTIC_COPY_ALL_VCPKG_DLLS)
        file(GLOB _dlls "${_vcpkg_bin}/*.dll")
    else()
        # 成对的“源 DLL 名;目标 DLL 名”，对应引擎 Sys_LoadLibrary 的查找名单
        set(_dll_map
            "SDL2.dll" "SDL2.dll"
            "zlib1.dll" "zlib1.dll"
            "mpir.dll" "mpir.dll"
            "libpng16.dll" "libpng16.dll"
            "ogg.dll" "libogg.dll"
            "ogg.dll" "ogg.dll"
            "vorbis.dll" "libvorbis.dll"
            "vorbis.dll" "vorbis.dll"
            "vorbisenc.dll" "libvorbisenc.dll"
            "vorbisfile.dll" "libvorbisfile.dll"
            "theora.dll" "libtheora-0.dll"
            "libcurl.dll" "libcurl-4.dll"
            "jpeg62.dll" "libjpeg.dll"
            "freetype.dll" "libfreetype-6.dll")
        list(LENGTH _dll_map _map_n)
        math(EXPR _map_last "${_map_n} - 1")
        set(_dlls "")
        set(_dll_dests "")
        foreach(_i RANGE 0 ${_map_last} 2)
            list(GET _dll_map ${_i} _src)
            math(EXPR _j "${_i} + 1")
            list(GET _dll_map ${_j} _dst)
            if(EXISTS "${_vcpkg_bin}/${_src}")
                list(APPEND _dlls "${_vcpkg_bin}/${_src}")
                list(APPEND _dll_dests "${_dll_dest}/${_dst}")
            endif()
        endforeach()
    endif()

    if(NOT _dlls)
        return()
    endif()

    set(_copy_cmds "")
    if(XONOTIC_COPY_ALL_VCPKG_DLLS)
        list(APPEND _copy_cmds
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_dll_dest}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_dlls} "${_dll_dest}")
    else()
        list(LENGTH _dlls _n)
        math(EXPR _last "${_n} - 1")
        foreach(_i RANGE 0 ${_last})
            list(GET _dlls ${_i} _src)
            list(GET _dll_dests ${_i} _dst)
            list(APPEND _copy_cmds
                COMMAND ${CMAKE_COMMAND} -E make_directory "${_dll_dest}"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_src}" "${_dst}")
        endforeach()
    endif()

    add_custom_command(TARGET ${target} POST_BUILD ${_copy_cmds}
        COMMENT "复制/对齐第三方 DLL 到 ${_dll_dest}")
endfunction()

# ============================================================================
# d0_blind_id 加密库模块（Windows / Linux）
# 产物命名与引擎 crypto.c 运行时加载名一致：
#   - Windows：libd0_blind_id-0.dll / libd0_rijndael-0.dll
#   - Linux：  libd0_blind_id.so.0 / libd0_rijndael.so.0（含 .so 符号链接）
# 大数后端通过 XONOTIC_D0_BIGNUM_BACKEND 选择：auto | gmp | tommath | openssl
# 依赖来源：Windows 走 vcpkg（VCPKG_INSTALLED_DIR），Linux 走系统包。
# ============================================================================

project(d0_blind_id LANGUAGES C)

if(MSVC)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

set(_vcpkg_prefix "")
if(DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
    set(_vcpkg_prefix "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}")
endif()

# ---- 大数后端自动探测（优先上游默认的 GMP）--------------------------------
set(_backend "${XONOTIC_D0_BIGNUM_BACKEND}")
if(_backend STREQUAL "auto")
    find_path(D0_GMP_INCLUDE_DIR gmp.h HINTS "${_vcpkg_prefix}/include")
    if(D0_GMP_INCLUDE_DIR)
        set(_backend "gmp")
    else()
        find_path(D0_TOMMATH_INCLUDE_DIR tommath.h HINTS "${_vcpkg_prefix}/include")
        if(D0_TOMMATH_INCLUDE_DIR)
            set(_backend "tommath")
        else()
            find_path(D0_OPENSSL_INCLUDE_DIR openssl/bn.h HINTS "${_vcpkg_prefix}/include")
            if(D0_OPENSSL_INCLUDE_DIR)
                set(_backend "openssl")
            endif()
        endif()
    endif()
endif()

set(D0_BIGNUM_SRC "")
set(D0_BIGNUM_DEFS "")
set(D0_BIGNUM_LIBS "")
set(D0_BIGNUM_INCLUDE "")

if(_backend STREQUAL "gmp")
    set(D0_BIGNUM_SRC d0_bignum-gmp.c)
    find_library(D0_GMP_LIBRARY NAMES gmp mpir
        HINTS "${_vcpkg_prefix}/lib")
    if(NOT D0_GMP_LIBRARY)
        message(FATAL_ERROR
            "d0_blind_id：选择 gmp 后端但未找到 gmp/mpir 库。"
            "Windows 请用 vcpkg 安装 mpir；Linux 请安装 libgmp-dev")
    endif()
    set(D0_BIGNUM_LIBS "${D0_GMP_LIBRARY}")
    set(D0_BIGNUM_INCLUDE "${D0_GMP_INCLUDE_DIR}")
elseif(_backend STREQUAL "tommath")
    set(D0_BIGNUM_SRC d0_bignum-tommath.c)
    set(D0_BIGNUM_DEFS TOMMATH)
    find_library(D0_TOMMATH_LIBRARY NAMES tommath
        HINTS "${_vcpkg_prefix}/lib")
    if(NOT D0_TOMMATH_LIBRARY)
        message(FATAL_ERROR
            "d0_blind_id：选择 tommath 后端但未找到 libtommath 库")
    endif()
    set(D0_BIGNUM_LIBS "${D0_TOMMATH_LIBRARY}")
    set(D0_BIGNUM_INCLUDE "${D0_TOMMATH_INCLUDE_DIR}")
elseif(_backend STREQUAL "openssl")
    set(D0_BIGNUM_SRC d0_bignum-openssl.c)
    find_package(OpenSSL REQUIRED)
    set(D0_BIGNUM_LIBS OpenSSL::Crypto)
else()
    message(STATUS
        "d0_blind_id：未找到可用的 bignum 后端"
        "（gmp/libtommath/openssl），跳过本模块")
    return()
endif()

# ---- 库目标 -----------------------------------------------------------------
add_library(d0_blind_id SHARED
    d0_blind_id.c d0.c d0_iobuf.c sha2.c "${D0_BIGNUM_SRC}")
target_compile_definitions(d0_blind_id PRIVATE D0_BUILDING_DLL ${D0_BIGNUM_DEFS})
target_include_directories(d0_blind_id PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${D0_BIGNUM_INCLUDE}"
    "${_vcpkg_prefix}/include")
target_link_libraries(d0_blind_id PRIVATE ${D0_BIGNUM_LIBS})

if(WIN32)
    target_compile_definitions(d0_blind_id PRIVATE
        WIN32
        $<$<EQUAL:${CMAKE_SIZEOF_VOID_P},8>:WIN64>)
    # sha2.c 要求 BYTE_ORDER 已定义；Windows x86/x64 均为小端
    target_compile_definitions(d0_blind_id PRIVATE
        BYTE_ORDER=LITTLE_ENDIAN
        LITTLE_ENDIAN=1234
        BIG_ENDIAN=4321)
    set_target_properties(d0_blind_id PROPERTIES OUTPUT_NAME "libd0_blind_id-0")
else()
    set_target_properties(d0_blind_id PROPERTIES
        OUTPUT_NAME "libd0_blind_id"
        VERSION "0.0.0"
        SOVERSION "0")
endif()

add_library(d0_rijndael SHARED d0_rijndael.c)
target_compile_definitions(d0_rijndael PRIVATE D0_BUILDING_DLL)
target_include_directories(d0_rijndael PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${_vcpkg_prefix}/include")
if(WIN32)
    target_compile_definitions(d0_rijndael PRIVATE
        WIN32
        $<$<EQUAL:${CMAKE_SIZEOF_VOID_P},8>:WIN64>)
    set_target_properties(d0_rijndael PROPERTIES OUTPUT_NAME "libd0_rijndael-0")
else()
    set_target_properties(d0_rijndael PROPERTIES
        OUTPUT_NAME "libd0_rijndael"
        VERSION "0.0.0"
        SOVERSION "0")
endif()

message(STATUS "d0_blind_id：bignum 后端 = ${_backend}")

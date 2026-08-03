# q3map2 依赖的轻量静态库（从 NetRadiant-YF/libs 提取的子集）

set(Q3MAP2_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

add_library(q3map2_mathlib STATIC
    mathlib/bbox.c
    mathlib/line.c
    mathlib/m4x4.c
    mathlib/mathlib.c
    mathlib/ray.c)

add_library(q3map2_ddslib STATIC ddslib/ddslib.c)

# CRN 纹理解码（新版 q3map2 无条件使用；crunch 为 header-only 库）
add_library(q3map2_crnrgba STATIC crnrgba/crn_rgba.cpp)
target_include_directories(q3map2_crnrgba PRIVATE
    "${Q3MAP2_LIBS_DIR}/crunch")
target_link_libraries(q3map2_crnrgba PUBLIC q3map2_ddslib)
if(MSVC)
    target_compile_options(q3map2_crnrgba PRIVATE /EHsc)
else()
    target_compile_options(q3map2_crnrgba PRIVATE -fexceptions)
endif()

add_library(q3map2_etclib STATIC etclib.c)

add_library(q3map2_filematch STATIC filematch.c)

add_library(q3map2_l_net STATIC l_net/l_net.c)

add_library(q3map2_picomodel STATIC
    picomodel/picointernal.c
    picomodel/picomodel.c
    picomodel/picomodules.c
    picomodel/pm_3ds.c
    picomodel/pm_ase.c
    picomodel/pm_fm.c
    picomodel/pm_iqm.c
    picomodel/pm_lwo.c
    picomodel/pm_md2.c
    picomodel/pm_md3.c
    picomodel/pm_mdc.c
    picomodel/pm_ms3d.c
    picomodel/pm_obj.c
    picomodel/pm_terrain.c
    picomodel/lwo/clip.c
    picomodel/lwo/envelope.c
    picomodel/lwo/list.c
    picomodel/lwo/lwio.c
    picomodel/lwo/lwo2.c
    picomodel/lwo/lwob.c
    picomodel/lwo/pntspols.c
    picomodel/lwo/surface.c
    picomodel/lwo/vecmath.c
    picomodel/lwo/vmap.c)

foreach(_lib
        q3map2_mathlib q3map2_ddslib q3map2_etclib
        q3map2_filematch q3map2_l_net q3map2_picomodel)
    target_include_directories(${_lib} PUBLIC "${Q3MAP2_LIBS_DIR}")
endforeach()
unset(_lib)

if(WIN32)
    target_sources(q3map2_l_net PRIVATE l_net/l_net_wins.c l_net/l_net_wins.h)
    target_link_libraries(q3map2_l_net PUBLIC ws2_32)
else()
    target_sources(q3map2_l_net PRIVATE l_net/l_net_berkley.c)
endif()

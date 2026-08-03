# ============================================================================
# 地图编译工具（q3map2，提取自 NetRadiant-YF/tools/quake3）
# 通过顶层选项 XONOTIC_BUILD_Q3MAP2 启用（默认 OFF）。
# 依赖：Windows 走 vcpkg（见 vcpkg.json 的 q3map2 feature）；
#       Linux 走系统包（见 BUILDING.md）。
# ============================================================================

if(NOT XONOTIC_BUILD_Q3MAP2)
    return()
endif()

add_subdirectory(libs)
add_subdirectory(q3map2)

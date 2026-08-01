# BUILDING 构建指南

本文档说明如何用 CMake 在 Windows 上构建本仓库（引擎、gmqcc、加密库与游戏代码）。

## 1. 前置要求

- Windows 10/11，Visual Studio 2022（勾选“使用 C++ 的桌面开发”，提供 MSVC）
- CMake ≥ 3.21
- Git
- vcpkg（依赖由仓库根目录 `vcpkg.json` 声明，配置阶段自动安装）

## 2. 设置 VCPKG_ROOT 环境变量

构建配置不包含 vcpkg 的绝对路径，请用环境变量 `VCPKG_ROOT` 指向 vcpkg 根目录。
PowerShell 中（当前会话）：

```powershell
$env:VCPKG_ROOT = "C:\path\to\vcpkg"   # 替换为你的 vcpkg 根目录
```

需要永久生效可执行 `setx VCPKG_ROOT "C:\path\to\vcpkg"`（新开终端生效）。

## 3. 第三方依赖（vcpkg.json）

依赖全部声明在根目录 `vcpkg.json`，版本基线由 `vcpkg-configuration.json` 固定，
配置阶段自动安装到构建目录下的 `vcpkg_installed`，不影响全局 vcpkg 安装。

| 包 | 用途 |
|---|---|
| sdl2 | 窗口、输入、音频（客户端） |
| zlib | pk3 解压 |
| mpir | d0_blind_id 大数后端（GMP 兼容；`auto` 检测到 gmp.h 即选用） |
| libjpeg-turbo | JPEG 贴图 |
| libpng | PNG 贴图 |
| libogg / libvorbis / libtheora | OGG 音频与录像编码 |
| curl（schannel 特性） | 主服务器查询、下载（Windows 原生 TLS，无额外 DLL） |
| freetype（仅 zlib 特性） | 字体渲染 |

## 4. 配置（x64，默认）

```powershell
cmake --preset msvc-x64
```

首次配置会按 `vcpkg.json` 自动安装依赖，耗时较长；之后的增量配置很快。

## 5. 构建

```powershell
cmake --build --preset msvc-x64
```

该命令构建引擎（客户端 + 专用服务器）、gmqcc 与 d0_blind_id 加密库。

构建 QuakeC 游戏代码（可选）：

```powershell
cmake --build build/msvc-x64 --target gamecode
```

游戏代码预处理优先使用 PATH 中的 `gcc`（与上游流程一致）；没有 gcc 时自动回退到
MSVC 的 `cl /E`。

## 6. 第三方 DLL 对齐官方发布版

引擎在运行时通过 `Sys_LoadLibrary` 按固定名称加载这些库（查找目录为根目录
`bin64`/`bin32`）。构建后会自动把 vcpkg 产出的 DLL 复制到对应目录，并按引擎
查找名重命名，与官方 0.8.6 发布版的 bin 目录对齐：

| vcpkg 产物 | 复制后的名称 | 用途 |
|---|---|---|
| SDL2.dll | SDL2.dll | 客户端加载期依赖（同时复制一份到可执行文件旁） |
| zlib1.dll | zlib1.dll | pk3 解压 |
| mpir.dll | mpir.dll | d0_blind_id 大数后端 |
| jpeg62.dll | libjpeg.dll | JPEG 贴图 |
| libpng16.dll | libpng16.dll | PNG 贴图 |
| ogg.dll | libogg.dll + ogg.dll | OGG 流（保留原名副本供 vorbis/theora 依赖） |
| vorbis.dll | libvorbis.dll + vorbis.dll | OGG 音频（保留原名副本） |
| vorbisenc.dll | libvorbisenc.dll | OGG 音频编码 |
| vorbisfile.dll | libvorbisfile.dll | OGG 文件读取 |
| theora.dll | libtheora-0.dll | 录像编码 |
| libcurl.dll | libcurl-4.dll | 主服务器查询、下载 |
| freetype.dll | libfreetype-6.dll | 字体渲染 |

说明：

- `ogg.dll`、`vorbis.dll` 需要保留原名副本，因为 vcpkg 的 vorbis/theora DLL
  导入表按原名引用它们；重命名副本用于引擎直接加载。
- 引擎自身的 `libd0_blind_id-0.dll`、`libd0_rijndael-0.dll` 输出到仓库根目录，
  引擎会从可执行文件所在目录加载。
- 设置 `-DXONOTIC_COPY_ALL_VCPKG_DLLS=ON` 可改为全量复制 vcpkg bin 目录
  （会包含引擎不需要的 DLL，且不做重命名）。

## 7. 产物布局

- 可执行文件与项目自身 DLL：仓库根目录
  （`xonotic-local-sdl.exe`、`xonotic-local-dedicated.exe`、`gmqcc.exe`、
  `libd0_blind_id-0.dll`、`libd0_rijndael-0.dll`）
- 第三方 DLL：根目录 `bin64`（x64）或 `bin32`（x86），见第 6 节
- 游戏代码：`source/csprogs.dat`、`source/menu.dat`、`source/progs.dat`

## 8. x86 构建

```powershell
cmake --preset msvc-x86
cmake --build --preset msvc-x86
```

依赖同样由 `vcpkg.json` 自动按 `x86-windows` 三元组安装，DLL 输出到 `bin32`。

## 9. 常用配置选项

- `XONOTIC_BUILD_ENGINE` / `XONOTIC_BUILD_GMQCC` / `XONOTIC_BUILD_D0_BLIND_ID` /
  `XONOTIC_BUILD_GAMECODE`：模块开关（默认 ON）
- `XONOTIC_D0_BIGNUM_BACKEND`：d0_blind_id 大数后端，`auto`（默认）/ `gmp` /
  `tommath` / `openssl`
- `XONOTIC_ENGINE_ZLIB_SHARED`、`XONOTIC_ENGINE_JPEG_SHARED`、
  `XONOTIC_ENGINE_CRYPTO_SHARED`：直接链接对应库（默认运行时 dlopen）
- `XONOTIC_COPY_THIRDPARTY_DLLS`：是否复制第三方 DLL 到 bin32/bin64（默认 ON）
- `XONOTIC_COPY_ALL_VCPKG_DLLS`：全量复制 vcpkg bin 目录（默认 OFF，见第 6 节）

示例：

```powershell
cmake --preset msvc-x64 -DXONOTIC_ENGINE_ZLIB_SHARED=ON
```

## 10. 运行

- 专用服务器：根目录下运行 `xonotic-local-dedicated.exe`
- 客户端：根目录下运行 `xonotic-local-sdl.exe`。SDL2.dll 是加载期依赖，
  CMake 会将其自动复制到可执行文件旁；`bin64` 中同时保留一份副本

## 11. 常见问题

- **`VCPKG_ROOT` 未设置**：CMake 会输出警告且不自动加载 vcpkg 工具链，
  请先按第 2 节设置。
- **bin64/bin32 残留旧 DLL**：早期配置可能复制过不再需要的 DLL，可手动
  删除目录内容后重新构建；对齐复制只新增/覆盖，不会自动清理。
- **首次配置很慢**：vcpkg 需要下载并构建依赖，属正常现象；依赖已安装后
  的重新配置只需数秒。

## 12. 非 Windows 平台

当前 CMake 模块面向 Windows；其他平台请使用各模块自带的 Makefile
（如 `make -C source/darkplaces`、`make -C source/qcsrc`）。

# 仓库指南

## 项目结构与模块组织

- `source/darkplaces/` — DarkPlaces 引擎（C 语言）：客户端与专用服务器二进制。
- `source/qcsrc/` — 用 QuakeC 编写的游戏逻辑与菜单；构建 `progs.dat`、`csprogs.dat`、`menu.dat`。
- `source/gmqcc/` — QuakeC 编译器（C++）及其回归测试套件。
- `source/d0_blind_id/`、`source/rcon2irc/` — 加密辅助库与 IRC 中继机器人。
- `server/` — 服务器启动脚本（`server_linux.sh`、`server_windows.bat`）、`server.cfg` 及管理工具。
- `docs/` — 地图制作、地图下载、FAQ 与玩法指南。
- `misc/` — 构建辅助（`buildsrc/`）、logo 与维护工具。

## 构建、测试与开发命令

Windows 下优先使用仓库根目录的模块化 CMake 构建（MSVC + vcpkg）：

- `cmake --preset msvc-x64` — 配置 x64 工程（Visual Studio 2022；vcpkg 根目录由环境变量 `VCPKG_ROOT` 指定，依赖由 `vcpkg.json` 声明）。
- `cmake --build --preset msvc-x64` — 构建引擎（`xonotic-local-sdl`、`xonotic-local-dedicated`）、gmqcc 与 d0_blind_id。
- `cmake --build build/msvc-x64 --target gamecode` — 编译 QuakeC 游戏代码，输出 `source/csprogs.dat`、`source/menu.dat`、`source/progs.dat`。
- 可执行文件与项目自身 DLL 输出到仓库根目录；第三方 DLL 输出到根目录 `bin64`（x64）或 `bin32`（x86）。
- x86 构建使用 `cmake --preset msvc-x86`（需先安装对应三元组依赖，如 `vcpkg install sdl2:x86-windows`）。

原有 Makefile 方式（`make -C source/darkplaces` 等）仍适用于非 Windows 平台。

顶层 `Makefile` 仅用于 stable 与 autobuild 发布树，在 git 检出中会直接报错。检出源码时应分别构建各组件：

- `make -C source/darkplaces` — 引擎；发布目标为 `sv-release`、`cl-release`、`sdl-release`，另有 `*-debug` 变体。
- `make -C source/gmqcc` 与 `make -C source/gmqcc test` — 编译器及其测试套件。
- `make -C source/qcsrc` — 游戏代码（`qc`、`sv`、`pk3`）；`make -C source/qcsrc test` 运行编译测试。
- `make client` / `make server` / `make both` — 仅限发布树构建。

搭建专用服务器时，将 `server/server_*` 复制到 Xonotic 根目录，并把 `server.cfg` 放入用户数据目录（Linux 下为 `~/.xonotic/data`）。

## 编码风格与命名约定

- QuakeC 与引擎 C 均使用 Tab 缩进、LF 换行、UTF-8 编码（见 `source/qcsrc/.editorconfig`）。
- 使用 `uncrustify -c source/qcsrc/uncrustify.cfg` 格式化 QuakeC 代码。
- 函数与变量使用小写 `snake_case`，文件名同样小写（如 `animdecide_load_if_needed`）。
- 游戏代码以 `-Wall -Werror` 编译，提交前须消除所有警告。

## 测试指南

- `gmqcc` 回归测试位于 `source/gmqcc/tests/`，为 `.qc`/`.tmpl` 配对文件；运行 `make -C source/gmqcc test`。
- `qcsrc` 编译测试通过 `make -C source/qcsrc test` 运行。
- 引擎没有单元测试套件；请构建 release 与 debug 目标，并在本地启动客户端/服务器进行验证。
- 测试文件以其覆盖的功能命名（`arrays.qc`、`bitnot.qc`）。

## 提交与合并请求指南

当前 Git 历史仅包含最初的导入提交，尚无仓库内约定。请遵循上游 Xonotic 的做法：使用简短祈使句标题，可附作用域前缀（如 `qcsrc: fix bot waypoint reset`），正文说明改动内容与原因。合并请求需描述改动、关联相关问题、说明测试方式，UI 或菜单改动应附截图。

## 安全与配置提示

`server.cfg` 包含 rcon 密码与服务器端口（默认 26000）；切勿提交机密信息，本地覆盖配置应保留在仓库之外。公开服务器需在防火墙开放 UDP 26000，自定义地图分发参见 `docs/mapdownload.txt`。

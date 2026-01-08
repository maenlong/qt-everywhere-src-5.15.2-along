# Qt5.15.2 Windows x86 (32-bit) 构建 — 合并脚本与配置文件说明

文件说明
- `qt-build.ini`         : 所有构建变量与说明的配置文件（可编辑）。
- `build-qt5-win32.bat`  : 单个合并脚本，根据 `qt-build.ini` 执行 `configure` -> `nmake` -> `nmake install`。
- `README-qt5-build.md`  : 本说明（你现在看到的文件）。

快速开始
1. 把三文件放在一起（建议放在 `qt-everywhere-src-5.15.2` 同级目录或任意你喜欢的位置）。
2. 编辑 `qt-build.ini`，把 `QT_SRC`、`VS_VCVARS`、`INSTALL_DIR` 等变量改为你的实际路径。
3. 在 Visual Studio 2017 的 Developer Command Prompt 中运行（确保已加载 VS 环境）：
   - **完整构建**（默认，清理并重新构建）：
     `build-qt5-win32.bat`
   - **仅继续编译**（不清理，用于报错修复后继续）：
     `build-qt5-win32.bat build`
   - **仅安装**：
     `build-qt5-win32.bat install`
   - **仅清理**：
     `build-qt5-win32.bat clean`
   - **指定配置文件与操作**：
     `build-qt5-win32.bat my.ini build`
4. 运行过程中，脚本会**弹出独立的 PowerShell 窗口**实时显示构建日志（支持颜色高亮）。
   主窗口将保持响应。日志文件保存在构建目录下：
   - `configure-output.txt`
   - `build-output.txt`
   - `install-output.txt`

主要改动（相对于早期版本）
- **实时日志窗口**：不再通过管道传输日志（避免环境损坏和 `locale.h` 丢失），而是启动独立的 PowerShell 窗口实时监控日志文件，并对 Error/Warning 进行颜色高亮。
- **操作参数支持**：支持 `build`、`install`、`clean`、`configure` 等参数，方便在编译出错后修复并继续编译，无需每次重新 configure。
- 已移除对 `jom` 的自动使用与 `JOM_PATH` 配置，构建工具统一为 Visual Studio 自带的 `nmake`。
- 脚本会在开始时调用 `vcvarsall.bat`（由 `VS_VCVARS` 指定），因此请保证该路径指向 VS2017 的 `vcvarsall.bat`。
- 与并行构建相关的逻辑已简化（脚本仍会设置并行线程数变量 `MAKE_JOBS`，但实际构建使用 `nmake`）。

常见配置项说明（节选）
- `BUILD_TYPE`：
  - `shared` : 构建动态库（默认）
  - `static` : 构建静态库
- `USE_STATIC_RUNTIME`（仅对 static 生效）：
  - `0` : 使用动态 CRT (`/MD`)
  - `1` : 使用静态 CRT (`/MT`)
  注意：`/MT` 可能影响第三方库兼容性，且静态链接 Qt 在 LGPL 下有合规性要求（请确认许可）。
- `SKIP_QTWEBENGINE`：
  - `1` : 跳过 qtwebengine（推荐，节省时间和磁盘）
  - `0` : 包含 qtwebengine（需先准备 depot_tools、Chromium 依赖等）
- `PERL_PATH` / `PYTHON_PATH`：
  - 若你的 perl/python 未加入系统 PATH，可在 ini 中指定目录（脚本会把它们 prepend 到 `PATH`）。
- `VS_VCVARS`：
  - 必填。指向 VS2017 的 `vcvarsall.bat`，脚本会调用以确保 `cl`、`link`、`nmake` 等工具可用。

关于 qtwebengine
- QtWebEngine 会把构建复杂度和磁盘占用大幅度提升（Chromium 源码、`depot_tools`、`ninja`、`gn`、`clang` 等）。
- 若要包含 qtwebengine：
  - 把 `SKIP_QTWEBENGINE` 设为 `0`。
  - 先准备 `depot_tools`，并将其加入 `PATH`。
  - 确保 Python 版本与 Chromium 要求匹配（部分旧 Chromium 需要 Python2）。
  - 需要大量磁盘空间（建议 >100GB）与较长的构建时间。

日志与故障排查
- `configure` 失败：检查 `configure-output.txt`，把前 200 行和错误信息贴出来我可以帮你分析。
- `build` 失败：检查 `build-output.txt` 的尾部。常见问题包括缺少 Perl、Python，或 VS 环境未正确设置（`vcvarsall` 路径错误）。
- 编译器警告提示：常见会看到 `cl` 的 `/Fd 被重写`（D9025）或编码警告 C4819（建议使用 UTF-8/Unicode 保存源文件以避免编码问题）。
- 若使用 `static` 且启用 `-static-runtime`，运行时链接错误通常和 CRT mismatch 相关，确保第三方库也用相同 CRT 编译。

构建示例（在 Developer Command Prompt 中）：
```bat
REM 完整构建 (Configure + Build + Install)
build-qt5-win32.bat

REM 仅运行 Configure (会清理构建目录)
build-qt5-win32.bat configure

REM 仅运行 Build (保留之前进度，用于断点续编)
build-qt5-win32.bat build

REM 仅运行 Install
build-qt5-win32.bat install

REM 清理构建 (nmake clean)
build-qt5-win32.bat clean

REM 指定配置文件的同时指定动作
build-qt5-win32.bat custom_config.ini build
```

脚本行为说明（关键点）
- 脚本会先调用 `vcvarsall.bat`（`VS_VCVARS`），确保 MSVC 工具可用；若调用失败会中止。
- 临时目录会被重定向到脚本配置或安全默认目录，并设置 `CL` 以把 PDB 放到该临时目录，避免路径包含非 ASCII 导致的问题。
- 构建和安装阶段现在始终使用 `nmake`（不再尝试使用 `jom`）。

如果你希望我进一步帮你：
- 我可以把脚本改写为 PowerShell 版本（更易于解析 INI、日志收集与异常处理）。
- 我可以根据你给出的实际路径（例如 VS 的具体安装目录、Perl 路径）把 `qt-build.ini` 示例值改成你的环境。
- 如果你确实要包含 `qtwebengine`，我可以给出单独的 webengine 准备脚本（`depot_tools` 下载、`gn`/`ninja` 检查、Chromium 依赖准备等）。

祝构建顺利！如遇任何 `configure`/`build` 错误，把 `configure-output.txt` 或 `build-output.txt` 的关键错误段贴过来，我来帮你分析。
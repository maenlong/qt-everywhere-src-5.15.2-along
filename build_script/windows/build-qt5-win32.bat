@echo off
REM -----------------------------------------------------------------------------
REM build-qt5-win32.bat
REM 合并脚本：基于 qt-build.ini 的设置，在 Windows x86 (32-bit) 上用 VS2017 构建 Qt5.15.2
REM 用法:
REM   build-qt5-win32.bat            (读取同目录下的 qt-build.ini)
REM   build-qt5-win32.bat C:\path\to\qt-build.ini
REM -----------------------------------------------------------------------------

setlocal

:: ----------------- 解析传入的配置文件路径 -----------------
if "%~1"=="" (
  set "INIFILE=%~dp0qt-build.ini"
) else (
  set "INIFILE=%~1"
)

if not exist "%INIFILE%" (
  echo ERROR: 配置文件不存在： "%INIFILE%"
  echo 请创建或指定 qt-build.ini，然后重试。
  exit /b 1
)

echo Reading config from "%INIFILE%"...

:: ----------------- 读取 INI（跳过以 ; 开头的注释行与空行） -----------------
for /f "usebackq tokens=1* delims==" %%a in (`type "%INIFILE%" ^| findstr /v /b ";" ^| findstr /r /v "^$"`) do (
  set "%%a=%%b"
)

:: ----------------- 设置默认值 & 验证必须项 -----------------
if not defined QT_SRC (
  echo ERROR: QT_SRC 未在配置文件中设置
  exit /b 1
)

if not defined BUILD_TYPE set "BUILD_TYPE=shared"
if /i "%BUILD_TYPE%"=="shared" (
  set "BUILD_TAG=shared"
) else (
  set "BUILD_TAG=static"
)

if not defined BUILD_DIR (
  set "BUILD_DIR=%QT_SRC%\build_%BUILD_TAG%"
)

if not defined INSTALL_DIR (
  set "INSTALL_DIR=C:\Qt\5.15.2\msvc2017_32_%BUILD_TAG%"
)

if not defined VS_VCVARS (
  echo ERROR: VS_VCVARS 未在配置文件中设置
  exit /b 1
)

if not defined VS_ARG set "VS_ARG=x86"
if not defined SKIP_QTWEBENGINE set "SKIP_QTWEBENGINE=1"
if not defined USE_STATIC_RUNTIME set "USE_STATIC_RUNTIME=0"
if not defined MAKE_JOBS set "MAKE_JOBS=%NUMBER_OF_PROCESSORS%"
if not defined EXTRA_CONFIG set "EXTRA_CONFIG="

:: ----------------- 基本检查 -----------------
if not exist "%QT_SRC%\configure.bat" (
  echo ERROR: 找不到 %QT_SRC%\configure.bat，請確認 QT_SRC 是否正確： %QT_SRC%
  exit /b 1
)

if not exist "%VS_VCVARS%" (
  echo ERROR: 找不到 vcvarsall.bat，請修改 VS_VCVARS 變量指向正確路徑
  exit /b 1
)

echo.
echo ====================================================
echo Qt 源码:    %QT_SRC%
echo 构建目录:  %BUILD_DIR%
echo 安装目录:  %INSTALL_DIR%
echo 构建类型:  %BUILD_TYPE%  (static-runtime=%USE_STATIC_RUNTIME%)
echo 跳过 webengine: %SKIP_QTWEBENGINE%
echo 并行任务数: %MAKE_JOBS%
echo 额外参数:  %EXTRA_CONFIG%
echo ====================================================
echo.

REM ----------------- 设置 Visual Studio 环境 -----------------
echo Setting Visual Studio environment...
call "%VS_VCVARS%" %VS_ARG%
if errorlevel 1 (
  echo ERROR: 无法设置 VS 环境（vcvarsall 调用失败）
  exit /b 1
)

REM ----------------- 把 perl/python/jom 加入 PATH（若配置了） -----------------
if defined PERL_PATH (
  set "PATH=%PERL_PATH%;%PATH%"
)
if defined PYTHON_PATH (
  set "PATH=%PYTHON_PATH%;%PATH%"
)
if defined JOM_PATH (
  set "PATH=%JOM_PATH%;%PATH%"
)

REM ----------------- 创建清理 / 切换到构建目录 -----------------
if exist "%BUILD_DIR%" (
  echo Removing existing build dir "%BUILD_DIR%" ...
  rd /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"
pushd "%BUILD_DIR%"

REM ----------------- 构造 configure 命令 -----------------
set "CONFIG_CMD=%QT_SRC%\configure.bat -prefix "%INSTALL_DIR%" -opensource -confirm-license -release -platform win32-msvc2017 -opengl desktop -nomake tests -nomake examples %EXTRA_CONFIG%"

if /i "%BUILD_TYPE%"=="static" (
  set "CONFIG_CMD=%CONFIG_CMD% -static"
  if "%USE_STATIC_RUNTIME%"=="1" (
    set "CONFIG_CMD=%CONFIG_CMD% -static-runtime"
  )
)

if "%SKIP_QTWEBENGINE%"=="1" (
  set "CONFIG_CMD=%CONFIG_CMD% -skip qtwebengine"
)

if defined OPENSSL_DIR (
  set "CONFIG_CMD=%CONFIG_CMD% -openssl-linked -I"%OPENSSL_DIR%\include" -L"%OPENSSL_DIR%\lib""
)

echo Running configure:
echo %CONFIG_CMD%
%CONFIG_CMD% > configure-output.txt 2>&1
if errorlevel 1 (
  echo configure failed. See configure-output.txt for details.
  popd
  exit /b 1
)

REM ----------------- 编译（使用 jom 或 nmake） -----------------
echo Starting build...
where jom >nul 2>&1
if %ERRORLEVEL%==0 (
  echo Using jom...
  jom -j %MAKE_JOBS% > build-output.txt 2>&1
) else (
  echo jom not found, using nmake...
  nmake > build-output.txt 2>&1
)
if errorlevel 1 (
  echo build failed. See build-output.txt for details.
  popd
  exit /b 1
)

REM ----------------- 安装 -----------------
echo Installing...
where jom >nul 2>&1
if %ERRORLEVEL%==0 (
  jom install > install-output.txt 2>&1
) else (
  nmake install > install-output.txt 2>&1
)
if errorlevel 1 (
  echo install failed. See install-output.txt for details.
  popd
  exit /b 1
)

echo Build and install finished. Qt installed to %INSTALL_DIR%

popd
endlocal
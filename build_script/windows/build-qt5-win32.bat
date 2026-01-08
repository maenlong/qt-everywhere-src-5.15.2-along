@echo off
REM -----------------------------------------------------------------------------
REM build-qt5-win32.bat
REM - 支持 <BUILD_TYPE> 变量替换
REM - 在 vcvarsall 后强化设置 TMP/TEMP 以及 CL 的中间文件/调试信息输出目录
REM - configure 失败时自动打印 configure 日志尾部，便于定位
REM -----------------------------------------------------------------------------

for /f "tokens=2 delims=:" %%A in ('chcp') do set "OLDCP=%%A"
set "OLDCP=%OLDCP: =%"
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ---- config file path (可通过参数1指定) ----
if "%~1"=="" (
  set "INIFILE=%~dp0qt-build.ini"
) else (
  set "INIFILE=%~1"
)

if not exist "%INIFILE%" (
  echo ERROR: 配置文件不存在: "%INIFILE%"
  exit /b 1
)

echo Reading config from "%INIFILE%"...
for /f "usebackq delims=" %%L in (`type "%INIFILE%" ^| findstr /v /b ";" ^| findstr /r /v "^$"`) do call :processLine "%%L"

:: ---- base dir for relative paths in ini (use ini file location) ----
for %%I in ("%INIFILE%") do set "INIFILE_DIR=%%~dpI"

:: ---- defaults & validation ----
if not defined QT_SRC (
  echo ERROR: QT_SRC 未定义，请检查配置文件。
  exit /b 1
)
if not defined BUILD_TYPE set "BUILD_TYPE=shared"
if /i "%BUILD_TYPE%"=="shared" (
  set "BUILD_TAG=shared"
) else (
  set "BUILD_TAG=static"
)

if not defined BUILD_DIR set "BUILD_DIR=%QT_SRC%\build_<BUILD_TYPE>"
if not defined INSTALL_DIR set "INSTALL_DIR=%~dp0install_<BUILD_TYPE>"
if not defined VS_VCVARS (
  echo ERROR: VS_VCVARS 未定义，请检查配置文件。
  exit /b 1
)
if not defined VS_ARG set "VS_ARG=x86"
if not defined SKIP_QTWEBENGINE set "SKIP_QTWEBENGINE=1"
if not defined USE_STATIC_RUNTIME set "USE_STATIC_RUNTIME=0"
if not defined MAKE_JOBS set "MAKE_JOBS=%NUMBER_OF_PROCESSORS%"
if not defined EXTRA_CONFIG set "EXTRA_CONFIG="

:: ---- replace <BUILD_TYPE> in common variables ----
for %%V in (QT_SRC BUILD_DIR INSTALL_DIR SAFE_TEMP_DIR PERL_PATH PYTHON_PATH OPENSSL_DIR EXTRA_CONFIG) do (
  if defined %%V (
    set "tmp=!%%V!"
    set "tmp=!tmp:<BUILD_TYPE>=%BUILD_TAG%!"
    set "%%V=!tmp!"
  )
)

:: ---- make SAFE_TEMP_DIR relative to ini folder if needed ----
if defined SAFE_TEMP_DIR (
  set "_STD=!SAFE_TEMP_DIR!"
  if /i not "!_STD:~0,2!"=="\\" if "!_STD:~1,1!" NEQ ":" (
    set "SAFE_TEMP_DIR=%INIFILE_DIR%!_STD!"
  )
)

:: ---- expand MAKE_JOBS if it contains env vars like %NUMBER_OF_PROCESSORS% ----
call set "MAKE_JOBS=%MAKE_JOBS%"

:: ---- expand relative to absolute paths ----
if defined QT_SRC    for %%I in ("%QT_SRC%")    do set "QT_SRC=%%~fI"
if defined BUILD_DIR for %%I in ("%BUILD_DIR%") do set "BUILD_DIR=%%~fI"
if defined INSTALL_DIR for %%I in ("%INSTALL_DIR%") do set "INSTALL_DIR=%%~fI"
if defined VS_VCVARS for %%I in ("%VS_VCVARS%") do set "VS_VCVARS=%%~fI"
if defined PERL_PATH for %%I in ("%PERL_PATH%") do set "PERL_PATH=%%~fI"
if defined PYTHON_PATH for %%I in ("%PYTHON_PATH%") do set "PYTHON_PATH=%%~fI"
REM jom removed - using Visual Studio nmake
if defined OPENSSL_DIR for %%I in ("%OPENSSL_DIR%") do set "OPENSSL_DIR=%%~fI"
if defined SAFE_TEMP_DIR for %%I in ("%SAFE_TEMP_DIR%") do set "SAFE_TEMP_DIR=%%~fI"

echo.
echo ====================================================
echo Qt源码:    %QT_SRC%
echo 构建目录:  %BUILD_DIR%
echo 安装目录:  %INSTALL_DIR%
echo 缓存目录:  %SAFE_TEMP_DIR%
echo vcvarsall:  %VS_VCVARS%
echo 构建类型:  %BUILD_TYPE%  (static-runtime=%USE_STATIC_RUNTIME%)
echo 跳过 webengine: %SKIP_QTWEBENGINE%
echo 并行线程数: %MAKE_JOBS%
echo 额外参数:  %EXTRA_CONFIG%
echo ====================================================
echo.

:: ---- call vcvarsall to setup MSVC env (this should succeed) ----
echo Setting Visual Studio environment...
call "%VS_VCVARS%" %VS_ARG%
if errorlevel 1 (
  echo ERROR: 无法设置 VS 编译环境（vcvarsall 调用失败）。
  exit /b 1
)

:: ---- SAFEGUARD: force TMP/TEMP to an ASCII-only temp dir ----
:: Prefer SAFE_TEMP_DIR from ini; fallback to a safe default on current drive.
if not defined SAFE_TEMP_DIR set "SAFE_TEMP_DIR=%~d0\qt_temp"
if not exist "%SAFE_TEMP_DIR%" mkdir "%SAFE_TEMP_DIR%" 2>nul
if not exist "%SAFE_TEMP_DIR%" (
  echo ERROR: 无法创建 SAFE_TEMP_DIR "%SAFE_TEMP_DIR%"（请检查路径/权限）。
  exit /b 1
)
set "TMP=%SAFE_TEMP_DIR%"
set "TEMP=%SAFE_TEMP_DIR%"
echo Using TEMP=%TEMP%

:: ---- SAFEGUARD: force CL parallel compile for nmake builds ----
REM Avoid forcing /Fd (Qt makefiles may set it), just enable /MP.
set "CL=%CL% /MP%MAKE_JOBS%"
echo Using CL=%CL%

:: ---- Add optional tool paths if provided ----
if defined PERL_PATH set "PATH=%PERL_PATH%;%PATH%"
if defined PYTHON_PATH set "PATH=%PYTHON_PATH%;%PATH%"

:: ---- prepare build dir ----
if exist "%BUILD_DIR%" (
  echo Removing existing build dir "%BUILD_DIR%" ...
  rd /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"
pushd "%BUILD_DIR%"

:: ---- prepare configure flags ----
set "STATICFLAG="
set "STATICRT="
set "SKIPFLAG="
if /i "%BUILD_TYPE%"=="static" set "STATICFLAG=-static"
if "%USE_STATIC_RUNTIME%"=="1" set "STATICRT=-static-runtime"
if "%SKIP_QTWEBENGINE%"=="1" set "SKIPFLAG=-skip qtwebengine"

echo Running configure:
echo call "%QT_SRC%\configure.bat" -prefix "%INSTALL_DIR%" -opensource -confirm-license -release -platform win32-msvc2017 -opengl desktop -nomake tests -nomake examples %EXTRA_CONFIG% %STATICFLAG% %STATICRT% %SKIPFLAG%
chcp 936 >nul
powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936); [Console]::InputEncoding = [Text.Encoding]::GetEncoding(936); & { & '%QT_SRC%\configure.bat' -prefix '%INSTALL_DIR%' -opensource -confirm-license -release -platform win32-msvc2017 -opengl desktop -nomake tests -nomake examples %EXTRA_CONFIG% %STATICFLAG% %STATICRT% %SKIPFLAG% 2>&1 | Tee-Object -FilePath 'configure-output.txt' ; exit $LASTEXITCODE }"
set "CFGERR=%ERRORLEVEL%"
chcp %OLDCP% >nul
if %CFGERR% NEQ 0 (
  echo configure failed. Showing last 300 lines of configure-output.txt:
  powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Content -Path 'configure-output.txt' -Tail 300 -Encoding OEM" 2>nul || type configure-output.txt | more
  popd
  exit /b 1
)

:: ---- build (nmake) ----
echo Starting build with nmake...
chcp 936 >nul
powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936); [Console]::InputEncoding = [Text.Encoding]::GetEncoding(936); & { nmake 2>&1 | Tee-Object -FilePath 'build-output.txt' ; exit $LASTEXITCODE }"
set "BUILERR=%ERRORLEVEL%"
chcp %OLDCP% >nul
if %BUILERR% NEQ 0 (
  echo build failed. Showing last 200 lines of build-output.txt:
  powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Content -Path 'build-output.txt' -Tail 200 -Encoding OEM" 2>nul || type build-output.txt | more
  popd
  exit /b 1
)

:: ---- install ----
echo Installing with nmake...
chcp 936 >nul
powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936); [Console]::InputEncoding = [Text.Encoding]::GetEncoding(936); & { nmake install 2>&1 | Tee-Object -FilePath 'install-output.txt' ; exit $LASTEXITCODE }"
set "INSTERR=%ERRORLEVEL%"
chcp %OLDCP% >nul
if %INSTERR% NEQ 0 (
  echo install failed. Showing last 200 lines of install-output.txt:
  powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Content -Path 'install-output.txt' -Tail 200 -Encoding OEM" 2>nul || type install-output.txt | more
  popd
  exit /b 1
)

echo Build and install finished. Qt installed to %INSTALL_DIR%

popd
endlocal
exit /b 0

:processLine
set "line=%~1"
for /f "tokens=1* delims==" %%A in ("%line%") do (
  set "key=%%A"
  set "val=%%B"
)
call :trim key key
call :trim val val
set "%key%=%val%"
goto :eof

:trim
setlocal enabledelayedexpansion
set "s=!%~1!"
if "!s!"=="" ( endlocal & set "%~2=" & goto :eof )
:th
if "!s:~0,1!"==" " set "s=!s:~1!" & goto :th
:tt
if "!s:~-1!"==" " set "s=!s:~0,-1!" & goto :tt
endlocal & set "%~2=%s%"
goto :eof
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
:: Support: build-qt5-win32.bat [ini_file] [action]
:: Actions: all(default), configure, build, install

set "INIFILE=%~dp0qt-build.ini"
set "ACTION=all"

:: Check if the first argument is a command directly
if /i "%~1"=="configure" set "ACTION=configure" & goto :CheckIni
if /i "%~1"=="build"     set "ACTION=build"     & goto :CheckIni
if /i "%~1"=="install"   set "ACTION=install"   & goto :CheckIni
if /i "%~1"=="clean"     set "ACTION=clean"     & goto :CheckIni

:: If not a command, treat as INI file if provided
if "%~1" neq "" (
  set "INIFILE=%~1"
  if "%~2" neq "" set "ACTION=%~2"
)

:CheckIni
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
if not defined BUILD_CONFIG set "BUILD_CONFIG=-release"
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
echo 架构:      %VS_ARG%
echo 构建类型:  %BUILD_TYPE%  (static-runtime=%USE_STATIC_RUNTIME%)
echo 构建配置:  "%BUILD_CONFIG%"
echo 跳过 webengine: %SKIP_QTWEBENGINE%
if defined OPENSSL_DIR (echo OpenSSL:    %OPENSSL_DIR%) else (echo OpenSSL:    未配置)
echo 并行线程数: %MAKE_JOBS%
echo 额外参数:  "%EXTRA_CONFIG%"
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
set "DO_CLEAN=0"
if /i "!ACTION!"=="all" set "DO_CLEAN=1"
if /i "!ACTION!"=="configure" set "DO_CLEAN=1"

if "!DO_CLEAN!"=="1" (
  if exist "%BUILD_DIR%" (
    echo Removing existing build dir "%BUILD_DIR%" ...
    rd /s /q "%BUILD_DIR%"
  )
  mkdir "%BUILD_DIR%"
)

if not exist "%BUILD_DIR%" (
    echo ERROR: Build directory "%BUILD_DIR%" does not exist. Cannot perform "!ACTION!".
    exit /b 1
)
pushd "%BUILD_DIR%"

if /i "!ACTION!"=="clean" (
    echo Cleaning build directory with nmake clean...
    if exist "Makefile" (
        chcp 936 >nul
        nmake clean
        chcp %OLDCP% >nul
    ) else (
        echo Warning: Makefile not found, skipping nmake clean.
    )
    popd
    exit /b 0
)

:: ---- prepare configure flags ----
set "STATICFLAG="
set "STATICRT="
set "SKIPFLAG="
set "SSLFLAG="
if /i "%BUILD_TYPE%"=="static" set "STATICFLAG=-static"
if "%USE_STATIC_RUNTIME%"=="1" set "STATICRT=-static-runtime"
if "%SKIP_QTWEBENGINE%"=="1" set "SKIPFLAG=-skip qtwebengine"
if defined OPENSSL_DIR if exist "%OPENSSL_DIR%" set "SSLFLAG=-openssl-linked OPENSSL_PREFIX="%OPENSSL_DIR%""

set "DO_CONFIGURE=0"
if /i "!ACTION!"=="all" set "DO_CONFIGURE=1"
if /i "!ACTION!"=="configure" set "DO_CONFIGURE=1"

if "!DO_CONFIGURE!"=="1" (
  set "TimeStartConf=!TIME!"
  echo Running configure:
  echo call "%QT_SRC%\configure.bat" -prefix "%INSTALL_DIR%" -opensource -confirm-license %BUILD_CONFIG% -mp -platform win32-msvc -opengl desktop -nomake tests -nomake examples -nomake tools %SSLFLAG% %EXTRA_CONFIG% %STATICFLAG% %STATICRT% %SKIPFLAG%
  REM Start log viewer for configure
  type nul > "configure-raw.txt"
  type nul > "configure-output.txt"
  start "Configure Log Viewer" powershell -NoProfile -Command "$h=Get-Host;$w=$h.UI.RawUI.WindowSize;$b=$h.UI.RawUI.BufferSize;$w.Height=50;$w.Width=120;$b.Height=9999;$b.Width=120;$h.UI.RawUI.WindowSize=$w;$h.UI.RawUI.BufferSize=$b; [Console]::OutputEncoding=[Text.Encoding]::Default; $raw='configure-raw.txt'; $out='configure-output.txt'; $sw=New-Object System.IO.StreamWriter($out,$true,[Text.Encoding]::Default); $sw.AutoFlush=$true; Write-Host 'Tailing configure-raw.txt...'; Get-Content -Path $raw -Wait -Encoding Default | ForEach-Object { $t=(Get-Date).ToString('HH:mm:ss.fff'); $l=$_; $line='['+$t+'] '+$l; $sw.WriteLine($line); if($l -match '(?i) error:'){Write-Host $line -ForegroundColor Red} elseif($l -match '(?i) warning:'){Write-Host $line -ForegroundColor Yellow} else {Write-Host $line} }"

  call "%QT_SRC%\configure.bat" -prefix "%INSTALL_DIR%" -opensource -confirm-license %BUILD_CONFIG% -mp -platform win32-msvc -opengl desktop -nomake tests -nomake examples -nomake tools %SSLFLAG% %EXTRA_CONFIG% %STATICFLAG% %STATICRT% %SKIPFLAG% >> "configure-raw.txt" 2>&1
  set "CFGERR=!ERRORLEVEL!"
  set "TimeEndConf=!TIME!"
  if !CFGERR! NEQ 0 (
    echo configure failed. Showing last 300 lines of configure-output.txt:
    powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::Default; Get-Content -Path 'configure-output.txt' -Tail 300 -Encoding Default" 2>nul || type configure-output.txt | more
    popd
    exit /b 1
  )
) else (
  echo Skipping configure step...
)

:: ---- build (nmake) ----
set "DO_BUILD=0"
if /i "!ACTION!"=="all" set "DO_BUILD=1"
if /i "!ACTION!"=="build" set "DO_BUILD=1"

if "!DO_BUILD!"=="1" (
  set "TimeStartBuild=!TIME!"
  echo Starting build with nmake...
  REM Start log viewer for build
  type nul > "build-raw.txt"
  type nul > "build-output.txt"
  start "Build Log Viewer" powershell -NoProfile -Command "$h=Get-Host;$w=$h.UI.RawUI.WindowSize;$b=$h.UI.RawUI.BufferSize;$w.Height=50;$w.Width=120;$b.Height=9999;$b.Width=120;$h.UI.RawUI.WindowSize=$w;$h.UI.RawUI.BufferSize=$b; [Console]::OutputEncoding=[Text.Encoding]::Default; $raw='build-raw.txt'; $out='build-output.txt'; $sw=New-Object System.IO.StreamWriter($out,$true,[Text.Encoding]::Default); $sw.AutoFlush=$true; Write-Host 'Tailing build-raw.txt...'; Get-Content -Path $raw -Wait -Encoding Default | ForEach-Object { $t=(Get-Date).ToString('HH:mm:ss.fff'); $l=$_; $line='['+$t+'] '+$l; $sw.WriteLine($line); if($l -match '(?i) error:'){Write-Host $line -ForegroundColor Red} elseif($l -match '(?i) warning:'){Write-Host $line -ForegroundColor Yellow} else {Write-Host $line} }"

  nmake >> "build-raw.txt" 2>&1
  set "BUILERR=!ERRORLEVEL!"
  set "TimeEndBuild=!TIME!"
  if !BUILERR! NEQ 0 (
    echo build failed. Showing last 200 lines of build-output.txt:
    powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::Default; Get-Content -Path 'build-output.txt' -Tail 200 -Encoding Default" 2>nul || type build-output.txt | more
    popd
    exit /b 1
  )
) else (
  echo Skipping build step...
)

:: ---- install ----
set "DO_INSTALL=0"
if /i "!ACTION!"=="all" set "DO_INSTALL=1"
if /i "!ACTION!"=="install" set "DO_INSTALL=1"

if "!DO_INSTALL!"=="1" (
  set "TimeStartInst=!TIME!"
  echo Starting install with nmake...
  type nul > "install-raw.txt"
  type nul > "install-output.txt"
  start "Install Log Viewer" powershell -NoProfile -Command "$h=Get-Host;$w=$h.UI.RawUI.WindowSize;$b=$h.UI.RawUI.BufferSize;$w.Height=50;$w.Width=120;$b.Height=9999;$b.Width=120;$h.UI.RawUI.WindowSize=$w;$h.UI.RawUI.BufferSize=$b; [Console]::OutputEncoding=[Text.Encoding]::Default; $raw='install-raw.txt'; $out='install-output.txt'; $sw=New-Object System.IO.StreamWriter($out,$true,[Text.Encoding]::Default); $sw.AutoFlush=$true; Write-Host 'Tailing install-raw.txt...'; Get-Content -Path $raw -Wait -Encoding Default | ForEach-Object { $t=(Get-Date).ToString('HH:mm:ss.fff'); $l=$_; $line='['+$t+'] '+$l; $sw.WriteLine($line); if($l -match '(?i) error:'){Write-Host $line -ForegroundColor Red} elseif($l -match '(?i) warning:'){Write-Host $line -ForegroundColor Yellow} else {Write-Host $line} }"

  nmake install >> "install-raw.txt" 2>&1
  set "INSTERR=!ERRORLEVEL!"
  set "TimeEndInst=!TIME!"
  if !INSTERR! NEQ 0 (
    echo install failed. Showing last 200 lines of install-output.txt:
    powershell -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::Default; Get-Content -Path 'install-output.txt' -Tail 200 -Encoding Default" 2>nul || type install-output.txt | more
    popd
    exit /b 1
  )
) else (
  echo Skipping install step...
)

echo Build and install finished. Qt installed to %INSTALL_DIR%

echo.
echo =========================================
echo             Build Statistics
echo =========================================
powershell -NoProfile -Command ^
  "$steps = @();" ^
  "if ('!DO_CONFIGURE!' -eq '1') { $steps += @{Name='Configure'; Start='!TimeStartConf!'; End='!TimeEndConf!'} };" ^
  "if ('!DO_BUILD!' -eq '1')     { $steps += @{Name='Build    '; Start='!TimeStartBuild!'; End='!TimeEndBuild!'} };" ^
  "if ('!DO_INSTALL!' -eq '1')   { $steps += @{Name='Install  '; Start='!TimeStartInst!'; End='!TimeEndInst!'} };" ^
  "$totalSeconds = 0;" ^
  "foreach ($s in $steps) {" ^
  "  try {" ^
  "    $start = [DateTime]::Parse($s.Start);" ^
  "    $end   = [DateTime]::Parse($s.End);" ^
  "    if ($end -lt $start) { $end = $end.AddDays(1) };" ^
  "    $dur = $end - $start;" ^
  "    $totalSeconds += $dur.TotalSeconds;" ^
  "    Write-Host ('{0} : {1:hh\:mm\:ss\.fff}' -f $s.Name, $dur);" ^
  "  } catch { Write-Host ('{0} : Error calculating time' -f $s.Name) }" ^
  "}" ^
  "$ts = [TimeSpan]::FromSeconds($totalSeconds);" ^
  "Write-Host ('-----------------------------------------');" ^
  "Write-Host ('Total Time : {0:hh\:mm\:ss\.fff}' -f $ts);"

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
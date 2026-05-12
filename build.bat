@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

set "MQ5_FILE=%~dp0Pending_tread.mq5"
set "EX5_FILE=%~dp0Pending_tread.ex5"
set "LOG_FILE=%~dp0Pending_tread_compile.log"
set "METAEDITOR="

if not exist "%MQ5_FILE%" (
  echo [LOI] Khong tim thay: %MQ5_FILE%
  exit /b 1
)

if exist "%ProgramFiles%\MetaTrader 5\MetaEditor64.exe" (
  set "METAEDITOR=%ProgramFiles%\MetaTrader 5\MetaEditor64.exe"
) else if exist "%ProgramFiles(x86)%\MetaTrader 5\MetaEditor64.exe" (
  set "METAEDITOR=%ProgramFiles(x86)%\MetaTrader 5\MetaEditor64.exe"
) else (
  for /f "delims=" %%E in ('where metaeditor64.exe 2^>nul') do (
    if not defined METAEDITOR set "METAEDITOR=%%E"
  )
)

if not defined METAEDITOR (
  echo [LOI] Khong tim thay MetaEditor64.exe. Hay cai MetaTrader 5 hoac them vao PATH.
  exit /b 1
)

echo [BUILD] %MQ5_FILE%
echo [TOOL]  %METAEDITOR%
echo.

"%METAEDITOR%" /compile:"%MQ5_FILE%" /log:"%LOG_FILE%"

if not exist "%EX5_FILE%" (
  echo.
  echo [LOI] Bien dich that bai.
  if exist "%LOG_FILE%" type "%LOG_FILE%"
  exit /b 1
)

echo.
echo [OK] Da tao: %EX5_FILE%
exit /b 0

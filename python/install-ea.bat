@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title Cai dat Expert Advisor vao MetaTrader 5

echo ============================================================
echo   CAI DAT EXPERT ADVISOR VAO METATRADER 5
echo ============================================================
echo.

REM Lay duong dan thu muc chua file .bat nay
set "SOURCE_DIR=%~dp0"
if "%SOURCE_DIR:~-1%"=="\" set "SOURCE_DIR=%SOURCE_DIR:~0,-1%"

REM Kiem tra file nguon ton tai
set "MQ5_FILE=%SOURCE_DIR%\bot.mq5"
set "EX5_FILE=%SOURCE_DIR%\bot.ex5"

if not exist "%MQ5_FILE%" (
    echo [LOI] Khong tim thay file: %MQ5_FILE%
    echo Hay chac chan file .bat nay nam cung thu muc voi bot.mq5
    pause
    exit /b 1
)

echo [OK] Tim thay file nguon:
echo      %MQ5_FILE%
if exist "%EX5_FILE%" echo      %EX5_FILE%
echo.

REM ============================================================
REM Tim cac thu muc MT5
REM ============================================================
echo [TIM KIEM] Dang quet cac cai dat MetaTrader 5...
echo.

set /a COUNT=0

REM 1) Quet thu muc data cua MT5 trong %APPDATA%
set "MT5_ROOT=%APPDATA%\MetaQuotes\Terminal"
if exist "%MT5_ROOT%" (
    for /d %%D in ("%MT5_ROOT%\*") do (
        if exist "%%D\MQL5\Experts" call :ADD_TARGET "%%D\MQL5\Experts"
    )
)

REM 2) Quet thu muc cai dat MT5
call :TRY_ADD "C:\Program Files\MetaTrader 5\MQL5\Experts"
call :TRY_ADD "C:\Program Files (x86)\MetaTrader 5\MQL5\Experts"

REM 3) Quet cac broker pho bien co the cai MT5 rieng
call :TRY_ADD "C:\Program Files\Exness MetaTrader 5\MQL5\Experts"
call :TRY_ADD "C:\Program Files\ICMarkets - MetaTrader 5\MQL5\Experts"
call :TRY_ADD "C:\Program Files\FBS MetaTrader 5\MQL5\Experts"
call :TRY_ADD "C:\Program Files\XM MT5\MQL5\Experts"

echo.

if %COUNT%==0 (
    echo [LOI] Khong tim thay cai dat MetaTrader 5 nao tren may.
    echo.
    echo Hay cai dat MT5 va chay no it nhat 1 lan de tao thu muc data.
    echo Thu muc thuong nam tai: %APPDATA%\MetaQuotes\Terminal\
    pause
    exit /b 1
)

echo Tim thay %COUNT% cai dat MetaTrader 5.
echo.

REM ============================================================
REM Hoi nguoi dung chon cai dat
REM ============================================================
echo Chon che do cai dat:
echo   [A] Cai dat vao TAT CA cac thu muc o tren
echo   [1-%COUNT%] Chi cai dat vao thu muc cu the
echo   [Q] Thoat
echo.
set /p "CHOICE=Nhap lua chon cua ban: "

if /i "%CHOICE%"=="Q" goto :END
if /i "%CHOICE%"=="A" goto :INSTALL_ALL

REM Xac thuc nhap so
set "VALID="
for /l %%I in (1,1,%COUNT%) do (
    if "%CHOICE%"=="%%I" set "VALID=1"
)

if not defined VALID (
    echo [LOI] Lua chon khong hop le.
    pause
    exit /b 1
)

call set "SELECTED=%%TARGET_%CHOICE%%%"
call :COPY_FILES "!SELECTED!"
goto :END

:INSTALL_ALL
echo.
echo [BAT DAU] Cai dat vao TAT CA %COUNT% thu muc...
echo.
for /l %%I in (1,1,%COUNT%) do (
    call set "DEST=%%TARGET_%%I%%"
    call :COPY_FILES "!DEST!"
)
goto :END

REM ============================================================
REM Subroutines
REM ============================================================
:TRY_ADD
if exist "%~1" call :ADD_TARGET "%~1"
exit /b 0

:ADD_TARGET
set /a COUNT+=1
set "TARGET_!COUNT!=%~1"
echo   [!COUNT!] %~1
exit /b 0

:COPY_FILES
set "DEST_DIR=%~1"
echo -----------------------------------------------------------
echo Dich: %DEST_DIR%
copy /Y "%MQ5_FILE%" "%DEST_DIR%\" >nul
if errorlevel 1 (
    echo   [LOI] Copy bot.mq5 that bai
) else (
    echo   [OK] Da copy bot.mq5
)

if exist "%EX5_FILE%" (
    copy /Y "%EX5_FILE%" "%DEST_DIR%\" >nul
    if errorlevel 1 (
        echo   [LOI] Copy bot.ex5 that bai
    ) else (
        echo   [OK] Da copy bot.ex5
    )
) else (
    echo   [BO QUA] bot.ex5 khong ton tai - hay bien dich trong MetaEditor ^(F7^)
)
echo.
exit /b 0

:END
echo ============================================================
echo   HOAN TAT
echo ============================================================
echo.
echo Buoc tiep theo:
echo   1. Mo MetaTrader 5
echo   2. Mo MetaEditor ^(F4^), bien dich bot.mq5 ^(F7^) neu chua co bot.ex5
echo   3. Vao Navigator -^> Expert Advisors -^> keo "bot" len bieu do
echo   4. Bat AutoTrading ^(Ctrl+E^)
echo.
pause
endlocal

@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

set "VENV_PY=%~dp0.venv\Scripts\python.exe"
set "PYINST=%~dp0.venv\Scripts\pyinstaller.exe"

if not exist "%VENV_PY%" (
  echo [.venv] Không tìm thấy .venv\Scripts\python.exe — hãy tạo virtualenv và cài dependencies trước.
  exit /b 1
)

if not exist "%PYINST%" (
  echo Đang cài PyInstaller vào .venv...
  "%VENV_PY%" -m pip install pyinstaller
  if errorlevel 1 exit /b 1
)

echo Đang build 4 file EXE vào dist\ ...
"%PYINST%" --noconfirm --onefile --console --hidden-import i18n --collect-all MetaTrader5 --name init-test init-test.py
if errorlevel 1 exit /b 1

"%PYINST%" --noconfirm --onefile --console --hidden-import i18n --collect-all MetaTrader5 --name account-info account-info.py
if errorlevel 1 exit /b 1

"%PYINST%" --noconfirm --onefile --console --hidden-import i18n --collect-all MetaTrader5 --name test-function test-function.py
if errorlevel 1 exit /b 1

"%PYINST%" --noconfirm --onefile --console --hidden-import i18n --name config_manager config_manager.py
if errorlevel 1 exit /b 1

echo.
echo Hoàn tất. Kết quả: %~dp0dist
exit /b 0

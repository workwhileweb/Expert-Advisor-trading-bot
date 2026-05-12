@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

py -m pip install --upgrade pip
py -m pip install torch MetaTrader5 onnx numpy pandas

py "%~dp0train_hybrid_lstm.py" --symbol XAUUSDm --timeframe M1 --bars 50000 --seq-len 48 --hidden 32 --epochs 8 --out-dir "%~dp0models"
if errorlevel 1 exit /b 1

echo.
echo [OK] Copy models\hybrid_lstm.onnx vao thu muc MQL5\Files cua terminal MT5 dang chay EA.
exit /b 0

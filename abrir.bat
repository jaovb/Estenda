@echo off
setlocal
cd /d "%~dp0"
set "PYW="
pyw -3 -c "import sys" >nul 2>nul && set "PYW=pyw -3"
if not defined PYW pythonw -c "import sys" >nul 2>nul && set "PYW=pythonw"
if not defined PYW (
    echo.
    echo  Python nao encontrado. Rode o instalar.bat primeiro.
    echo.
    pause
    exit /b 1
)
start "" %PYW% "%~dp0app.py"
exit /b 0

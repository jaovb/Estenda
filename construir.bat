@echo off
setlocal
cd /d "%~dp0"
title Ponte Remota - gerando o executavel

set "PY=python"
where py >nul 2>nul && set "PY=py"

%PY% --version >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Python nao encontrado.
  echo  Instale o Python 3.9 ou mais novo em https://www.python.org/downloads/
  echo  e marque "Add python.exe to PATH" na instalacao.
  echo.
  pause
  exit /b 1
)

echo.
echo  [1/2] Instalando dependencias...
%PY% -m pip install --upgrade pip >nul
%PY% -m pip install -r requisitos.txt pyinstaller
if errorlevel 1 goto erro

echo.
echo  [2/2] Gerando PonteRemota.exe (leva 1 a 2 minutos)...
%PY% -m PyInstaller --noconfirm --clean --onefile --windowed --name PonteRemota ^
  --icon icone.ico --add-data "interface;interface" app.py
if errorlevel 1 goto erro

echo.
echo  Pronto! O executavel esta em: %~dp0dist\PonteRemota.exe
echo  Para um instalador com atalho e desinstalador, rode o gerar_instalador.bat.
echo.
explorer "%~dp0dist"
pause
exit /b 0

:erro
echo.
echo  Algo deu errado. Copie as mensagens acima e mande para quem te ajudou.
echo.
pause
exit /b 1

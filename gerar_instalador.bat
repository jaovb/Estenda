@echo off
setlocal
cd /d "%~dp0"
title Ponte Remota - gerando o instalador

if exist dist\PonteRemota.exe goto temexe
echo.
echo  O PonteRemota.exe ainda nao foi gerado. Rode o construir.bat primeiro.
pause
exit /b 1

:temexe
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" goto temiscc
set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" goto temiscc

echo  Instalando o Inno Setup pelo winget (uma vez so)...
where winget >nul 2>nul
if errorlevel 1 goto sem_inno
winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" goto temiscc
set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" goto temiscc

:sem_inno
echo.
echo  Nao achei o Inno Setup. Instale em https://jrsoftware.org/isdl.php e rode de novo.
pause
exit /b 1

:temiscc
"%ISCC%" instalador.iss
if errorlevel 1 (
  echo.
  echo  Falhou ao gerar o instalador. Copie as mensagens acima.
  pause
  exit /b 1
)
echo.
echo  Pronto: %~dp0dist\PonteRemota-Instalador.exe
explorer "%~dp0dist"
pause

@echo off
setlocal
cd /d "%~dp0"
title Ponte Remota - gerando o app do tablet (APK)

where flutter >nul 2>nul
if errorlevel 1 (
  echo.
  echo  O Flutter nao foi encontrado no PATH.
  echo  Instale em https://docs.flutter.dev/get-started/install/windows/mobile
  echo  e rode "flutter doctor" ate o Android aparecer com OK.
  echo.
  pause
  exit /b 1
)

echo.
echo  [1/3] Preparando o projeto Android...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preparar_android.ps1"
if errorlevel 1 goto erro

echo.
echo  [2/3] Baixando as bibliotecas (crypto, shared_preferences)...
call flutter pub get
if errorlevel 1 goto erro

echo.
echo  [3/3] Gerando o APK (a primeira vez demora alguns minutos)...
call flutter build apk --release
if errorlevel 1 goto erro

if not exist "%~dp0..\dist" mkdir "%~dp0..\dist"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%~dp0..\dist\PonteRemota-tablet.apk" >nul
echo.
echo  Pronto: %~dp0..\dist\PonteRemota-tablet.apk
echo  Mande esse arquivo para o tablet (cabo, Drive, WhatsApp) e abra para instalar.
echo  Ou, com o tablet no cabo e a depuracao USB ligada: flutter install
echo.
explorer "%~dp0..\dist"
pause
exit /b 0

:erro
echo.
echo  Algo deu errado. Copie as mensagens acima e me mande.
echo.
pause
exit /b 1

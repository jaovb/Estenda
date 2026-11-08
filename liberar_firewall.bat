@echo off
setlocal
cd /d "%~dp0"
title Ponte Remota - liberar no firewall

rem Precisa de administrador: se nao for, pede e reabre.
net session >nul 2>&1
if errorlevel 1 (
  echo  Pedindo permissao de administrador...
  if "%~1"=="" (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  ) else (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
  )
  exit /b
)

set "PORTA=%~1"
if "%PORTA%"=="" set "PORTA=24860"

echo.
echo  Liberando a porta %PORTA% so para o Tailscale e a rede de casa...
netsh advfirewall firewall delete rule name="Ponte Remota" >nul 2>&1
netsh advfirewall firewall add rule name="Ponte Remota" dir=in action=allow protocol=TCP localport=%PORTA% remoteip=100.64.0.0/10,fd7a:115c:a1e0::/48,LocalSubnet profile=any
if errorlevel 1 (
  echo.
  echo  Nao deu certo. Copie a mensagem acima.
  pause
  exit /b 1
)
echo.
echo  Pronto. A internet aberta continua bloqueada; so o Tailscale e a rede de casa entram.
echo  Se um dia voce clicou em "Cancelar" no aviso do firewall, abra
echo  "Permitir um aplicativo pelo Firewall do Windows" e marque o Ponte Remota (ou o Python).
echo.
pause

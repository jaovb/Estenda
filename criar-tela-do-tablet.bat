@echo off
setlocal
title Estenda - criar a tela do tablet
rem pede permissao de administrador (o Windows pergunta uma vez)
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo  Estenda - criando a tela do tablet (Virtual Display Driver)
echo  ---------------------------------------------------------
echo.
where winget >nul 2>&1
if errorlevel 1 (
  echo  Este Windows nao tem o winget. Atualize o "Instalador de Aplicativo" na Microsoft Store e rode de novo.
  goto fim
)
echo  [1/3] Instalando o Visual C++ ^(o driver precisa dele^)...
winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-source-agreements --accept-package-agreements --silent
echo.
echo  [2/3] Instalando o driver de tela virtual...
echo        Se o Windows perguntar se confia no driver, clique em INSTALAR.
winget install --id VirtualDrivers.Virtual-Display-Driver -e --accept-source-agreements --accept-package-agreements
echo.
echo  [3/3] Conferindo...
powershell -NoProfile -Command "$d = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Virtual|IddSample|MttVDD' }; if ($d) { $d | ForEach-Object { if ($_.Status -ne 'OK') { Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue } }; Write-Host ''; Write-Host '  PRONTO: o driver esta instalado:' $($d.FriendlyName -join ', '); Write-Host '  Reinicie o PC. Depois, em Configuracoes > Sistema > Tela, deixe a tela nova em Estender.' } else { Write-Host ''; Write-Host '  O driver NAO apareceu. Tire um print desta janela e mande para o Claude.' }"
:fim
echo.
pause

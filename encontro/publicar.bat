@echo off
setlocal
cd /d "%~dp0"
title Estenda - publicando o ponto de encontro
echo.
echo  Estenda - ponto de encontro (uma vez so)
echo  Voce so precisa entrar na sua conta da Cloudflare quando o navegador abrir.
echo.

rem ---- 1. Node.js (instala sozinho se faltar)
where npx >nul 2>nul
if errorlevel 1 (
  if exist "%ProgramFiles%\nodejs\npx.cmd" (
    set "PATH=%ProgramFiles%\nodejs;%PATH%"
  ) else (
    echo  [1/4] Instalando o Node.js ^(o Windows pode pedir permissao^)...
    winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    set "PATH=%ProgramFiles%\nodejs;%PATH%"
  )
)
where npx >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Nao consegui instalar o Node.js sozinho. Instale em https://nodejs.org ^(LTS^) e rode de novo.
  goto erro
)
echo  [1/4] Node.js pronto.

rem ---- 2. pagina do tablet
echo  [2/4] Copiando a pagina do tablet...
if not exist publico\fontes mkdir publico\fontes
copy /y "..\interface\remoto.html" "publico\index.html" >nul
copy /y "..\interface\icone.png" "publico\icone.png" >nul
for %%f in (icone-192.png icone-512.png icone-mascara.png icone-apple.png sw.js) do copy /y "..\interface\%%f" "publico\%%f" >nul
copy /y "..\interface\fontes\*.ttf" "publico\fontes\" >nul

rem ---- 3. conta da Cloudflare (abre o navegador so na primeira vez)
echo  [3/4] Conferindo a conta da Cloudflare...
call npx --yes wrangler@4 whoami 2>nul | find /i "You are logged in" >nul
if errorlevel 1 (
  echo.
  echo  O navegador vai abrir: entre na sua conta da Cloudflare ^(ou crie uma, gratis^)
  echo  e clique em "Allow". Depois volte aqui.
  echo.
  call npx --yes wrangler@4 login
  if errorlevel 1 goto erro
)

rem ---- 4. publicar (a primeira vez pode perguntar o nome do seu subdominio workers.dev)
echo  [4/4] Publicando...
call npx --yes wrangler@4 deploy
if errorlevel 1 goto erro
rem de novo, so para registrar o endereco e configurar o Estenda (nao muda nada)
call npx --yes wrangler@4 deploy > deploy.log 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar.ps1" -Registro "%~dp0deploy.log"
if errorlevel 1 (
  echo  Copie o endereco https://...workers.dev mostrado acima e cole no painel:
  echo  Configuracoes, De longe.
)

echo.
echo  Tudo pronto. No painel do Estenda, leia o QR "App (casa e longe)" com o tablet
echo  e toque em "Instalar o app Estenda".
echo  Quando eu mandar uma versao nova, rode este arquivo de novo.
echo.
pause
exit /b 0

:erro
echo.
echo  Algo deu errado. Tire um print desta janela e me mande.
echo.
pause
exit /b 1

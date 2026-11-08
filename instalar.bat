@echo off
setlocal
cd /d "%~dp0"
title Ponte Remota - instalacao
echo.
echo  === Ponte Remota: instalacao ===
echo.

call :achar_python
if defined PY goto tem_python

echo  Python 3.9 ou mais novo nao foi encontrado.
echo.
where winget >nul 2>nul
if errorlevel 1 goto sem_winget
choice /C SN /M " Instalar o Python 3.12 agora pelo winget"
if errorlevel 2 goto sem_winget
winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
echo.
echo  Feche esta janela e rode o instalar.bat de novo.
pause
exit /b 1

:sem_winget
echo  Instale o Python em https://www.python.org/downloads/
echo  (marque "Add python.exe to PATH" na primeira tela do instalador)
echo  e rode o instalar.bat de novo.
pause
exit /b 1

:tem_python
echo  Usando:
%PY% --version
echo.
echo  Instalando as bibliotecas mss e pillow (precisa de internet)...
%PY% -m pip install --upgrade -r requisitos.txt
if errorlevel 1 (
    echo.
    echo  Falhou ao instalar as bibliotecas. Confira a internet e rode de novo.
    pause
    exit /b 1
)
echo.
echo  Criando o atalho "Ponte Remota" na Area de Trabalho e no Menu Iniciar...
for /f "delims=" %%P in ('%PY% -c "import sys,os;print(os.path.join(os.path.dirname(sys.executable),'pythonw.exe'))"') do set "PYW=%%P"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$w=New-Object -ComObject WScript.Shell; foreach($d in @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))){ $s=$w.CreateShortcut((Join-Path $d 'Ponte Remota.lnk')); $s.TargetPath='%PYW%'; $s.Arguments='\"%~dp0app.py\"'; $s.WorkingDirectory='%~dp0'; $s.IconLocation='%~dp0icone.ico'; $s.Description='Ponte Remota: o PC no tablet'; $s.Save() }"
echo.
echo  Tudo pronto. Abra pelo atalho "Ponte Remota".
echo  Na primeira vez que ligar o acesso, o Windows pergunta sobre o firewall:
echo  marque "Redes privadas" e permita. Se precisar, rode o liberar_firewall.bat.
echo.
pause
exit /b 0

:achar_python
set "PY="
py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>nul && set "PY=py -3" && goto :eof
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>nul && set "PY=python" && goto :eof
goto :eof

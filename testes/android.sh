#!/bin/bash
# Instala o APK de teste no emulador, abre e espera a tela do PC chegar (o app escreve no logcat).
# Uso: testes/android.sh NOME arquivo.apk
nome=$1; apk=$2; saida=testes/saida; mkdir -p $saida
pacote=br.unb.ponte.ponte_remota
adb uninstall $pacote >/dev/null 2>&1
adb install "$apk" || exit 1
adb logcat -c
adb shell monkey -p $pacote -c android.intent.category.LAUNCHER 1 >/dev/null
ok=0
for i in $(seq 1 45); do
  sleep 2
  linha=$(adb logcat -d | grep ESTENDA_ESTADO | tail -1)
  if echo "$linha" | grep -q '"sessao":true' && echo "$linha" | grep -q '"quadros":[1-9]'; then ok=1; break; fi
done
sleep 4
adb exec-out screencap -p > $saida/android_$nome.png
echo "---- último estado: $(adb logcat -d | grep ESTENDA_ESTADO | tail -1 | sed 's/.*ESTENDA_ESTADO //')"
adb logcat -d | grep -E "ESTENDA_ERRO|chromium.*(Uncaught|ERROR)|FATAL" | tail -15
adb logcat -d > $saida/logcat_$nome.txt
adb shell am force-stop $pacote
if [ $ok = 1 ]; then echo "ok     android ($nome): o app abriu a tela do PC e chegou imagem"; else echo "FALHOU android ($nome)"; exit 1; fi

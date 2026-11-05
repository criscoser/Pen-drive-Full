#!/bin/bash
# Pendrive Full - diagnostico sem Windows
CY='\033[96m'; RX='\033[95m'; MU='\033[90m'; OK='\033[92m'; B='\033[1m'; X='\033[0m'
clear
echo
echo -e "  ${B}${CY}PENDRIVE${RX}://${CY}FULL${X}  ${MU}v1.0 · diagnóstico sem Windows${X}"
echo -e "  ${MU}> só lê informações. Não altera nada neste computador.${X}"
echo
# Atalho na area de trabalho para rodar de novo quando quiser
if [ -d "$HOME/Desktop" ] && [ ! -f "$HOME/Desktop/pendrive-full-diagnostico.desktop" ]; then
    cp /usr/share/applications/pendrive-full-diagnostico.desktop "$HOME/Desktop/" 2>/dev/null && chmod +x "$HOME/Desktop/pendrive-full-diagnostico.desktop" 2>/dev/null
    gio set "$HOME/Desktop/pendrive-full-diagnostico.desktop" metadata::trusted true 2>/dev/null
fi
if [ "$1" != "--ja" ]; then
    echo -e "  Rodar o diagnóstico agora? ${B}[S/n]${X} ${MU}(começa sozinho em 15 s · aperte N para só usar o Linux)${X}"
    read -r -t 15 -n 1 resp; echo
    case "$resp" in n|N) echo -e "  ${MU}Ok. Para rodar depois: ícone 'Diagnóstico Pendrive Full' na área de trabalho.${X}"; sleep 3; exit 0;; esac
fi
python3 /opt/pendrive-full/diagnostico.py
echo
echo -e "  ${MU}O relatório completo abriu no navegador. Aperte ENTER para fechar esta janela.${X}"
read -r

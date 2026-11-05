#!/bin/bash
# Abre o diagnostico numa janela de terminal assim que a area de trabalho do Linux Mint carrega.
sleep 3
CMD="bash /opt/pendrive-full/diagnostico.sh"
if command -v xfce4-terminal >/dev/null; then
    exec xfce4-terminal --title "PENDRIVE://FULL - diagnostico" --geometry=104x36 --hide-menubar -x $CMD
elif command -v gnome-terminal >/dev/null; then
    exec gnome-terminal --title "PENDRIVE://FULL - diagnostico" -- $CMD
else
    exec x-terminal-emulator -e $CMD
fi

#!/bin/sh
# Monta o pacote que o Ventoy injeta no Linux Mint (diagnostico sem Windows).
# Usa o LiveInjection oficial do Ventoy: https://github.com/ventoy/LiveInjection (GPL-3.0)
#
#   sh montar.sh /caminho/para/LiveInjection
#
# Antes, coloque em sysroot/opt/pendrive-full/ o pacote oficial do Ubuntu 24.04 (base do Mint 22):
#   smartmontools_7.4-2build1_amd64.deb  (SHA-256 8859c62e6346dcf0a1db77a3647f75bb7e009fd28750f5fe0f4f5a95e5078f90)
# Resultado: ../pendrive/ventoy/diagnostico-linux.tar.gz
set -e
LI=${1:?informe a pasta do LiveInjection}
AQUI=$(cd "$(dirname "$0")" && pwd)
SAIDA="$AQUI/../pendrive/ventoy/diagnostico-linux.tar.gz"
TMP=$(mktemp -d)
WD=live_injection_7ed136ec_7a61_4b54_adc3_ae494d5106ea
mkdir -p "$TMP/$WD"

# Permissoes normais (o pack.sh original aplica 777 em tudo, o que deixaria /etc e /opt do Linux abertos)
find "$AQUI/sysroot" -type d -exec chmod 755 {} +
find "$AQUI/sysroot" -type f -exec chmod 644 {} +
chmod 755 "$AQUI"/sysroot/opt/pendrive-full/*.sh "$AQUI"/sysroot/opt/pendrive-full/*.py
(cd "$AQUI" && tar --owner=0 --group=0 --numeric-owner -czf "$TMP/$WD/sysroot.tar.gz" sysroot)

cp -a "$LI/internal/distro" "$TMP/$WD/"
sed 's|^chmod -R 777 /\$datadir/sysroot|# (Pendrive Full) sem chmod 777: as permissoes ja vem certas no pacote|' "$LI/internal/hook.sh" | tr -d '\r' > "$TMP/$WD/hook.sh"
grep -q 'chmod -R 777' "$TMP/$WD/hook.sh" && { echo "ERRO: hook.sh mudou, revise"; exit 1; }

(cd "$TMP" && tar --owner=0 --group=0 --numeric-owner -czf "$SAIDA" "$WD")
rm -rf "$TMP"
ls -l "$SAIDA"

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pendrive Full - diagnostico sem Windows (roda no Linux Mint live pelo Ventoy).

Le a saude da maquina (SSD/HD, bateria, memoria, processador, BIOS), mostra um
resumo no terminal, gera o mesmo relatorio HTML do Windows e grava no pendrive
(Relatorios/ e Relatorios/dados/), para entrar no Resumo-das-maquinas.

Nao altera nada no computador: so le informacoes.
"""
import datetime
import glob
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
FAKE = os.environ.get('PF_FAKE')          # pasta com saidas gravadas (so para teste)

# ---------------------------------------------------------------- utilidades
C = {'ac': '\033[96m', 'ok': '\033[92m', 'av': '\033[93m', 'ru': '\033[91m', 'mu': '\033[90m', 'b': '\033[1m', 'x': '\033[0m'}


def cor(t, c):
    return f"{C[c]}{t}{C['x']}"


def run(cmd, sudo=False, timeout=60):
    """Executa um comando e devolve a saida (texto). Nunca levanta erro."""
    if FAKE:
        nome = re.sub(r'[^A-Za-z0-9]+', '_', ' '.join(cmd)).strip('_')[:120]
        arq = os.path.join(FAKE, nome + '.txt')
        return open(arq, encoding='utf-8').read() if os.path.exists(arq) else ''
    if sudo and os.geteuid() != 0:
        cmd = ['sudo', '-n'] + cmd
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ''


def ler(caminho):
    try:
        with open(caminho, encoding='utf-8', errors='replace') as f:
            return f.read().strip()
    except Exception:
        return ''


def num(v):
    try:
        return int(str(v).strip())
    except Exception:
        return None


def barra(pct, tam=20):
    n = max(0, min(tam, round((pct or 0) / 100 * tam)))
    return '█' * n + '░' * (tam - n)


def fmt(v, suf=''):
    if v is None:
        return '?'
    if isinstance(v, (int, float)):
        return f"{v:,.0f}".replace(',', '.') + suf
    return f"{v}{suf}"


# ---------------------------------------------------------------- smartctl
def acha_smartctl():
    """smartctl do sistema, ou extraido do pacote que vai junto (sem instalar nada)."""
    if FAKE:
        return 'smartctl'
    s = shutil.which('smartctl') or ('/usr/sbin/smartctl' if os.path.exists('/usr/sbin/smartctl') else None)
    if s:
        return s
    for deb in sorted(glob.glob(os.path.join(AQUI, 'smartmontools*.deb'))) + sorted(glob.glob('/media/*/*/Portateis/Linux/smartmontools*.deb')):
        destino = os.path.join(tempfile.gettempdir(), 'pf-smart')
        subprocess.run(['dpkg-deb', '-x', deb, destino], capture_output=True)
        s = os.path.join(destino, 'usr', 'sbin', 'smartctl')
        if os.path.exists(s):
            return s
    # Ultimo recurso: com internet, instala pelo proprio Linux (so nesta sessao, nada vai para o disco do PC)
    if run(['ping', '-c', '1', '-W', '3', 'archive.ubuntu.com']).strip():
        print(cor('  > baixando o leitor de SMART (smartmontools)...', 'mu'))
        run(['apt-get', 'update'], sudo=True, timeout=180)
        run(['apt-get', 'install', '-y', '--no-install-recommends', 'smartmontools'], sudo=True, timeout=180)
        if os.path.exists('/usr/sbin/smartctl'):
            return '/usr/sbin/smartctl'
    return None


# ---------------------------------------------------------------- coleta
def dmi(chave):
    v = run(['dmidecode', '-s', chave], sudo=True).strip()
    v = '\n'.join(l for l in v.splitlines() if not l.startswith('#')).strip()
    if v.lower() in ('', 'not specified', 'to be filled by o.e.m.', 'default string', 'system serial number', 'none'):
        return ''
    return v


def coleta_maquina():
    m = {
        'Fabricante': dmi('system-manufacturer'), 'Produto': dmi('system-product-name'), 'Versao': dmi('system-version'),
        'Serie': dmi('system-serial-number'), 'Bios': re.sub(r'\s+\)', ')', re.sub(r'\s+', ' ', dmi('bios-version'))).strip(),
        'BiosData': dmi('bios-release-date'),
    }
    cpu = ''
    for l in run(['lscpu']).splitlines():
        if l.lower().startswith('model name') or l.lower().startswith('nome do modelo'):
            cpu = l.split(':', 1)[1].strip()
            break
    m['Cpu'] = cpu or '?'
    m['Uefi'] = os.path.isdir('/sys/firmware/efi') if not FAKE else True
    # Nome igual ao do Windows: MODELO-SERIE (ex.: T480-PE04DSDC)
    modelo = re.sub(r'(?i)thinkpad\s*', '', m['Versao']).strip() if 'lenovo' in m['Fabricante'].lower() else ''
    if not modelo:
        modelo = m['Versao'] if m['Versao'] and m['Versao'].lower() not in ('', '1.0') else ''
    if not modelo:
        modelo = 'PC'
    nome = re.sub(r'[^A-Za-z0-9-]', '', f"{modelo}-{m['Serie']}")[:15].strip('-') or 'PC'
    m['Modelo'] = modelo
    m['Nome'] = nome
    titulo = m['Versao'] if 'lenovo' in m['Fabricante'].lower() and m['Versao'] else m['Produto']
    m['Titulo'] = f"{m['Fabricante']} {titulo}".strip()
    return m


def coleta_memoria():
    saida = run(['dmidecode', '-t', '17'], sudo=True)
    pentes, slots = [], 0
    for bloco in saida.split('\n\n'):
        if 'Memory Device' not in bloco:
            continue
        slots += 1
        campos = {}
        for l in bloco.splitlines():
            if ':' in l:
                k, v = l.split(':', 1)
                campos[k.strip()] = v.strip()
        tam = campos.get('Size', '')
        if not tam or 'No Module' in tam or 'Not Installed' in tam:
            continue
        mt = re.match(r'(\d+)\s*(GB|MB)', tam)
        gb = (int(mt.group(1)) / (1024 if mt.group(2) == 'MB' else 1)) if mt else 0
        vel = campos.get('Configured Memory Speed') or campos.get('Configured Clock Speed') or campos.get('Speed') or '?'
        pentes.append({'Slot': campos.get('Locator', '?'), 'GB': gb, 'Velocidade': vel, 'Tipo': campos.get('Type', ''),
                       'Fabricante': f"{campos.get('Manufacturer', '')} {campos.get('Part Number', '')}".strip()})
    total = round(sum(p['GB'] for p in pentes))
    if not total:   # sem dmidecode: usa o que o Linux enxerga
        mt = re.search(r'MemTotal:\s+(\d+)', ler('/proc/meminfo') if not FAKE else run(['cat', '/proc/meminfo']))
        total = round(int(mt.group(1)) / 1024 / 1024) if mt else 0
    return {'Total': total, 'Pentes': pentes, 'Slots': slots}


def coleta_bateria():
    bats = []
    base = os.path.join(FAKE, 'power_supply') if FAKE else '/sys/class/power_supply'
    for d in sorted(glob.glob(os.path.join(base, 'BAT*'))):
        un = 'mWh'
        atual = num(ler(os.path.join(d, 'energy_full')))
        orig = num(ler(os.path.join(d, 'energy_full_design')))
        if not orig:
            un = 'mAh'
            atual = num(ler(os.path.join(d, 'charge_full')))
            orig = num(ler(os.path.join(d, 'charge_full_design')))
        if not orig:
            continue
        bats.append({'Nome': os.path.basename(d), 'Atual': atual or 0, 'Original': orig, 'Un': un, 'Ciclos': num(ler(os.path.join(d, 'cycle_count'))),
                     'Modelo': f"{ler(os.path.join(d, 'manufacturer'))} {ler(os.path.join(d, 'model_name'))}".strip()})
    if not bats:
        return None
    orig = sum(b['Original'] for b in bats)
    atual = sum(b['Atual'] for b in bats)
    return {'Pct': round(100 * atual / orig) if orig else None, 'Original': orig // 1000, 'Atual': atual // 1000, 'Baterias': bats}


def coleta_discos(smartctl):
    try:
        lista = json.loads(run(['lsblk', '-J', '-d', '-b', '-o', 'NAME,MODEL,SERIAL,SIZE,ROTA,TRAN,TYPE']) or '{}').get('blockdevices', [])
    except Exception:
        lista = []
    discos = []
    for d in lista:
        if d.get('type') != 'disk' or (d.get('tran') or '') == 'usb' or d['name'].startswith(('loop', 'zram', 'sr', 'dm-')):
            continue
        dev = '/dev/' + d['name']
        info = {'Dev': dev, 'Modelo': (d.get('model') or '?').strip(), 'Serie': (d.get('serial') or '').strip(),
                'GB': round(int(d.get('size') or 0) / 1e9), 'Tipo': 'HD' if str(d.get('rota')) in ('1', 'True', 'true') else 'SSD',
                'Saude': None, 'Erros': None, 'Horas': None, 'Gravado': None, 'Desligamentos': None, 'Temp': None, 'Passou': None,
                'Sistemas': []}
        if d['name'].startswith('nvme'):
            info['Tipo'] = 'SSD NVMe'
        if smartctl:
            try:
                j = json.loads(run([smartctl, '-j', '-a', dev], sudo=True) or '{}')
            except Exception:
                j = {}
            le_smart(j, info)
        # O que tem gravado no disco (so le o tipo das particoes, nao monta nada)
        try:
            parts = json.loads(run(['lsblk', '-J', '-o', 'NAME,FSTYPE,LABEL,PARTTYPENAME', dev]) or '{}').get('blockdevices', [{}])[0].get('children', [])
        except Exception:
            parts = []
        tipos = {(p.get('fstype') or '').lower() for p in parts}
        nomes = ' '.join((p.get('parttypename') or '') + ' ' + (p.get('label') or '') for p in parts).lower()
        if 'ntfs' in tipos or 'bitlocker' in tipos or 'microsoft' in nomes:
            info['Sistemas'].append('Windows')
        if tipos & {'ext4', 'btrfs', 'xfs'}:
            info['Sistemas'].append('Linux')
        info['Particoes'] = len(parts)
        discos.append(info)
    return discos


def le_smart(j, info):
    if not j:
        return
    info['Modelo'] = j.get('model_name') or info['Modelo']
    info['Serie'] = j.get('serial_number') or info['Serie']
    st = j.get('smart_status') or {}
    if 'passed' in st:
        info['Passou'] = bool(st['passed'])
    info['Horas'] = (j.get('power_on_time') or {}).get('hours')
    info['Temp'] = (j.get('temperature') or {}).get('current')
    if (j.get('rotation_rate') or 0) > 0:
        info['Tipo'] = 'HD'
    nv = j.get('nvme_smart_health_information_log')
    if nv:
        pu = nv.get('percentage_used')
        if pu is not None:
            info['Saude'] = max(0, 100 - int(pu))
        info['Erros'] = nv.get('media_errors')
        info['Desligamentos'] = nv.get('unsafe_shutdowns')
        if nv.get('data_units_written') is not None:
            info['Gravado'] = round(nv['data_units_written'] * 512000 / 1e9)
        info['Horas'] = nv.get('power_on_hours', info['Horas'])
        return
    attrs = {a.get('id'): a for a in (j.get('ata_smart_attributes') or {}).get('table', [])}

    def bruto(i):
        a = attrs.get(i)
        return (a.get('raw') or {}).get('value') if a else None
    # Vida util do SSD: o valor normalizado (0-100) destes atributos, o primeiro que existir
    for i in (231, 233, 177, 169, 202, 173):
        a = attrs.get(i)
        if a and info['Tipo'] != 'HD' and a.get('value') is not None and 0 < a['value'] <= 100:
            info['Saude'] = int(a['value'])
            break
    erros = [bruto(i) for i in (5, 197, 198) if bruto(i) is not None]
    info['Erros'] = sum(erros) if erros else None
    info['Desligamentos'] = bruto(192) if bruto(192) is not None else bruto(174)
    lbas = bruto(241)
    if lbas is not None and 'lba' in (attrs[241].get('name') or '').lower():
        info['Gravado'] = round(lbas * (j.get('logical_block_size') or 512) / 1e9)


# ---------------------------------------------------------------- avaliacao (mesmas regras do relatorio do Windows)
def avalia(maq, mem, bat, discos):
    cards = []

    def card(nome, valor, status, dica):
        cards.append({'Nome': nome, 'Valor': valor, 'Status': status, 'Dica': dica})

    # Disco principal = o primeiro interno
    d = discos[0] if discos else None
    if not d:
        card('SSD', 'Nenhum disco', 'ruim', 'Nenhum SSD/HD interno detectado - verifique o disco e o cabo')
    else:
        st, dica = 'info', 'Não foi possível ler a saúde do disco'
        if d['Saude'] is not None:
            if d['Saude'] >= 70:
                st, dica = 'ok', 'Vida útil boa'
            elif d['Saude'] >= 30:
                st, dica = 'atencao', 'Desgaste médio - acompanhe'
            else:
                st, dica = 'ruim', 'Pouca vida útil - planeje a troca'
        elif d['Passou'] is True:
            st, dica = 'ok', 'Teste SMART aprovado'
        if d['Erros']:
            st, dica = 'ruim', f"{fmt(d['Erros'])} erros de leitura/gravação - TROCAR o disco e não guardar nada importante nele"
        if d['Passou'] is False:
            st, dica = 'ruim', 'O próprio disco informa FALHA (SMART) - TROCAR'
        if d['Serie']:
            dica += f" (série {d['Serie']})"
        valor = f"{d['Saude']}% de vida útil" if d['Saude'] is not None else ('Aprovado' if d['Passou'] else '?')
        card('SSD', valor, st, dica)

    if bat and bat['Pct'] is not None:
        st = 'ok' if bat['Pct'] >= 80 else ('atencao' if bat['Pct'] >= 60 else 'ruim')
        dica = {'ok': 'Autonomia boa', 'atencao': 'Autonomia reduzida', 'ruim': 'Bateria gasta - considerar troca'}[st]
        ciclos = ' + '.join(str(b['Ciclos']) for b in bat['Baterias'] if b['Ciclos'] is not None)
        extra = f" ({ciclos} ciclos" + (f", {len(bat['Baterias'])} baterias)" if len(bat['Baterias']) > 1 else ')') if ciclos else ''
        card('Bateria', f"{bat['Pct']}% da original", st, dica + extra)
    else:
        card('Bateria', 'Sem bateria', 'info', 'Desktop ou bateria não detectada')

    gb = mem['Total']
    canal = 'dois canais' if len(mem['Pentes']) >= 2 else 'canal único'
    st = 'ok' if gb >= 16 else ('atencao' if gb >= 8 else 'ruim')
    if gb >= 16:
        dica = 'Memória suficiente'
    elif len(mem['Pentes']) < 2 and mem['Slots'] >= 2:
        dica = 'Colocar +1 pente de 8 GB deixa a máquina bem mais rápida'
    else:
        dica = 'Pouca memória para o uso atual'
    card('Memória', f"{gb} GB ({canal})", st, dica + ' · teste com o MemTest86 do pendrive')

    card('Drivers', 'Sem Windows', 'info', 'Verifique depois de instalar o Windows')

    sist = sorted({s for x in discos for s in x['Sistemas']})
    if 'Windows' in sist:
        card('Windows', 'Encontrado no disco', 'atencao', 'O disco tem Windows, mas ele não iniciou - pode estar corrompido')
    else:
        card('Windows', 'Não instalado', 'info', 'Disco sem Windows' + (f" ({', '.join(sist)})" if sist else ' - pronto para instalar'))

    bios_dt = None
    try:
        bios_dt = datetime.datetime.strptime(maq['BiosData'], '%m/%d/%Y')
    except Exception:
        pass
    if bios_dt:
        idade = (datetime.datetime.now() - bios_dt).days / 365
        st = 'ok' if idade <= 2 else 'atencao'
        card('BIOS', f"{maq['Bios']} ({bios_dt:%m/%Y})", st, 'Atualizada' if st == 'ok' else 'Antiga - atualize pelo site ou ferramenta do fabricante')
    else:
        card('BIOS', maq['Bios'] or '?', 'info', 'Data da BIOS não informada')
    return cards


# ---------------------------------------------------------------- HTML (mesmo visual do relatorio do Windows)
COR = {'ok': '#1f9d55', 'atencao': '#d4880f', 'ruim': '#d33a2c', 'info': '#6b7280'}
FUNDO = {'ok': '#e8f6ee', 'atencao': '#fdf3e1', 'ruim': '#fbe9e7', 'info': '#f1f2f4'}
ROTULO = {'ok': 'OK', 'atencao': 'ATENÇÃO', 'ruim': 'PROBLEMA', 'info': 'INFO'}
GERAL_TXT = {'ok': 'Máquina aprovada', 'atencao': 'Aprovada com observações', 'ruim': 'Precisa de manutenção'}


def geral(cards):
    st = [c['Status'] for c in cards]
    return 'ruim' if 'ruim' in st else ('atencao' if 'atencao' in st else 'ok')


def monta_html(maq, mem, bat, discos, extras, cards, agora):
    e = html.escape
    g = geral(cards)
    hc = '\n'.join(
        f"<div class='card' style='border-top:5px solid {COR[c['Status']]};background:{FUNDO[c['Status']]}'><div class='cn'>{e(c['Nome'])}"
        f"<span class='tag' style='background:{COR[c['Status']]}'>{ROTULO[c['Status']]}</span></div><div class='cv'>{e(str(c['Valor']))}</div>"
        f"<div class='cd'>{e(c['Dica'])}</div></div>" for c in cards)
    linhas_disco = ''
    for d in discos:
        linhas_disco += (f"<tr><th colspan='2' style='color:#1f2933;padding-top:14px'>{e(d['Tipo'])} {e(d['Dev'])} &middot; {d['GB']} GB</th></tr>"
                         f"<tr><th>Modelo</th><td>{e(d['Modelo'])}</td></tr><tr><th>Número de série</th><td>{e(d['Serie'] or '?')}</td></tr>"
                         f"<tr><th>Vida útil restante</th><td>{fmt(d['Saude'], '%')}</td></tr>"
                         f"<tr><th>Teste SMART do próprio disco</th><td>{'Aprovado' if d['Passou'] else ('FALHOU' if d['Passou'] is False else '?')}</td></tr>"
                         f"<tr><th>Erros de dados (tem que ser 0)</th><td>{fmt(d['Erros'])}</td></tr>"
                         f"<tr><th>Horas ligado</th><td>{fmt(d['Horas'], ' h')}</td></tr><tr><th>Total gravado</th><td>{fmt(d['Gravado'], ' GB')}</td></tr>"
                         f"<tr><th>Desligamentos inesperados</th><td>{fmt(d['Desligamentos'])}</td></tr><tr><th>Temperatura</th><td>{fmt(d['Temp'], ' &deg;C')}</td></tr>"
                         f"<tr><th>Sistemas no disco</th><td>{e(', '.join(d['Sistemas']) or 'nenhum')} ({d.get('Particoes', 0)} partição(ões))</td></tr>")
    if not discos:
        linhas_disco = '<tr><td>Nenhum disco interno detectado</td></tr>'
    if bat:
        lb = ''.join(f"<tr><th>{e(b['Nome'])} {e(b['Modelo'])}</th><td>{fmt(b['Atual'] // 1000, ' ' + b['Un'])} de {fmt(b['Original'] // 1000, ' ' + b['Un'])} "
                     f"({round(100 * b['Atual'] / b['Original']) if b['Original'] else '?'}%) &middot; {fmt(b['Ciclos'])} ciclos</td></tr>" for b in bat['Baterias'])
    else:
        lb = '<tr><td>Não detectada</td></tr>'
    lm = ''.join(f"<tr><td>{e(p['Slot'])}</td><td>{p['GB']:g} GB {e(p['Tipo'])}</td><td>{e(p['Velocidade'])}</td><td>{e(p['Fabricante'])}</td></tr>" for p in mem['Pentes'])
    lx = ''.join(f"<li>{e(x)}</li>" for x in extras) or '<li>?</li>'
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Relatório {e(maq['Nome'])}</title>
<style>
*{{box-sizing:border-box}} body{{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:#f4f5f7;color:#1f2933}}
.wrap{{max-width:1000px;margin:0 auto;padding:24px 16px}}
header{{background:#1f2933;color:#fff;border-radius:14px;padding:22px 26px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:12px;align-items:center}}
header h1{{margin:0;font-size:26px}} header .sub{{opacity:.8;font-size:14px;margin-top:4px}}
.veredito{{padding:10px 18px;border-radius:999px;font-weight:700;font-size:16px;color:#fff;background:{COR[g]}}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin:20px 0}}
.card{{border-radius:12px;padding:16px 18px;box-shadow:0 1px 2px rgba(0,0,0,.06)}}
.cn{{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:#52606d;display:flex;justify-content:space-between;align-items:center}}
.tag{{color:#fff;font-size:11px;padding:2px 8px;border-radius:999px;letter-spacing:.03em}}
.cv{{font-size:24px;font-weight:700;margin:8px 0 4px}} .cd{{font-size:13px;color:#3e4c59}}
section{{background:#fff;border-radius:12px;padding:18px 22px;margin-bottom:14px;box-shadow:0 1px 2px rgba(0,0,0,.06)}}
h2{{font-size:16px;margin:0 0 12px;color:#1f2933}}
table{{width:100%;border-collapse:collapse;font-size:14px}} td,th{{padding:7px 8px;border-bottom:1px solid #e4e7eb;text-align:left;vertical-align:top}} th{{color:#52606d;font-weight:600;width:38%}}
ul{{margin:0;padding-left:18px}} li{{padding:3px 0;font-size:14px}}
footer{{text-align:center;color:#7b8794;font-size:12px;margin:18px 0}}
@media print{{body{{background:#fff}} section,.card{{box-shadow:none;border:1px solid #ddd}}}}
</style></head><body><div class="wrap">
<header><div><h1>{e(maq['Nome'])}</h1><div class="sub">{e(maq['Titulo'])} &middot; Série {e(maq['Serie'] or '?')} &middot; {agora:%d/%m/%Y %H:%M} &middot; diagnóstico sem Windows</div></div>
<div class="veredito">{GERAL_TXT[g]}</div></header>
<div class="grid">
{hc}
</div>
<section><h2>Máquina</h2><table>
<tr><th>Modelo</th><td>{e(maq['Titulo'])} ({e(maq['Produto'])})</td></tr>
<tr><th>Processador</th><td>{e(maq['Cpu'])}</td></tr>
<tr><th>BIOS</th><td>{e(maq['Bios'] or '?')} de {e(maq['BiosData'] or '?')} &middot; modo {'UEFI' if maq['Uefi'] else 'Legacy/BIOS'}</td></tr>
</table></section>
<section><h2>Discos</h2><table>{linhas_disco}</table></section>
<section><h2>Bateria</h2><table>{lb}</table></section>
<section><h2>Memória - {mem['Total']} GB, {len(mem['Pentes'])} pente(s), {mem['Slots']} slot(s)</h2><table>
<tr><th>Slot</th><th>Tamanho</th><th>Velocidade</th><th>Fabricante / modelo</th></tr>{lm}
</table></section>
<section><h2>Vídeo e rede</h2><ul>{lx}</ul></section>
<footer>Gerado pelo Pendrive Full &middot; diagnóstico pelo Linux, nada foi alterado no computador</footer>
</div></body></html>
"""


# ---------------------------------------------------------------- pendrive
def acha_pendrive():
    """Pasta raiz do pendrive Ventoy (particao com o rotulo Ventoy). Monta se precisar."""
    if FAKE:
        return os.environ.get('PF_PENDRIVE')
    try:
        devs = json.loads(run(['lsblk', '-J', '-o', 'NAME,LABEL,MOUNTPOINT,FSTYPE']) or '{}').get('blockdevices', [])
    except Exception:
        devs = []
    alvo = None

    def busca(lista):
        nonlocal alvo
        for d in lista:
            if (d.get('label') or '').lower() == 'ventoy' and d.get('fstype') in ('exfat', 'ntfs', 'vfat'):
                alvo = d
            busca(d.get('children') or [])
    busca(devs)
    if not alvo:
        return None
    if alvo.get('mountpoint'):
        return alvo['mountpoint']
    out = run(['udisksctl', 'mount', '-b', '/dev/' + alvo['name'], '--no-user-interaction'])
    m = re.search(r' at (.+?)\.?$', out.strip())
    return m.group(1) if m else None


def resumo(pasta):
    """Refaz Relatorios/Resumo-das-maquinas.html (igual ao do Windows) com todas as maquinas ja atendidas."""
    e = html.escape
    todas = []
    for f in glob.glob(os.path.join(pasta, 'dados', '*.json')):
        try:
            todas.append(json.load(open(f, encoding='utf-8-sig')))
        except Exception:
            pass
    todas.sort(key=lambda m: str(m.get('Nome', '')).lower())
    colunas = ['SSD', 'Bateria', 'Memória', 'Drivers', 'Windows', 'BIOS']
    cab = ''.join(f'<th>{c}</th>' for c in colunas)
    linhas = []
    for m in todas:
        cartoes = m.get('Cards') or []
        if isinstance(cartoes, dict):
            cartoes = [cartoes]
        cel = ''
        for n in colunas:
            c = next((x for x in cartoes if x.get('Nome') == n), None)
            cel += (f"<td><span class='dot' style='background:{COR.get(c.get('Status'), COR['info'])}'></span>{e(str(c.get('Valor', '')))}</td>" if c else '<td>-</td>')
        ssd = f"<br>SSD: {e(str(m['SerieSSD']))}" if m.get('SerieSSD') else ''
        linhas.append(f"<tr><td><a href='{e(str(m.get('Arquivo', '')))}'><b>{e(str(m.get('Nome', '')))}</b></a><div class='s'>{e(str(m.get('Modelo', '')))} &middot; {e(str(m.get('Data', '')))}{ssd}</div></td>"
                      f"<td><span class='v' style='background:{COR.get(m.get('Geral'), COR['info'])}'>{e(str(m.get('GeralTxt', '')))}</span></td>{cel}</tr>")
    pagina = f"""<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Resumo das máquinas</title>
<style>body{{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:#f4f5f7;color:#1f2933}}.wrap{{max-width:1200px;margin:0 auto;padding:24px 16px}}
h1{{margin:0 0 4px}}.sub{{color:#52606d;margin-bottom:18px}}table{{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 2px rgba(0,0,0,.06);font-size:14px}}
th{{background:#1f2933;color:#fff;text-align:left;padding:10px;font-weight:600}}td{{padding:10px;border-bottom:1px solid #e4e7eb;vertical-align:top}}a{{color:#1f2933}}
.s{{color:#7b8794;font-size:12px}}.dot{{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px}}.v{{color:#fff;font-size:12px;font-weight:700;padding:3px 10px;border-radius:999px;white-space:nowrap}}</style></head>
<body><div class="wrap"><h1>Resumo das máquinas</h1><div class="sub">{len(todas)} máquina(s) &middot; clique no nome para ver o relatório completo</div>
<table><tr><th>Máquina</th><th>Situação</th>{cab}</tr>
{chr(10).join(linhas)}
</table></div></body></html>
"""
    with open(os.path.join(pasta, 'Resumo-das-maquinas.html'), 'w', encoding='utf-8-sig') as f:
        f.write(pagina)


def grava(maq, cards, html_txt, agora):
    destinos = []
    arq = f"Relatorio-{maq['Nome']}.html"
    for mesa in (os.path.expanduser('~/Desktop'), os.path.expanduser('~/Área de Trabalho'), os.path.expanduser('~'), tempfile.gettempdir()):
        try:
            if os.path.isdir(mesa):
                caminho_local = os.path.join(mesa, arq)
                with open(caminho_local, 'w', encoding='utf-8') as f:
                    f.write(html_txt)
                destinos.append(caminho_local)
                break
        except Exception:
            continue
    raiz = acha_pendrive()
    if raiz and os.path.isdir(raiz):
        try:
            pasta = os.path.join(raiz, 'Relatorios')
            os.makedirs(os.path.join(pasta, 'dados'), exist_ok=True)
            with open(os.path.join(pasta, arq), 'w', encoding='utf-8') as f:
                f.write(html_txt)
            g = geral(cards)
            dados = {'Nome': maq['Nome'], 'Modelo': maq['Modelo'], 'Serie': maq['Serie'], 'SerieSSD': maq.get('SerieSSD', ''),
                     'Data': f"{agora:%d/%m/%Y %H:%M}", 'Geral': g, 'GeralTxt': GERAL_TXT[g], 'Cards': cards, 'Arquivo': arq, 'Origem': 'Linux'}
            with open(os.path.join(pasta, 'dados', maq['Nome'] + '.json'), 'w', encoding='utf-8-sig') as f:
                json.dump(dados, f, ensure_ascii=False, indent=2)
            destinos.append(os.path.join(pasta, arq))
            resumo(pasta)
        except Exception as ex:
            print(cor(f"  (aviso) não foi possível gravar no pendrive: {ex}", 'av'))
    else:
        print(cor('  (aviso) pendrive não encontrado para gravar; o relatório ficou na Área de Trabalho do Linux', 'av'))
    return destinos


# ---------------------------------------------------------------- terminal
def mostra_terminal(maq, cards, discos):
    simb = {'ok': cor('[ OK ]', 'ok'), 'atencao': cor('[WARN]', 'av'), 'ruim': cor('[FAIL]', 'ru'), 'info': cor('[INFO]', 'mu')}
    print()
    print(cor(f"  {maq['Nome']}", 'b') + cor(f"  ·  {maq['Titulo']}  ·  série {maq['Serie'] or '?'}", 'mu'))
    print(cor(f"  {maq['Cpu']}", 'mu'))
    print()
    for c in cards:
        valor = str(c['Valor'])
        m = re.match(r'(\d+)%', valor)
        b = ''
        if m:
            k = {'ok': 'ok', 'atencao': 'av', 'ruim': 'ru'}.get(c['Status'], 'mu')
            b = cor(barra(int(m.group(1))), k) + ' '
        print(f"  {simb[c['Status']]} {c['Nome']:<9} {b}{cor(valor, 'b')}")
        print(cor(f"           {c['Dica']}", 'mu'))
    g = geral(cards)
    print()
    print('  ' + {'ok': cor('■ ' + GERAL_TXT[g], 'ok'), 'atencao': cor('■ ' + GERAL_TXT[g], 'av'), 'ruim': cor('■ ' + GERAL_TXT[g], 'ru')}[g])


def extras_hw():
    itens = []
    for l in run(['lspci']).splitlines():
        if re.search(r'VGA|3D controller|Display controller|Network controller|Ethernet controller', l):
            itens.append(re.sub(r'^\S+\s+', '', l))
    return itens


def main():
    print(cor('  > lendo informações da máquina...', 'mu'))
    agora = datetime.datetime.now()
    smartctl = acha_smartctl()
    if not smartctl:
        print(cor('  (aviso) smartctl não encontrado: a saúde do disco não será lida', 'av'))
    maq = coleta_maquina()
    mem = coleta_memoria()
    bat = coleta_bateria()
    print(cor('  > lendo a saúde dos discos (SMART)...', 'mu'))
    discos = coleta_discos(smartctl)
    maq['SerieSSD'] = discos[0]['Serie'] if discos else ''
    if not maq['Serie'] and maq['SerieSSD']:
        # PC sem numero de serie na placa: usa o final da serie do disco para cada maquina ter seu proprio relatorio
        maq['Nome'] = re.sub(r'[^A-Za-z0-9-]', '', f"{maq['Modelo']}-{maq['SerieSSD'][-8:]}")[:15].strip('-')
    extras = extras_hw()
    cards = avalia(maq, mem, bat, discos)
    mostra_terminal(maq, cards, discos)
    html_txt = monta_html(maq, mem, bat, discos, extras, cards, agora)
    destinos = grava(maq, cards, html_txt, agora)
    print()
    for d in destinos:
        print(cor('  [ OK ] ', 'ok') + f"relatório salvo em {d}")
    if destinos and not FAKE and os.environ.get('PF_SEM_NAVEGADOR') != '1':
        subprocess.Popen(['xdg-open', destinos[0]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(1)

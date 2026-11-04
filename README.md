# Pendrive Fodão

> 🇧🇷 [Português](#-português) · 🇺🇸 [English](#-english)

Pendrive multiboot de manutenção baseado no [Ventoy](https://github.com/ventoy/Ventoy): formata, instala o Windows 11 sem perguntas, configura a máquina sozinho e entrega um relatório visual da saúde do hardware.

*A Ventoy-based multiboot maintenance USB drive: it reinstalls Windows 11 unattended, configures the machine by itself and produces a visual hardware health report.*

![Relatório de exemplo](docs/relatorio-exemplo.png)

---

## 🇧🇷 Português

> ⚠️ **Projeto em desenvolvimento.** Testado em notebooks Lenovo ThinkPad T490 com Windows 11 Pro. Use por sua conta e risco e teste numa máquina antes de usar nas outras.

### O que ele faz

**No boot (menu do Ventoy)**
- Instala o Windows 11 com o arquivo de respostas `autounattend.xml`: português, teclado ABNT2, conta local sem e-mail da Microsoft, sem telas de privacidade. **A escolha do disco continua manual**, para nunca apagar o disco errado.
- Ferramentas de boot: MemTest86 (memória), Rescuezilla (backup/clonagem), GParted (partições), Linux Mint (resgate de arquivos), ShredOS (apagar disco).
- Se a máquina reiniciar com o pendrive conectado e ninguém escolher nada, em 10 segundos ela entra no Windows instalado.

**Depois da instalação (`POS-FORMATACAO.bat`, ou sozinho no primeiro login)**
1. Energia: não dorme na tomada durante o processo.
2. Wi-Fi: conecta na rede configurada.
3. Limpeza: remove apps desnecessários e propagandas, mostra extensões de arquivo.
4. Programas via `winget`: Chrome, 7-Zip, Adobe Reader, VLC, AnyDesk, Lenovo System Update. **Pula o que já está instalado.**
5. Microsoft 365 Apps (Office) pelo instalador oficial da Microsoft.
6. Chrome como navegador padrão e fixado na barra de tarefas, sem perguntas.
7. Drivers e BIOS Lenovo.
8. Windows Update.
9. Renomeia o PC (`MODELO-SÉRIE`) e gera o relatório.

**Relatório visual**
- Cartões verde/amarelo/vermelho para SSD, bateria, memória, drivers, ativação do Windows e BIOS, com uma frase dizendo o que fazer.
- `Relatorios/Resumo-das-maquinas.html` no pendrive compara todas as máquinas já atendidas.
- `RELATORIO.bat` gera só o relatório, sem refazer a pós-formatação.

![Resumo das máquinas](docs/resumo-exemplo.png)

### Estrutura

```
pendrive/                       → conteúdo da raiz do pendrive Ventoy
├── POS-FORMATACAO.bat          → pós-formatação completa
├── RELATORIO.bat               → só o relatório
├── PosFormatacao/
│   ├── pos-formatacao.ps1      → o script principal
│   └── config.example.json     → copie para config.json e preencha
├── ventoy/
│   ├── ventoy.json             → configuração do Ventoy
│   └── script/autounattend.xml → instalação automática do Windows 11
├── ISOs/                       → ISOs (não versionadas, ver LEIA-ME de cada pasta)
├── Drivers/  Portateis/        → programas portáteis (não versionados)
docs/                           → imagens do README
```

### Como montar o seu

1. Instale o Ventoy no pendrive (exFAT, GPT, Secure Boot ligado).
2. Copie o conteúdo da pasta `pendrive/` para a raiz do pendrive.
3. Baixe as ISOs e ferramentas indicadas no `LEIA-ME.txt` de cada pasta, sempre dos sites oficiais.
4. Copie `PosFormatacao/config.example.json` para `config.json` e preencha Wi-Fi, programas e Office.
5. Se a sua ISO do Windows tiver outro nome, ajuste o caminho em `ventoy/ventoy.json`.

> 🔒 O `config.json` guarda a senha do Wi-Fi e **não** vai para o repositório (`.gitignore`).

### Licença

A definir antes da publicação. As ferramentas de terceiros (Ventoy, MemTest86, etc.) **não** são redistribuídas aqui: cada uma é baixada do site oficial e segue a sua própria licença.

---

## 🇺🇸 English

> ⚠️ **Work in progress.** Tested on Lenovo ThinkPad T490 laptops with Windows 11 Pro. Use at your own risk and test on one machine first.

> 🌐 The pendrive itself is currently in Brazilian Portuguese. A language selector (Portuguese / US English) is on the [roadmap](ROADMAP.md).

### What it does

**At boot (Ventoy menu)**
- Installs Windows 11 with an `autounattend.xml` answer file: local account without a Microsoft account, no privacy screens. **Disk selection stays manual**, so it never wipes the wrong drive.
- Boot tools: MemTest86 (RAM), Rescuezilla (backup/cloning), GParted (partitions), Linux Mint (file rescue), ShredOS (disk wipe).
- If the machine reboots with the drive plugged in and nobody picks anything, it boots the installed Windows after 10 seconds.

**After installation (`POS-FORMATACAO.bat`, or automatically at first logon)**
1. Power: no sleep on AC while it runs.
2. Wi-Fi: connects to the configured network.
3. Cleanup: removes bloatware and ads, shows file extensions.
4. Apps via `winget`: Chrome, 7-Zip, Adobe Reader, VLC, AnyDesk, Lenovo System Update. **Skips anything already installed.**
5. Microsoft 365 Apps (Office) through Microsoft's official deployment tool.
6. Chrome as default browser and pinned to the taskbar, with no prompts.
7. Lenovo drivers and BIOS.
8. Windows Update.
9. Renames the PC (`MODEL-SERIAL`) and builds the report.

**Visual report**
- Green/yellow/red cards for SSD, battery, RAM, drivers, Windows activation and BIOS, each with a plain-language next step.
- `Relatorios/Resumo-das-maquinas.html` on the drive compares every machine serviced.
- `RELATORIO.bat` builds only the report, without re-running the post-install steps.

### Build your own

1. Install Ventoy on the USB drive (exFAT, GPT, Secure Boot on).
2. Copy the contents of `pendrive/` to the root of the drive.
3. Download the ISOs and tools listed in each folder's `LEIA-ME.txt`, always from the official sites.
4. Copy `PosFormatacao/config.example.json` to `config.json` and fill in Wi-Fi, apps and Office.
5. If your Windows ISO has a different name, update the path in `ventoy/ventoy.json`.

> 🔒 `config.json` holds the Wi-Fi password and is **not** committed (`.gitignore`).

### License

To be decided before the public release. Third-party tools (Ventoy, MemTest86, etc.) are **not** redistributed here: each one is downloaded from its official site and keeps its own license.

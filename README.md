# Pendrive Full

> 🇧🇷 [Português](#-português) · 🇺🇸 [English](#-english)

Pendrive multiboot de manutenção baseado no [Ventoy](https://github.com/ventoy/Ventoy): formata, instala o Windows 11 sem perguntas, configura a máquina sozinho e entrega um relatório visual da saúde do hardware.

*A Ventoy-based multiboot maintenance USB drive: it reinstalls Windows 11 unattended, configures the machine by itself and produces a visual hardware health report.*

![Relatório de exemplo](docs/relatorio-exemplo.png)

---

## 🇧🇷 Português

> ⚠️ **Projeto em desenvolvimento.** Feito para qualquer PC com Windows 10/11, de qualquer marca. Testado até agora em notebooks Lenovo ThinkPad T490 com Windows 11 Pro. Use por sua conta e risco e teste numa máquina antes de usar nas outras.

### O que ele faz

**No boot (menu do Ventoy)**
- Instala o Windows 11 (ou o 10, para PCs que não aceitam o 11) com o arquivo de respostas `autounattend.xml`: português, teclado ABNT2, conta local sem e-mail da Microsoft, sem telas de privacidade. **A escolha do disco continua manual**, para nunca apagar o disco errado.
- Ferramentas de boot: MemTest86 (memória), Rescuezilla (backup/clonagem), SystemRescue (partições, TestDisk/PhotoRec), netboot.xyz (baixa outros sistemas pela rede), ShredOS (apagar disco).
- Linux live: Linux Mint XFCE (leve, para PCs fracos e resgate de arquivos) e Kali Linux (instalador; segurança e redes).
- Ferramentas portáteis no Windows: CrystalDiskInfo (SSD), HWiNFO (hardware e temperaturas), **teste de estresse** com Prime95 (processador e memória) e FurMark 2 (placa de vídeo), e **teste das portas USB** com USB Device Tree Viewer e CrystalDiskMark.
- `ISOs/SHA256-OFICIAIS.txt` lista o SHA-256 oficial de cada ISO para conferir o download.
- Se a máquina reiniciar com o pendrive conectado e ninguém escolher nada, em 10 segundos ela entra no Windows instalado.

**Depois da instalação (`POS-FORMATACAO.bat`, ou sozinho no primeiro login)**
1. Energia: não dorme na tomada durante o processo.
2. Wi-Fi: se não houver internet, lista as redes disponíveis para a pessoa escolher e digitar a senha (e pode salvar no pendrive para as próximas máquinas).
3. Limpeza: remove apps desnecessários e propagandas, mostra extensões de arquivo.
4. **Privacidade e otimização:** telemetria no mínimo que o Windows aceita, sem envio de dados de uso, sem Bing/Copilot/Recall, tarefas de coleta desligadas, visual mais leve, Inicialização Rápida desligada, limpeza automática e TRIM do SSD. Defender e Windows Update continuam ligados.
5. **Você escolhe tudo numa janela no início** (Wi-Fi, programas e otimização) e o resto é automático. Programas disponíveis: Chrome, Firefox, 7-Zip, Adobe Reader, VLC, AnyDesk, TeamViewer, Zoom, Teams, LibreOffice, Notepad++, Office. Instala via `winget` e **pula o que já está instalado**. O Office baixa em segundo plano enquanto as outras etapas rodam.
6. Microsoft 365 Apps (Office), se marcado, pelo instalador oficial da Microsoft.
7. Chrome como navegador padrão e fixado na barra de tarefas, sem perguntas.
8. Drivers: Windows Update em qualquer marca; em computadores Lenovo, também drivers e BIOS pelo Lenovo System Update.
9. Windows Update.
10. Renomeia o PC (`MODELO-SÉRIE`) e gera o relatório.

**Relatório visual**
- Cartões verde/amarelo/vermelho para SSD, bateria, memória, drivers, ativação do Windows e BIOS, com uma frase dizendo o que fazer.
- `Relatorios/Resumo-das-maquinas.html` no pendrive compara todas as máquinas já atendidas.
- `RELATORIO.bat` gera só o relatório, sem alterar nada no PC.

**PC em uso (`OTIMIZAR.bat`)**
- Para um computador que já tem arquivos e programas importantes: cria um **ponto de restauração** antes, aplica só privacidade, otimização e limpeza de temporários, e gera o relatório.
- **Não** desinstala programas ou apps, **não** mexe em arquivos, **não** troca navegador nem barra de tarefas, **não** renomeia o PC e **não** atualiza a BIOS.
- O relatório mostra quanto tempo levou cada etapa.

![Resumo das máquinas](docs/resumo-exemplo.png)

### Estrutura

```
pendrive/                       → conteúdo da raiz do pendrive Ventoy
├── POS-FORMATACAO.bat          → pós-formatação completa
├── RELATORIO.bat               → só o relatório
├── OTIMIZAR.bat                → só otimizar um PC em uso
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

1. Instale o Ventoy no pendrive (exFAT, GPT e, em Opções, marque **Secure Boot Support**). Essa opção é do instalador do Ventoy, não da BIOS: ela permite dar boot também em PCs com Secure Boot ligado. Na primeira vez num PC assim, o Ventoy pede para registrar a chave (*Enroll key*), uma vez só. Com o Secure Boot desligado na BIOS também funciona.
2. Copie o conteúdo da pasta `pendrive/` para a raiz do pendrive.
3. Baixe as ISOs e ferramentas indicadas no `LEIA-ME.txt` de cada pasta, sempre dos sites oficiais.
4. (Opcional) Copie `PosFormatacao/config.example.json` para `config.json` para fixar Wi-Fi, programas e Office. Sem ele, o script pergunta o Wi-Fi na hora.
5. Coloque as ISOs do Windows em `ISOs/Windows/`: todas elas usam a instalação automática.

> 🔒 O `config.json` guarda a senha do Wi-Fi e **não** vai para o repositório (`.gitignore`).

### Licença

A definir antes da publicação. As ferramentas de terceiros (Ventoy, MemTest86, etc.) **não** são redistribuídas aqui: cada uma é baixada do site oficial e segue a sua própria licença.

---

## 🇺🇸 English

> ⚠️ **Work in progress.** Built for any Windows 10/11 PC of any brand. So far tested on Lenovo ThinkPad T490 laptops with Windows 11 Pro. Use at your own risk and test on one machine first.

> 🌐 The pendrive itself is currently in Brazilian Portuguese. A language selector (Portuguese / US English) is on the [roadmap](ROADMAP.md).

### What it does

**At boot (Ventoy menu)**
- Installs Windows 11 (or 10, for PCs that can't run 11) with an `autounattend.xml` answer file: local account without a Microsoft account, no privacy screens. **Disk selection stays manual**, so it never wipes the wrong drive.
- Boot tools: MemTest86 (RAM), Rescuezilla (backup/cloning), SystemRescue (partitions, TestDisk/PhotoRec), netboot.xyz (boots other systems over the network), ShredOS (disk wipe).
- Live Linux: Linux Mint XFCE (lightweight, for weak PCs and file rescue) and Kali Linux (installer; security and networking).
- Portable Windows tools: CrystalDiskInfo (SSD), HWiNFO (hardware and temperatures), **stress testing** with Prime95 (CPU and RAM) and FurMark 2 (graphics card), and **USB port testing** with USB Device Tree Viewer and CrystalDiskMark.
- `ISOs/SHA256-OFICIAIS.txt` lists each ISO's official SHA-256 to verify downloads.
- If the machine reboots with the drive plugged in and nobody picks anything, it boots the installed Windows after 10 seconds.

**After installation (`POS-FORMATACAO.bat`, or automatically at first logon)**
1. Power: no sleep on AC while it runs.
2. Wi-Fi: if there is no internet, lists the nearby networks so the user picks one and types the password (optionally saved on the drive for the next machines).
3. Cleanup: removes bloatware and ads, shows file extensions.
4. **Privacy and optimization:** telemetry at the lowest level Windows accepts, no usage data sent, no Bing/Copilot/Recall, data-collection tasks disabled, lighter visuals, Fast Startup off, automatic cleanup and SSD TRIM. Defender and Windows Update stay on.
5. **You choose everything in one window at the start** (Wi-Fi, apps and optimization) and the rest is automatic. Apps available: Chrome, Firefox, 7-Zip, Adobe Reader, VLC, AnyDesk, TeamViewer, Zoom, Teams, LibreOffice, Notepad++, Office. Installs via `winget` and **skips anything already installed**. Office downloads in the background while the other steps run.
6. Microsoft 365 Apps (Office), if selected, through Microsoft's official deployment tool.
7. Chrome as default browser and pinned to the taskbar, with no prompts.
8. Drivers: Windows Update on any brand; on Lenovo machines, drivers and BIOS through Lenovo System Update too.
9. Windows Update.
10. Renames the PC (`MODEL-SERIAL`) and builds the report.

**Visual report**
- Green/yellow/red cards for SSD, battery, RAM, drivers, Windows activation and BIOS, each with a plain-language next step.
- `Relatorios/Resumo-das-maquinas.html` on the drive compares every machine serviced.
- `RELATORIO.bat` builds only the report, without changing anything on the PC.

**PC in use (`OTIMIZAR.bat`)**
- For a computer that already has important files and apps: creates a **restore point** first, applies only privacy, optimization and temp-file cleanup, and builds the report.
- It does **not** uninstall apps, touch files, change the browser or taskbar, rename the PC or update the BIOS.
- The report shows how long each step took.

### Build your own

1. Install Ventoy on the USB drive (exFAT, GPT and, under Options, tick **Secure Boot Support**). This is a Ventoy installer option, not a BIOS setting: it lets the drive boot on PCs with Secure Boot enabled. The first time on such a PC, Ventoy asks you to enroll its key, once. It also works with Secure Boot disabled in the BIOS.
2. Copy the contents of `pendrive/` to the root of the drive.
3. Download the ISOs and tools listed in each folder's `LEIA-ME.txt`, always from the official sites.
4. (Optional) Copy `PosFormatacao/config.example.json` to `config.json` to preset Wi-Fi, apps and Office. Without it, the script asks for Wi-Fi on the spot.
5. Put Windows ISOs in `ISOs/Windows/`: every ISO there uses the unattended install.

> 🔒 `config.json` holds the Wi-Fi password and is **not** committed (`.gitignore`).

### License

To be decided before the public release. Third-party tools (Ventoy, MemTest86, etc.) are **not** redistributed here: each one is downloaded from its official site and keeps its own license.

# Pendrive Fodão

> 🇧🇷 [Português](#-português) · 🇺🇸 [English](#-english)

Pendrive multiboot de manutenção baseado no [Ventoy](https://github.com/ventoy/Ventoy): formata, instala o Windows 11 sem perguntas, configura a máquina sozinho e entrega um relatório visual da saúde do hardware.

*A Ventoy-based multiboot maintenance USB drive: it reinstalls Windows 11 unattended, configures the machine by itself and produces a visual hardware health report.*

![Relatório de exemplo](docs/relatorio-exemplo.png)

---

## 🇧🇷 Português

> ⚠️ **Projeto em desenvolvimento.** Feito para qualquer PC com Windows 10/11, de qualquer marca. Testado até agora em notebooks Lenovo ThinkPad T490 com Windows 11 Pro. Use por sua conta e risco e teste numa máquina antes de usar nas outras.

### O que ele faz

**No boot (menu do Ventoy)**
- Instala o Windows 11 com o arquivo de respostas `autounattend.xml`: português, teclado ABNT2, conta local sem e-mail da Microsoft, sem telas de privacidade. **A escolha do disco continua manual**, para nunca apagar o disco errado.
- Ferramentas de boot: MemTest86 (memória), Rescuezilla (backup/clonagem), GParted (partições), Linux Mint (resgate de arquivos), ShredOS (apagar disco).
- Ferramentas portáteis no Windows: CrystalDiskInfo (SSD), HWiNFO (hardware e temperaturas) e **teste de estresse** com Prime95 (processador e memória) e FurMark 2 (placa de vídeo).
- Se a máquina reiniciar com o pendrive conectado e ninguém escolher nada, em 10 segundos ela entra no Windows instalado.

**Depois da instalação (`POS-FORMATACAO.bat`, ou sozinho no primeiro login)**
1. Energia: não dorme na tomada durante o processo.
2. Wi-Fi: se não houver internet, lista as redes disponíveis para a pessoa escolher e digitar a senha (e pode salvar no pendrive para as próximas máquinas).
3. Limpeza: remove apps desnecessários e propagandas, mostra extensões de arquivo.
4. **Privacidade e otimização:** telemetria no mínimo que o Windows aceita, sem envio de dados de uso, sem Bing/Copilot/Recall, tarefas de coleta desligadas, visual mais leve, Inicialização Rápida desligada, limpeza automática e TRIM do SSD. Defender e Windows Update continuam ligados.
5. **Você escolhe os programas** num menu no início (Chrome, Firefox, 7-Zip, Adobe Reader, VLC, AnyDesk, TeamViewer, Zoom, Teams, LibreOffice, Notepad++, Office). Instala via `winget` e **pula o que já está instalado**.
6. Microsoft 365 Apps (Office), se marcado, pelo instalador oficial da Microsoft.
7. Chrome como navegador padrão e fixado na barra de tarefas, sem perguntas.
8. Drivers: Windows Update em qualquer marca; em computadores Lenovo, também drivers e BIOS pelo Lenovo System Update.
9. Windows Update.
10. Renomeia o PC (`MODELO-SÉRIE`) e gera o relatório.

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
4. (Opcional) Copie `PosFormatacao/config.example.json` para `config.json` para fixar Wi-Fi, programas e Office. Sem ele, o script pergunta o Wi-Fi na hora.
5. Se a sua ISO do Windows tiver outro nome, ajuste o caminho em `ventoy/ventoy.json`.

> 🔒 O `config.json` guarda a senha do Wi-Fi e **não** vai para o repositório (`.gitignore`).

### Licença

A definir antes da publicação. As ferramentas de terceiros (Ventoy, MemTest86, etc.) **não** são redistribuídas aqui: cada uma é baixada do site oficial e segue a sua própria licença.

---

## 🇺🇸 English

> ⚠️ **Work in progress.** Built for any Windows 10/11 PC of any brand. So far tested on Lenovo ThinkPad T490 laptops with Windows 11 Pro. Use at your own risk and test on one machine first.

> 🌐 The pendrive itself is currently in Brazilian Portuguese. A language selector (Portuguese / US English) is on the [roadmap](ROADMAP.md).

### What it does

**At boot (Ventoy menu)**
- Installs Windows 11 with an `autounattend.xml` answer file: local account without a Microsoft account, no privacy screens. **Disk selection stays manual**, so it never wipes the wrong drive.
- Boot tools: MemTest86 (RAM), Rescuezilla (backup/cloning), GParted (partitions), Linux Mint (file rescue), ShredOS (disk wipe).
- Portable Windows tools: CrystalDiskInfo (SSD), HWiNFO (hardware and temperatures) and **stress testing** with Prime95 (CPU and RAM) and FurMark 2 (graphics card).
- If the machine reboots with the drive plugged in and nobody picks anything, it boots the installed Windows after 10 seconds.

**After installation (`POS-FORMATACAO.bat`, or automatically at first logon)**
1. Power: no sleep on AC while it runs.
2. Wi-Fi: if there is no internet, lists the nearby networks so the user picks one and types the password (optionally saved on the drive for the next machines).
3. Cleanup: removes bloatware and ads, shows file extensions.
4. **Privacy and optimization:** telemetry at the lowest level Windows accepts, no usage data sent, no Bing/Copilot/Recall, data-collection tasks disabled, lighter visuals, Fast Startup off, automatic cleanup and SSD TRIM. Defender and Windows Update stay on.
5. **You pick the apps** from a menu at the start (Chrome, Firefox, 7-Zip, Adobe Reader, VLC, AnyDesk, TeamViewer, Zoom, Teams, LibreOffice, Notepad++, Office). Installs via `winget` and **skips anything already installed**.
6. Microsoft 365 Apps (Office), if selected, through Microsoft's official deployment tool.
7. Chrome as default browser and pinned to the taskbar, with no prompts.
8. Drivers: Windows Update on any brand; on Lenovo machines, drivers and BIOS through Lenovo System Update too.
9. Windows Update.
10. Renames the PC (`MODEL-SERIAL`) and builds the report.

**Visual report**
- Green/yellow/red cards for SSD, battery, RAM, drivers, Windows activation and BIOS, each with a plain-language next step.
- `Relatorios/Resumo-das-maquinas.html` on the drive compares every machine serviced.
- `RELATORIO.bat` builds only the report, without re-running the post-install steps.

### Build your own

1. Install Ventoy on the USB drive (exFAT, GPT, Secure Boot on).
2. Copy the contents of `pendrive/` to the root of the drive.
3. Download the ISOs and tools listed in each folder's `LEIA-ME.txt`, always from the official sites.
4. (Optional) Copy `PosFormatacao/config.example.json` to `config.json` to preset Wi-Fi, apps and Office. Without it, the script asks for Wi-Fi on the spot.
5. If your Windows ISO has a different name, update the path in `ventoy/ventoy.json`.

> 🔒 `config.json` holds the Wi-Fi password and is **not** committed (`.gitignore`).

### License

To be decided before the public release. Third-party tools (Ventoy, MemTest86, etc.) are **not** redistributed here: each one is downloaded from its official site and keeps its own license.

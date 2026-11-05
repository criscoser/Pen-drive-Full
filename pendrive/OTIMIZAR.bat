@echo off
title OTIMIZAR
echo Otimizando este computador (sem instalar, desinstalar ou renomear nada)...
echo Aceite a permissao de administrador (Sim).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PosFormatacao\pos-formatacao.ps1" -SoOtimizar

@echo off
:: Crea o modifica bginfo.bgi (accanto a setup.cmd). Istruzioni: docs\BGINFO.md
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Crea-BGInfo.ps1"

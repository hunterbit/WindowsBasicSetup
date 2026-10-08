@echo off
:: ============================================================
::  SETUP AUTOMATICO - launcher
::  Metti setup.cmd, setup.ps1 e config.json nella stessa cartella.
::  Programmi e ottimizzazioni si scelgono dai menu di setup.ps1.
:: ============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

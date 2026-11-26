@echo off
:: ============================================================
::  SETUP AUTOMATICO - launcher
::  Metti setup.cmd, setup.ps1, config.json e la cartella lib nella stessa cartella.
::  Avvia setup.ps1 come amministratore con la console nascosta: si vede solo la finestra
::  grafica. setup.ps1 mostra la console solo se serve (errori, menu a terminale).
:: ============================================================

powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0setup.ps1\"'"

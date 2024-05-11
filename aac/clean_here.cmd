@echo off

rmdir /q /S .venv
rmdir /q /S tSK.egg-info
rmdir /q /S __pycache__
del LOGS\*.log*
del *.log*

timeout -t 3

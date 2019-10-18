@for %%i in (*.dpr) do dcc32.exe -U.\shl\ "%%~i"
@pause
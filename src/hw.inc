; Primo hardware constants. Sources: Primo Füzetek Hardver 5.3.2 (I/O), Raktáros (colour layout), demo (vsync/screen switch).
defc ORG          = 0x4400      ; machine-code load address (BASIC CALL(17408))
defc SHADOW_PORT0 = 0x403B      ; RAM mirror of the write-only output port 0 -- always go through it
defc PORT0        = 0x00        ; OUT: control register / IN: keyboard + status
defc P0_NMI       = 0x80        ; D7: 1 = NMI (20 ms frame interrupt) enabled
defc P0_SOUND     = 0x10        ; D4: speaker
defc P0_SCREEN    = 0x08        ; D3: 1 = screen at $E800, 0 = 8 KB lower ($C800)
defc IN_VSYNC     = 0x20        ; IN bit D5: 1 during frame blanking
defc COLOR_ROM0   = 0xC3        ; first ROM byte is JP on the colour ROM (Raktáros' detection)

defc VRAM_MONO    = 0xE800      ; 256x192, 32 bytes/line, 6144 bytes (48K/64K models)
defc VRAM_MONO_SZ = 0x1800
defc VRAM_CTRL    = 0xE000      ; colour model: control, palette ($E020), colour RAM ($E080)
defc VRAM_COLOR   = 0xE700      ; colour model pixels: 256x200 = 6400 bytes up to $FFFF
defc COLOR_TOP     = 8          ; colour picture is 200 lines; the game's 192 start this many lines down (as zsugabubus: origin = mono $E800)
defc VRAM_CTRL_SZ = 0x2000

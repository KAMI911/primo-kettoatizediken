; Generic helpers shared by the game and the tests.

; detect_color -> A = 1 colour model, 0 monochrome. Clobbers F.
; Reads ROM byte 0 (never writes). Build-time override avoids the check.
detect_color:
IF TARGET_BW
        xor     a
        ret
ELIF TARGET_COLOR
        ld      a,1
        ret
ELSE
        ld      a,(0)
        cp      COLOR_ROM0
        ld      a,0
        ret     nz
        inc     a
        ret
ENDIF

; memfill  HL = dest, BC = count (0 = no-op), A = value. Never writes outside [HL, HL+BC). Clobbers AF,BC,DE,HL.
; Caller guarantees HL+BC <= 0x10000.
memfill:
        ld      e,a
        ld      a,b
        or      c
        ret     z
        ld      (hl),e
        dec     bc
        ld      a,b
        or      c
        ret     z
        ld      d,h
        ld      e,l
        inc     de
        ldir
        ret

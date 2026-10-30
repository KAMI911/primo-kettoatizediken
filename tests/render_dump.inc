; Only assembled with -DRENDER_TEST (plus optionally -DRS_SPLASH or -DRS_HELP): draws one screen and streams the
; 8 KB video area ($E000-$FFFF) to port 1 so tools/render.py can turn it into a PNG.
IF RS_KEYTEST
        ld      hl,kt_demo
        ld      de,kt_buf
        ld      bc,7
        ldir
        ld      a,0x39
        ld      (kt_last),a
        call    kt_draw                 ; held codes 39 0E 1F, last 39
        jp      rt_dump0
kt_demo: defb 3,0x39,0x0E,0x1F,0,0,0
        call    key_test                ; ticks returns the same value for every IN, so BRK is 'pressed' at once
ELIF RS_SPLASH
        call    draw_splash
        ld      de,170*32+8             ; put_hex check: should read 3F A5
        call    loc
        ld      a,0x3F
        call    put_hex
        ld      a,0xA5
        call    put_hex
ELIF RS_HELP
        call    cls
        ld      hl,help_tbl
        ld      de,1*256+2
rt_h:   ld      a,(hl)
        or      a
        jr      z,rt_dump0
        push    de
        call    puts_at
        ex      de,hl
        inc     hl
        pop     de
        inc     d
        jr      rt_h
ELSE
        ld      hl,rt_board
        ld      de,board
        ld      bc,16
        ldir
        ld      hl,12345
        ld      (score),hl
        ld      (best),hl
        ld      hl,msg_win
        ld      (msg_ptr),hl
        call    redraw_all
IF RS_ANIM
        ; exercise animation, flash and sound code; the final picture must equal the plain board scene
        ld      a,(is_color)
        ld      hl,mflag
        ld      b,16
        ld      a,1
rt_f:   ld      (hl),a
        inc     hl
        djnz    rt_f
        call    draw_dirty              ; redraw every cell via the dirty path
        call    flash_merged            ; 4 toggles = identity
        ld      a,5
        call    toggle_cell
        ld      a,5
        call    toggle_cell
        call    snd_move
        call    snd_merge
        call    snd_win
        call    snd_over
ENDIF
ENDIF
rt_dump0:
        ld      hl,0xE000
        ld      bc,0x2000
rt_dump:
        ld      a,(hl)
        out     (1),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,rt_dump
rt_done:
        halt
rt_board: defb  0,1,2,3, 4,5,6,7, 8,9,10,11, 12,0,13,1

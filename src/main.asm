; 1024 for the Primo (monochrome A/B and colour C/Pro). Builds universal (run-time detect), -DTARGET_BW (never colour). -DTARGET_COLOR is only used by `make shots`.
; Language: English by default, -DLANG_HU for Hungarian (text in src/text_*.inc, made by tools/gen_text.py).
; Keys: arrows, WASD, IJKL or 8 4 2 6 move, R new game, M sound on/off, C switch mono/colour drawing, H help, Q or BRK quit.
; Needs the 48K/64K screen layout (video at $E800 mono; colour model $E700, game area from $E800).
        include "hw.inc"
        org     ORG

defc KEY_NONE   = 0xFF
defc KEY_NEW    = 4
defc KEY_SOUND  = 5
defc KEY_MODE   = 6
defc KEY_HELP   = 7
defc KEY_QUIT   = 8
defc KEY_ANY    = 9                     ; any other key (splash and help only)
defc BOARD_X    = 6                     ; board left edge, byte column
defc BOARD_Y    = 16                    ; board top edge, pixel line
defc WIN_EXP    = 10                    ; 2^10 = 1024
defc LINE_HEAD  = 4*32                  ; score line (pixel line 4)
defc LINE_MSG   = 180*32                ; message line (pixel line 180)

start:
        ld      (old_sp),sp             ; the caller's stack: `quit` returns through it
        ld      sp,stack_top            ; own stack in plain RAM, never in video memory
        call    detect_color
        ld      (is_color),a
        ld      (has_col),a             ; colour hardware present: only then C and the colour texts are offered
        ld      a,1
        ld      (sound),a
        call    init_video
IF RENDER_TEST
        include "../tests/render_dump.inc"
ENDIF
splash_loop:
        call    draw_splash
        call    wait_any
        ld      c,a
        call    wait_release
        ld      a,c
        cp      KEY_SOUND
        jr      z,spl_snd
        cp      KEY_MODE
        jr      z,spl_mode
        cp      KEY_HELP
        jr      z,spl_help
        cp      KEY_QUIT
        jr      z,quit
        call    new_game
        jr      main_loop
spl_snd:
        call    toggle_sound
        jr      splash_loop
spl_mode:
        ld      a,(has_col)
        or      a
        jr      z,splash_loop           ; no colour hardware: C does nothing
        call    toggle_mode
        jr      splash_loop
; quit: clear the screen, restore the caller's stack and return (to BASIC).
quit:   call    cls
        ld      sp,(old_sp)
        ret
spl_help:
        call    help_screen
        jr      splash_loop

main_loop:
        call    wait_key
        ld      c,a
        cp      KEY_NEW
        jr      z,ml_new
        cp      KEY_SOUND
        jr      z,ml_snd
        cp      KEY_MODE
        jr      z,ml_mode
        cp      KEY_HELP
        jr      z,ml_help
        cp      KEY_QUIT
        jr      z,quit
        ld      a,(over)
        or      a
        jr      nz,ml_rel               ; game over: only the menu keys work
        ld      a,c
        ld      (dir),a
        xor     a
        ld      (anim),a
sl_lp:  ld      a,(dir)                 ; slide animation: one cell per step, redrawing only the cells that changed
        call    shift_move
        or      a
        jr      z,sl_end
        ld      a,1
        ld      (anim),a
        call    draw_dirty
        ld      bc,0x0500
        call    delay
        jr      sl_lp
sl_end: ld      a,(dir)
        call    do_move                 ; merge what is left to merge
        ld      (merged),a
        ld      b,a
        ld      a,(anim)
        or      b
        jr      z,ml_rel                ; nothing moved: no new tile
        call    spawn
        call    after_move
        jr      ml_rel
ml_new: call    new_game
        jr      ml_rel
ml_snd: call    toggle_sound
        call    draw_sound
        jr      ml_rel
ml_mode:
        ld      a,(has_col)
        or      a
        jr      z,ml_rel
        call    toggle_mode
        call    redraw_all
        jr      ml_rel
ml_help:
        call    help_screen
        call    redraw_all
ml_rel: call    wait_release
        jr      main_loop

; ---------------------------------------------------------------- game flow
new_game:
        ld      hl,board
        ld      bc,16
        xor     a
        call    memfill
        ld      hl,0
        ld      (score),hl
        xor     a
        ld      (won),a
        ld      (over),a
        call    spawn
        call    spawn
        ld      hl,msg_help
        ld      a,(has_col)
        or      a
        jr      nz,ng_msg
        ld      hl,msg_help_m
ng_msg: ld      (msg_ptr),hl
        jp      redraw_all

after_move:
        ld      hl,(score)
        ld      de,(best)
        or      a
        sbc     hl,de                   ; score > best ?
        jr      c,am_nb
        jr      z,am_nb
        ld      hl,(score)
        ld      (best),hl
am_nb:  call    draw_board
        call    draw_scores
        ld      a,(merged)
        or      a
        jr      z,am_mv
        call    snd_merge
        call    flash_merged
        jr      am_sp
am_mv:  call    snd_move
am_sp:  ld      a,(sp_idx)              ; the new tile blinks once
        call    toggle_cell
        ld      bc,0x0800
        call    delay
        ld      a,(sp_idx)
        call    toggle_cell
        call    has_moves
        or      a
        jr      nz,am_ok
        ld      a,1
        ld      (over),a
        call    snd_over
        ld      hl,msg_over
        jp      show_msg
am_ok:  ld      a,(won)
        or      a
        ret     nz
        call    max_tile
        cp      WIN_EXP
        ret     c
        ld      a,1
        ld      (won),a
        call    snd_win
        ld      hl,msg_win
        jp      show_msg

toggle_sound:
        ld      a,(sound)
        xor     1
        ld      (sound),a
        jp      nz,snd_move             ; short click as feedback when switching on
        ret

; toggle_mode: switch between mono and colour drawing (fixes a wrong auto-detection), re-initialises the video.
toggle_mode:
        ld      a,(is_color)
        xor     1
        ld      (is_color),a
        jp      nz,init_video           ; -> colour: init_video wipes everything and programs the palette
        ld      hl,VRAM_CTRL            ; -> mono: switch colour off (control $E001 = 0) and drop the colour RAM and
        ld      bc,0x0800               ; the 8 extra colour lines ($E700), or the old colours stay on the mono picture
        xor     a
        call    memfill
        jp      init_video

; ---------------------------------------------------------------- animation
; delay  BC = count (~26 T-states per count). Clobbers AF,BC.
delay:  dec     bc
        ld      a,b
        or      c
        jr      nz,delay
        ret

; flash_merged: the cells flagged in mflag blink twice (inverted / normal).
flash_merged:
        ld      b,4
fm_lp:  push    bc
        call    toggle_flagged
        ld      bc,0x0C00
        call    delay
        pop     bc
        djnz    fm_lp
        ret

toggle_flagged:
        ld      c,0
tf_lp:  ld      a,c
        ld      e,a
        ld      d,0
        ld      hl,mflag
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,tf_nx
        ld      a,c
        call    toggle_cell
tf_nx:  inc     c
        ld      a,c
        cp      16
        jr      nz,tf_lp
        ret

; toggle_cell  A = cell index: inverts its 40x40 pixels (colour model: swaps tile and digit colours). Preserves BC.
toggle_cell:
        push    bc
        call    cell_scr
        ld      c,40
xc_ln:  ld      b,5
xc_by:  ld      a,(hl)
        cpl
        ld      (hl),a
        inc     hl
        djnz    xc_by
        ld      de,27
        add     hl,de
        dec     c
        jr      nz,xc_ln
        pop     bc
        ret

; cell_scr  A = cell index -> HL = screen address of its top-left byte. Clobbers AF,DE,HL.
cell_scr:
        ld      d,a
        and     3
        ld      e,a
        add     a,a
        add     a,a
        add     a,e                     ; col*5
        add     a,BOARD_X
        ld      e,a
        ld      a,d
        rrca
        rrca
        and     3                       ; row
        ld      d,a
        add     a,a
        add     a,a
        add     a,d                     ; row*5
        add     a,BOARD_Y*32/256        ; high byte of (BOARD_Y + row*40) * 32
        ld      d,a
        ld      hl,(vbase)
        add     hl,de
        ret

; ---------------------------------------------------------------- sound (1-bit speaker, port 0 bit D4)
; beep  HL = number of half-periods, C = pitch (bigger = lower). Does nothing when sound is off.
; Works from the shadow register so the other port bits (NMI, screen area, tape) stay as the ROM wants them.
beep:   ld      a,(sound)
        or      a
        ret     z
        ld      a,(SHADOW_PORT0)
        and     ~P0_SOUND
        ld      e,a                     ; E = speaker low, D = speaker high
        or      P0_SOUND
        ld      d,a
bp_lp:  ld      a,d
        out     (PORT0),a
        ld      b,c
bp_1:   djnz    bp_1
        ld      a,e
        out     (PORT0),a
        ld      b,c
bp_2:   djnz    bp_2
        dec     hl
        ld      a,h
        or      l
        jr      nz,bp_lp
        ret

snd_move:
        ld      hl,24
        ld      c,60
        jr      beep
snd_merge:
        ld      hl,50
        ld      c,34
        call    beep
        ld      hl,70
        ld      c,22
        jr      beep
snd_win:
        ld      de,win_notes
sw_lp:  ld      a,(de)
        or      a
        ret     z
        ld      c,a
        inc     de
        push    de
        ld      hl,90
        call    beep
        pop     de
        jr      sw_lp
snd_over:
        ld      de,over_notes
        jr      sw_lp

win_notes:  defb 40,32,26,20,0
over_notes: defb 22,32,45,70,0

; ---------------------------------------------------------------- input
; read_key -> A = 0..3 direction, KEY_NEW/SOUND/MODE/HELP, or KEY_NONE. Key table: scan code, result;
; polled with IN (code), bit 0 = pressed.
read_key:
        ld      hl,keytab
rk_lp:  ld      a,(hl)
        inc     hl
        cp      0xFF
        ret     z                       ; A = KEY_NONE
        ld      c,a
        ld      b,0
        in      a,(c)
        rra
        jr      c,rk_hit
        inc     hl
        jr      rk_lp
rk_hit: ld      a,(hl)
        ret

; read_any -> A = as read_key, or KEY_ANY if some other key of the 64 is down, else KEY_NONE. Clobbers AF,BC,HL.
read_any:
        call    read_key
        cp      KEY_NONE
        ret     nz
        ld      c,0
ra_l:   ld      b,0
        in      a,(c)
        rra
        jr      c,ra_hit
        inc     c
        ld      a,c
        cp      64
        jr      nz,ra_l
        ld      a,KEY_NONE
        ret
ra_hit: ld      a,KEY_ANY
        ret

; wait_any: like wait_key, but any key counts (splash and help screens).
wait_any:
        call    read_any
        cp      KEY_NONE
        jr      nz,wk_got
        ld      hl,(ctr)
        inc     hl
        ld      (ctr),hl
        jr      wait_any

; wait_key -> A = key. Runs a counter meanwhile and stirs it into the random seed, so every game differs.
wait_key:
        call    read_key
        cp      KEY_NONE
        jr      nz,wk_got
        ld      hl,(ctr)
        inc     hl
        ld      (ctr),hl
        jr      wait_key
wk_got: push    af
        ld      a,r
        call    seed_mix
        pop     af
        ret

; wait_release: wait until no key is down, then ~40 ms of debounce. Clobbers AF,BC,HL.
wait_release:
        call    read_key
        cp      KEY_NONE
        jr      nz,wait_release
        ld      bc,0x1000
        jp      delay

; ---------------------------------------------------------------- video
init_video:
        ld      a,(is_color)
        or      a
        jr      nz,iv_col
        ld      hl,VRAM_MONO
        ld      (vbase),hl
        jr      cls
iv_col: ld      hl,VRAM_CTRL            ; wipe control, palette, colour RAM and pixels first (as Raktaros): a reset
        ld      bc,VRAM_CTRL_SZ         ; leaves whatever the ROM or the last program put in the control area
        xor     a
        call    memfill
        call    set_palette
        ld      hl,VRAM_COLOR+COLOR_TOP*32
        ld      (vbase),hl
; cls: clear pixels (and colour RAM on the colour model).
cls:    ld      hl,(vbase)
        ld      bc,VRAM_MONO_SZ
        ld      a,(is_color)
        or      a
        jr      z,cls_px
        ld      hl,VRAM_COLOR           ; colour model: wipe all 200 lines, including the 8 above the game area
        ld      bc,VRAM_MONO_SZ+0x100
cls_px: xor     a
        call    memfill
        ld      a,(is_color)
        or      a
        ret     z
        ld      hl,VRAM_CTRL+0x80
        ld      bc,1600
        xor     a
        jp      memfill

; set_palette: colour model only. Three banks of 32 bytes (index = pixel<<4 | colour nibble), stored inverted.
; Then control register = colour on, bank 1 (values as used by the working Raktaros code).
set_palette:
        ld      hl,VRAM_CTRL+0x20
        ld      c,3
sp_bank:
        ld      de,palette
        ld      b,32
sp_cp:  ld      a,(de)
        cpl
        ld      (hl),a
        inc     de
        inc     hl
        djnz    sp_cp
        dec     c
        jr      nz,sp_bank
        ld      a,0x81
        ld      (VRAM_CTRL+1),a
        ret

; put_kami  A = char, HL = cell, C = colour byte (palette nibble twice), B = 1 for inverse video. -> HL = next cell.
; Colour model: the two colour RAM cells of the glyph get the colour. Clobbers AF,BC,DE.
put_kami:
        push    hl
        push    bc
        call    putc
        pop     bc
        ex      (sp),hl                 ; HL = this cell, stack = next cell
        ld      a,b
        or      a
        jr      z,pk_nc
        push    hl
        ld      de,32
        ld      b,8
pk_i:   ld      a,(hl)
        cpl
        ld      (hl),a
        add     hl,de
        djnz    pk_i
        pop     hl
pk_nc:  ld      a,(is_color)
        or      a
        jr      z,pk_end
        ld      d,c
        ld      bc,(vbase)
        or      a
        sbc     hl,bc                   ; offset in the picture -> colour RAM byte of the same cell
        ld      a,l
        and     0x1F
        ld      c,a
        ld      a,l
        and     0x80
        ld      l,a
        srl     h
        rr      l
        srl     h
        rr      l
        ld      b,0
        add     hl,bc
        ld      bc,VRAM_CTRL+0x80+COLOR_TOP/4*32
        add     hl,bc
        ld      (hl),d
        ld      bc,32
        add     hl,bc
        ld      (hl),d
pk_end: pop     hl
        ret

; putc  A = ASCII 32..95 (others show '?'), HL = top byte of the 8x8 cell. Draws the glyph, -> HL = next cell. Clobbers AF,BC,DE.
putc:
        push    hl
        call    glyph
        ex      de,hl                   ; DE = glyph
        pop     hl
        push    hl
        ld      b,8
pc_ln:  ld      a,(de)
        ld      (hl),a
        inc     de
        ld      a,l
        add     a,32
        ld      l,a
        jr      nc,pc_nc
        inc     h
pc_nc:  djnz    pc_ln
        pop     hl
        inc     hl
        ret

; glyph  A = character code -> HL = address of its 8-byte glyph. 32..95 = ASCII caps, 0x80..0x88 = accented caps
; (font_ext), anything else shows '?'. Clobbers AF,DE,HL.
glyph:  ld      de,font
        cp      0x80
        jr      c,gl_n
        sub     0x80
        cp      9
        jr      nc,gl_q
        ld      de,font_ext
        jr      gl_o
gl_n:   sub     32
        cp      64
        jr      c,gl_o
gl_q:   ld      de,font
        ld      a,'?'-32
gl_o:   ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,de
        ret

; puts  HL = dest, DE = zero-terminated string -> HL = next cell. Clobbers AF,BC,DE.
puts:
        ld      a,(de)
        or      a
        ret     z
        inc     de
        push    de
        call    putc
        pop     de
        jr      puts

; puts_n  HL = dest, DE = string, B = length (>0) -> HL = next cell. Clobbers AF,BC,DE.
puts_n:
        ld      a,(de)
        inc     de
        push    de
        push    bc
        call    putc
        pop     bc
        pop     de
        djnz    puts_n
        ret

; put_num  HL = value, DE = dest -> prints it right-padded with spaces to 5 cells. Clobbers AF,BC,DE,HL.
put_num:
        push    de
        call    utoa
        pop     de
        ex      de,hl                   ; HL = dest, DE = digits
        push    bc
        call    puts_n
        pop     bc
        ld      a,5
        sub     b
        ret     z
        ld      b,a
pn_sp:  ld      a,' '
        push    bc
        call    putc
        pop     bc
        djnz    pn_sp
        ret

; loc  DE = byte offset from the screen start -> HL = screen address. Clobbers HL.
loc:    ld      hl,(vbase)
        add     hl,de
        ret

; puts_at  HL = zero-terminated text, DE = screen offset -> DE = address of the terminator. Clobbers AF,BC,DE,HL.
puts_at:
        push    hl
        call    loc
        pop     de
        jp      puts

; show_msg  HL = zero-terminated text -> remembers it, clears the 8-line message strip and prints the text at column 3.
show_msg:
        ld      (msg_ptr),hl
        push    hl
        ld      de,LINE_MSG
        call    loc
        push    hl
        ld      bc,256
        xor     a
        call    memfill
        pop     hl
        ld      de,3
        add     hl,de
        pop     de
        jp      puts

draw_scores:
        ld      de,LINE_HEAD+11
        call    loc
        ex      de,hl
        ld      hl,(score)
        call    put_num
        ld      de,LINE_HEAD+21
        call    loc
        ex      de,hl
        ld      hl,(best)
        jp      put_num

draw_sound:
        ld      de,LINE_HEAD+27
        call    loc
        ld      de,txt_snd_on
        ld      a,(sound)
        or      a
        jr      nz,ds_p
        ld      de,txt_snd_off
ds_p:   jp      puts

draw_header:
        ld      hl,txt_title
        ld      de,LINE_HEAD
        call    puts_at
        ld      hl,txt_score
        ld      de,LINE_HEAD+5
        call    puts_at
        ld      hl,txt_best
        ld      de,LINE_HEAD+17
        call    puts_at
        jp      draw_sound

; redraw_all: clear and draw the whole game screen from the current state.
redraw_all:
        call    cls
        call    draw_header
        call    draw_board
        call    draw_scores
        ld      hl,(msg_ptr)
        jp      show_msg

; draw_board: redraws all 16 cells (5 bytes x 40 lines each) and, on the colour model, their colour nibbles.
; draw_dirty: only the cells flagged in mflag (used by the slide animation).
draw_board:
        xor     a
        jr      db_go
draw_dirty:
        ld      a,1
db_go:  ld      (dmode),a
        ld      hl,(vbase)
        ld      de,BOARD_Y*32+BOARD_X
        add     hl,de
        ld      (scrp),hl
        ld      hl,VRAM_CTRL+0x80+(COLOR_TOP/4+BOARD_Y/4)*32+BOARD_X
        ld      (colp),hl
        ld      ix,board
        ld      c,4
db_r:   ld      b,4
db_c:   push    bc
        ld      a,(dmode)
        or      a
        jr      z,db_d
        ld      a,(ix+16)               ; mflag
        or      a
        jr      z,db_n
db_d:   ld      a,(ix+0)
        call    draw_cell
db_n:   inc     ix
        ld      hl,(scrp)
        ld      de,5
        add     hl,de
        ld      (scrp),hl
        ld      hl,(colp)
        add     hl,de
        ld      (colp),hl
        pop     bc
        djnz    db_c
        ld      hl,(scrp)
        ld      de,40*32-20
        add     hl,de
        ld      (scrp),hl
        ld      hl,(colp)
        ld      de,10*32-20
        add     hl,de
        ld      (colp),hl
        dec     c
        jr      nz,db_r
        ret

; draw_cell  A = exponent, (scrp) = top-left byte, (colp) = its colour RAM byte. Preserves IX. Clobbers the rest.
draw_cell:
        ld      (cur_e),a
        ld      hl,(scrp)
        ld      a,0xFF
        call    row5
        ld      b,38
dc_mid: push    bc
        call    rowmid
        pop     bc
        djnz    dc_mid
        ld      a,0xFF
        call    row5
        ld      a,(cur_e)
        or      a
        jr      z,dc_col
        call    pow2
        call    utoa                    ; HL = digits, B = count
        ld      a,b
        ld      c,1                     ; 2-3 digits start at byte 1
        cp      1
        jr      nz,dc_n1
        inc     c                       ; one digit at byte 2 (centred)
        jr      dc_pos
dc_n1:  cp      4
        jr      nz,dc_pos
        dec     c                       ; four digits start at byte 0
dc_pos: ld      de,(scrp)
        push    hl
        ld      hl,16*32
        add     hl,de
        ld      e,c
        ld      d,0
        add     hl,de
        pop     de
        call    puts_n
        ld      hl,(scrp)               ; wide numbers cover a border byte: put both border pixels back
        ld      de,16*32
        add     hl,de
        ld      b,8
dc_bd:  set     7,(hl)
        ld      de,4
        add     hl,de
        set     0,(hl)
        ld      de,28
        add     hl,de
        djnz    dc_bd
dc_col: ld      a,(is_color)
        or      a
        ret     z
        ld      a,(cur_e)
        ld      c,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      c
        ld      d,a                     ; both nibbles = exponent -> palette entry
        ld      hl,(colp)
        ld      c,10
dc_cr:  ld      b,5
dc_cb:  ld      (hl),d
        inc     hl
        djnz    dc_cb
        ld      a,l
        add     a,27
        ld      l,a
        jr      nc,dc_nc
        inc     h
dc_nc:  dec     c
        jr      nz,dc_cr
        ret

; row5  A = byte, HL = line start: writes 5 bytes, -> HL = start of next line. Clobbers B,DE.
row5:   ld      b,5
r5_l:   ld      (hl),a
        inc     hl
        djnz    r5_l
        ld      de,27
        add     hl,de
        ret

; rowmid  HL = line start: left border pixel, 3 empty bytes, right border pixel -> HL = next line. Clobbers A,DE.
rowmid: ld      (hl),0x80
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),0x01
        ld      de,28
        add     hl,de
        ret

; puts2  HL = dest, DE = zero-terminated text -> drawn 2x2. Clobbers AF,BC,DE.
puts2:  ld      a,(de)
        or      a
        ret     z
        inc     de
        push    de
        call    putc2
        pop     de
        jr      puts2

; putc2  A = ASCII char, HL = dest -> draws it 2x2 (16x16 pixels), HL = dest+2. Clobbers AF,BC,DE.
putc2:
        push    hl
        call    glyph
        ex      de,hl                   ; DE = glyph
        pop     hl
        push    hl
        ld      b,8
p2_ln:  ld      a,(de)
        inc     de
        push    de
        push    bc
        ld      c,a
        rrca
        rrca
        rrca
        rrca
        and     0x0F
        call    dbl_nib
        ld      b,a                     ; left byte
        ld      a,c
        and     0x0F
        call    dbl_nib
        ld      c,a                     ; right byte
        ld      (hl),b
        inc     hl
        ld      (hl),c
        ld      de,31
        add     hl,de
        ld      (hl),b
        inc     hl
        ld      (hl),c
        add     hl,de                   ; start of the next glyph row pair
        pop     bc
        pop     de
        djnz    p2_ln
        pop     hl
        inc     hl
        inc     hl
        ret

; dbl_nib  A = nibble -> A = each bit doubled. Preserves everything else.
dbl_nib:
        push    hl
        push    de
        ld      e,a
        ld      d,0
        ld      hl,dbltab
        add     hl,de
        ld      a,(hl)
        pop     de
        pop     hl
        ret

; ---------------------------------------------------------------- splash and help screens
draw_splash:
        call    cls
        ld      de,8*32+9
        call    loc
        ld      de,txt_name1
        call    puts2
        ld      de,28*32+7
        call    loc
        ld      de,txt_name2
        call    puts2
        ld      hl,(vbase)                      ; a row of four sample tiles: 2, 8, 128, 1024
        ld      de,56*32+BOARD_X
        add     hl,de
        ld      (scrp),hl
        ld      hl,VRAM_CTRL+0x80+(COLOR_TOP/4+56/4)*32+BOARD_X
        ld      (colp),hl
        ld      ix,splash_tiles
        ld      b,4
spl_t:  push    bc
        ld      a,(ix+0)
        inc     ix
        call    draw_cell
        ld      hl,(scrp)
        ld      de,5
        add     hl,de
        ld      (scrp),hl
        ld      hl,(colp)
        add     hl,de
        ld      (colp),hl
        pop     bc
        djnz    spl_t
        ld      hl,txt_tag
        ld      de,100*32+4
        call    puts_at
        ld      hl,txt_start
        ld      de,116*32+5
        call    puts_at
        ld      hl,txt_k_help
        ld      de,140*32+8
        call    puts_at
        ld      hl,txt_k_snd
        ld      de,148*32+8
        call    puts_at
        ld      de,txt_on               ; HL = cursor after the label
        ld      a,(sound)
        or      a
        jr      nz,spl_s
        ld      de,txt_off
spl_s:  call    puts
        ld      de,156*32+8
        ld      a,(has_col)
        or      a
        jr      z,spl_q                 ; no colour hardware: no C line, Q moves up
        ld      hl,txt_k_mode
        call    puts_at
        ld      de,txt_colour
        ld      a,(is_color)
        or      a
        jr      nz,spl_m
        ld      de,txt_mono
spl_m:  call    puts
        ld      de,164*32+8
spl_q:  ld      hl,txt_k_quit
        call    puts_at
        ld      hl,txt_by               ; "MADE BY: KAMI & AI": K M vivid, A I vivid and inverse
        ld      de,172*32+4
        call    puts_at
        ld      a,'K'
        ld      bc,0x00EE
        call    put_kami
        ld      a,'A'
        ld      bc,0x01FF
        call    put_kami
        ld      a,'M'
        ld      bc,0x00EE
        call    put_kami
        ld      a,'I'
        ld      bc,0x01FF
        call    put_kami
        ld      de,txt_and_
        call    puts
        ld      hl,txt_credit
        ld      de,182*32+8
        jp      puts_at

help_screen:
        call    cls
        ld      hl,help_tbl
        ld      a,(has_col)
        or      a
        jr      nz,hs_go
        ld      hl,help_tbl_m
hs_go:  ld      de,1*256+2              ; text row 1, column 2
hs_lp:  ld      a,(hl)
        or      a
        jr      z,hs_end
        push    de
        call    puts_at                 ; -> DE at the string's terminator
        ex      de,hl
        inc     hl                      ; next string
        pop     de
        inc     d                       ; next text row (+256 bytes)
        jr      hs_lp
hs_end: call    wait_any
        jp      wait_release

        include "lib.asm"
        include "logic.asm"
        include "font.inc"
        include "font_ext.inc"

; scan code, result (direction 0 left, 1 right, 2 up, 3 down, 4 new game)
keytab: defb    0x39,0, 0x0E,0, 0x26,0, 0x1F,0, 0x35,0  ; left:  arrow, A, J, 4, CLS/BS
        defb    0x3D,1, 0x08,1, 0x28,1, 0x1B,1          ; right: arrow, D, L, 6
        defb    0x01,2, 0x06,2, 0x2E,2, 0x21,2          ; up:    arrow, W, I, 8
        defb    0x0F,3, 0x02,3, 0x2A,3, 0x0B,3          ; down:  arrow, S, K, 2
        defb    0x14,KEY_NEW            ; R
        defb    0x2C,KEY_SOUND          ; M
        defb    0x10,KEY_MODE           ; C
        defb    0x18,KEY_HELP           ; H
        defb    0x0C,KEY_QUIT           ; Q
        defb    0x3F,KEY_QUIT           ; BRK
        defb    0xFF

; Palette, RRRGGGBB, not yet inverted. 16 backgrounds (pixel 0) by colour nibble = tile exponent, then 16 foregrounds (pixel 1).
palette:
        defb    0x00,0xFE,0xFA,0xF0,0xEC,0xE8,0xE0,0xFC     ; empty, 2, 4, 8, 16, 32, 64, 128
        defb    0xBC,0x1C,0x1F,0xFF,0xFF,0xFF,0x00,0x00     ; 256, 512, 1024, 2048..8192 white, nibbles 14/15 = black (KAMI credit)
        defb    0xFF,0x00,0x00,0x00,0x00,0x00,0xFF,0x00     ; text/borders: white on empty, black on tiles, white on 64
        defb    0x00,0x00,0x00,0x00,0x00,0x00,0xE3,0x1F     ; nibble 14 ink magenta, 15 ink cyan (K M / A I of the credit)

IF LANG_HU
        include "text_hu.inc"
ELSE
        include "text_en.inc"
ENDIF

splash_tiles: defb 1,3,7,10
dbltab:   defb  0x00,0x03,0x0C,0x0F,0x30,0x33,0x3C,0x3F,0xC0,0xC3,0xCC,0xCF,0xF0,0xF3,0xFC,0xFF

is_color: defb  0
has_col:  defb  0
old_sp:   defw  0
vbase:    defw  0
scrp:     defw  0
colp:     defw  0
cur_e:    defb  0
won:      defb  0
over:     defb  0
best:     defw  0
sound:    defb  1
msg_ptr:  defw  0
dmode:    defb  0
dir:      defb  0
anim:     defb  0
merged:   defb  0
          defs  96                      ; stack
stack_top:

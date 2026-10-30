; 1024 game rules. Pure logic, no hardware access, unit-tested in tests/test_logic.asm.
; Board = 16 bytes, row-major, each byte is the tile exponent: 0 = empty, n = 2^n (10 = 1024). Max exponent MAX_EXP (13 = 8192, still 4 digits).
defc MAX_EXP = 13
; Direction codes: 0 left, 1 right, 2 up, 3 down.

; pow2  A = exponent (low 4 bits used) -> HL = 1 << A. Clobbers AF,DE.
pow2:
        and     0x0F
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,pow2tab
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; add_score  A = exponent of the tile just created by a merge; score += 2^A, saturating at 0xFFFF.
; Clobbers AF,DE,HL.
add_score:
        call    pow2
        ld      de,(score)
        add     hl,de
        jr      nc,as_ok
        ld      hl,0xFFFF
as_ok:  ld      (score),hl
        ret

; slide4  HL = 4-byte line, index 0 is the edge tiles move towards. Slides and merges (each tile merges at most
; once per move, the top exponent never merges) and adds merge values to `score`.
; Merge marks (1 per result cell) are left in tmp+4..7.
; -> A = 1 if the line changed, else 0. Clobbers AF,BC,DE,HL.
slide4:
        ld      (s_buf),hl
        xor     a
        ld      (tmp),a
        ld      (tmp+1),a
        ld      (tmp+2),a
        ld      (tmp+3),a
        ld      (tmp+4),a
        ld      (tmp+5),a
        ld      (tmp+6),a
        ld      (tmp+7),a
        ld      de,tmp                  ; DE = write pointer into tmp
        ld      b,4
        ld      c,0                     ; C = 1 while the last written tile may still merge
s4_lp:  ld      a,(hl)
        inc     hl
        or      a
        jr      z,s4_nx                 ; empty: skip
        bit     0,c
        jr      z,s4_st
        push    hl
        ld      h,d
        ld      l,e
        dec     hl                      ; HL -> last written tile
        cp      (hl)
        jr      nz,s4_nm
        cp      MAX_EXP
        jr      z,s4_nm
        inc     (hl)                    ; merge
        inc     hl                      ; mark the result cell in tmp+4..7
        inc     hl
        inc     hl
        inc     hl
        ld      (hl),1
        ld      c,0
        pop     hl
        push    hl
        push    de
        push    bc
        inc     a                       ; exponent of the new tile
        call    add_score
        pop     bc
        pop     de
        pop     hl
        jr      s4_nx
s4_nm:  pop     hl
s4_st:  ld      (de),a
        inc     de
        ld      c,1
s4_nx:  djnz    s4_lp
        ld      hl,(s_buf)              ; copy tmp back, remember whether anything differed
        ld      de,tmp
        ld      b,4
        ld      c,0
s4_cp:  ld      a,(de)
        cp      (hl)
        jr      z,s4_same
        ld      c,1
        ld      (hl),a
s4_same:
        inc     hl
        inc     de
        djnz    s4_cp
        ld      a,c
        ret

; shift4  HL = 4-byte line (index 0 = edge). Moves every tile one step towards the edge if that cell is empty
; (one animation step, no merging). Moved cells (source and target) are marked in tmp+4..7.
; -> A = 1 if anything moved. Clobbers AF,BC,DE,HL.
shift4:
        xor     a
        ld      (tmp+4),a
        ld      (tmp+5),a
        ld      (tmp+6),a
        ld      (tmp+7),a
        ld      c,0
        ld      b,3
        inc     hl                      ; HL -> line[1]
        ld      de,tmp+4                ; DE -> mark of line[0]
sh_l:   ld      a,(hl)
        or      a
        jr      z,sh_n
        dec     hl
        ld      a,(hl)
        inc     hl
        or      a
        jr      nz,sh_n                 ; target occupied
        ld      a,(hl)
        dec     hl
        ld      (hl),a
        inc     hl
        xor     a
        ld      (hl),a
        inc     a
        ld      (de),a
        inc     de
        ld      (de),a
        dec     de
        ld      c,1
sh_n:   inc     hl
        inc     de
        djnz    sh_l
        ld      a,c
        ret

; cell_addr  A = cell index 0..15 -> HL = board + A. Preserves A,BC,DE.
cell_addr:
        push    de
        ld      e,a
        ld      d,0
        ld      hl,board
        add     hl,de
        pop     de
        ret

; do_move  A = direction (low 2 bits): slide + merge the whole board. -> A = 1 if anything changed.
; Cells that received a merge are flagged in mflag[]. Clobbers everything but IX/IY.
do_move:
        ld      c,0
        jr      move_core

; shift_move  A = direction: one animation step (no merging). -> A = 1 if anything moved; moved cells flagged in mflag[].
shift_move:
        ld      c,1
move_core:
        push    af
        ld      a,c
        ld      (mode),a
        ld      hl,mflag
        ld      b,16
        xor     a
mc_z:   ld      (hl),a
        inc     hl
        djnz    mc_z
        pop     af
        and     3
        ld      e,a
        add     a,a
        add     a,a
        add     a,e                     ; *5 bytes per dirtab entry
        ld      e,a
        ld      d,0
        ld      hl,dirtab
        add     hl,de
        ld      a,(hl)
        ld      (step),a
        inc     hl
        ld      (starts),hl
        xor     a
        ld      (changed),a
        ld      a,4
        ld      (lcnt),a
dm_line:
        ld      hl,(starts)
        ld      a,(hl)                  ; first cell index of this line
        inc     hl
        ld      (starts),hl
        push    af
        ld      de,lbuf
        ld      b,4
dm_g:   call    cell_addr
        push    af
        ld      a,(hl)
        ld      (de),a
        inc     de
        pop     af
        ld      hl,step
        add     a,(hl)
        djnz    dm_g
        ld      a,(mode)
        or      a
        ld      hl,lbuf
        jr      nz,dm_sh
        call    slide4
        jr      dm_pd
dm_sh:  call    shift4
dm_pd:  ld      hl,changed
        or      (hl)
        ld      (hl),a
        pop     af
        ld      de,lbuf
        ld      b,4
        ld      iy,tmp+4
dm_s:   call    cell_addr
        push    af
        ld      a,(de)
        ld      (hl),a
        inc     de
        ld      a,(iy+0)                ; mark of this cell -> mflag[idx] (board+16)
        inc     iy
        push    de
        ld      de,16
        add     hl,de
        pop     de
        ld      (hl),a
        pop     af
        ld      hl,step
        add     a,(hl)
        djnz    dm_s
        ld      hl,lcnt
        dec     (hl)
        jr      nz,dm_line
        ld      a,(changed)
        ret

; rnd -> HL = next 16-bit xorshift value (7,9,8). The state must be non-zero. Clobbers AF,HL.
rnd:
        ld      hl,(seed)
        ld      a,h
        rra
        ld      a,l
        rra
        xor     h
        ld      h,a
        ld      a,l
        rra
        ld      a,h
        rra
        xor     l
        ld      l,a
        xor     h
        ld      h,a
        ld      (seed),hl
        ret

; seed_mix  A = entropy byte. Stirs A and `ctr` into the generator state, never leaving it zero.
seed_mix:
        ld      hl,(seed)
        ld      de,(ctr)
        add     hl,de
        ld      e,a
        ld      d,0
        add     hl,de
        inc     hl
        ld      a,h
        or      l
        jr      nz,sm_ok
        ld      hl,0xACE1
sm_ok:  ld      (seed),hl
        ret

; spawn  puts a 2 (90%) or a 4 (10%) on a random empty cell -> A = 1 placed, 0 board full.
; Clobbers AF,BC,DE,HL.
spawn:
        ld      hl,board
        ld      b,16
        ld      c,0                     ; C = number of empty cells
sp_c:   ld      a,(hl)
        or      a
        jr      nz,sp_n
        inc     c
sp_n:   inc     hl
        djnz    sp_c
        ld      a,c
        or      a
        ret     z
        call    rnd
        ld      a,h
        xor     l
sp_m:   cp      c                       ; A = random mod C
        jr      c,sp_f
        sub     c
        jr      sp_m
sp_f:   ld      e,a                     ; E = which empty cell to take
        ld      hl,board
sp_s:   ld      a,(hl)
        or      a
        jr      nz,sp_x
        ld      a,e
        or      a
        jr      z,sp_p
        dec     e
sp_x:   inc     hl
        jr      sp_s
sp_p:   push    hl
        ld      de,board
        or      a
        sbc     hl,de
        ld      a,l
        ld      (sp_idx),a              ; index of the new tile, for the appear effect
        call    rnd
        ld      a,h
        pop     hl
        cp      26                      ; 26/256 ~ 10%
        ld      a,1
        jr      nc,sp_w
        inc     a
sp_w:   ld      (hl),a
        ld      a,1
        ret

; has_moves -> A = 1 if a move or merge is still possible, else 0. Clobbers AF,BC,DE,HL.
has_moves:
        ld      hl,board
        ld      b,16
hm_e:   ld      a,(hl)
        or      a
        jr      z,hm_yes
        inc     hl
        djnz    hm_e
        ld      hl,board
        ld      c,0                     ; C = cell index
hm_l:   ld      b,(hl)
        ld      a,c
        and     3
        cp      3
        jr      z,hm_dn                 ; last column has no right neighbour (no wrap to next row)
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      b
        jr      z,hm_yes
hm_dn:  ld      a,c
        cp      12
        jr      nc,hm_nx                ; last row has no cell below
        push    hl
        ld      de,4
        add     hl,de
        ld      a,(hl)
        pop     hl
        cp      b
        jr      z,hm_yes
hm_nx:  inc     hl
        inc     c
        ld      a,c
        cp      16
        jr      nz,hm_l
        xor     a
        ret
hm_yes: ld      a,1
        ret

; max_tile -> A = largest exponent on the board. Clobbers AF,BC,HL.
max_tile:
        ld      hl,board
        ld      b,16
        ld      c,0
mt_l:   ld      a,(hl)
        cp      c
        jr      c,mt_n
        ld      c,a
mt_n:   inc     hl
        djnz    mt_l
        ld      a,c
        ret

; utoa  HL = value -> HL = first digit (ASCII, in numbuf), B = digit count 1..5. Clobbers AF,C,DE.
utoa:
        ld      de,numbuf
        ld      bc,-10000
        call    ut_d
        ld      bc,-1000
        call    ut_d
        ld      bc,-100
        call    ut_d
        ld      bc,-10
        call    ut_d
        ld      bc,-1
        call    ut_d
        ld      hl,numbuf
        ld      b,5
ut_s:   ld      a,b
        cp      1
        ret     z                       ; keep at least one digit
        ld      a,(hl)
        cp      '0'
        ret     nz
        inc     hl
        djnz    ut_s
        ret
ut_d:   ld      a,'0'-1
ut_c:   inc     a
        add     hl,bc
        jr      c,ut_c
        sbc     hl,bc
        ld      (de),a
        inc     de
        ret

pow2tab:  defw  1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768
; step, then first cell of each of the 4 lines
dirtab:   defb  1,  0,4,8,12            ; left
          defb  -1, 3,7,11,15           ; right
          defb  4,  0,1,2,3             ; up
          defb  -4, 12,13,14,15         ; down

; --- state
board:    defs  16
mflag:    defs  16              ; must follow board: merge/move flags per cell
sp_idx:   defb  0
mode:     defb  0
score:    defw  0
seed:     defw  0xACE1
ctr:      defw  0
; --- scratch
lbuf:     defs  4
tmp:      defs  8
numbuf:   defs  5
s_buf:    defw  0
starts:   defw  0
step:     defb  0
changed:  defb  0
lcnt:     defb  0

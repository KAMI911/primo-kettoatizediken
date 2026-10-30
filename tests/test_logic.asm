; Unit tests for src/logic.asm and src/lib.asm, run headless in z88dk-ticks. Text goes to port 1 (-iochar 1).
        include "hw.inc"
        defc IOCHAR = 1
        org     0x4400

        ld      sp,0xFFF0
        ; ---- slide4: table driven. Each case: in[4], out[4], changed, score delta
        ld      hl,msg_slide
        ld      (curmsg),hl
        ld      ix,cases
nextcase:
        ld      a,(ix+0)
        cp      0xFF
        jr      z,cases_done
        ld      a,(ix+0)
        ld      (work),a
        ld      a,(ix+1)
        ld      (work+1),a
        ld      a,(ix+2)
        ld      (work+2),a
        ld      a,(ix+3)
        ld      (work+3),a
        ld      hl,0
        ld      (score),hl
        ld      hl,work
        call    slide4
        cp      (ix+8)
        jp      nz,fail
        ld      a,(work)
        cp      (ix+4)
        jp      nz,fail
        ld      a,(work+1)
        cp      (ix+5)
        jp      nz,fail
        ld      a,(work+2)
        cp      (ix+6)
        jp      nz,fail
        ld      a,(work+3)
        cp      (ix+7)
        jp      nz,fail
        ld      hl,(score)
        ld      a,(ix+9)
        cp      l
        jp      nz,fail
        ld      a,h
        or      a
        jp      nz,fail
        ld      de,10
        add     ix,de
        jr      nextcase
cases_done:
        ; ---- score saturates instead of wrapping
        ld      hl,msg_sat
        ld      (curmsg),hl
        ld      hl,0xFFFE
        ld      (score),hl
        ld      a,1
        ld      (work),a
        ld      (work+1),a
        xor     a
        ld      (work+2),a
        ld      (work+3),a
        ld      hl,work
        call    slide4
        ld      hl,(score)
        ld      de,0xFFFF
        or      a
        sbc     hl,de
        jp      nz,fail

        ; ---- do_move on a whole board
        ld      hl,msg_move
        ld      (curmsg),hl
        call    clr_board               ; row 0: 1 1 0 0   ; left -> cell0 = 2
        ld      a,1
        ld      (board),a
        ld      (board+1),a
        xor     a
        call    do_move
        cp      1
        jp      nz,fail
        ld      a,(board)
        cp      2
        jp      nz,fail
        call    board_sum
        cp      2
        jp      nz,fail
        call    clr_board               ; right -> cell3 = 2
        ld      a,1
        ld      (board),a
        ld      (board+1),a
        ld      a,1
        call    do_move
        ld      a,(board+3)
        cp      2
        jp      nz,fail
        call    board_sum
        cp      2
        jp      nz,fail
        call    clr_board               ; column 0: 1 over 1 ; up -> cell0, down -> cell12
        ld      a,1
        ld      (board),a
        ld      (board+4),a
        ld      a,2
        call    do_move
        ld      a,(board)
        cp      2
        jp      nz,fail
        call    board_sum
        cp      2
        jp      nz,fail
        call    clr_board
        ld      a,1
        ld      (board),a
        ld      (board+4),a
        ld      a,3
        call    do_move
        ld      a,(board+12)
        cp      2
        jp      nz,fail
        call    board_sum
        cp      2
        jp      nz,fail
        call    clr_board               ; nothing to do -> returns 0, board unchanged
        ld      a,3
        ld      (board+12),a
        ld      a,3
        call    do_move
        or      a
        jp      nz,fail
        ld      a,(board+12)
        cp      3
        jp      nz,fail
        call    clr_board               ; row 1 must not leak into row 0 when moving left: 0 0 0 1 | 1 0 0 0
        ld      a,1
        ld      (board+3),a
        ld      (board+4),a
        xor     a
        call    do_move
        ld      a,(board)
        cp      1
        jp      nz,fail
        ld      a,(board+4)
        cp      1
        jp      nz,fail
        call    board_sum
        cp      2
        jp      nz,fail


        ; ---- shift_move (animation step) and merge flags
        ld      hl,msg_shift
        ld      (curmsg),hl
        call    clr_board               ; row 0: 0 0 0 1, left: one step per call
        ld      a,1
        ld      (board+3),a
        xor     a
        call    shift_move
        cp      1
        jp      nz,fail
        ld      a,(board+2)
        cp      1
        jp      nz,fail
        ld      a,(board+3)
        or      a
        jp      nz,fail
        ld      a,(mflag+2)
        cp      1
        jp      nz,fail
        ld      a,(mflag+3)
        cp      1
        jp      nz,fail
        ld      a,(mflag+1)
        or      a
        jp      nz,fail
        xor     a
        call    shift_move
        xor     a
        call    shift_move
        ld      a,(board)
        cp      1
        jp      nz,fail
        xor     a
        call    shift_move              ; settled: nothing moves
        or      a
        jp      nz,fail
        call    clr_board               ; 1 1 0 0 / 2 2 2 2 : shift never merges
        ld      a,1
        ld      (board),a
        ld      (board+1),a
        xor     a
        call    shift_move
        or      a
        jp      nz,fail
        call    clr_board               ; merge flags: 1 1 1 1 left -> cells 0 and 1 flagged
        ld      a,1
        ld      (board),a
        ld      (board+1),a
        ld      (board+2),a
        ld      (board+3),a
        xor     a
        call    do_move
        ld      a,(mflag)
        cp      1
        jp      nz,fail
        ld      a,(mflag+1)
        cp      1
        jp      nz,fail
        ld      a,(mflag+2)
        or      a
        jp      nz,fail
        ld      a,(mflag+4)             ; other rows unflagged
        or      a
        jp      nz,fail


        ; ---- whole-move reference check: shift animation steps, then do_move, as the game does. 36-byte records.
        ld      hl,msg_ref
        ld      (curmsg),hl
        ld      ix,cases2
ref_next:
        ld      a,(ix+0)
        cp      255
        jp      z,ref_done
        push    ix
        pop     hl                      ; copy the 16 input cells
        ld      de,board
        ld      bc,16
        ldir
        ld      hl,0
        ld      (score),hl
        xor     a
        ld      (anyshift),a
ref_sh: ld      a,(ix+16)
        call    shift_move
        or      a
        jr      z,ref_dm
        ld      a,1
        ld      (anyshift),a
        jr      ref_sh
ref_dm: ld      a,(ix+16)
        call    do_move
        ld      hl,anyshift
        or      (hl)                    ; moved = any shift or any merge
        cp      (ix+33)
        jp      nz,fail
        ld      b,16
        ld      hl,board
        push    ix
        pop     de
        ld      de,17
        add     ix,de
        ld      c,0
ref_c:  ld      a,(hl)
        cp      (ix+0)
        jp      nz,fail
        inc     hl
        inc     ix
        djnz    ref_c
        ld      hl,(score)
        ld      a,(ix+1)
        cp      l
        jp      nz,fail
        ld      a,(ix+2)
        cp      h
        jp      nz,fail
        ld      de,3
        add     ix,de                   ; IX was at out[16] = record+33; +3 -> next record at +36
        jp      ref_next
ref_done:

        ; ---- spawn
        ld      hl,msg_spawn
        ld      (curmsg),hl
        call    clr_board
        ld      b,16
t_fill:
        push    bc
        call    spawn
        cp      1
        jp      nz,fail
        pop     bc
        djnz    t_fill
        ld      hl,board                ; every cell is now 1 or 2
        ld      b,16
t_chk: ld      a,(hl)
        dec     a
        cp      2
        jp      nc,fail
        inc     hl
        djnz    t_chk
        call    spawn                   ; full board: returns 0 and changes nothing
        or      a
        jp      nz,fail
        call    board_sum
        ld      c,a
        call    clr_board
        ld      a,5
        ld      b,16
        ld      hl,board
t_f5:  ld      (hl),a
        inc     hl
        djnz    t_f5
        xor     a
        ld      (board+9),a             ; exactly one hole at cell 9
        call    spawn
        cp      1
        jp      nz,fail
        ld      a,(board+9)
        or      a
        jp      z,fail
        cp      3
        jp      nc,fail
        call    board_sum              ; 15*5 + new tile (1 or 2)
        sub     75
        cp      3
        jp      nc,fail
        ld      a,(board+8)
        cp      5
        jp      nz,fail
        ld      a,(board+10)
        cp      5
        jp      nz,fail
        ; both tile values appear over many spawns, and 2 is the common one
        ld      hl,0
        ld      (cnt2),hl
        ld      (cnt4),hl
        ld      bc,600
t_dist:
        push    bc
        call    clr_board
        call    spawn
        ld      hl,board
        ld      b,16
t_f:   ld      a,(hl)
        inc     hl
        or      a
        jr      z,t_nx
        cp      1
        jr      nz,t_4
        ld      de,(cnt2)
        inc     de
        ld      (cnt2),de
        jr      t_nx
t_4:   ld      de,(cnt4)
        inc     de
        ld      (cnt4),de
t_nx:  djnz    t_f
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      nz,t_dist
        ld      hl,(cnt4)               ; 600 trials at ~10%: expect ~60, accept 20..120
        ld      de,20
        or      a
        sbc     hl,de
        jp      c,fail
        ld      hl,(cnt4)
        ld      de,120
        or      a
        sbc     hl,de
        jp      nc,fail

        ; ---- has_moves
        ld      hl,msg_hm
        ld      (curmsg),hl
        call    checker                 ; checkerboard, no equal neighbours (cells 3 and 4 are equal: row wrap must not count)
        call    has_moves
        or      a
        jp      nz,fail
        call    checker
        ld      a,7
        ld      (board+5),a             ; still no pair
        call    has_moves
        or      a
        jp      nz,fail
        call    checker
        ld      a,(board+9)
        ld      (board+10),a            ; horizontal pair
        call    has_moves
        cp      1
        jp      nz,fail
        call    checker
        ld      a,(board+13)
        ld      (board+9),a             ; vertical pair in the last row/column area
        call    has_moves
        cp      1
        jp      nz,fail
        call    checker
        xor     a
        ld      (board+15),a            ; a hole
        call    has_moves
        cp      1
        jp      nz,fail
        call    checker
        ld      a,(board+14)
        ld      (board+15),a            ; pair at the very end
        call    has_moves
        cp      1
        jp      nz,fail

        ; ---- max_tile
        ld      hl,msg_max
        ld      (curmsg),hl
        call    clr_board
        call    max_tile
        or      a
        jp      nz,fail
        ld      a,10
        ld      (board+15),a
        ld      a,3
        ld      (board+2),a
        call    max_tile
        cp      10
        jp      nz,fail

        ; ---- utoa
        ld      hl,msg_utoa
        ld      (curmsg),hl
        ld      hl,0
        ld      de,s0
        call    chk_utoa
        ld      hl,7
        ld      de,s7
        call    chk_utoa
        ld      hl,10
        ld      de,s10
        call    chk_utoa
        ld      hl,1024
        ld      de,s1024
        call    chk_utoa
        ld      hl,10000
        ld      de,s10000
        call    chk_utoa
        ld      hl,65535
        ld      de,s65535
        call    chk_utoa

        ; ---- pow2
        ld      hl,msg_pow
        ld      (curmsg),hl
        ld      a,10
        call    pow2
        ld      de,1024
        or      a
        sbc     hl,de
        jp      nz,fail
        ld      a,15
        call    pow2
        ld      de,32768
        or      a
        sbc     hl,de
        jp      nz,fail

        ; ---- rng never sticks at zero and seed_mix never leaves it zero
        ld      hl,msg_rng
        ld      (curmsg),hl
        ld      hl,0xFFFF
        ld      (seed),hl
        ld      (ctr),hl
        ld      a,1
        call    seed_mix                ; 0xFFFF+0xFFFF+1+1 = 0x0001 ... must be non-zero in any case
        ld      hl,(seed)
        ld      a,h
        or      l
        jp      z,fail
        ld      hl,0xFFFF
        ld      (seed),hl
        ld      hl,0
        ld      (ctr),hl
        ld      a,0                     ; 0xFFFF + 0 + 0 + 1 = 0 -> must be replaced
        call    seed_mix
        ld      hl,(seed)
        ld      a,h
        or      l
        jp      z,fail
        ld      b,200
rng_l:  push    bc
        call    rnd
        pop     bc
        ld      a,h
        or      l
        jp      z,fail
        djnz    rng_l

        ld      hl,msg_ok
        jr      print_done

fail:   ld      hl,msg_fail
        call    print
        ld      hl,(curmsg)
print_done:
        call    print
        jr      done
print:  ld      a,(hl)
        or      a
        ret     z
        out     (IOCHAR),a
        inc     hl
        jr      print
done:   halt

; ---- helpers
clr_board:
        ld      hl,board
        ld      b,16
        xor     a
cb_l:   ld      (hl),a
        inc     hl
        djnz    cb_l
        ret

board_sum:                              ; A = sum of all exponents
        ld      hl,board
        ld      b,16
        xor     a
bs_l:   add     a,(hl)
        inc     hl
        djnz    bs_l
        ret

checker:                                ; b[i] = 1 + ((i + i/4) & 1): no equal neighbours inside a row or column
        ld      hl,board
        ld      c,0
ck_l:   ld      a,c
        srl     a
        srl     a
        add     a,c
        and     1
        inc     a
        ld      (hl),a
        inc     hl
        inc     c
        ld      a,c
        cp      16
        jr      nz,ck_l
        ret

chk_utoa:                               ; HL = value, DE = expected zero-terminated string
        push    de
        call    utoa
        pop     de
cu_l:   ld      a,(de)
        or      a
        jr      z,cu_end
        ld      c,a
        ld      a,b
        or      a
        jp      z,fail                  ; string longer than the count
        ld      a,c
        cp      (hl)
        jp      nz,fail
        inc     hl
        inc     de
        dec     b
        jr      cu_l
cu_end: ld      a,b
        or      a
        jp      nz,fail                 ; count longer than the string
        ret

        include "../src/lib.asm"
        include "../src/logic.asm"

        include "cases.inc"
work:     defs  4
anyshift: defb  0
curmsg:   defw  0
cnt2:     defw  0
cnt4:     defw  0
s0:       defm  "0", 0
s7:       defm  "7", 0
s10:      defm  "10", 0
s1024:    defm  "1024", 0
s10000:   defm  "10000", 0
s65535:   defm  "65535", 0
msg_ok:    defm "ALL PASS", 10, 0
msg_fail:  defm "FAIL ", 0
msg_slide: defm "slide4", 10, 0
msg_sat:   defm "score saturation", 10, 0
msg_move:  defm "do_move", 10, 0
msg_ref:   defm "reference moves", 10, 0
msg_shift: defm "shift_move", 10, 0
msg_spawn: defm "spawn", 10, 0
msg_hm:    defm "has_moves", 10, 0
msg_max:   defm "max_tile", 10, 0
msg_utoa:  defm "utoa", 10, 0
msg_pow:   defm "pow2", 10, 0
msg_rng:   defm "rng", 10, 0
; in[4], out[4], changed, score delta
cases:
        defb 0,0,0,0,   0,0,0,0,   0, 0
        defb 1,0,0,0,   1,0,0,0,   0, 0
        defb 0,0,0,1,   1,0,0,0,   1, 0
        defb 1,1,0,0,   2,0,0,0,   1, 4
        defb 1,1,1,1,   2,2,0,0,   1, 8
        defb 1,1,1,0,   2,1,0,0,   1, 4
        defb 2,1,1,0,   2,2,0,0,   1, 4
        defb 1,0,1,2,   2,2,0,0,   1, 4
        defb 1,2,1,2,   1,2,1,2,   0, 0
        defb 1,1,2,2,   2,3,0,0,   1, 12
        defb 2,2,1,1,   3,2,0,0,   1, 12
        defb 13,13,0,0, 13,13,0,0, 0, 0
        defb 0,3,0,3,   4,0,0,0,   1, 16
        defb 0xFF

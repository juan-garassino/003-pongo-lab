/* Enter openra1n's relocatable LZ4 loader with Pongo's boot argument zeroed. */

.set staging_base, 0x180200000
.set wrapper_offset, 0x200
.set initial_instruction_window, 0x400

.globl _start
.align 4
_start:
    /* Clean the trampoline and loader header before instruction fetch. */
    ldr x4, =staging_base
    add x6, x4, #initial_instruction_window
    dsb sy
1:
    dc civac, x4
    add x4, x4, #0x40
    cmp x4, x6
    b.lo 1b
    dsb sy
    isb
    ic iallu
    dsb sy
    isb

    /* gaster EXEC leaves the target address in x8; Pongo expects x8/x0 args. */
    mov x8, xzr
    mov x0, xzr
    ldr x9, =staging_base + wrapper_offset
    br x9

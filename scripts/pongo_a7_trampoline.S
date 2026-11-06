/*
 * Explicit A7 PongoOS register/copy trampoline.
 *
 * Arguments supplied by gaster's EXEC request handler:
 *   x0 = Pongo boot arguments (zero for the plain shell)
 *   x1 = low Pongo load address
 *   x2 = Pongo relocation address
 *   x3 = trampoline address
 *   x4 = exact uploaded image length
 *   x5 = low image copy-window end
 */
.globl _start
.align 4
_start:
    /* Pongo's first stage takes boot arguments in x8, not x0. */
    mov x8, x0
    /* Match the known booter's Pongo base in the platform register. */
    mov x18, x1

    /* Pongo copies a full 2 MiB window; clear bytes beyond the uploaded image. */
    add x6, x1, x4
    add x6, x6, #7
    bic x6, x6, #7
1:
    cmp x6, x5
    b.hs 2f
    str xzr, [x6], #8
    b 1b

    /* Clean the uploaded source before taking the MMU and caches offline. */
2:
    mov x4, x1
    dsb sy
3:
    dc civac, x4
    add x4, x4, #0x40
    cmp x4, x5
    b.lo 3b

    /* Also clean the separately copied trampoline before disabling caches. */
    mov x4, x3
    add x7, x4, #0x100
7:
    dc civac, x4
    add x4, x4, #0x40
    cmp x4, x7
    b.lo 7b
    dsb sy
    isb
    ic iallu
    dsb sy
    isb

    /* Match the known A7 Pongo booter's transition to physical execution. */
    mrs x6, CurrentEL
    cmp x6, #0xc
    b.eq 4f
    cmp x6, #0x8
    b.eq 5f
    msr sctlr_el1, xzr
    b 6f
4:
    msr sctlr_el3, xzr
    b 6f
5:
    msr sctlr_el2, xzr
6:
    dsb sy
    isb

    /* Low Pongo copies itself to x2 and returns; enter that relocated image. */
    blr x1
    mov x8, x0
    mov x18, x1
    br x2

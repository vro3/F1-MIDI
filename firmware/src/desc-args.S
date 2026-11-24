.text
.align 4
.globl args_fs
args_fs:
    stw r8, sp[1]
    stw r9, sp[5]
    ldc r8, 117
    stw r8, sp[2]
    stw r8, sp[6]
    stw r8, sp[10]
    stw r8, sp[12]
    ldaw r8, dp[0x111]
    stw r8, sp[3]
    ldc r8, 10
    stw r8, sp[4]
    stw r8, sp[11]
    ldaw r8, dp[0x12e]
    stw r8, sp[7]
    stw r4, sp[8]
    ldc r8, 18
    stw r8, sp[9]
    mkmsk r8, 3
    stw r8, sp[13]

.globl args_hs
args_hs:
    stw r8, sp[1]
    stw r9, sp[5]
    ldc r8, 117
    stw r8, sp[2]
    stw r8, sp[6]
    stw r8, sp[10]
    stw r8, sp[12]
    ldaw r8, dp[0x12b]
    stw r8, sp[3]
    ldc r8, 10
    stw r8, sp[4]
    stw r8, sp[11]
    ldaw r8, dp[0x12e]
    stw r8, sp[7]
    stw r4, sp[8]
    ldc r8, 18
    stw r8, sp[9]
    mkmsk r8, 3
    stw r8, sp[13]

.globl refs
refs:
ldaw r3, dp[0x43]
ldaw r2, dp[0x61]

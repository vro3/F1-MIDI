.text
.globl tile_start
tile_start:
.space 0x646
bl worker
.space 0x7188-0x64a
stock_send:
.space 0xb1c0-0x7188
worker:
entsp 24
stw r4, sp[19]
stw r5, sp[20]
stw r8, sp[21]
stw r9, sp[22]
stw r10, sp[23]
ldaw r8, dp[153] // file offset b170: digital history, analog history, encoder and init flag
ldc r4, 0
ldc r5, 0
ldaw r9, sp[1]
// Scan the four switch bytes from MSB to LSB.
switch_byte:
add r0, r4, 1
ld8u r10, r6[r0]
ld8u r1, r8[r4]
st8 r10, r8[r4]
xor r1, r1, r10
eq r0, r4, 2
bf r0, check_last
ldc r2, 252
and r1, r1, r2
check_last:
eq r0, r4, 3
bf r0, masked
ldc r2, 254
and r1, r1, r2
masked:
ldc r2, 128
shl r3, r4, 3
ldc r11, 36
add r3, r3, r11
switch_bit:
and r0, r1, r2
bf r0, next_bit
and r0, r10, r2
bf r0, released
ldw r0, dp[157]
bu finish_note
released:
ldc r0, 32776
finish_note:
shl r11, r3, 16
or r0, r0, r11
stw r0, r9[r5]
add r5, r5, 1
next_bit:
add r3, r3, 1
shr r2, r2, 1
bt r2, switch_bit
add r4, r4, 1
eq r0, r4, 2
bt r0, flush_notes
eq r0, r4, 4
bf r0, switch_byte
flush_notes:
bl submit
ldc r1, 0
lss r1, r0, r1
bt r1, restore
eq r0, r4, 4
bf r0, switch_byte
// Eight 12-bit controls become absolute seven-bit CCs.
ldc r4, 0
ldc r0, 13
ld8u r10, r8[r0]
analog:
add r0, r4, 3
shl r0, r0, 1
ld8u r1, r6[r0]
add r0, r0, 1
ld8u r2, r6[r0]
shl r2, r2, 8
or r1, r1, r2
shr r1, r1, 5
zext r1, 7
add r2, r4, 4
ld8u r0, r8[r2]
st8 r1, r8[r2]
eq r0, r0, r1
bt r0, next_cc
bf r10, next_cc
add r3, r4, 8
add r3, r3, 8
bl append_cc
next_cc:
add r4, r4, 1
eq r0, r4, 8
bf r0, analog
// Signed modulo-16 encoder delta, in relative two's-complement format.
ldc r0, 5
ld8u r1, r6[r0]
zext r1, 4
ldc r2, 12
ld8u r0, r8[r2]
st8 r1, r8[r2]
sub r1, r1, r0
zext r1, 4
bf r1, complete
bf r10, complete
sext r1, 4
zext r1, 7
ldc r3, 24
bl append_cc
complete:
ldc r0, 13
ldc r1, 1
st8 r1, r8[r0]
bl submit
restore:
ldw r4, sp[19]
ldw r5, sp[20]
ldw r8, sp[21]
ldw r9, sp[22]
ldw r10, sp[23]
retsp 24
append_cc:
shl r1, r1, 24
shl r3, r3, 16
or r1, r1, r3
ldc r0, 45067
or r1, r1, r0
stw r1, r9[r5]
add r5, r5, 1
retsp 0
submit:
bf r5, empty
entsp 2
mov r0, r7
mov r1, r9
shl r2, r5, 2
ldc r3, 24
bl stock_send
ldc r5, 0
retsp 2
empty:
ldc r0, 0
retsp 0

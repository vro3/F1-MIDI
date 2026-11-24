.text
.globl tile_start
tile_start:
.space 0x554
bu receive_loop
.space 0x646-0x558
bl tx_plus
.space 0xfb4-0x64a
bl wake
.space 0x5038-0xfb8
// Startup owns these buffers before the MIDI and OUT threads start.
stw r0, dp[161]
ldaw r1, dp[131]
ldc r2, 0
ldc r3, 32512
paint_red:
stw r3, r1[r2]
add r2, r2, 1
ldc r0, 16
lsu r0, r2, r0
bt r0, paint_red
ldc r0, 0
stw r0, dp[151]
ldc r0, 65535
add r0, r0, 1
stw r0, dp[152]
retsp 0

wake:
ldw r1, dp[0x412]
ldw r0, dp[0x3e8]
bt r0, wake_done
ldw r0, dp[151]
or r1, r1, r0
ldw r0, dp[152]
shr r0, r0, 16
or r1, r1, r0
wake_done:
retsp 0

receive_loop:
extsp 144
ldc r0, 0
stw r0, sp[1]
receive:
mov r0, r5
ldaw r1, sp[7]
ldc r2, 520
bl get_buffer
ldc r1, 0
lss r1, r0, r1
bt r1, rx_reset
ldc r1, 512
lsu r1, r1, r0
bt r1, bad_transfer
mov r1, r0
zext r1, 2
bt r1, bad_transfer
shr r6, r0, 2
ldc r7, 0
each:
eq r0, r7, r6
bt r0, receive
ldaw r1, sp[7]
ldw r0, r1[r7]
ldaw r1, sp[1]
ldaw r2, dp[131]
ldaw r3, dp[147]
bl color_event
bf r0, next
ldc r0, 1
stw r0, dp[151]
await_ack:
ldw r0, dp[151]
bt r0, await_ack
next:
add r7, r7, 1
bu each
rx_reset:
mov r0, r5
ldc r1, 0
bl reset_endpoint
bad_transfer:
ldc r0, 0
stw r0, sp[1]
bu receive

tx_plus:
entsp 8
stw r4, sp[1]
stw r5, sp[2]
stw r6, sp[3]
stw r7, sp[4]
stw r8, sp[5]
stw r9, sp[6]
stw r10, sp[7]
bl existing_worker
ldc r1, 0
lss r1, r0, r1
bt r1, return_tx
ldw r4, dp[153]
zext r4, 16
ldw r6, dp[151]
bt r6, render
ldw r1, dp[152]
eq r1, r1, r4
bt r1, success
render:
stw r4, dp[152]
shl r0, r4, 8
shr r4, r4, 8
or r4, r0, r4
ldc r5, 0
ldaw r11, cp[128]
mov r9, r11
ldw r8, dp[161]
ldc r10, 0
pad:
ldaw r1, dp[131]
ldw r2, r1[r5]
ldc r0, 32768
and r3, r4, r0
ldc r11, 3
component:
mov r0, r2
zext r0, 7
bf r3, dim
shl r1, r0, 1
shr r0, r0, 1
add r0, r0, r1
bu level
dim:
shr r0, r0, 4
level:
ldc r1, 383
sub r0, r1, r0
ld8u r1, r9[r10]
shl r1, r1, 16
or r0, r0, r1
outct res[r8], 1
chkct res[r8], 1
out res[r8], r0
outct res[r8], 1
chkct res[r8], 1
add r10, r10, 1
shr r2, r2, 8
sub r11, r11, 1
bt r11, component
shl r4, r4, 1
add r5, r5, 1
ldc r0, 16
lsu r0, r5, r0
bt r0, pad
bf r6, success
mov r0, r7
ldaw r1, dp[147]
ldc r2, 16
ldc r3, 24
bl send_buffer
// Release the mailbox even on USB reset; Studio times out or retries.
ldc r1, 0
stw r1, dp[151]
bu return_tx
success:
ldc r0, 0
return_tx:
ldw r4, sp[1]
ldw r5, sp[2]
ldw r6, sp[3]
ldw r7, sp[4]
ldw r8, sp[5]
ldw r9, sp[6]
ldw r10, sp[7]
retsp 8
// The stock alternate-mode parent discards reports. Its old 128-byte scratch
// buffer cannot accept a high-speed bulk transfer.
drain_alt:
entsp 136
mov r0, r1
ldaw r1, sp[1]
ldc r2, 520
bl get_buffer
retsp 136

color_event:
	entsp 9
	stw r4, sp[8]
	stw r5, sp[7]
	stw r6, sp[6]
	stw r7, sp[5]
	stw r8, sp[4]
	stw r9, sp[3]
	stw r10, sp[2]
	mov r11, r0
	mov r6, r11
	zext r6, 8
	shr r4, r6, 4
	ldc r0, 0
	bt r4, .LBB0_29
	shr r9, r11, 8
	mov r5, r9
	zext r5, 8
	mkmsk r4, 4
	eq r4, r6, r4
	bf r4, .LBB0_3
	ldc r4, 247
	lsu r4, r4, r5
	bt r4, .LBB0_29
.LBB0_3:
	ldw r10, r1[0]
	ldc r0, 0
	stw r0, r1[0]
	ldw r4, dp[162]
	eq r4, r11, r4
	bf r4, .LBB0_5
	mkmsk r2, 1
	stw r2, r1[0]
	bu .LBB0_29
.LBB0_5:
	shr r4, r11, 16
	mov r7, r4
	zext r7, 8
	shr r8, r11, 24
	stw r8, sp[1]
	eq r8, r10, 1
	bf r8, .LBB0_11
	eq r8, r6, 4
	bf r8, .LBB0_11
	ldc r8, 49
	eq r8, r5, r8
	bf r8, .LBB0_11
	eq r8, r7, 1
	bf r8, .LBB0_11
	ashr r8, r11, 32
	bt r8, .LBB0_11
	ldc r2, 2
	stw r2, r1[0]
	ldw r2, sp[1]
	stw r2, r1[1]
	bu .LBB0_29
.LBB0_11:
	eq r8, r10, 2
	stw r8, sp[0]
	bf r8, .LBB0_17
	eq r8, r6, 4
	bf r8, .LBB0_17
	eq r8, r5, 2
	bf r8, .LBB0_17
	shr r8, r7, 4
	bt r8, .LBB0_17
	ashr r11, r11, 32
	bt r11, .LBB0_17
	mkmsk r2, 2
	stw r2, r1[0]
	stw r7, r1[2]
	ldw r2, sp[1]
	stw r2, r1[3]
	bu .LBB0_29
.LBB0_17:
	or r11, r9, r4
	ldc r4, 128
	and r11, r11, r4
	ldw r4, sp[1]
	bt r11, .LBB0_22
	eq r11, r10, 3
	bf r11, .LBB0_22
	eq r11, r6, 7
	bf r11, .LBB0_22
	ldc r11, 247
	eq r11, r4, r11
	bf r11, .LBB0_22
	ldw r0, r1[2]
	ldw r11, r1[3]
	shl r11, r11, 8
	shl r4, r5, 16
	or r4, r4, r7
	or r11, r4, r11
	stw r11, r2[r0]
	bu .LBB0_28
.LBB0_22:
	ldw r11, sp[0]
	bf r11, .LBB0_29
	eq r11, r6, 7
	bf r11, .LBB0_29
	eq r11, r5, 1
	bf r11, .LBB0_29
	shr r11, r7, 4
	bt r11, .LBB0_29
	ldc r11, 247
	eq r11, r4, r11
	bf r11, .LBB0_29
	ldw r11, r2[r7]
	mov r0, r7
.LBB0_28:
	ldw r2, dp[162]
	stw r2, r3[0]
	ldw r1, r1[1]
	shl r1, r1, 24
	ldw r2, dp[163]
	or r1, r1, r2
	stw r1, r3[1]
	shl r0, r0, 16
	shr r1, r11, 8
	shl r2, r11, 16
	ldw r11, dp[164]
	and r11, r2, r11
	or r0, r0, r11
	ldc r11, 772
	or r0, r0, r11
	stw r0, r3[2]
	ldc r0, 32512
	and r0, r1, r0
	ldw r1, dp[165]
	and r1, r2, r1
	or r0, r1, r0
	ldw r1, dp[166]
	or r0, r0, r1
	stw r0, r3[3]
	mkmsk r0, 1
.LBB0_29:
	ldw r10, sp[2]
	ldw r9, sp[3]
	ldw r8, sp[4]
	ldw r7, sp[5]
	ldw r6, sp[6]
	ldw r5, sp[7]
	ldw r4, sp[8]
	retsp 9

runtime_end:
.space 5314
legacy_receive:
bu drain_alt
.space 0x715c-0x67a8
get_buffer:
.space 44
send_buffer:
.space 2432
reset_endpoint:
.space 14008
existing_worker:
nop

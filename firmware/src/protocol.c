/* Only MIDI cable zero. Consume a USB event a word at a time; pad colors are BRG. */
unsigned color_event(unsigned word, unsigned *state, unsigned *colors, unsigned *reply) {
    unsigned header = word & 255, a = (word >> 8) & 255, b = (word >> 16) & 255, c = word >> 24;
    if (header >= 16 || (header == 15 && a >= 248)) return 0;
    unsigned phase = state[0];
    state[0] = 0;
    if (word == 0x467df004u) { state[0] = 1; return 0; }
    if (phase == 1 && header == 4 && a == '1' && b == 1 && c < 128) {
        state[0] = 2; state[1] = c; return 0;
    }
    unsigned pad;
    if (phase == 2 && header == 4 && a == 2 && b < 16 && c < 128) {
        state[0] = 3; state[2] = b; state[3] = c; return 0;
    }
    if (phase == 3 && header == 7 && a < 128 && b < 128 && c == 247) {
        pad = state[2];
        colors[pad] = b | (state[3] << 8) | (a << 16);
    } else if (phase == 2 && header == 7 && a == 1 && b < 16 && c == 247) {
        pad = b;
    } else return 0;
    unsigned rgb = colors[pad];
    reply[0] = 0x467df004u;
    reply[1] = 0x013104u | (state[1] << 24);
    reply[2] = 0x304u | (pad << 16) | (((rgb >> 8) & 127) << 24);
    reply[3] = 0xf7000007u | ((rgb >> 8) & 0x7f00u) | ((rgb & 127) << 16);
    return 1;
}

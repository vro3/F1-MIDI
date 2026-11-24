#ifndef F1_PAD_COLOR_H
#define F1_PAD_COLOR_H
#include <stdint.h>
#include <stddef.h>

/* Private development SysEx: F0 7D 'F' '1' 01 request op pad [r g b] F7.
   01 reads, 02 previews, 03 replies with RGB. All RGB components are 0..127.
   Cable zero only. State belongs to one USB session; initialize before use. */
typedef struct {
    uint8_t colors[16][3];
    uint8_t message[12];
    unsigned used;
} F1ColorSession;

void f1_color_init(F1ColorSession *s);
/* Consume one USB MIDI 1.0 event. On a reply writes four events to out. */
size_t f1_color_event(F1ColorSession *s,const uint8_t event[4],uint8_t out[16]);
#endif

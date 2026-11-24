#include "PadColor.h"
#include <string.h>

void f1_color_init(F1ColorSession *s) {
    memset(s,0,sizeof *s);
    for (unsigned pad=0; pad<16; ++pad) s->colors[pad][0]=127;
}

static size_t handle(F1ColorSession *s,unsigned length,uint8_t out[16]) {
    const uint8_t *m=s->message;
    const uint8_t prefix[]={0xf0,0x7d,'F','1',1};
    if (length<9 || memcmp(m,prefix,sizeof prefix) || m[7]>=16) return 0;
    uint8_t *rgb=s->colors[m[7]];
    if (m[6]==2 && length==12) memcpy(rgb,m+8,3);
    else if (!(m[6]==1 && length==9)) return 0;
    uint8_t response[]={0xf0,0x7d,'F','1',1,m[5],3,m[7],rgb[0],rgb[1],rgb[2],0xf7};
    for (unsigned i=0; i<4; ++i) {
        out[4*i]=i==3 ? 7 : 4;
        memcpy(out+4*i+1,response+3*i,3);
    }
    return 16;
}

size_t f1_color_event(F1ColorSession *s,const uint8_t event[4],uint8_t out[16]) {
    if (event[0]>>4) return 0;
    unsigned cin=event[0]&15;
    if (cin==15 && event[1]>=0xf8) return 0;
    if (cin<4 || cin>7) { s->used=0; return 0; }
    unsigned count=cin==4 ? 3 : cin-4;
    if (event[1]==0xf0) s->used=0;
    if (!s->used && event[1]!=0xf0) return 0;
    if (s->used+count>sizeof s->message) { s->used=0; return 0; }
    for (unsigned i=0; i<count; ++i) {
        uint8_t b=event[i+1];
        int end=cin!=4 && i+1==count;
        if (end ? b!=0xf7 : b>=128 && !(s->used==0 && b==0xf0)) {
            s->used=0; return 0;
        }
        s->message[s->used++]=b;
    }
    if (cin==4) return 0;
    unsigned length=s->used;
    s->used=0;
    return handle(s,length,out);
}

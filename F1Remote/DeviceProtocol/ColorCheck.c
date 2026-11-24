#include "PadColor.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static size_t request(F1ColorSession *s,unsigned cmd,unsigned pad,const uint8_t rgb[3],uint8_t reply[16]) {
    uint8_t e[][4]={{4,240,125,'F'},{4,'1',1,19},{7,1,pad,247},{7,0,0,247}};
    if(cmd==2) {
        e[2][0]=4;e[2][1]=2;e[2][3]=rgb[0];e[3][1]=rgb[1];e[3][2]=rgb[2];
    }
    for(unsigned i=0;i<(cmd==2?3u:2u);i++) assert(!f1_color_event(s,e[i],reply));
    return f1_color_event(s,e[cmd==2?3:2],reply);
}
int main(void) {
    F1ColorSession s;
    f1_color_init(&s);
    uint8_t out[16],rgb[3];
    for(unsigned i=0;i<16;i++) {
        rgb[0]=i;rgb[1]=127-i;rgb[2]=32+i;
        assert(request(&s,2,i,rgb,out)==16);
        uint8_t expected[]={4,240,125,'F',4,'1',1,19,4,3,i,rgb[0],7,rgb[1],rgb[2],247};
        assert(!memcmp(expected,out,16));
    }
    for(unsigned i=0;i<16;i++) {
        assert(request(&s,1,i,rgb,out)==16 && out[11]==i && out[13]==127-i && out[14]==32+i);
    }
    F1ColorSession previous=s;
    assert(!request(&s,2,16,rgb,out));
    rgb[2]=128;assert(!request(&s,2,3,rgb,out));
    assert(!memcmp(previous.colors,s.colors,sizeof s.colors));
    f1_color_init(&s);
    assert(request(&s,1,3,rgb,out)==16 && out[11]==127 && out[13]==0 && out[14]==0);
    puts("PASS: 16 distinct previews and readbacks; invalid writes; session reset.");
    return 0;
}

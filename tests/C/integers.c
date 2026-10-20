typedef unsigned u32;
volatile u32 seed=0x8badf00d;
__attribute__((noinline)) u32 mix(u32 x,u32 y){x^=y;x=(x<<7)|(x>>25);return x*33u+0x1234;}
int test_main(void){u32 x=seed,y=0x13579bdfu;for(unsigned i=0;i<40;i++){x=mix(x,y);y=y*1664525u+1013904223u;}return x!=0x36eb20eeu;}

volatile unsigned values[4]={3,19,42,0};
__attribute__((noinline)) unsigned choose(unsigned a,unsigned b,unsigned c){return c?a:b;}
int test_main(void){if(choose(values[0],values[1],values[2])!=3)return 1;if(choose(values[0],values[1],values[3])!=19)return 2;return 0;}

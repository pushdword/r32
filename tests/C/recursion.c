volatile unsigned seed[8]={0,1,2,3,4,5,6,7};
__attribute__((noinline)) unsigned f(unsigned n){if(n<2)return 1;return n*f(n-1)+seed[n];}
int test_main(void){return f(seed[7])!=13699;}

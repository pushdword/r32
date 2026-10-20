volatile unsigned seed=1;
__attribute__((noinline)) unsigned f(unsigned a,unsigned b,unsigned c,unsigned d,unsigned e,unsigned f,unsigned g,unsigned h,unsigned i,unsigned j,unsigned k,unsigned l){return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j+11*k+12*l;}
int test_main(void){unsigned x=seed;return f(x,x+1,x+2,x+3,x+4,x+5,x+6,x+7,x+8,x+9,x+10,x+11)!=650;}

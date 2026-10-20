#include <stdarg.h>
volatile unsigned seed=1;
__attribute__((noinline)) unsigned sum(unsigned n,...){va_list ap;va_start(ap,n);unsigned s=0;for(unsigned i=0;i<n;i++)s+=va_arg(ap,unsigned);va_end(ap);return s;}
int test_main(void){unsigned x=seed;return sum(10,x,2,3,4,5,6,7,8,9,10)!=55;}

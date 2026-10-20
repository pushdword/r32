#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <math.h>
#include <setjmp.h>
#ifndef __R32_CPU__
#error native R32 frontend required
#endif
#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error R32 little-endian predefines required
#endif
#ifdef __riscv
#error Expected the native R32 compiler target
#endif
_Static_assert(sizeof(void*)==4 && sizeof(long)==4 && sizeof(long long)==8,"ILP32");
_Static_assert(sizeof(double)==8 && sizeof(long double)==8,"binary64 double");
_Static_assert(_Alignof(long long)==8 && _Alignof(double)==8,"64bit alignment");
_Static_assert((char)-1<0,"signed char ABI");
int r32_console_putc(unsigned char b){*(volatile unsigned*)0xf0000000=b;return 0;}
static int fail(int n){printf("SDK FAIL %d\n",n);return n;}
static __attribute__((noinline)) unsigned long long words(int prefix,...){
 va_list ap;va_start(ap,prefix);unsigned long long result=0;
 for(int i=0;i<prefix;i++)result+=va_arg(ap,unsigned long long);
 va_end(ap);return result;
}
static __attribute__((noinline)) double reals(int count,...){va_list ap;va_start(ap,count);double r=0;for(int i=0;i<count;i++)r+=va_arg(ap,double);va_end(ap);return r;}
static __attribute__((noinline)) unsigned long long divv(unsigned long long x,unsigned long long y){return x/y;}
static __attribute__((noinline)) long long divs(long long x,long long y){return x/y;}
static __attribute__((noinline)) double calc(double a,double b){return (a+b)*(a-b)/b;}
static int compare(const void*a,const void*b){int x=*(const int*)a,y=*(const int*)b;return (x>y)-(x<y);}
extern void optional_sdk_hook(void) __attribute__((weak));
static volatile unsigned long long dividend_u=0xfedcba9876543210ull,divisor_u=12345;
static volatile long long dividend_s=-1234567890123ll,divisor_s=12345;
static volatile double operand_a=5.0,operand_b=2.0;
static jmp_buf env;static volatile int saved;
static __attribute__((noinline)) void jump(void){saved=7;longjmp(env,0);}
int main(void){
 if(optional_sdk_hook)optional_sdk_hook();
 if(words(5,1ull,0x123456789abcdef0ull,3ull,4ull,5ull)!=0x123456789abcdefdull)return fail(1);
 if(reals(5,1.25,2.5,3.75,4.0,5.5)!=17.0)return fail(2);
 if(divv(dividend_u,divisor_u)!=0x548fd367c6dfeull)return fail(3);
 if(divs(dividend_s,divisor_s)!=-100005499ll)return fail(4);
 if(calc(operand_a,operand_b)!=10.5)return fail(5);
 volatile double x=2.0;double s=sqrt(x);if(!(s>1.41421356237309 && s<1.41421356237310))return fail(6);
 if(signbit(-0.0)==0 || !isnan(sqrt(-x)) || !isinf(1.0/(x-x)))return fail(7);
 char text[128];snprintf(text,sizeof text,"%lld %llu %.3f",-1234567890123ll,0xfedcba9876543210ull,1.25);
 if(strcmp(text,"-1234567890123 18364758544493064720 1.250"))return fail(8);
 int *a=calloc(64,sizeof *a);if(!a)return fail(9);for(int i=0;i<64;i++)a[i]=63-i;qsort(a,64,sizeof *a,compare);for(int i=0;i<64;i++)if(a[i]!=i)return fail(10);free(a);
 if(setjmp(env)==0)jump();if(saved!=7)return fail(11);
 puts("SDK PASS: native R32 ABI varargs64 soft-double math stdio heap setjmp");return 0;
}

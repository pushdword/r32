static volatile unsigned state,chosen;
__attribute__((noinline)) static unsigned step(unsigned n,unsigned x){
 switch(n){
 case 0:state+=3;break;case 1:state^=x;break;case 2:state*=7;break;
 case 3:state-=x;break;case 4:state+=x*5;break;case 5:state>>=1;break;
 case 6:state|=x;break;case 7:state&=x;break;default:state=19;break;
 }
 return state;
}
int test_main(void){
 unsigned expected=11;state=11;
 for(unsigned i=0;i<40;i++){
  chosen=i%9;unsigned n=chosen,x=i*13+5;
  switch(n){case 0:expected+=3;break;case 1:expected^=x;break;case 2:expected*=7;break;
  case 3:expected-=x;break;case 4:expected+=x*5;break;case 5:expected>>=1;break;
  case 6:expected|=x;break;case 7:expected&=x;break;default:expected=19;break;}
  if(step(n,x)!=expected)return i+1;
 }
 return 0;
}

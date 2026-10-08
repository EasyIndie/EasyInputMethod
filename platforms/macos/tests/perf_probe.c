#include "ime.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mach/mach.h>
#include <string.h>
static double footprint(void) { task_vm_info_data_t info; mach_msg_type_number_t n=TASK_VM_INFO_COUNT; if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&n)!=KERN_SUCCESS)return -1;return info.phys_footprint/1048576.0; }
#include <sys/resource.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static int compare(const void*a,const void*b) { double x=*(const double*)a,y=*(const double*)b; return (x>y)-(x<y); }
int main(int argc,char**argv) {
 if(argc!=5)return 2;
 ime_config_init(argv[4]);
 ImeSession*s=ime_session_new_with_data(argv[1],strcmp(argv[2],"-")?argv[2]:NULL,strcmp(argv[3],"-")?argv[3]:NULL); if(!s)return 3;
 printf("loaded_footprint_mib=%.2f\n",footprint());
 double values[5000]; int n=0;
 const char*inputs[]={"wq","nihao","zhongguo","zz","a","kwwl"};
 for(int i=0;i<100;i++) for(int j=0;j<6;j++) { if(j==0 && i%10==0)printf("round=%d footprint=%.2f\n",i,footprint()); ime_session_reset(s);
  for(const char*p=inputs[j];*p;p++) { double t=now(); ime_session_configure(s); ime_session_key(s,*p); values[n++]=(now()-t)*1000; }
 }
 qsort(values,n,sizeof(double),compare);
 struct rusage usage; getrusage(RUSAGE_SELF,&usage);
 printf("keys=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f peak_rss_mib=%.2f\n",n,values[n/2],values[n*95/100],values[n-1],usage.ru_maxrss/1048576.0);
 printf("steady_footprint_mib=%.2f\n",footprint());
 ime_session_free(s);return 0;
}

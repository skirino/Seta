#include <stdio.h>
#include <string.h>
#include <libproc.h>

int readCwd(pid_t pid, char* buff) {
  struct proc_vnodepathinfo vpi;
  int ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
  if (ret <= 0) {
    return -1;
  }
  int len = strlen(vpi.pvi_cdir.vip_path);
  strncpy(buff, vpi.pvi_cdir.vip_path, len + 1); // copy including NULL character
  return len;
}

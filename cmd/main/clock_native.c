#ifdef __cplusplus
extern "C" {
#endif

#include <time.h>

// Wall-clock seconds since the Unix epoch. Only the native CLI uses this;
// every library package keeps its clock injected by callers.
long long mooncache_wall_clock_seconds(void) {
  time_t now = time(NULL);
  return (long long)now;
}

#ifdef __cplusplus
}
#endif

/* libc symbols the Xash3D objects need that the RADV link would otherwise
 * resolve from libScePosixForWebKit (not loaded for a native game: the call
 * lands on address 0x300). The normal Xash build took them from the payload
 * SDK's static libc.a. */
#include <ctype.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>

struct passwd;
struct passwd *getpwuid(unsigned uid) { (void)uid; return NULL; }

char *strcasestr(const char *s, const char *find)
{
   size_t n = strlen(find);
   if (!n)
      return (char *)s;
   for (; *s; s++) {
      size_t i = 0;
      while (i < n && s[i] && tolower((unsigned char)s[i]) == tolower((unsigned char)find[i]))
         i++;
      if (i == n)
         return (char *)s;
   }
   return NULL;
}

int isatty(int fd) { (void)fd; errno = ENOTTY; return 0; }

int mkstemp(char *tmpl)
{
   size_t len = strlen(tmpl);
   if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX")) { errno = EINVAL; return -1; }
   static unsigned counter;
   for (int attempt = 0; attempt < 100; attempt++) {
      unsigned v = (unsigned)time(NULL) * 2654435761u + counter++ * 40503u;
      for (int i = 0; i < 6; i++) {
         tmpl[len - 6 + i] = "abcdefghijklmnopqrstuvwxyz0123456789"[v % 36];
         v /= 36;
      }
      int fd = open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
      if (fd >= 0 || errno != EEXIST)
         return fd;
   }
   return -1;
}

/* 120 Hz: the Zink/Vulkan build can open VideoOut at 119.88 Hz (PS5_Vulkan's
 * VideoOut WSI). Overrides the engine's weak default (host.c). */
int ps5_hfr_available(void) { return 1; }

/* Asked by the VideoOut WSI (wsi_common_videoout.c) before it opens the
 * display: high frame rate only when the player chose 120 Hz in Video modes. */
#include <stdbool.h>
#include <stdio.h>
bool ps5_videoout_want_high_frame_rate(void)
{
	FILE *f = fopen("/download0/xash_refresh.txt", "r");
	int hz = 60;
	if (f) {
		if (fscanf(f, "%d", &hz) != 1)
			hz = 60;
		fclose(f);
	}
	return hz == 120;
}

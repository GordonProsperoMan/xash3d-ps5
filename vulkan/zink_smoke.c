// Zink-on-RADV smoke test for the PS5 (Xash3D-PS5 experimental branch).
// EGL (ps5_zink_egl.c) -> Mesa GL -> Zink -> RADV -> VideoOut.
// Clears the screen through a colour cycle and draws a triangle for ~10 s,
// printing renderer info and frame timing to klog, then closes the app.
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

typedef unsigned int GLenum;
typedef unsigned int GLbitfield;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned char GLubyte;
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_DEPTH_BUFFER_BIT 0x00000100
#define GL_TRIANGLES 0x0004
#define GL_VENDOR 0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02

typedef void (*PFNCLEARCOLOR)(GLfloat, GLfloat, GLfloat, GLfloat);
typedef void (*PFNCLEAR)(GLbitfield);
typedef const GLubyte *(*PFNGETSTRING)(GLenum);
typedef void (*PFNBEGIN)(GLenum);
typedef void (*PFNEND)(void);
typedef void (*PFNCOLOR3F)(GLfloat, GLfloat, GLfloat);
typedef void (*PFNVERTEX2F)(GLfloat, GLfloat);
typedef void (*PFNVIEWPORT)(GLint, GLint, GLsizei, GLsizei);
typedef void (*PFNFINISH)(void);

int sceSystemServiceLoadExec(const char *path, char *const argv[]);

static double now(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return ts.tv_sec + ts.tv_nsec / 1e9;
}

#define LOAD(type, name) type name = (type)eglGetProcAddress(#name)

int main(void)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   zlog("[zink-smoke] start\n");
   EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
   EGLint maj, min;
   if (!eglInitialize(dpy, &maj, &min)) {
      zlog("[zink-smoke] eglInitialize failed 0x%x\n", eglGetError());
      goto out;
   }
   EGLConfig cfg; EGLint n = 0;
   eglChooseConfig(dpy, NULL, &cfg, 1, &n);
   EGLSurface surf = eglCreateWindowSurface(dpy, cfg, 0, NULL);
   if (surf == EGL_NO_SURFACE) {
      zlog("[zink-smoke] eglCreateWindowSurface failed 0x%x\n", eglGetError());
      goto out;
   }
   eglBindAPI(EGL_OPENGL_API);
   EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, NULL);
   if (ctx == EGL_NO_CONTEXT) {
      zlog("[zink-smoke] eglCreateContext failed 0x%x\n", eglGetError());
      goto out;
   }
   if (!eglMakeCurrent(dpy, surf, surf, ctx)) {
      zlog("[zink-smoke] eglMakeCurrent failed 0x%x\n", eglGetError());
      goto out;
   }
   LOAD(PFNGETSTRING, glGetString);
   LOAD(PFNCLEARCOLOR, glClearColor);
   LOAD(PFNCLEAR, glClear);
   LOAD(PFNBEGIN, glBegin);
   LOAD(PFNEND, glEnd);
   LOAD(PFNCOLOR3F, glColor3f);
   LOAD(PFNVERTEX2F, glVertex2f);
   LOAD(PFNVIEWPORT, glViewport);
   if (!glGetString || !glClear) {
      zlog("[zink-smoke] GL entry points missing\n");
      goto out;
   }
   zlog("[zink-smoke] GL_VENDOR=%s\n", glGetString(GL_VENDOR));
   zlog("[zink-smoke] GL_RENDERER=%s\n", glGetString(GL_RENDERER));
   zlog("[zink-smoke] GL_VERSION=%s\n", glGetString(GL_VERSION));
   EGLint w = 0, h = 0;
   eglQuerySurface(dpy, surf, EGL_WIDTH, &w);
   eglQuerySurface(dpy, surf, EGL_HEIGHT, &h);
   glViewport(0, 0, w, h);
   eglSwapInterval(dpy, 1);

   double start = now(), last = start;
   int frames = 0, total = 0;
   while (now() - start < 10.0) {
      float t = (float)(now() - start);
      glClearColor(0.5f + 0.5f * (t - (int)t), 0.2f, 0.6f - 0.05f * t, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
      glBegin(GL_TRIANGLES);
      glColor3f(1, 0, 0); glVertex2f(-0.6f, -0.5f);
      glColor3f(0, 1, 0); glVertex2f(0.6f, -0.5f);
      glColor3f(0, 0, 1); glVertex2f(0.0f, 0.6f);
      glEnd();
      if (!eglSwapBuffers(dpy, surf)) {
         zlog("[zink-smoke] eglSwapBuffers failed 0x%x at frame %d\n", eglGetError(), total);
         break;
      }
      frames++; total++;
      if (now() - last >= 1.0) {
         zlog("[zink-smoke] fps=%.1f frames=%d\n", frames / (now() - last), total);
         frames = 0;
         last = now();
      }
   }
   zlog("[zink-smoke] done, %d frames\n", total);
   eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
out:
   zlog("[zink-smoke] closing\n");
   sceSystemServiceLoadExec("exit", NULL);
   for (;;)
      sleep(1);
}

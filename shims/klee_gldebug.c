/* klee debug: keep Mir's std::cout usable when glGetString() returns NULL,
 * and report the EGL/GL state at that point. */
typedef unsigned long size_t;
void *dlsym(void *, const char *);
int fprintf(void *, const char *, ...);
extern void *stderr;
#define RTLD_NEXT ((void *)-1l)

const unsigned char *glGetString(unsigned int name)
{
	static const unsigned char *(*real)(unsigned int);
	static void *(*getctx)(void);
	static int (*eglerr)(void);
	if (!real) {
		real = dlsym(RTLD_NEXT, "glGetString");
		getctx = dlsym(RTLD_NEXT, "eglGetCurrentContext");
		eglerr = dlsym(RTLD_NEXT, "eglGetError");
	}
	const unsigned char *r = real ? real(name) : 0;
	if (!r) {
		fprintf(stderr, "klee_gl: glGetString(0x%x)=NULL ctx=%p eglError=0x%x\n", name,
			getctx ? getctx() : (void *)0, eglerr ? eglerr() : -1);
		return (const unsigned char *)"(null)";
	}
	return r;
}

/* KLEE_WHITE=1: paint every frame white right before it is posted, to test
 * the compositor -> HWC -> panel path independently of the shell's content */
char *getenv(const char *);
unsigned int eglSwapBuffers(void *dpy, void *surf)
{
	static unsigned int (*real)(void *, void *);
	static void (*clearcolor)(float, float, float, float);
	static void (*clear)(unsigned int);
	static void (*disable)(unsigned int);
	static int white = -1;
	if (!real) {
		real = dlsym(RTLD_NEXT, "eglSwapBuffers");
		clearcolor = dlsym(RTLD_NEXT, "glClearColor");
		clear = dlsym(RTLD_NEXT, "glClear");
		disable = dlsym(RTLD_NEXT, "glDisable");
	}
	if (white < 0)
		white = getenv("KLEE_WHITE") != 0;
	if (white && clearcolor && clear && disable) {
		disable(0x0C11); /* GL_SCISSOR_TEST */
		clearcolor(1, 1, 1, 1);
		clear(0x4000); /* GL_COLOR_BUFFER_BIT */
	}
	return real(dpy, surf);
}

/*
 * klee: Mir's android platform creates its own ANativeWindow for the display.
 * Newer Mali drivers validate the window with queries Mir does not know
 * (e.g. NATIVE_WINDOW_IS_VALID) and then reject it ("Bad native window during
 * surface check"). Wrap query()/perform() of windows passed to EGL, answer
 * what is missing and log any other failing request.
 */
typedef unsigned long size_t;
void *dlsym(void *, const char *);
int snprintf(char *, size_t, const char *, ...);
long write(int, const void *, size_t);
#define RTLD_NEXT ((void *)-1l)
#define NULL ((void *)0)

/* offsets in struct ANativeWindow (aarch64) */
#define OFF_QUERY 144
#define OFF_PERFORM 152
#define WINDOW_MAGIC 0x5f776e64 /* '_wnd' */
#define NATIVE_WINDOW_IS_VALID 17

typedef int (*query_fn)(const void *, int, int *);
typedef int (*perform_fn)(void *, int, ...);

#define MAXW 16
static struct { void *win; query_fn q; } wins[MAXW];
static int nlog;

static void say(const char *m)
{
	int l = 0;
	while (m[l])
		l++;
	write(2, m, l);
}

static query_fn orig_query(const void *w)
{
	for (int i = 0; i < MAXW; i++)
		if (wins[i].win == w)
			return wins[i].q;
	return NULL;
}

static int my_query(const void *w, int what, int *value)
{
	query_fn q = orig_query(w);
	int r = q ? q(w, what, value) : -22;
	if (r != 0 && what == NATIVE_WINDOW_IS_VALID) {
		*value = 1;
		r = 0;
	}
	if (r != 0 && nlog < 50) {
		char m[96];
		snprintf(m, sizeof(m), "klee_win: query(%d) -> %d\n", what, r);
		say(m);
		nlog++;
	}
	return r;
}

static void wrap(void *win)
{
	if (!win || *(int *)win != WINDOW_MAGIC)
		return;
	query_fn *qp = (query_fn *)((char *)win + OFF_QUERY);
	if (*qp == my_query)
		return;
	for (int i = 0; i < MAXW; i++) {
		if (!wins[i].win) {
			wins[i].win = win;
			wins[i].q = *qp;
			*qp = my_query;
			say("klee_win: wrapped a native window\n");
			return;
		}
	}
}

void *eglCreateWindowSurface(void *dpy, void *cfg, void *win, const int *attr)
{
	static void *(*real)(void *, void *, void *, const int *);
	if (!real)
		real = dlsym(RTLD_NEXT, "eglCreateWindowSurface");
	wrap(win);
	return real(dpy, cfg, win, attr);
}

void *eglCreatePlatformWindowSurface(void *dpy, void *cfg, void *win, const long *attr)
{
	static void *(*real)(void *, void *, void *, const long *);
	if (!real)
		real = dlsym(RTLD_NEXT, "eglCreatePlatformWindowSurface");
	wrap(win);
	return real(dpy, cfg, win, attr);
}

/*
 * klee: libhybris bionic shim (loaded with HYBRIS_LD_PRELOAD).
 *
 * libhybris redirects malloc/free of Android libraries to glibc, but not
 * realpath()/getcwd(). When those allocate their result themselves
 * (realpath(p, NULL), getcwd(NULL, 0)) the memory comes from bionic's
 * allocator, and the caller's free() then goes to glibc -> "free(): invalid
 * pointer" abort. The Mali EGL driver (libGLES_mali.so) does exactly that.
 * Here the allocating cases use a stack buffer + strdup (hooked -> glibc).
 */
typedef unsigned long size_t;
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *strdup(const char *);

#define RTLD_NOW 2
typedef char *(*realpath_fn)(const char *, char *);
typedef char *(*getcwd_fn)(char *, size_t);

static void *libc_sym(const char *name)
{
	static void *libc;
	if (!libc)
		libc = dlopen("libc.so", RTLD_NOW);
	return libc ? dlsym(libc, name) : 0;
}

char *realpath(const char *path, char *resolved)
{
	static realpath_fn real;
	char buf[4096];
	if (!real)
		real = (realpath_fn)libc_sym("realpath");
	if (!real)
		return 0;
	if (resolved)
		return real(path, resolved);
	if (!real(path, buf))
		return 0;
	return strdup(buf);
}

char *getcwd(char *buf, size_t size)
{
	static getcwd_fn real;
	char tmp[4096];
	if (!real)
		real = (getcwd_fn)libc_sym("getcwd");
	if (!real)
		return 0;
	if (buf)
		return real(buf, size);
	if (!real(tmp, sizeof(tmp)))
		return 0;
	return strdup(tmp);
}

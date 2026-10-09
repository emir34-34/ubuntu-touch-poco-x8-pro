/*
 * klee: route free() of bionic (scudo) allocations back to bionic.
 *
 * Vendor libraries loaded by libhybris call bionic libc functions that are
 * not hooked; those allocate with bionic's own malloc (scudo). When the vendor
 * code later calls free(), libhybris hooks it to glibc's free(), which aborts
 * with "free(): invalid pointer". LD_PRELOAD this into the glibc process: a
 * pointer that lies in a [anon:scudo:*] mapping is handed to bionic's free().
 */
/* no glibc headers in the sysroot: declare what we use */
typedef unsigned long uintptr_t, size_t;
typedef long ssize_t;
typedef struct { const char *dli_fname; void *dli_fbase; const char *dli_sname; void *dli_saddr; } Dl_info;
typedef union { char size[48]; long align; } pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER { { 0 } }
#define RTLD_NOW 2
#define O_RDONLY 0
#define O_CLOEXEC 02000000
#define NULL ((void *)0)
struct dl_phdr_info { uintptr_t dlpi_addr; const char *dlpi_name; const void *dlpi_phdr; unsigned short dlpi_phnum; };
typedef struct { unsigned int p_type, p_flags; unsigned long p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align; } Elf64_Phdr;
int dl_iterate_phdr(int (*)(struct dl_phdr_info *, size_t, void *), void *);
int pthread_mutex_lock(pthread_mutex_t *);
int pthread_mutex_unlock(pthread_mutex_t *);
int open(const char *, int, ...);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int close(int);
char *strstr(const char *, const char *);
int sscanf(const char *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);

extern void *android_dlopen(const char *, int);
extern void *android_dlsym(void *, const char *);
extern void __libc_free(void *);

/* all mappings of the process (sorted, as in /proc/self/maps), flagged
 * whether they belong to bionic's scudo allocator */
#define MAXR 16384
static struct { uintptr_t s, e; int scudo; } ranges[MAXR];
static int nranges;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void (*bionic_free)(void *);
static int logged;

/* -1: unknown address, 0: glibc/other, 1: scudo */
static int classify(uintptr_t p)
{
	int lo = 0, hi = nranges - 1;
	while (lo <= hi) {
		int mid = (lo + hi) / 2;
		if (p < ranges[mid].s)
			hi = mid - 1;
		else if (p >= ranges[mid].e)
			lo = mid + 1;
		else
			return ranges[mid].scudo;
	}
	return -1;
}

/* parse /proc/self/maps without allocating (we are inside free) */
static void scan_maps(void)
{
	static char buf[1 << 16];
	char line[512];
	int fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC), li = 0;
	ssize_t n;

	nranges = 0;
	if (fd < 0)
		return;
	while ((n = read(fd, buf, sizeof(buf))) > 0) {
		for (ssize_t i = 0; i < n; i++) {
			if (buf[i] != '\n') {
				if (li < (int)sizeof(line) - 1)
					line[li++] = buf[i];
				continue;
			}
			line[li] = 0;
			li = 0;
			unsigned long s, e;
			if (nranges < MAXR && sscanf(line, "%lx-%lx", &s, &e) == 2) {
				ranges[nranges].s = s;
				ranges[nranges].e = e;
				ranges[nranges].scudo = strstr(line, "scudo") != NULL;
				nranges++;
			}
		}
	}
	close(fd);
}

/* executable segments of objects loaded by glibc's ld.so; bionic objects
 * loaded by libhybris' linker never show up here. Two buffers: readers use
 * the published one while a rescan fills the other. */
#define MAXC 2048
struct codeset { int n; struct { uintptr_t s, e; } r[MAXC]; };
static struct codeset sets[2];
static struct codeset *volatile cur;
static unsigned long long adds_seen = ~0ull;

static int phdr_cb(struct dl_phdr_info *info, size_t sz, void *data)
{
	struct codeset *cs = data;
	const Elf64_Phdr *ph = info->dlpi_phdr;
	(void)sz;
	for (int i = 0; i < info->dlpi_phnum; i++) {
		if (ph[i].p_type != 1 || !(ph[i].p_flags & 1) || cs->n >= MAXC)
			continue;
		cs->r[cs->n].s = info->dlpi_addr + ph[i].p_vaddr;
		cs->r[cs->n].e = cs->r[cs->n].s + ph[i].p_memsz;
		cs->n++;
	}
	return 0;
}

/* glibc's struct dl_phdr_info continues with dlpi_adds: objects loaded so far */
static int adds_cb(struct dl_phdr_info *info, size_t sz, void *data)
{
	*(unsigned long long *)data = sz > 32 ? *(const unsigned long long *)((const char *)info + 32) : 0;
	return 1;
}

static int code_hit(const struct codeset *cs, uintptr_t a)
{
	if (!cs)
		return 0;
	for (int i = 0; i < cs->n; i++)
		if (a >= cs->r[i].s && a < cs->r[i].e)
			return 1;
	return 0;
}

static int glibc_code(uintptr_t a)
{
	unsigned long long adds = 0;

	if (code_hit(cur, a))
		return 1;
	dl_iterate_phdr(adds_cb, &adds);
	if (adds == adds_seen)
		return 0;
	/* glibc loaded something new since the last scan */
	pthread_mutex_lock(&lock);
	if (adds != adds_seen) {
		struct codeset *next = cur == &sets[0] ? &sets[1] : &sets[0];
		next->n = 0;
		dl_iterate_phdr(phdr_cb, next);
		__atomic_store_n(&cur, next, __ATOMIC_RELEASE);
		adds_seen = adds;
	}
	pthread_mutex_unlock(&lock);
	return code_hit(cur, a);
}

void free(void *p)
{
	uintptr_t caller = (uintptr_t)__builtin_return_address(0);

	if (!p)
		return;
	/* fast path: caller is code loaded by glibc's ld.so (cached ranges) */
	if (glibc_code(caller)) {
		__libc_free(p);
		return;
	}
	pthread_mutex_lock(&lock);
	int bionic = classify((uintptr_t)p);
	if (bionic < 0) {
		scan_maps();
		bionic = classify((uintptr_t)p) == 1;
	}
	if (bionic && !bionic_free) {
		void *h = android_dlopen("libc.so", RTLD_NOW);
		bionic_free = h ? android_dlsym(h, "free") : NULL;
	}
	if (bionic && logged < 20) {
		char msg[160];
		int l = snprintf(msg, sizeof(msg), "klee_free: bionic ptr %p freed from %p -> %s\n",
				 p, (void *)caller, bionic_free ? "bionic free" : "LEAKED");
		write(2, msg, l);
		logged++;
	}
	pthread_mutex_unlock(&lock);
	if (!bionic)
		__libc_free(p);
	else if (bionic_free)
		bionic_free(p);
	/* else: leak it rather than abort */
}

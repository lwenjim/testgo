/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.ac by autoheader.  */

/* Define to 1 to get debugging info */
/* #undef DEBUG */

/* Define if overwriting argv changes args visible in ps (1) */
#define ENABLE_MIRROR_ARGS 1

/* Define if your getopt() correctly understands double colons in the option
   string */
#define GETOPT_GROKS_OPTIONAL_ARGS 1

/* Define to 1 if you have the `basename' function. */
#define HAVE_BASENAME 1

/* Define to 1 if you have the <curses.h> header file. */
#define HAVE_CURSES_H 1

/* Define to 1 if you have the declaration of `procstat_getfiles', and to 0 if
   you don't. */
#define HAVE_DECL_PROCSTAT_GETFILES 0

/* Define to 1 if you have the declaration of `procstat_getprocs', and to 0 if
   you don't. */
#define HAVE_DECL_PROCSTAT_GETPROCS 0

/* Define to 1 if you have the declaration of `procstat_open_sysctl', and to 0
   if you don't. */
#define HAVE_DECL_PROCSTAT_OPEN_SYSCTL 0

/* Define to 1 if you have the declaration of `PROC_PIDVNODEPATHINFO', and to
   0 if you don't. */
#define HAVE_DECL_PROC_PIDVNODEPATHINFO 0

/* Define to 1 if you have the declaration of `STAILQ_FOREACH ', and to 0 if
   you don't. */
#define HAVE_DECL_STAILQ_FOREACH_ 0

/* Define to 1 if you have the `dirname' function. */
#define HAVE_DIRNAME 1

/* Define to 1 if you have the <errno.h> header file. */
#define HAVE_ERRNO_H 1

/* Define to 1 if you have the <fcntl.h> header file. */
#define HAVE_FCNTL_H 1

/* Define to 1 if you have the `flock' function. */
#define HAVE_FLOCK 1

/* Define to 1 to use FREEBSD libprocstat */
/* #undef HAVE_FREEBSD_LIBPROCSTAT */

/* Define to 1 if you have the <getopt.h> header file. */
#define HAVE_GETOPT_H 1

/* Define to 1 if you have the `getopt_long' function. */
#define HAVE_GETOPT_LONG 1

/* Define if you have _GNU_SOURCE getpt() */
/* #undef HAVE_GETPT */

/* Define to 1 if you have the `getpty' function. */
/* #undef HAVE_GETPTY */

/* Define to 1 if you have the `grantpt' function. */
#define HAVE_GRANTPT 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define to 1 if you have the `isastream' function. */
/* #undef HAVE_ISASTREAM */

/* Define to 1 if you have the <libgen.h> header file. */
#define HAVE_LIBGEN_H 1

/* Define to 1 if you have the `util' library (-lutil). */
#define HAVE_LIBUTIL 1

/* Define to 1 if you have the <libutil.h> header file. */
/* #undef HAVE_LIBUTIL_H */

/* Define to 1 if you have the <minix/config.h> header file. */
/* #undef HAVE_MINIX_CONFIG_H */

/* Define to 1 if you have the `mkstemps' function. */
#define HAVE_MKSTEMPS 1

/* Define to 1 if you have the <ncurses/term.h> header file. */
/* #undef HAVE_NCURSES_TERM_H */

/* Define to 1 if you have the `openpty' function. */
#define HAVE_OPENPTY 1

/* Define to 1 if <opt_proc_mountpoint>/<pid>/cwd is a link to working
   directory of process <pid> */
#define HAVE_PROC_PID_CWD 1 

/* Define to 1 if you have the `pselect' function. */
#define HAVE_PSELECT 1

/* Define to 1 if you have the <pty.h> header file. */
#define HAVE_PTY_H 1

/* Define to 1 if you have the `putenv' function. */
#define HAVE_PUTENV 1

/* Define to 1 if you have the `readlink' function. */
#define HAVE_READLINK 1

/* Define to 1 if you have the <regex.h> header file. */
#define HAVE_REGEX_H 1

/* Define to 1 if your readline lib has rl_basic_quote_characters */
#define HAVE_RL_BASIC_QUOTE_CHARS 1 

/* Define to 1 if your readline lib has rl_executing_keyseq */
#define HAVE_RL_EXECUTING_KEYSEQ 1 

/* Define to 1 if your readline lib has rl_readline_version */
#define HAVE_RL_READLINE_VERSION 1 

/* Define to 1 if your readline lib has rl_set_screen_size */
#define HAVE_RL_SET_SCREEN_SIZE 1 

/* Define to 1 if your readline lib has rl_variable_value */
#define HAVE_RL_VARIABLE_VALUE 1 

/* Define to 1 if you have the <sched.h> header file. */
#define HAVE_SCHED_H 1

/* Define to 1 if you have the `sched_yield' function. */
#define HAVE_SCHED_YIELD 1

/* Define to 1 if you have the `setenv' function. */
#define HAVE_SETENV 1

/* Define to 1 if you have the `setitimer' function. */
#define HAVE_SETITIMER 1

/* Define to 1 if you have the `setrlimit' function. */
#define HAVE_SETRLIMIT 1

/* Define to 1 if you have the `setsid' function. */
#define HAVE_SETSID 1

/* Define to 1 if you have the `sigaction' function. */
#define HAVE_SIGACTION 1

/* Define to 1 if you have the `snprintf' function. */
#define HAVE_SNPRINTF 1

/* Define to 1 if you have the <stddef.h> header file. */
#define HAVE_STDDEF_H 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdio.h> header file. */
#define HAVE_STDIO_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the `strlcat' function. */
/* #undef HAVE_STRLCAT */

/* Define to 1 if you have the `strlcpy' function. */
/* #undef HAVE_STRLCPY */

/* Define to 1 if you have the `strnlen' function. */
#define HAVE_STRNLEN 1

/* Define to 1 if you have the <stropts.h> header file. */
/* #undef HAVE_STROPTS_H */

/* Define to 1 if you have the `system' function. */
#define HAVE_SYSTEM 1

/* Define to 1 if you have the <sys/file.h> header file. */
#define HAVE_SYS_FILE_H 1

/* Define to 1 if you have the <sys/ioctl.h> header file. */
#define HAVE_SYS_IOCTL_H 1

/* Define to 1 if you have the <sys/resource.h> header file. */
#define HAVE_SYS_RESOURCE_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/time.h> header file. */
#define HAVE_SYS_TIME_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <sys/wait.h> header file. */
#define HAVE_SYS_WAIT_H 1

/* Define to 1 if you have the <termcap.h> header file. */
#define HAVE_TERMCAP_H 1

/* Define to 1 if you have the <termios.h> header file. */
#define HAVE_TERMIOS_H 1

/* Define to 1 if you have the <term.h> header file. */
#define HAVE_TERM_H 1

/* Define to 1 if you have the `tigetnum' function. */
#define HAVE_TIGETNUM 1

/* Define to 1 if you have the <time.h> header file. */
#define HAVE_TIME_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the `unlockpt' function. */
#define HAVE_UNLOCKPT 1

/* Define to 1 if you have the <util.h> header file. */
/* #undef HAVE_UTIL_H */

/* Define to 1 if you have the <wchar.h> header file. */
#define HAVE_WCHAR_H 1

/* Define to 1 to use homegrown_redisplay() */
/* #undef HOMEGROWN_REDISPLAY */

/* Define to 1 to be aware of wide chars in prompts */
#define MULTIBYTE_AWARE 1 

/* Name of package */
#define PACKAGE "rlwrap"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME "rlwrap"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "rlwrap 0.46.1"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME "rlwrap"

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "0.46.1"

/* Define to location of Linux-style procfs mountpoint if provided and valid
   */
#define PROC_MOUNTPOINT "/proc"

/* Define for first char in devptyXX */
#define PTYCHAR1 "?"

/* Define for second char in devptyXX */
#define PTYCHAR2 "?"

/* Define for this pty type */
/* #undef PTYS_ARE_CLONE */

/* Define for this pty type */
/* #undef PTYS_ARE_GETPT */

/* Define for this pty type */
/* #undef PTYS_ARE_GETPTY */

/* Define for this pty type */
/* #undef PTYS_ARE_NUMERIC */

/* Define for this pty type */
#define PTYS_ARE_OPENPTY 1

/* Define for this pty type */
/* #undef PTYS_ARE_PTC */

/* Define for this pty type */
/* #undef PTYS_ARE_PTMX */

/* Define for this pty type */
/* #undef PTYS_ARE_SEARCHED */

/* Define for this pty type */
/* #undef PTYS_ARE__GETPTY */

/* nonsense arg to overwrite conftest argv with */
#define RANDOM_NONSENSE2 "iraliuuklajcorjfunavdsytdiydjaoaeauiapidtoxogfplrxfmfcmajikwenafwcownmoodxjljhsv"

/* Define to 1 to use private _rl_horizontal_scroll_mode */
#define SPY_ON_READLINE 1 

/* Define to 1 if all of the C90 standard headers exist (not just the ones
   required in a freestanding environment). This macro is provided for
   backward compatibility; new code need not use it. */
#define STDC_HEADERS 1

/* Define as the type for the argument to the putc function of tputs ('int' or
   'char') */
#define TPUTS_PUTC_ARGTYPE int

/* Enable extensions on AIX 3, Interix.  */
#ifndef _ALL_SOURCE
# define _ALL_SOURCE 1
#endif
/* Enable general extensions on macOS.  */
#ifndef _DARWIN_C_SOURCE
# define _DARWIN_C_SOURCE 1
#endif
/* Enable general extensions on Solaris.  */
#ifndef __EXTENSIONS__
# define __EXTENSIONS__ 1
#endif
/* Enable GNU extensions on systems that have them.  */
#ifndef _GNU_SOURCE
# define _GNU_SOURCE 1
#endif
/* Enable X/Open compliant socket functions that do not require linking
   with -lxnet on HP-UX 11.11.  */
#ifndef _HPUX_ALT_XOPEN_SOCKET_API
# define _HPUX_ALT_XOPEN_SOCKET_API 1
#endif
/* Identify the host operating system as Minix.
   This macro does not affect the system headers' behavior.
   A future release of Autoconf may stop defining this macro.  */
#ifndef _MINIX
/* # undef _MINIX */
#endif
/* Enable general extensions on NetBSD.
   Enable NetBSD compatibility extensions on Minix.  */
#ifndef _NETBSD_SOURCE
# define _NETBSD_SOURCE 1
#endif
/* Enable OpenBSD compatibility extensions on NetBSD.
   Oddly enough, this does nothing on OpenBSD.  */
#ifndef _OPENBSD_SOURCE
# define _OPENBSD_SOURCE 1
#endif
/* Define to 1 if needed for POSIX-compatible behavior.  */
#ifndef _POSIX_SOURCE
/* # undef _POSIX_SOURCE */
#endif
/* Define to 2 if needed for POSIX-compatible behavior.  */
#ifndef _POSIX_1_SOURCE
/* # undef _POSIX_1_SOURCE */
#endif
/* Enable POSIX-compatible threading on Solaris.  */
#ifndef _POSIX_PTHREAD_SEMANTICS
# define _POSIX_PTHREAD_SEMANTICS 1
#endif
/* Enable extensions specified by ISO/IEC TS 18661-5:2014.  */
#ifndef __STDC_WANT_IEC_60559_ATTRIBS_EXT__
# define __STDC_WANT_IEC_60559_ATTRIBS_EXT__ 1
#endif
/* Enable extensions specified by ISO/IEC TS 18661-1:2014.  */
#ifndef __STDC_WANT_IEC_60559_BFP_EXT__
# define __STDC_WANT_IEC_60559_BFP_EXT__ 1
#endif
/* Enable extensions specified by ISO/IEC TS 18661-2:2015.  */
#ifndef __STDC_WANT_IEC_60559_DFP_EXT__
# define __STDC_WANT_IEC_60559_DFP_EXT__ 1
#endif
/* Enable extensions specified by ISO/IEC TS 18661-4:2015.  */
#ifndef __STDC_WANT_IEC_60559_FUNCS_EXT__
# define __STDC_WANT_IEC_60559_FUNCS_EXT__ 1
#endif
/* Enable extensions specified by ISO/IEC TS 18661-3:2015.  */
#ifndef __STDC_WANT_IEC_60559_TYPES_EXT__
# define __STDC_WANT_IEC_60559_TYPES_EXT__ 1
#endif
/* Enable extensions specified by ISO/IEC TR 24731-2:2010.  */
#ifndef __STDC_WANT_LIB_EXT2__
# define __STDC_WANT_LIB_EXT2__ 1
#endif
/* Enable extensions specified by ISO/IEC 24747:2009.  */
#ifndef __STDC_WANT_MATH_SPEC_FUNCS__
# define __STDC_WANT_MATH_SPEC_FUNCS__ 1
#endif
/* Enable extensions on HP NonStop.  */
#ifndef _TANDEM_SOURCE
# define _TANDEM_SOURCE 1
#endif
/* Enable X/Open extensions.  Define to 500 only if necessary
   to make mbstate_t available.  */
#ifndef _XOPEN_SOURCE
/* # undef _XOPEN_SOURCE */
#endif


/* Version number of package */
#define VERSION "0.46.1"

/* Define to empty if `const' does not conform to ANSI C. */
/* #undef const */

/* Define as a signed integer type capable of holding a process identifier. */
/* #undef pid_t */

/* Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010
 *               Free Software Foundation, Inc. */
/* This file is part of GNU Modula-2.

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA */

#include <config.h>

#if defined(HAVE_MATH_H)
#   include <math.h>
#endif

#if defined(HAVE_STDLIB_H)
#   include <stdlib.h>
#endif

#if defined(HAVE_SYS_STAT_H)
#   include <sys/stat.h>
#endif

#ifdef HAVE_STDIO_H
#  include <stdio.h>
#endif

/* Define a generic NULL if one hasn't already been defined.  */
#if !defined(NULL)
#  define NULL 0
#endif


/*
   strtime - returns the address of a string which describes the
             local time.
*/

char *wrapc_strtime (void)
{
#if defined(HAVE_CTIME)
  time_t clock = time((void *)0) ;
  char *string = ctime(&clock);

  string[24] = (char) 0;

  return string;
#else
  return "";
#endif
}


int wrapc_filesize (int f, unsigned int *low, unsigned int *high)
{
#if defined(HAVE_SYS_STAT_H) && defined(HAVE_STRUCT_STAT)
  struct stat s;
  int res = fstat (f, (struct stat *) &s);

  if (res == 0) {
    *low = (unsigned int) s.st_size ;
    *high = (unsigned int) (s.st_size >> (sizeof(unsigned int)*8));
  }
  return res;
#else
  return -1;
#endif
}


/*
 *   filemtime - returns the mtime of a file, f.
 */

int wrapc_filemtime (int f)
{
#if defined(HAVE_SYS_STAT_H) && defined(HAVE_STRUCT_STAT)
  struct stat s;

  if (fstat(f, (struct stat *) &s) == 0)
    return s.st_mtime;
  else
    return -1;
#else
  return -1;
#endif
}


/*
   getrand - returns a random number between 0..n-1
*/

int wrapc_getrand (int n)
{
  return rand() % n;
}

#if defined(HAVE_PWD_H)
#include <pwd.h>

char *wrapc_getusername (void)
{
  return getpwuid(getuid()) -> pw_gecos;
}

/*
   getnameuidgid - fills in the, uid, and, gid, which represents
                   user, name.
*/

void wrapc_getnameuidgid (char *name, int *uid, int *gid)
{
  struct passwd *p=getpwnam(name);

  if (p == NULL) {
    *uid = -1;
    *gid = -1;
  } else {
    *uid = p->pw_uid;
    *gid = p->pw_gid;
  }
}
#else
char *wrapc_getusername (void)
{
  return "unknown";
}

void wrapc_getnameuidgid (char *name, int *uid, int *gid)
{
  *uid = -1;
  *gid = -1;
}
#endif


int wrapc_signbit (double r)
{
#if defined(HAVE_SIGNBIT)
  /* signbit is a macro which tests its argument against sizeof(float),
     sizeof(double) */
  return signbit (r);
#else
  return 0;
#endif
}

int wrapc_signbitl (long double r)
{
#if defined(HAVE_SIGNBITL)
  /* signbit is a macro which tests its argument against sizeof(float),
     sizeof(double) */
  return signbitl (r);
#else
  return 0;
#endif
}

int wrapc_signbitf (float r)
{
#if defined(HAVE_SIGNBITF)
  /* signbit is a macro which tests its argument against sizeof(float),
     sizeof(double) */
  return signbitf (r);
#else
  return 0;
#endif
}

/*
   init - init/finish functions for the module
*/

void _M2_wrapc_init () {}
void _M2_wrapc_finish () {}

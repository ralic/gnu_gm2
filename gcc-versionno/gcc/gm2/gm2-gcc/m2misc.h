
/* Copyright (C) 2012
 * Free Software Foundation, Inc.
 *
 *  Gaius Mulley <gaius@glam.ac.uk> constructed this file.
 */

/*
This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

GNU Modula-2 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Modula-2; see the file COPYING.  If not, write to the
Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.
*/

#if !defined(m2misc_h)

#   define m2misc_h
#   if defined(m2misc_c)
#      if defined(__GNUG__)
#         define EXTERN extern "C"
#      else
#         define EXTERN 
#      endif
#   else
#      if defined(__GNUG__)
#         define EXTERN extern "C"
#      else
#         define EXTERN extern
#      endif
#   endif

EXTERN void m2misc_DebugTree (tree t);
EXTERN void m2misc_printStmt (void);
EXTERN void m2misc_DebugTreeChain (tree t);

#  undef EXTERN
#endif

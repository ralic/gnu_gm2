(* Copyright (C) 2001 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
MODULE gm2 ;

(*
   Author     : Gaius Mulley
   Title      : gm2
   Date       : 1987  [$Date: 2002/04/15 16:26:51 $]
   SYSTEM     : UNIX (GNU Modula-2)
   Description: Main module of the compiler, collects arguments and
                starts the compilation.
   Version    : $Revision: 1.2 $
*)

FROM M2Options IMPORT IsAnOption, ParseOptions ;
FROM M2Comp IMPORT Compile ;
FROM SArgs IMPORT GetArg, Narg ;
FROM Strings IMPORT String, InitString, string, KillString, EqualArray ;
FROM M2Printf IMPORT fprintf0 ;
FROM FIO IMPORT StdErr ;
FROM libc IMPORT exit ;


(*
   StartParsing - scans the command line and processes the arguments.
                  It attempts to compile the first module supplied.
*)

PROCEDURE StartParsing ;
VAR
   s, module: String ;
   n        : CARDINAL ;
BEGIN
   ParseOptions ;
   n := 1 ;
   module := NIL ;
   WHILE GetArg(s, n) AND
         (IsAnOption(s) OR EqualArray(s, '-M') OR EqualArray(s, '-o') OR
          EqualArray(s, '-dumpbase') OR EqualArray(s, '-version'))
   DO
      IF EqualArray(s, '-M') OR EqualArray(s, '-o')
      THEN
         INC(n)
      ELSIF EqualArray(s, '-dumpbase') AND GetArg(module, n+1)
      THEN
         INC(n)
      ELSIF EqualArray(s, '-version')
      THEN
      ELSIF EqualArray(s, '-Wcppbegin')
      THEN
         REPEAT
            INC(n)
         UNTIL (NOT GetArg(s, n)) OR (s=NIL) OR EqualArray(s, '-Wcppend') ;
         IF NOT EqualArray(s, '-Wcppend')
         THEN
            fprintf0(StdErr, 'expecting -Wcppend argument after a -Wcppbegin\n') ;
            exit(1)
         END
      END ;
      s := KillString(s) ;
      INC(n)
   END ;
   IF GetArg(s, n) AND (NOT IsAnOption(s))
   THEN
      Compile(s)
   END ;
   s := KillString(s) ;
   module := KillString(module)
END StartParsing ;


BEGIN
   StartParsing
END gm2.
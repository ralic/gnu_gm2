(* Copyright (C) 2009 Free Software Foundation, Inc. *)
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
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. *)

MODULE testio2 ;

FROM TextIO IMPORT ReadString, ReadRestLine, ReadToken, SkipLine ;
FROM SeqFile IMPORT OpenResults, ChanId, OpenRead, read ;
FROM IOConsts IMPORT ReadResults ;
FROM Strings IMPORT Length ;
FROM libc IMPORT exit, printf ;

VAR
   c: ChanId ;
   r: OpenResults ;
   s: ARRAY [0..80] OF CHAR ;
BEGIN
   OpenRead(c, 'testinput', read, r) ;
   ReadString(c, s) ;
   IF Length(s)#Length('this is a line of text')
   THEN
      printf("failed reading first string\n") ;
      exit(1)
   END ;
   ReadString(c, s) ;
   IF Length(s)#0
   THEN
      printf("failed reading second string\n") ;
      exit(2)
   END ;
   SkipLine(c) ;
   ReadToken(c, s) ;
   IF Length(s)#Length('some')
   THEN
      printf("failed reading third string\n") ;
      printf("should have only read 'some' and we read '%s' instead\n", s) ;
      exit(3)
   END
END testio2.

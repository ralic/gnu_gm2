(* Copyright (C) 2003 Free Software Foundation, Inc. *)
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

MODULE testiso2 ;

FROM SYSTEM IMPORT BITSET, WORD, BYTE, LOC, ADR ;

VAR
   b: BYTE ;
   l: LOC ;
   w: WORD ;
   bi: BITSET ;
   ch: CHAR ;
   v : POINTER TO CARDINAL ;
BEGIN
   w := 1234H ;
   b := BYTE(010H) ;
   b := VAL(BYTE, 0FFH) ;
   l := 7FH ;
   ch := 'z' ;
   bi := BITSET{1, 3, 5, 6, 31}
END testiso2.
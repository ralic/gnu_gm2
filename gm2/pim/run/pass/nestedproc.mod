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
MODULE nestedproc ;

FROM NumberIO IMPORT WriteCard ;
FROM StrIO IMPORT WriteString, WriteLn ;

VAR
   j: CARDINAL ;


PROCEDURE middle ;
VAR
   j: CARDINAL ;

   PROCEDURE displayit ;
   BEGIN
      WriteCard(j, 0) ; WriteLn
   END displayit ;

   PROCEDURE inner ;
   VAR
      j: CARDINAL ;
   BEGIN
      j := 999
   END inner ;

BEGIN
   j := 222 ;
   inner ;
   displayit
END middle ;



BEGIN
   j := 111 ;
   WriteString('the answers on the next two lines should be 111 and 222') ; WriteLn ;
   WriteCard(j, 0) ; WriteLn ;
   middle
   (* should yield   222 *)
END nestedproc.
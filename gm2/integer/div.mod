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
MODULE div ;

FROM libc IMPORT exit ;

VAR
   x, y: INTEGER ;
BEGIN
   x := -3 ;
   y :=  2 ;
   IF x DIV y#-1
   THEN
      exit(1)
   END ;
   IF -3 DIV 2#-1
   THEN
      exit(2)
   END
END div.
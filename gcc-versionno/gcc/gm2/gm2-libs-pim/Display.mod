(* Copyright (C) 2004, 2005, 2006, 2007, 2008, 2009, 2010
                 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

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
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA *)

IMPLEMENTATION MODULE Display ;

FROM FIO IMPORT StdOut, WriteChar ;
FROM ASCII IMPORT EOL, nl, bs, del ;


(*
   Write - display a character to the stdout.
           ASCII.EOL moves to the beginning of the next line.
           ASCII.del erases the character to the left of the cursor.
*)

PROCEDURE Write (ch: CHAR) ;
BEGIN
   CASE ch OF

   EOL:   WriteChar(StdOut, nl) |
   del:   WriteChar(StdOut, bs) ;
          WriteChar(StdOut, ' ') ;
          WriteChar(StdOut, bs)

   ELSE
      WriteChar(StdOut, ch)
   END
END Write ;


END Display.

(* Copyright (C) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009,
                 2010
                 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. *)

MODULE testwin ;

FROM WindowDevice IMPORT Window, InitWindow, SetWindow, TitleWindow,
                         WriteChar, PutOnTop ;
FROM StdIO IMPORT PushOutput, Write ;
FROM StrIO IMPORT WriteString, WriteLn ;
FROM ncurses IMPORT Blue, Red, White, Green, Yellow ;


VAR
   First,
   Second   : Window ;
   Debugging: Window ;

(*
   SetupWindows - sets up three windows, First, Second and Debugging.
                  After this procedure has been called all StdIO
                  writes will go through LocalWrite.
*)

PROCEDURE SetupWindows ;
BEGIN
   WriteString('\nBefore SetWindow') ;

   (* first process window *)
   First := SetWindow(InitWindow(), Blue, White, 37, 9, 1, 1, FALSE) ;
   WriteString('\nBefore TitleWindow') ;
   TitleWindow(First, 'Initial process') ;

   (* second process window *)
   Second := SetWindow(InitWindow(), Green, White, 36, 9, 41, 1, FALSE) ;
   TitleWindow(Second, 'Second process') ;

   (* debugging window at the bottom *)
   Debugging := SetWindow(InitWindow(), Red, White, 77, 10, 1, 12, FALSE) ;
   TitleWindow(Debugging, 'Debugging output') ;
   PutOnTop(Debugging) ;

   PushOutput(LocalWrite)
END SetupWindows ;


(*
   LocalWrite - 
*)

PROCEDURE LocalWrite (ch: CHAR) ;
BEGIN
   WriteChar(First, ch) ;
   WriteChar(Second, ch) ;
   WriteChar(Debugging, ch) ;
END LocalWrite ;


BEGIN
   SetupWindows ;
   LOOP
      WriteString('hello world')
   END
END testwin.

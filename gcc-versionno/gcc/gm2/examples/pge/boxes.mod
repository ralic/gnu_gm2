(* Copyright (C) 2012 Free Software Foundation, Inc. *)
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
Foundation, 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA. *)

MODULE boxes ;


IMPORT popWorld ;
IMPORT twoDsim ;

FROM deviceIf IMPORT Colour, red, blue, green, yellow, purple, defineColour ;
FROM Fractions IMPORT Fract, initFract, zero, one, two, cardinal, negate, div, pi ;
FROM Points IMPORT Point, initPoint ;

FROM macroObjects IMPORT Macro, circle, moveTo, up, down, left, right, rotate,
                         append, translate, rootMacro, dup, unRootMacro, initMacro, rectangle,
                         triangle, angledRect ;


CONST
   testCorner = FALSE ;
   testRight  = FALSE ;


(*
   placeBoundary - 
*)

PROCEDURE placeBoundary ;
VAR
   m: Macro ;
BEGIN
   m := initMacro() ;

   (* left edge *)
   m := moveTo(m, initPoint(zero(), zero())) ;
   m := rectangle(m, TRUE, zero(), dark, initFract(0, 1, 100), one()) ;

   (* right edge *)
   m := moveTo(m, initPoint(initFract(0, 99, 100), zero())) ;
   m := rectangle(m, TRUE, zero(), dark, initFract(0, 1, 100), one()) ;

   (* bot edge *)
   m := moveTo(m, initPoint(zero(), zero())) ;
   m := rectangle(m, TRUE, zero(), dark, one(), initFract(0, 1, 100)) ;

   (* top edge *)
   m := moveTo(m, initPoint(zero(), initFract(0, 99, 100))) ;
   m := rectangle(m, TRUE, zero(), dark, one(), initFract(0, 1, 100)) ;

   popWorld.populate(m, TRUE, TRUE)
END placeBoundary ;


(*
   dropBall - 
*)

PROCEDURE dropBall (c: Colour) ;
VAR
   m: Macro ;
BEGIN
   m := initMacro() ;

   (* drop the ball at the top of stairs with a leftwards velocity *)
   m := moveTo(m, initPoint(initFract(0, 17, 20), initFract(0, 37, 40))) ;

   m := circle(m, TRUE, zero(), c, size) ;
   m := rootMacro(m) ;
   popWorld.mass(cardinal(1)) ;
   popWorld.velocity(initPoint(zero(), zero())) ;
   popWorld.populate(m, FALSE, TRUE) ;
END dropBall ;


(*
   dropBox - 
*)

PROCEDURE dropBox (c: Colour) ;
VAR
   m: Macro ;
BEGIN
   m := initMacro() ;

   (* drop the ball at the top of stairs with a leftwards velocity *)
   m := moveTo(m, initPoint(initFract(0, 17, 20), initFract(0, 37, 40))) ;
   m := rectangle(m, TRUE, zero(), c, initFract(0, 1, 20), initFract(0, 1, 20)) ;

   popWorld.mass(cardinal(1)) ;
   popWorld.velocity(initPoint(zero(), zero())) ;
   popWorld.populate(m, FALSE, TRUE) ;
END dropBox ;


(*
   fireBox - 
*)

PROCEDURE fireBox (c: Colour) ;
VAR
   m: Macro ;
BEGIN
   m := initMacro() ;

   (* drop the ball at the top of stairs with a leftwards velocity *)
   m := moveTo(m, initPoint(initFract(0, 17, 20), initFract(0, 3, 40))) ;
   m := rectangle(m, TRUE, zero(), c, initFract(0, 1, 20), initFract(0, 1, 20)) ;

   popWorld.mass(cardinal(1)) ;
   popWorld.velocity(initPoint(zero(), cardinal(6))) ;
   popWorld.populate(m, FALSE, TRUE) ;
END fireBox ;


VAR
   size       : Fract ;
   light, dark: Colour ;
BEGIN
   popWorld.init(TRUE) ;
   light := defineColour(initFract(0, 166, 256),
                         initFract(0, 124, 256),
                         initFract(0, 54, 256)) ;
   dark := defineColour(initFract(0, 76, 256),
                        initFract(0, 47, 256),
                        zero()) ;

   size := initFract(0, 1, 21) ;
   placeBoundary ;
   fireBox(green()) ;
   twoDsim.gravity(-9.81) ;

   twoDsim.simulateFor(1.0)
END boxes.

(* Copyright (C) 2009, 2010
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
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA *)

IMPLEMENTATION MODULE ShortComplexMath ;

IMPORT cbuiltin ;


(* Returns the length of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_cabsf)) abs (z: SHORTCOMPLEX): SHORTREAL;
BEGIN
   RETURN cbuiltin.cabsf (z)
END abs ;


(* Returns the angle that z subtends to the positive real axis *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_cargf)) arg (z: SHORTCOMPLEX): SHORTREAL;
BEGIN
   RETURN cbuiltin.cargf (z)
END arg ;


(* Returns the complex conjugate of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_conjf)) conj (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.conjf (z)
END conj ;


(* Returns the value of the number base raised to the power exponent *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_cpowerf)) power (base: SHORTCOMPLEX; exponent: SHORTREAL): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.cpowf (base, exponent)
END power ;


(* Returns the principal square root of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_csqrtf)) sqrt (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.csqrtf (z)
END sqrt ;


(* Returns the complex exponential of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_cexpf)) exp (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.cexpf (z)
END exp ;


(* Returns the principal value of the natural logarithm of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_clnf)) ln (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.clogf (z)
END ln ;


(* Returns the sine of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_csinf)) sin (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.csinf (z)
END sin ;


(* Returns the cosine of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_ccosf)) cos (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.ccosf (z)
END cos ;


(* Returns the tangent of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_ctanf)) tan (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.ctanf (z)
END tan ;


(* Returns the arcsine of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_carcsinf)) arcsin (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.casinf (z)
END arcsin ;


(* Returns the arccosine of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_carccosf)) arccos (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.cacosf (z)
END arccos ;


(* Returns the arctangent of z *)

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_carctanf)) arctan (z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN cbuiltin.catanf (z)
END arctan ;


(* Returns the complex number with the specified polar coordinates *)

PROCEDURE polarToComplex (abs, arg: SHORTREAL): SHORTCOMPLEX;
BEGIN
   RETURN CMPLX (abs*cbuiltin.cosf(arg), abs*cbuiltin.sinf(arg))
END polarToComplex ;


(* Returns the scalar product of scalar with z *)

PROCEDURE scalarMult (scalar: SHORTREAL; z: SHORTCOMPLEX): SHORTCOMPLEX;
BEGIN
   RETURN CMPLX (RE(z)*scalar, IM(z)*scalar)
END scalarMult ;


(* Returns TRUE if the current coroutine is in the exceptional
   execution state because of the raising of an exception in a
   routine from this module; otherwise returns FALSE.
*)

PROCEDURE IsCMathException (): BOOLEAN;
BEGIN
   (* --fixme-- we should really attempt to catch sigfpe in these procedures *)
   RETURN( FALSE )
END IsCMathException ;


END ShortComplexMath.

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
IMPLEMENTATION MODULE M2System ;

(*
    Title      : M2System
    Author     : Gaius Mulley
    System     : UNIX (gm2)
    Date       : Mon Jul 10 20:24:31 2000
    Last edit  : Mon Jul 10 20:24:31 2000
    Description: gcc version of M2System. It defines the builtin types within the
                 SYSTEM.def module. Remember that these modules (SYSTEM.def, SYSTEM.mod)
                 really exist, but not all type definitions are expressed in this file.
                 We also need to tell the compiler the size of the data types.
*)

FROM NameKey IMPORT MakeKey, NulName ;

FROM SymbolTable IMPORT NulSym,
                        SetCurrentModule,
                        StartScope,
                        EndScope,
      	       	     	MakeConstLit,
                        MakeConstVar,
                        MakePointer,
                        MakeType,
                        MakeProcedure,
      	       	     	MakeSet,
      	       	     	MakeSubrange,
                        PutFunction,
                        PutType, PutPointer,
      	       	     	PutSet,
      	       	     	PutSubrange,
                        GetSym,
                        PopValue,
                        PopSize ;

FROM M2Batch IMPORT MakeDefinitionSource ;
FROM M2Base IMPORT Cardinal ;
FROM M2ALU IMPORT PushCard, PushIntegerTree ;
FROM M2Error IMPORT InternalError ;
FROM gccgm2 IMPORT GetMaxFrom, GetMinFrom, GetWordType, GetPointerType,
                   GetBitsPerWord, GetSizeOf, BuildSize ;

VAR
   MinWord   , MaxWord,
   MinAddress, MaxAddress,
   MinByte   , MaxByte,
   MinBitset , MaxBitset : CARDINAL ;


(*
   InitSystem - creates the system dependant types and procedures.
                Note that they are not exported here, but they are
                exported in the textual module: SYSTEM.def.
                We build our system types from those given in the gcc
                backend. Essentially we perform double book keeping.
*)

PROCEDURE InitSystem ;
VAR
   System     : CARDINAL ;
   BitsetRange: CARDINAL ;
BEGIN
   (* create SYSTEM module *)
   System := MakeDefinitionSource(MakeKey('SYSTEM')) ;
   StartScope(System) ;

   Word := MakeType(MakeKey('WORD')) ;
   PutType(Word, NulSym) ;                    (* Base Type       *)
   PushIntegerTree(BuildSize(GetWordType(), FALSE)) ;
   PopSize(Word) ;

   (* ADDRESS = POINTER TO WORD *)

   Address := MakePointer(MakeKey('ADDRESS')) ;
   PutPointer(Address, Word) ;                (* Base Type       *)
   PushIntegerTree(GetSizeOf(GetPointerType())) ;
   PopSize(Address) ;

   Byte := MakeType(MakeKey('BYTE')) ;
   PutType(Byte, NulSym) ;                    (* Base Type       *)
   PushIntegerTree(GetSizeOf(GetPointerType())) ;
   PopSize(Byte) ;

   Bitset := MakeSet(MakeKey('BITSET')) ;     (* Base Type       *)

   (* MinBitset *)
   MinBitset := MakeConstLit(MakeKey('0')) ;

   (* MaxBitset *)
   MaxBitset := MakeConstVar(MakeKey('MaxBitset')) ;
   PushCard(GetBitsPerWord()-1) ;
   PopValue(MaxBitset) ;

   BitsetRange := MakeSubrange(NulName) ;
   PutSubrange( BitsetRange, MinBitset, MaxBitset, Word) ;
   PutSet(Bitset, BitsetRange) ;

   PushIntegerTree(GetSizeOf(GetWordType())) ;
   PopSize(Bitset) ;

   (* And now the predefined pseudo functions *)

   Size := MakeProcedure(MakeKey('SIZE')) ;   (* Function        *)
   PutFunction(Size, Cardinal) ;              (* Return Type     *)
                                              (* Cardinal        *)

   Adr := MakeProcedure(MakeKey('ADR')) ;     (* Function        *)
   PutFunction(Adr, Address) ;                (* Return Type     *)
                                              (* Address         *)

   TSize := MakeProcedure(MakeKey('TSIZE')) ; (* Function        *)
   PutFunction(TSize, Cardinal) ;             (* Return Type     *)
                                              (* Cardinal        *)

   (* MaxWord *)
   MaxWord := MakeConstVar(MakeKey('MaxWord')) ;
   PushIntegerTree(GetMaxFrom(GetWordType())) ;
   PopValue(MaxWord) ;

   (* MinWord *)
   MinWord := MakeConstVar(MakeKey('MinWord')) ;
   PushIntegerTree(GetMinFrom(GetWordType())) ;
   PopValue(MinWord) ;

   (* MaxAddress *)
   MaxAddress := MakeConstVar(MakeKey('MaxAddress')) ;
   PushIntegerTree(GetMaxFrom(GetPointerType())) ;
   PopValue(MaxAddress) ;

   (* MinAddress *)
   MinAddress := MakeConstVar(MakeKey('MinAddress')) ;
   PushIntegerTree(GetMinFrom(GetPointerType())) ;
   PopValue(MinAddress) ;

   (* MaxByte *)
   MaxByte := MakeConstVar(MakeKey('MaxByte')) ;
   PushIntegerTree(GetMaxFrom(GetPointerType())) ;
   PopValue(MaxAddress) ;

   (* MinByte *)
   MinByte := MakeConstVar(MakeKey('MinByte')) ;
   PushIntegerTree(GetMinFrom(GetPointerType())) ;
   PopValue(MinByte) ;

   EndScope
END InitSystem ;


(*
   GetSystemTypeMinMax - returns the minimum and maximum values for a given system type.
*)

PROCEDURE GetSystemTypeMinMax (type: CARDINAL; VAR min, max: CARDINAL) ;
BEGIN
   IF type=Word
   THEN
      min := MinWord ;
      max := MaxWord
   ELSIF type=Byte
   THEN
      min := MinByte ;
      max := MaxByte
   ELSIF type=Address
   THEN
      min := MinAddress ;
      max := MaxAddress
   ELSIF type=Bitset
   THEN
      min := MinBitset ;
      max := MaxBitset
   ELSE
      InternalError('system does not know about this type', __FILE__, __LINE__)
   END
END GetSystemTypeMinMax ;


(*
   IsPseudoSystemFunction - returns true if Sym is a SYSTEM pseudo function.
*)

PROCEDURE IsPseudoSystemFunction (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( (Sym=Adr) OR (Sym=TSize) OR (Sym=Size) )
END IsPseudoSystemFunction ;


(*
   IsSystemType - returns TRUE if Sym is a SYSTEM (inbuilt) type.
                  It does not search your SYSTEM implementation module.
*)

PROCEDURE IsSystemType (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN(
          (Sym=Word)    OR (Sym=Byte) OR
          (Sym=Address) OR (Sym=Bitset)
         )
END IsSystemType ;


END M2System.
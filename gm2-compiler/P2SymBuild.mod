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
IMPLEMENTATION MODULE P2SymBuild ;


FROM NameKey IMPORT Name, MakeKey, makekey, KeyToCharStar, NulName ;
FROM StrLib IMPORT StrEqual ;
FROM M2Debug IMPORT Assert, WriteDebug ;
FROM M2LexBuf IMPORT GetTokenNo ;
FROM M2Base IMPORT Char, MixTypes ;
FROM M2Error IMPORT InternalError, WriteFormat1, WriteFormat2, WriteFormat0, ErrorStringAt2 ;
FROM Strings IMPORT String, InitString, InitStringCharStar, Mark, Slice, ConCat, KillString, string ;
FROM FormatStrings IMPORT Sprintf0, Sprintf1, Sprintf2, Sprintf4 ;

FROM M2Reserved IMPORT ImportTok, ExportTok, QualifiedTok, UnQualifiedTok,
                       NulTok, VarTok, ArrayTok ;

FROM FifoQueue IMPORT GetFromFifoQueue, PutIntoFifoQueue ;

FROM SymbolTable IMPORT NulSym,
                        ModeOfAddr,
                        StartScope, EndScope, PseudoScope,
                        SetCurrentModule, SetFileModule,
                        GetCurrentModule,
                        MakeConstLit,
                        MakeConstLitString,
                        MakeEnumeration, MakeSubrange,
                        MakeVar, MakeType, PutType,
                        PutMode,
                        PutFieldEnumeration, PutSubrange, PutVar, PutConst,
                        PutConstSet,
                        IsDefImp, IsType,
                        IsSubrange, IsEnumeration, IsConstString,
                        GetSym, RequestSym, IsUnknown, RenameSym,
                        GetLocalSym, Father, IsRecord,
                        GetFromOuterModule,
                        GetExported,
                        PutImported,
                        PutExported, PutExportQualified, PutExportUnQualified,
                        PutExportUnImplemented,
                        CheckForEnumerationInCurrentModule,
                        CheckForExportedImplementation,
                        MakeProcedure,
                        PutFunction, PutParam, PutVarParam,
                        GetNthParam,
                        IsProcedure,
                        NoOfElements,
                        MakePointer, PutPointer,
      	          	MakeSet, PutSet,
                        MakeRecord, PutFieldRecord,
                        MakeVarient, MakeFieldVarient,
                        MakeArray, PutFieldArray,
                        MakeSubscript, PutSubscript,
                        PutConstString, GetString,
                        PutArray, IsArray,
                        GetType,
                        IsProcType, MakeProcType,
                        PutProcTypeVarParam, PutProcTypeParam,
                        MakeConstVar,
                        MakeUnbounded, PutUnbounded,
                        NoOfParam,
                        GetParam,
                        AreParametersDefinedInDefinition,
                        AreParametersDefinedInImplementation,
                        AreProcedureParametersDefined,
                        ParametersDefinedInDefinition,
                        ParametersDefinedInImplementation,
                        ProcedureParametersDefined,
                        CheckForUnImplementedExports,
                        CheckForUndeclaredExports,
                        IsUnboundedParam,
                        IsVarParam,
                        GetSymName,
                        GetDeclared ;

FROM M2Batch IMPORT MakeDefinitionSource,
                    MakeImplementationSource,
                    MakeProgramSource ;

FROM M2Quads IMPORT PushT, PopT,
                    PushTF, PopTF,
                    OperandT, PopN, DisplayStack ;

FROM M2Comp IMPORT CompilingDefinitionModule,
                   CompilingImplementationModule,
                   CompilingProgramModule ;



(* %%%FORWARD%%%
PROCEDURE BuildFormalParameterSection ; FORWARD ;
PROCEDURE BuildNulParam ; FORWARD ;
PROCEDURE CheckFormalParameterSection ; FORWARD ;
PROCEDURE FailParameter (CurrentState : ARRAY OF CHAR;
                         PreviousState: ARRAY OF CHAR;
                         Given        : Name ;
                         ParameterNo  : CARDINAL;
                         ProcedureSym : CARDINAL) ; FORWARD ;
   %%%FORWARD%%% *)

VAR
   IsBuildingConstDeclaration: BOOLEAN ;
   AnonymousName             : CARDINAL ;


(*
   CheckAnonymous - 
*)

PROCEDURE CheckAnonymous (name: Name) : Name ;
BEGIN
   IF name=NulName
   THEN
      INC(AnonymousName) ;
      name := makekey(string(Mark(Sprintf1(Mark(InitString('$$%d')), AnonymousName))))
   END ;
   RETURN( name )
END CheckAnonymous ;


(*
   StartBuildDefinitionModule - Creates a definition module and starts
                                a new scope.

                                he Stack is expected:

                                Entry                 Exit

                         Ptr ->                                     <- Ptr
                                +------------+        +-----------+
                                | NameStart  |        | NameStart |
                                |------------|        |-----------|

*)

PROCEDURE P2StartBuildDefModule ;
VAR
   name     : Name ;
   ModuleSym: CARDINAL ;
BEGIN
   PopT(name) ;
   ModuleSym := MakeDefinitionSource(name) ;
   SetCurrentModule(ModuleSym) ;
   SetFileModule(ModuleSym) ;
   StartScope(ModuleSym) ;
   Assert(IsDefImp(ModuleSym)) ;
   Assert(CompilingDefinitionModule()) ;
   PushT(name)
END P2StartBuildDefModule ;


(*
   EndBuildDefinitionModule - Destroys the definition module scope and
                              checks for correct name.

                              The Stack is expected:

                              Entry                 Exit

                       Ptr ->
                              +------------+        +-----------+
                              | NameEnd    |        |           |
                              |------------|        |-----------|
                              | NameStart  |        |           | <- Ptr
                              |------------|        |-----------|
*)

PROCEDURE P2EndBuildDefModule ;
VAR
   NameStart,
   NameEnd  : Name ;
BEGIN                                 
   Assert(CompilingDefinitionModule()) ;
   CheckForUndeclaredExports(GetCurrentModule()) ;
   EndScope ;
   PopT(NameStart) ;
   PopT(NameEnd) ;
   IF NameStart#NameEnd
   THEN
      WriteFormat2('inconsistant definition module name, module began as (%a) and ended with (%a)', NameStart, NameEnd)
   END
END P2EndBuildDefModule ;


(*
   StartBuildImplementationModule - Creates an implementation module and starts
                                    a new scope.

                                    The Stack is expected:

                                    Entry                 Exit

                             Ptr ->                                     <- Ptr
                                    +------------+        +-----------+
                                    | NameStart  |        | NameStart |
                                    |------------|        |-----------|

*)

PROCEDURE P2StartBuildImplementationModule ;
VAR
   name     : Name ;
   ModuleSym: CARDINAL ;
BEGIN
   PopT(name) ;
   ModuleSym := MakeImplementationSource(name) ;
   SetCurrentModule(ModuleSym) ;
   SetFileModule(ModuleSym) ;
   StartScope(ModuleSym) ;
   Assert(IsDefImp(ModuleSym)) ;
   Assert(CompilingImplementationModule()) ;
   PushT(name)
END P2StartBuildImplementationModule ;


(*
   EndBuildImplementationModule - Destroys the implementation module scope and
                                  checks for correct name.

                                  The Stack is expected:

                                  Entry                 Exit

                           Ptr ->
                                  +------------+        +-----------+
                                  | NameEnd    |        |           |
                                  |------------|        |-----------|
                                  | NameStart  |        |           | <- Ptr
                                  |------------|        |-----------|
*)

PROCEDURE P2EndBuildImplementationModule ;
VAR
   NameStart,
   NameEnd  : Name ;
BEGIN
   Assert(CompilingImplementationModule()) ;
   CheckForUnImplementedExports ;
   EndScope ;
   PopT(NameStart) ;
   PopT(NameEnd) ;
   IF NameStart#NameEnd
   THEN
      WriteFormat1('inconsistant implementation module name %a', NameStart)
   END
END P2EndBuildImplementationModule ;


(*
   StartBuildProgramModule - Creates a program module and starts
                             a new scope.

                             The Stack is expected:

                             Entry                 Exit

                      Ptr ->                                     <- Ptr
                             +------------+        +-----------+
                             | NameStart  |        | NameStart |
                             |------------|        |-----------|

*)

PROCEDURE P2StartBuildProgramModule ;
VAR
   name     : Name ;
   ModuleSym: CARDINAL ;
BEGIN
   PopT(name) ;
   ModuleSym := MakeProgramSource(name) ;
   SetCurrentModule(ModuleSym) ;
   SetFileModule(ModuleSym) ;
   StartScope(ModuleSym) ;
   Assert(CompilingProgramModule()) ;
   Assert(NOT IsDefImp(ModuleSym)) ;
   PushT(name) ;
END P2StartBuildProgramModule ;


(*
   EndBuildProgramModule - Destroys the program module scope and
                           checks for correct name.

                           The Stack is expected:

                           Entry                 Exit

                    Ptr ->
                           +------------+        +-----------+
                           | NameEnd    |        |           |
                           |------------|        |-----------|
                           | NameStart  |        |           | <- Ptr
                           |------------|        |-----------|
*)

PROCEDURE P2EndBuildProgramModule ;
VAR
   NameStart,
   NameEnd  : Name ;
BEGIN
   Assert(CompilingProgramModule()) ;
   CheckForUndeclaredExports(GetCurrentModule()) ;  (* Not really allowed exports here though! *)
   EndScope ;
   PopT(NameStart) ;
   PopT(NameEnd) ;
   IF NameStart#NameEnd
   THEN
      WriteFormat2('inconsistant program module name %a does not match %a', NameStart, NameEnd)
   END
END P2EndBuildProgramModule ;


(*
   StartBuildInnerModule - Creates an Inner module and starts
                           a new scope.

                           The Stack is expected:

                           Entry                 Exit

                    Ptr ->                                     <- Ptr
                           +------------+        +-----------+
                           | NameStart  |        | NameStart |
                           |------------|        |-----------|

*)

PROCEDURE StartBuildInnerModule ;
VAR
   name     : Name ;
   ModuleSym: CARDINAL ;
BEGIN
   PopT(name) ;
   ModuleSym := RequestSym(name) ;
   StartScope(ModuleSym) ;
   Assert(NOT IsDefImp(ModuleSym)) ;
   PushT(name)
END StartBuildInnerModule ;


(*
   EndBuildInnerModule - Destroys the Inner module scope and
                         checks for correct name.

                         The Stack is expected:

                         Entry                 Exit

                  Ptr ->
                         +------------+        +-----------+
                         | NameEnd    |        |           |
                         |------------|        |-----------|
                         | NameStart  |        |           | <- Ptr
                         |------------|        |-----------|
*)

PROCEDURE EndBuildInnerModule ;
VAR
   NameStart,
   NameEnd  : Name ;
BEGIN
   CheckForUndeclaredExports(GetCurrentModule()) ;
   EndScope ;
   PopT(NameStart) ;
   PopT(NameEnd) ;
   IF NameStart#NameEnd
   THEN
      WriteFormat2('inconsistant inner module name %a does not match %a',
                   NameStart, NameEnd)
   END
END EndBuildInnerModule ;


(*
   BuildImportOuterModule - Builds imported identifiers into an outer module
                            from a definition module.

                            The Stack is expected:

                            Entry           OR    Entry

                     Ptr ->                Ptr ->
                            +------------+        +-----------+
                            | #          |        | #         |
                            |------------|        |-----------|
                            | Id1        |        | Id1       |
                            |------------|        |-----------|
                            .            .        .           .
                            .            .        .           .
                            .            .        .           .
                            |------------|        |-----------|
                            | Id#        |        | Id#       |
                            |------------|        |-----------|
                            | ImportTok  |        | Ident     |
                            |------------|        |-----------|

                            IMPORT Id1, .. Id# ;  FROM Ident IMPORT Id1 .. Id# ;


                            Exit

                            All above stack discarded
*)

PROCEDURE BuildImportOuterModule ;
VAR
   Sym, ModSym,
   i, n       : CARDINAL ;
BEGIN
   PopT(n) ;       (* n   = # of the Ident List *)
   IF OperandT(n+1)#ImportTok
   THEN
      (* Ident List contains list of objects *)
      ModSym := MakeDefinitionSource(OperandT(n+1)) ;
      i := 1 ;
      WHILE i<=n DO
         Sym := GetExported(ModSym, OperandT(i)) ;
         CheckForEnumerationInCurrentModule(Sym) ;
         INC(i)
      END
   END ;
   PopN(n+1)   (* clear stack *)
END BuildImportOuterModule ;


(*
   BuildExportOuterModule - Builds exported identifiers from an outer module
                            to the outside world of library modules.

                            The Stack is expected:

                            Entry           OR    Entry

                     Ptr ->                Ptr ->
                            +------------+        +--------------+
                            | #          |        | #            |
                            |------------|        |--------------|
                            | Id1        |        | Id1          |
                            |------------|        |--------------|
                            .            .        .              .
                            .            .        .              .
                            .            .        .              .
                            |------------|        |--------------|
                            | Id#        |        | Id#          |
                            |------------|        |--------------|
                            | ExportTok  |        | QualifiedTok |
                            |------------|        |--------------|

                            EXPORT Id1, .. Id# ;  EXPORT QUALIFIED Id1 .. Id# ;

                            Error Condition


                            Exit

                            All above stack discarded
*)

PROCEDURE BuildExportOuterModule ;
VAR
   n: CARDINAL ;
BEGIN
   PopT(n) ;       (* n   = # of the Ident List *)
   PopN(n+1)
END BuildExportOuterModule ;


(*
   BuildImportInnerModule - Builds imported identifiers into an inner module
                            from the last level of module.

                            The Stack is expected:

                            Entry           OR    Entry

                     Ptr ->                Ptr ->
                            +------------+        +-----------+
                            | #          |        | #         |
                            |------------|        |-----------|
                            | Id1        |        | Id1       |
                            |------------|        |-----------|
                            .            .        .           .
                            .            .        .           .
                            .            .        .           .
                            |------------|        |-----------|
                            | Id#        |        | Id#       |
                            |------------|        |-----------|
                            | ImportTok  |        | Ident     |
                            |------------|        |-----------|

                            IMPORT Id1, .. Id# ;  FROM Ident IMPORT Id1 .. Id# ;


                                                  Error Condition
                            Exit

                            All above stack discarded
*)

PROCEDURE BuildImportInnerModule ;
VAR
   Sym, ModSym,
   n, i       : CARDINAL ;
BEGIN
   PopT(n) ;       (* i   = # of the Ident List *)
   IF OperandT(n+1)=ImportTok
   THEN
      (* Ident List contains list of objects *)
      i := 1 ;
      WHILE i<=n DO
         Sym := GetFromOuterModule(OperandT(i)) ;
         CheckForEnumerationInCurrentModule(Sym) ;
         INC(i)
      END
   ELSE
      WriteFormat0('not allowed to import using FROM in an inner module')
   END ;
   PopN(n+1)   (* Clear Stack *)
END BuildImportInnerModule ;


(*
   BuildExportInnerModule - Builds exported identifiers from an inner module
                            to the next layer module.

                            The Stack is expected:

                            Entry           OR    Entry

                     Ptr ->                Ptr ->
                            +------------+        +--------------+
                            | #          |        | #            |
                            |------------|        |--------------|
                            | Id1        |        | Id1          |
                            |------------|        |--------------|
                            .            .        .              .
                            .            .        .              .
                            .            .        .              .
                            |------------|        |--------------|
                            | Id#        |        | Id#          |
                            |------------|        |--------------|
                            | ExportTok  |        | QualifiedTok |
                            |------------|        |--------------|

                            EXPORT Id1, .. Id# ;  EXPORT QUALIFIED Id1 .. Id# ;


                            Exit

                            All above stack discarded
*)

PROCEDURE BuildExportInnerModule ;
VAR
   n: CARDINAL ;
BEGIN
   PopT(n) ;
   PopN(n+1)   (* clear stack               *)
END BuildExportInnerModule ;


(*
   BuildNumber - Converts a number into a symbol.


                 Stack

                 Entry                 Exit

          Ptr ->                                      <- Ptr
                 +------------+        +------------+
                 | Name       |        | Sym        |
                 |------------+        |------------|
*)

PROCEDURE BuildNumber ;
VAR
   name: Name ;
   Sym : CARDINAL ;
BEGIN
   PopT(name) ;
   Sym := MakeConstLit(name) ;
   PushTF(Sym, GetType(Sym))
END BuildNumber ;


(*
   BuildString - Converts a string into a symbol.


                 Stack

                 Entry                 Exit

          Ptr ->                                      <- Ptr
                 +------------+        +------------+
                 | Name       |        | Sym        |
                 |------------+        |------------|
*)

PROCEDURE BuildString ;
VAR
   name: Name ;
   Sym : CARDINAL ;
BEGIN
   PopT(name) ;
   (* slice off the leading and trailing quotes *)
   Sym := MakeConstLitString(makekey(string(Mark(Slice(Mark(InitStringCharStar(KeyToCharStar(name))), 1, -1))))) ;
   PushTF(Sym, NulSym)
END BuildString ;


(*
   BuildConst - builds a constant.
                Stack

                Entry                 Exit

         Ptr ->
                +------------+
                | Name       |
                |------------+                       <- Ptr
*)

PROCEDURE BuildConst ;
VAR
   name: Name ;
   Sym : CARDINAL ;
BEGIN
   PopT(name) ;
   Sym := MakeConstVar(name) ;
   PushT(Sym)
END BuildConst ;


(*
   BuildConstTypeFromAssignment - assigns a string to the constant name.
                                  But it only does this if we in a CONST statement.
                                  In both cases the string on top of the stack is removed.

                                  Stack

                                  Entry           Exit

                           Ptr ->
                                  +------------+
                                  | Expr       |
                                  |------------|
                                  | Sym        |            <- Ptr
                                  |------------|
*)

PROCEDURE BuildConstTypeFromAssignment ;
VAR
   Expr,
   Sym : CARDINAL ;
BEGIN
   (* we might get called via a type declaration, consider
      TYPE  CharSet = SET OF ['0'..'9'] ;
   *)
   IF IsBuildingConstDeclaration
   THEN
      PopT(Expr) ;
      PopT(Sym) ;
      IF IsConstString(Expr)
      THEN
         PutConstString(Sym, GetString(Expr))
      END ;
      PushT(Sym)
   ELSE
      PopT(Expr)    (* remove the string *)
   END
END BuildConstTypeFromAssignment ;


(*
   BuildConstSetType - assigns the const var symbol on top of the stack
                       as being a set constant. The stack is unchanged.

                                  Entry           Exit

                       Ptr ->                                    <- Ptr
                              +------------+      +------------+
                              | Sym        |      | Sym        |
                              |------------|      |------------|
*)

PROCEDURE BuildConstSetType ;
VAR
   Expr,
   Sym : CARDINAL ;
BEGIN
   PopT(Expr) ;
   PutConstSet(Expr) ;
   PushT(Expr)
END BuildConstSetType ;


(*
   BuildEnumeration - Builds an Enumeration type Type.


                      Stack

                      Entry                 Exit

               Ptr ->
                      +------------+
                      | #          |
                      |------------|
                      | en 1       |
                      |------------|
                      | en 2       |
                      |------------|
                      .            .
                      .            .
                      .            .                       <- Ptr
                      |------------|        +------------+
                      | en #       |        | Type       |
                      |------------|        |------------|
                      | Name       |        | Name       |
                      |------------|        |------------|
*)

PROCEDURE BuildEnumeration ;
VAR
   name: Name ;
   n, i,
   Type: CARDINAL ;
BEGIN
   PopT(n) ;       (* n := # *)
   name := OperandT(n+1) ;
   GetFromFifoQueue(Type) ;
   CheckForExportedImplementation(Type) ;   (* May be an exported hidden type *)
   PopN(n) ;
   PushT(Type)
END BuildEnumeration ;


(*
   BuildSubrange - Builds a Subrange type Symbol.


                      Stack

                      Entry                 Exit


                                                           <- Ptr
                                            +------------+
               Ptr ->                       | Type       |
                      +------------+        |------------|
                      | Name       |        | Name       |
                      |------------|        |------------| 
*)

PROCEDURE BuildSubrange ;
VAR
   name: Name ;
   Type: CARDINAL ;
BEGIN
   PopT(name) ;
   Type := MakeSubrange(name) ;
   PutIntoFifoQueue(Type) ;   (* Store Subrange away so that we can fill in *)
                              (* its bounds during pass 3.                  *)
   CheckForExportedImplementation(Type) ;   (* May be an exported hidden type *)
   PushT(name) ;
   PushT(Type)
END BuildSubrange ;


(*
   BuildVariable - Builds variables listed in an IdentList with a Type.

                   Stack

                   Entry                 Exit

            Ptr ->
                   +------------+        +------------+
                   | Type | Name|        |            |
                   |------------|        |------------|
                   | #          |        |            |
                   |------------|        |------------|
                   | Ident 1    |        |            |
                   |------------|        |------------|
                   | Ident 2    |        |            |
                   |------------|        |------------|
                   .            .        .            .
                   .            .        .            .
                   .            .        .            .
                   |------------|        |------------|
                   | Ident #    |        |            | <- Ptr
                   |------------|        |------------|

                                           Empty
*)

PROCEDURE BuildVariable ;
VAR
   name: Name ;
   Type,
   Var,
   i, n: CARDINAL ;
BEGIN
   PopTF(Type, name) ;
   PopT(n) ;
   i := 1 ;
   WHILE i<=n DO
      Var := MakeVar(OperandT(n+1-i)) ;
      PutVar(Var, Type) ;
      INC(i)
   END ;
   PopN(n)
END BuildVariable ;


(*
   BuildType - Builds a Type.


               Stack

               Entry                 Exit

        Ptr ->
               +------------+
               | Type       |                          <- Ptr
               |------------|        +---------------+
               | Name       |        | Type  | Name  |
               |------------|        |---------------|

                                     Empty
*)

PROCEDURE BuildType ;
VAR
   Sym,
   Type: CARDINAL ;
   name: Name ;
BEGIN
   (*
      Two cases

      - the type name the same as Name, or the name is nul. - do nothing.
      - when type with a name that is different to Name. In which case
        we create a new type.
   *)
   PopT(Type) ;
   PopT(name) ;
   IF (name=NulName) OR (GetSymName(Type)=name)
   THEN
      (*
         Typically the declaration that causes this case is:

         VAR
            a: RECORD
                  etc
               END ;
             ^
             |
             +---- type has no name.
      *)
      (* WriteString('Blank name type') ; WriteLn ; *)
      PushTF(Type, name)
   ELSE
      (* example   TYPE a = CARDINAL *)
      Sym := MakeType(name) ;
      PutType(Sym, Type) ;
      CheckForExportedImplementation(Sym) ;   (* May be an exported hidden type *)
      PushTF(Sym, name)
   END
END BuildType ;


(*
   StartBuildProcedure - Builds a Procedure.

                         The Stack:

                         Entry                 Exit

                                                              <- Ptr
                                               +------------+
                  Ptr ->                       | ProcSym    |
                         +------------+        |------------|
                         | Name       |        | Name       |
                         |------------|        |------------|
*)

PROCEDURE StartBuildProcedure ;
VAR 
   name   : Name ;
   ProcSym: CARDINAL ;
BEGIN
   PopT(name) ;
   PushT(name) ;  (* name saved for the EndBuildProcedure name check *)
   ProcSym := RequestSym(name) ;
   IF IsUnknown(ProcSym)
   THEN
      (*
         May have been compiled in DEF or IMP module, remember that IMP maybe
         compiled before corresponding DEF module.
         - no defs should always be compilied before implementation modules.
      *)
      ProcSym := MakeProcedure(name)
   ELSE
      IF NOT IsProcedure(ProcSym)
      THEN
         ErrorStringAt2(Sprintf1(Mark(InitString('procedure name (%a) has been declared as another object elsewhere')),
                                 name), GetTokenNo(), GetDeclared(ProcSym))
      END
   END ;
   IF CompilingDefinitionModule()
   THEN
      PutExportUnImplemented(ProcSym)    (* Defined but not yet implemented *)
   ELSE
      CheckForExportedImplementation(ProcSym)   (* May be exported procedure *)
   END ;
   PushT(ProcSym) ;
   StartScope(ProcSym)
END StartBuildProcedure ;


(*
   EndBuildProcedure - Ends building a Procedure.
                       It checks the start procedure name matches the end
                       procedure name.

                       The Stack:

                       (Procedure Not Defined in definition module)

                       Entry                 Exit

                Ptr ->
                       +------------+
                       | NameEnd    |
                       |------------|
                       | ProcSym    |
                       |------------|
                       | NameStart  |
                       |------------|
                                             Empty
*)

PROCEDURE EndBuildProcedure ;
VAR
   NameEnd,
   NameStart: Name ;
   ProcSym  : CARDINAL ;
BEGIN
   PopT(NameEnd) ;
   PopT(ProcSym) ;
   Assert(IsProcedure(ProcSym)) ;
   PopT(NameStart) ;
   IF NameEnd#NameStart
   THEN
      WriteFormat2('end procedure name does not match beginning %a name %a', NameStart, NameEnd)
   END ;
   EndScope
END EndBuildProcedure ;


(*
   BuildProcedureHeading - Builds a procedure heading for the definition
                           module procedures.

                           Operation only performed if compiling a
                           definition module.

                           The Stack:

                           Entry                       Exit

                    Ptr ->
                           +------------+
                           | ProcSym    |
                           |------------|
                           | NameStart  |
                           |------------|
                                                       Empty

*)

PROCEDURE BuildProcedureHeading ;
VAR
   ProcSym  : CARDINAL ;
   NameStart: Name ;
BEGIN
   IF CompilingDefinitionModule()
   THEN
      PopT(ProcSym) ;
      Assert(IsProcedure(ProcSym)) ;
      PopT(NameStart) ;
      EndScope
   END
END BuildProcedureHeading ;


(*
   BuildFPSection - Builds a Formal Parameter in a procedure.

                    The Stack:

                    Entry                 Exit

             Ptr ->
                    +------------+
                    | ParamTotal |
                    |------------|
                    | TypeSym    |
                    |------------|
                    | Array/Nul  |
                    |------------|
                    | NoOfIds    |
                    |------------|
                    | Id 1       |
                    |------------|
                    .            .
                    .            .
                    .            .
                    |------------|
                    | Id n       |                       <- Ptr
                    |------------|        +------------+
                    | Var / Nul  |        | ParamTotal |
                    |------------|        |------------|
                    | ProcSym    |        | ProcSym    |
                    |------------|        |------------|
*)

PROCEDURE BuildFPSection ;
VAR
   ProcSym,
   ParamTotal: CARDINAL ;
BEGIN
   PopT(ParamTotal) ;
   ProcSym := CARDINAL(OperandT(3+CARDINAL(OperandT(3))+2)) ;
   PushT(ParamTotal) ;
   Assert(IsProcedure(ProcSym)) ;
   IF CompilingDefinitionModule()
   THEN
      IF AreParametersDefinedInDefinition(ProcSym) AND (ParamTotal=0)
      THEN
         WriteFormat1('cannot declare procedure %a twice in definition module', GetSymName(ProcSym))
      ELSIF AreParametersDefinedInImplementation(ProcSym)
      THEN
         CheckFormalParameterSection
      ELSE
         BuildFormalParameterSection ;
         IF ParamTotal=0
         THEN
            ParametersDefinedInDefinition(ProcSym) ;
            ProcedureParametersDefined(ProcSym)
         END
      END
   ELSIF CompilingImplementationModule()
   THEN
      IF AreParametersDefinedInImplementation(ProcSym) AND (ParamTotal=0)
      THEN
         WriteFormat1('cannot declare procedure %a twice in implementation module', GetSymName(ProcSym))
      ELSIF AreParametersDefinedInDefinition(ProcSym)
      THEN
         CheckFormalParameterSection
      ELSE
         BuildFormalParameterSection ;
         IF ParamTotal=0
         THEN
            ParametersDefinedInImplementation(ProcSym) ;
            ProcedureParametersDefined(ProcSym)
         END
      END
   ELSIF CompilingProgramModule()
   THEN
      IF AreProcedureParametersDefined(ProcSym) AND (ParamTotal=0)
      THEN
         WriteFormat1('procedure %a parameters already declared in program module', GetSymName(ProcSym))
      ELSE
         BuildFormalParameterSection ;
         IF ParamTotal=0
         THEN
            ProcedureParametersDefined(ProcSym)
         END
      END
   ELSE
      InternalError('should never reach this point', __FILE__, __LINE__)
   END ;
   Assert(IsProcedure(OperandT(2)))
END BuildFPSection ;


(*
   BuildFormalParameterSection - Builds a Formal Parameter in a procedure.

                                 The Stack:

                                 Entry                 Exit

                          Ptr ->
                                 +------------+
                                 | ParamTotal |
                                 |------------|
                                 | TypeSym    |
                                 |------------|
                                 | Array/Nul  |
                                 |------------|
                                 | NoOfIds    |
                                 |------------|
                                 | Id 1       |
                                 |------------|
                                 .            .
                                 .            .
                                 .            .
                                 |------------|
                                 | Id n       |                       <- Ptr
                                 |------------|        +------------+
                                 | Var / Nul  |        | ParamTotal |
                                 |------------|        |------------|
                                 | ProcSym    |        | ProcSym    |
                                 |------------|        |------------|
*)

PROCEDURE BuildFormalParameterSection ;
VAR
   Var,
   Array     : Name ;
   ParamTotal,
   TypeSym,
   UnBoundedSym,
   NoOfIds,
   ProcSym,
   i           : CARDINAL ;
BEGIN
   PopT(ParamTotal) ;
   PopT(TypeSym) ;
   PopT(Array) ;
   Assert( (Array=ArrayTok) OR (Array=NulTok) ) ;
   PopT(NoOfIds) ;
   ProcSym := OperandT(NoOfIds+2) ;
   Assert(IsProcedure(ProcSym)) ;
   Var := OperandT(NoOfIds+1) ;
   Assert( (Var=VarTok) OR (Var=NulTok) ) ;
   IF Array=ArrayTok
   THEN
      UnBoundedSym := MakeUnbounded() ;
      PutUnbounded(UnBoundedSym, TypeSym) ;
      TypeSym := UnBoundedSym
   END ;
   i := 1 ;
(*
   WriteString('Procedure ') ; WriteKey(GetSymName(ProcSym)) ;
   WriteString(' adding No. of identifiers:') ; WriteCard(NoOfIds, 4) ; WriteLn ;
*)
   WHILE i<=NoOfIds DO
      IF Var=VarTok
      THEN
         (* VAR pamarater *)
         IF NOT PutVarParam(ProcSym, ParamTotal+i, OperandT(NoOfIds+1-i), TypeSym)
         THEN
            InternalError('problems adding a VarParameter - wrong param #?', __FILE__, __LINE__)
         END
      ELSE
         (* Non VAR parameter *)
         IF NOT PutParam(ProcSym, ParamTotal+i, OperandT(NoOfIds+1-i), TypeSym)
         THEN
            InternalError('problems adding a Parameter - wrong param #?', __FILE__, __LINE__)
         END
      END ;
(*
      WriteString(' parameter') ; WriteCard(ParamTotal+i, 4) ; WriteLn ;
      WriteKey(Operand(Ptr+i+1)) ; WriteString(' is a parameter with type ') ;
      WriteKey(GetSymName(TypeSym)) ; WriteLn ;
*)
      INC(i)
   END ;
   PopN(NoOfIds+1) ;
   PushT(ParamTotal+NoOfIds) ;
   Assert(IsProcedure(OperandT(2)))
END BuildFormalParameterSection ;


(*
   CheckFormalParameterSection - Checks a Formal Parameter in a procedure.

                                 The Stack:

                                 Entry                 Exit

                          Ptr ->
                                 +------------+
                                 | ParamTotal |
                                 |------------|
                                 | TypeSym    |
                                 |------------|
                                 | Array/Nul  |
                                 |------------|
                                 | NoOfIds    |
                                 |------------|
                                 | Id 1       |
                                 |------------|
                                 .            .
                                 .            .
                                 .            .
                                 |------------|
                                 | Id n       |                       <- Ptr
                                 |------------|        +------------+
                                 | Var / Nul  |        | ParamTotal |
                                 |------------|        |------------|
                                 | ProcSym    |        | ProcSym    |
                                 |------------|        |------------|
*)

PROCEDURE CheckFormalParameterSection ;
VAR
   Array, Var: Name ;
   Unbounded : BOOLEAN ;
   ParamI,
   ParamIType,
   ParamTotal,
   TypeSym,
   NoOfIds,
   ProcSym,
   pi, i     : CARDINAL ;
BEGIN
   PopT(ParamTotal) ;
   PopT(TypeSym) ;
   PopT(Array) ;
   Assert( (Array=ArrayTok) OR (Array=NulTok) ) ;
   PopT(NoOfIds) ;
   ProcSym := OperandT(NoOfIds+2) ;
   Assert(IsProcedure(ProcSym)) ;
   Var := OperandT(NoOfIds+1) ;
   Assert( (Var=VarTok) OR (Var=NulTok) ) ;
   Unbounded := (Array=ArrayTok) ;  (* ARRAY OF Type, parameter *)
   i := 1 ;
   pi := NoOfIds ;     (* stack index referencing stacked parameter, i *)
(*
   WriteString('No. of identifiers:') ; WriteCard(NoOfIds, 4) ; WriteLn ;
*)
   WHILE i<=NoOfIds DO
      IF ParamTotal+i<=NoOfParam(ProcSym)
      THEN
         IF Unbounded AND (NOT IsUnboundedParam(ProcSym, ParamTotal+i))
         THEN
            FailParameter('the parameter was declared as an ARRAY OF CHAR',
                          'the parameter was not declared as an ARRAY OF CHAR',
                          NulName, ParamTotal+i, ProcSym)
         ELSIF (NOT Unbounded) AND IsUnboundedParam(ProcSym, ParamTotal+i)
         THEN
            FailParameter('the parameter was not declared as an ARRAY OF CHAR',
                          'the parameter was declared as an ARRAY OF CHAR',
                          NulName, ParamTotal+i, ProcSym)
         END ;
         IF (Var=VarTok) AND (NOT IsVarParam(ProcSym, ParamTotal+i))
         THEN
            (* expecting non VAR pamarater *)
            FailParameter('the parameter has been declared as a VAR parameter',
                          'the parameter was not declared as a VAR parameter',
                          NulName, ParamTotal+i, ProcSym)
         ELSIF (Var=NulTok) AND IsVarParam(ProcSym, ParamTotal+i)
         THEN
            (* expecting VAR pamarater *)
            FailParameter('the parameter was not declared as a VAR parameter',
                          'the parameter has been declared as a VAR parameter',
                          NulName, ParamTotal+i, ProcSym)
         END ;
         ParamI := GetParam(ProcSym, ParamTotal+i) ;
         IF GetSymName(ParamI)#OperandT(pi)
         THEN
            (* different parameter names *)
            FailParameter('',
                          'the parameter has been declared with a different name',
                          OperandT(pi), ParamTotal+i, ProcSym)
         END ;
         IF Unbounded
         THEN
            (* GetType(ParamI) yields an UnboundedSym *)
            ParamIType := GetType(GetType(ParamI))
         ELSE
            ParamIType := GetType(ParamI)
         END ;
         IF ParamIType#TypeSym
         THEN
            (* different parameter types *)
            FailParameter('',
                          'the parameter has been declared with a different type',
                          OperandT(pi), ParamTotal+i, ProcSym)
         END
      ELSE
         FailParameter('too many parameters',
                       'fewer parameters were declared',
                       NulName, ParamTotal+i, ProcSym)
      END ;
      INC(i) ;
      DEC(pi)
   END ;
   PopN(NoOfIds+1) ;   (* +1 for the Var/Nul *)
   PushT(ParamTotal+NoOfIds) ;
   Assert(IsProcedure(OperandT(2)))
END CheckFormalParameterSection ;


(*
   FailParameter - generates an error message indicating that a parameter
                   declaration has failed.

                   The parameters are:

                   CurrentState  - string describing the current failing state.
                   PreviousState - string describing the old defined state.
                   Given         - token or identifier that was given.
                   ParameterNo   - parameter number that has failed.
                   ProcedureSym  - procedure symbol where parameter has failed.

                   If any parameter is Nul then it is ignored.
*)

PROCEDURE FailParameter (CurrentState : ARRAY OF CHAR;
                         PreviousState: ARRAY OF CHAR;
                         Given        : Name ;
                         ParameterNo  : CARDINAL;
                         ProcedureSym : CARDINAL) ;
VAR
   First,
   Second      : CARDINAL ;
   FirstModule,
   SecondModule,
   s1          : String ;
BEGIN
   IF NoOfParam(ProcedureSym)>=ParameterNo
   THEN
      First := GetDeclared(GetNthParam(ProcedureSym, ParameterNo))
   ELSE
      (* ParameterNo does not exist - which is probably the reason why this routine was called.. *)
      First := GetDeclared(ProcedureSym)
   END ;
   IF CompilingDefinitionModule()
   THEN
      FirstModule := InitString('definition module') ;
      SecondModule := InitString('implementation module')
   ELSIF CompilingImplementationModule()
   THEN
      FirstModule := InitString('implementation module') ;
      SecondModule := InitString('definition module')
   ELSIF CompilingProgramModule()
   THEN
      FirstModule := InitString('program module') ;
      SecondModule := InitString('definition module')
   END ;
   s1 := Sprintf4(Mark(InitString('declaration of procedure %s in the %s differs from the %s, problem with parameter number %d')),
                  Mark(InitStringCharStar(KeyToCharStar(GetSymName(ProcedureSym)))),
                  Mark(FirstModule),
                  SecondModule,
                  ParameterNo) ;
   IF NoOfParam(ProcedureSym)>=ParameterNo
   THEN
      s1 := ConCat(s1, Mark(Sprintf1(Mark(InitString(' (%s)')),
                                     Mark(InitStringCharStar(KeyToCharStar(GetSymName(GetNthParam(ProcedureSym, ParameterNo))))))))
   END ;
   IF NOT StrEqual(CurrentState, '')
   THEN
      s1 := ConCat(s1, Mark(Sprintf1(Mark(InitString(', %s')), Mark(InitString(CurrentState)))))
   END ;
   IF NOT StrEqual(PreviousState, '')
   THEN
      s1 := ConCat(s1, Mark(Sprintf2(Mark(InitString(' in the %s %s')), Mark(SecondModule), Mark(InitString(PreviousState)))))
   END ;
   IF Given#NulName
   THEN
      s1 := ConCat(s1, Mark(Sprintf1(Mark(InitString(' (%s)')), Mark(InitStringCharStar(KeyToCharStar(Given))))))
   END ;
   s1 := ConCat(s1, Mark(Sprintf0(Mark(InitString('\n'))))) ;
   ErrorStringAt2(s1, GetTokenNo(), First)
END FailParameter ;


(*
   StartBuildFormalParameters - Initialises the quadruple stack for
                                Formal Parameters.

                                The Stack:

                                Entry                Exit

                                                                    <- Ptr
                                                     +------------+
                                Empty                | 0          |
                                                     |------------|
*)

PROCEDURE StartBuildFormalParameters ;
BEGIN
   PushT(0)
END StartBuildFormalParameters ;


(*
   EndBuildFormalParameters - Resets the quadruple stack after building
                              Formal Parameters.

                              The Stack:

                              Entry                    Exit

                       Ptr ->
                              +------------+
                              | NoOfParam  |                          <- Ptr
                              |------------|           +------------+
                              | ProcSym    |           | ProcSym    |
                              |------------|           |------------|
*)

PROCEDURE EndBuildFormalParameters ;
VAR
   NoOfPar  : CARDINAL ;
   ProcSym  : CARDINAL ;
BEGIN
   PopT(NoOfPar) ;
   PopT(ProcSym) ;
   PushT(ProcSym) ;
   Assert(IsProcedure(ProcSym)) ;
   IF NoOfParam(ProcSym)#NoOfPar
   THEN
      IF CompilingDefinitionModule()
      THEN
         WriteFormat1('smaller number of procedure (%a) parameters in the DEFINITION MODULE', GetSymName(ProcSym))
      ELSE
         WriteFormat1('larger number of procedure (%a) parameters in the DEFINIION MODULE', GetSymName(ProcSym))
      END
   END ;
   Assert(IsProcedure(OperandT(1)))
END EndBuildFormalParameters ;


(*
   BuildFunction - Builds a procedures return type.
                   Procedure becomes a function.

                    The Stack:

                    Entry                 Exit

             Ptr ->
                    +------------+
                    | TypeSym    |                       <- Ptr
                    |------------|        +------------+
                    | ProcSym    |        | ProcSym    |
                    |------------|        |------------|
*)

PROCEDURE BuildFunction ;
VAR
   TypeSym,
   ProcSym : CARDINAL ;
BEGIN
   PopT(TypeSym) ;
   PopT(ProcSym) ;
   PutFunction(ProcSym, TypeSym) ;
(*
   WriteString('Procedure ') ; WriteKey(GetSymName(ProcSym)) ;
   WriteString(' has a return argument ') ;
   WriteKey(GetSymName(TypeSym)) ;
   WriteString(' checking ') ; WriteKey(GetSymName(GetType(ProcSym))) ;
   WriteLn ;
*)
   PushT(ProcSym)
END BuildFunction ;


(*
   BuildNulParam - Builds a nul parameter on the stack.
                   The Stack:

                   Entry             Exit

                                                    <- Ptr
                   Empty             +------------+
                                     | 0          |
                                     |------------|
*)

PROCEDURE BuildNulParam ;
BEGIN
   PushT(0)
END BuildNulParam ;


(*
   BuildPointerType - builds a pointer type.
                      The Stack:

                      Entry                       Exit
                      =====                       ====


               Ptr ->                                             <- Ptr
                      +------------+              +-------------+
                      | Type       |              | PointerType |
                      |------------|              |-------------|
                      | Name       |              | Name        |
                      |------------|              |-------------|
*)

PROCEDURE BuildPointerType ;
VAR
   name     : Name ;
   Type,
   PtrToType: CARDINAL ;
BEGIN
   PopT(Type) ;
   PopT(name) ;
   name := CheckAnonymous(name) ;
   PtrToType := MakePointer(name) ;
   PutPointer(PtrToType, Type) ;
   CheckForExportedImplementation(PtrToType) ;   (* May be an exported hidden type *)
   PushT(name) ;
   PushT(PtrToType)
(*
 ; WriteKey(name) ; WriteString(' Pointer made') ; WriteLn
*)
END BuildPointerType ;


(*
   BuildSetType - builds a set type.
                  The Stack:

                  Entry                       Exit
                  =====                       ====


           Ptr ->                                             <- Ptr
                  +------------+              +-------------+
                  | Type       |              | SetType     |
                  |------------|              |-------------|
                  | Name       |              | Name        |
                  |------------|              |-------------|
*)

PROCEDURE BuildSetType ;
VAR
   name   : Name ;
   Type,
   SetType: CARDINAL ;
BEGIN
   PopT(Type) ;
   PopT(name) ;
   SetType := MakeSet(name) ;
   CheckForExportedImplementation(SetType) ;   (* May be an exported hidden type *)
   PutSet(SetType, Type) ;
   PushT(name) ;
   PushT(SetType)
END BuildSetType ;


(*
   BuildRecord - Builds a record type.
                 The Stack:

                 Entry                        Exit
                 =====                        ====

                                                            <- Ptr
                                              +-----------+
          Ptr ->                              | RecordSym |
                 +------------+               |-----------|
                 | Name       |               | Name      |
                 |------------|               |-----------|
*)

PROCEDURE BuildRecord ;
VAR
   name      : Name ;
   RecordType: CARDINAL ;
BEGIN
   PopT(name) ;
   PushT(name) ;
   name := CheckAnonymous(name) ;
   RecordType := MakeRecord(name) ;
   CheckForExportedImplementation(RecordType) ;   (* May be an exported hidden type *)
   PushT(RecordType)
(* ; WriteKey(name) ; WriteString(' RECORD made') ; WriteLn *)
END BuildRecord ;


(*
   BuildFieldRecord - Builds a field into a record sym.
                      The Stack:


                      Entry                     Exit
                      =====                     ====

               Ptr ->
                      +-------------+
                      | Type | Name |
                      |-------------|
                      | n           |
                      |-------------|
                      | Id 1        |
                      |-------------|
                      .             .
                      .             .
                      .             .
                      |-------------|
                      | Id n        |                           <- Ptr
                      |-------------|           +-------------+
                      | RecordSym   |           | RecordSym   |
                      |-------------|           |-------------|
                      | RecordName  |           | RecordName  |
                      |-------------|           |-------------|
*)

PROCEDURE BuildFieldRecord ;
VAR
   name      : Name ;
   Parent,
   Type,
   NoOfFields,
   Record,
   Ptr, i    : CARDINAL ;
BEGIN
   PopTF(Type, name) ;
   PopT(NoOfFields) ;
   Record := OperandT(NoOfFields+1) ;
   IF IsRecord(Record)
   THEN
      Parent := Record
   ELSE
      (* Record maybe VarientRecord *)
      Parent := Father(Record)
   END ;
   i := 1 ;
   WHILE i<=NoOfFields DO
(*
      WriteKey(Operand(NoOfFields+1-i)) ; WriteString(' is a Field with type ') ;
      WriteKey(GetSymName(Type)) ; WriteLn ;
*)
      IF GetLocalSym(Parent, OperandT(NoOfFields+1-i))=NulSym
      THEN
         PutFieldRecord(Record, OperandT(NoOfFields+1-i), Type)
      ELSE
         IF GetSymName(Parent)=NulName
         THEN
            WriteFormat1('field %a is already present inside record', OperandT(NoOfFields+1-i))
         ELSE
            WriteFormat2('field %a is already present inside record %s', OperandT(NoOfFields+1-i), GetSymName(Parent))
         END
      END ;
      INC(i)
   END ;
   PopN(NoOfFields+1) ;
   PushT(Record)
END BuildFieldRecord ;


(*
   BuildVarientSelector - Builds a field into a record sym.
                          The Stack:


                          Entry                     Exit
                          =====                     ====

                   Ptr ->
                          +-------------+
                          | Qualident   |
                          |-------------|
                          | Ident       |                           <- Ptr
                          |-------------|           +-------------+
                          | RecordSym   |           | RecordSym   |
                          |-------------|           |-------------|
*)

PROCEDURE BuildVarientSelector ;
VAR
   Qualident,
   Ident    : CARDINAL ;
BEGIN
   PopT(Qualident) ;
   PushT(1) ;  (* Number of Idents *)
   PushTF(Qualident, GetSymName(Qualident)) ;
   BuildFieldRecord
END BuildVarientSelector ;


(*
   StartBuildVarientFieldRecord - Builds a varient field into a varient sym.
                                  The Stack:


                                  Entry                     Exit
                                  =====                     ====

                                                                       <- Ptr
                                                       +-------------+
                      Ptr ->                           | VarientField|
                             +-------------+           |-------------|
                             | VarientSym  |           | RecordSym   |
                             |-------------|           |-------------|
*)

PROCEDURE StartBuildVarientFieldRecord ;
VAR
   FieldSym,
   VarientSym: CARDINAL ;
BEGIN
   PopT(VarientSym) ;
   FieldSym := MakeFieldVarient(VarientSym) ;
   PushT(VarientSym) ;
   PushT(FieldSym)
END StartBuildVarientFieldRecord ;


(*
   EndBuildVarientFieldRecord - Removes a varient field from the stack.
                                The Stack:


                                Entry                     Exit
                                =====                     ====

                         Ptr ->
                                +-------------+
                                | VarientField|                           <- Ptr
                                |-------------|           +-------------+
                                | VarientSym  |           | VarientSym  |
                                |-------------|           |-------------|
*)

PROCEDURE EndBuildVarientFieldRecord ;
VAR
   FieldSym: CARDINAL ;
BEGIN
   PopT(FieldSym)
END EndBuildVarientFieldRecord ;


(*
   StartBuildVarient - Builds a varient symbol on top of a record sym.
                       The Stack:


                       Entry                     Exit
                       =====                     ====

                                                                 <- Ptr
                                                 +-------------+
                Ptr ->                           | VarientSym  |
                       +-------------+           |-------------|
                       | RecordSym   |           | RecordSym   |
                       |-------------|           |-------------|
                       | RecordName  |           | RecordName  |
                       |-------------|           |-------------|
*)

PROCEDURE StartBuildVarient ;
VAR
   RecordSym,
   Sym      : CARDINAL ;
BEGIN
   PopT(RecordSym) ;
   Sym := MakeVarient(RecordSym) ;
   PushT(RecordSym) ;
   PushT(Sym)
END StartBuildVarient ;



(*
   EndBuildVarient - Removes the varient symbol from the stack.
                     The Stack:

                     Entry                     Exit
                     =====                     ====

              Ptr ->
                     +-------------+
                     | VarientSym  |                           <- Ptr
                     |-------------|           +-------------+
                     | RecordSym   |           | RecordSym   |
                     |-------------|           |-------------|
                     | RecordName  |           | RecordName  |
                     |-------------|           |-------------|
*)

PROCEDURE EndBuildVarient ;
VAR
   Sym: CARDINAL ;
BEGIN
   PopT(Sym)
END EndBuildVarient ;


(*
   BuildNulName - Pushes a NulName onto the top of the stack.
                  The Stack:


                  Entry                    Exit

                                                          <- Ptr
                  Empty                    +------------+
                                           | NulName   |
                                           |------------|
*)

PROCEDURE BuildNulName ;
BEGIN
   PushT(NulName)
END BuildNulName ;


(*
   BuildTypeEnd - Pops the type Type and Name.
                  The Stack:


                  Entry                    Exit


           Ptr ->
                  +-------------+
                  | Type | Name |          Empty
                  |-------------|
*)

PROCEDURE BuildTypeEnd ;
VAR
   Type: CARDINAL ;
   name: Name ;
BEGIN
   PopTF(Type, name)
END BuildTypeEnd ;


(*
   StartBuildArray - Builds an array type.
                     The Stack:

                     Entry                        Exit
                     =====                        ====

                                                                <- Ptr
                                                  +-----------+
              Ptr ->                              | ArraySym  |
                     +------------+               |-----------|
                     | Name       |               | Name      |
                     |------------|               |-----------|
*)

PROCEDURE StartBuildArray ;
VAR
   name     : Name ;
   ArrayType: CARDINAL ;
BEGIN
   PopT(name) ;
   PushT(name) ;
   ArrayType := MakeArray(name) ;
   CheckForExportedImplementation(ArrayType) ;   (* May be an exported hidden type *)
   PushT(ArrayType)
(* ; WriteKey(Name) ; WriteString(' ARRAY made') ; WriteLn *)
END StartBuildArray ;


(*
   EndBuildArray - Builds an array type.
                   The Stack:

                   Entry                        Exit
                   =====                        ====

            Ptr ->
                   +------------+
                   | TypeSym    |                              <- Ptr
                   |------------|               +------------+
                   | ArraySym   |               | ArraySym   |
                   |------------|               |------------|
                   | Name       |               | Name       |
                   |------------|               |------------|
*)

PROCEDURE EndBuildArray ;
VAR
   TypeSym,
   ArraySym: CARDINAL ;
BEGIN
   PopT(TypeSym) ;
   PopT(ArraySym) ;
   Assert(IsArray(ArraySym)) ;
   PutArray(ArraySym, TypeSym) ;
   PushT(ArraySym)
END EndBuildArray ;


(*
   BuildFieldArray - Builds a field into an array sym.
                     The Stack:


                     Entry                     Exit
                     =====                     ====

              Ptr ->
                     +-------------+
                     | Type | Name |                           <- Ptr
                     |-------------|           +-------------+
                     | ArraySym    |           | ArraySym    |
                     |-------------|           |-------------|
                     | ArrayName   |           | ArrayName   |
                     |-------------|           |-------------|
*)

PROCEDURE BuildFieldArray ;
VAR
   s         : String ;
   Subrange,
   Subscript,
   Type,
   Array     : CARDINAL ;
   name      : Name ;
BEGIN
   PopTF(Type, name) ;
   PopT(Array) ;
   Assert(IsArray(Array)) ;
   Subscript := MakeSubscript() ;
   IF IsEnumeration(Type)
   THEN
      (* We must now create a subrange type based upon the enumeration type *)
      Subrange := MakeSubrange(NulName) ;
      IF NoOfElements(Type)=0
      THEN
         WriteFormat0('cannot create an array with 0 elements')
      ELSE
         s := Sprintf1(Mark(InitString('%d')), NoOfElements(Type)-1) ;
         PutSubrange(Subrange,
                     MakeConstLit(MakeKey('0')), MakeConstLit(makekey(string(s))),
                     Type) ;
         s := KillString(s) ;
         PutSubscript(Subscript, Subrange)
      END
   ELSE
      (*
         Would like to Assert(IsSubrange(Type)) - but unfortunately
         the subrange type might be declared later on in the file.
         Hence we take it in 'faith' at this point - check later in
         the M2SymBuild and M2CodeGen pass.
      *)
      PutSubscript(Subscript, Type)
   END ;
   PutFieldArray(Array, Subscript) ;
   PushT(Array)
(* ; WriteString('Field Placed in Array') ; WriteLn *)
END BuildFieldArray ;



(*
   BuildProcedureType - builds a procedure type symbol.
                        The Stack:


                                                               <- Ptr
                                               +-------------+
                 Ptr ->                        | ProcTypeSym |
                        +-------------+        |-------------|
                        | Name        |        | Name        |
                        |-------------|        |-------------|
*)

PROCEDURE BuildProcedureType ;
VAR
   name       : Name ;
   ProcTypeSym: CARDINAL ;
BEGIN
   PopT(name) ;
   ProcTypeSym := MakeProcType(name) ;
   PushT(name) ;
   PushT(ProcTypeSym)
END BuildProcedureType ;


(*
   BuildFormalType - Builds a Formal Parameter in a procedure type.

                     The Stack:

                     Entry                 Exit

              Ptr ->
                     +------------+
                     | TypeSym    |
                     |------------|
                     | Array/Nul  |
                     |------------|
                     | Var / Nul  |                         <- Ptr
                     |------------|        +--------------+
                     | ProcTypeSym|        | ProcTypeSym  |
                     |------------|        |--------------|
*)

PROCEDURE BuildFormalType ;
VAR
   Array, Var : Name ;
   TypeSym,
   UnboundedSym,
   ProcTypeSym: CARDINAL ;
BEGIN
   PopT(TypeSym) ;
   PopT(Array) ;
   PopT(Var) ;
   PopT(ProcTypeSym) ;

   Assert( (Array=ArrayTok) OR (Array=NulTok) ) ;
   Assert(IsProcType(ProcTypeSym)) ;
   Assert( (Var=VarTok) OR (Var=NulTok) ) ;

   IF Array=ArrayTok
   THEN
      UnboundedSym := MakeUnbounded() ;
      PutUnbounded(UnboundedSym, TypeSym) ;
      TypeSym := UnboundedSym
   END ;
   IF Var=VarTok
   THEN
      (* VAR pamarater *)
      PutProcTypeVarParam(ProcTypeSym, TypeSym)
   ELSE
      (* Non VAR parameter *)
      PutProcTypeParam(ProcTypeSym, TypeSym)
   END ;
   PushT(ProcTypeSym)
END BuildFormalType ;


(*
   BuildPriority - give a module a constant priority.

                   The Stack:

                   Entry                 Exit

            Ptr ->
                   +------------+
                   | ConstSym   |                         <- Ptr
                   |------------|        +--------------+
                   | ModuleName |        | ModuleName   |
                   |------------|        |--------------|
*)

PROCEDURE BuildPriority ;
VAR
   ModuleName: Name ;
   ConstSym  : CARDINAL ;
BEGIN
   PopT(ConstSym) ;
   PopT(ModuleName) ;
   PushT(ModuleName) ;
   InternalError('not implemented yet - to implement place a PutModulePriority and GetModulePriority into SymbolTable', __FILE__, __LINE__)
END BuildPriority ;


(*
   StartBuildingConstDeclaration - 
*)

PROCEDURE StartBuildingConstDeclaration ;
BEGIN
   IsBuildingConstDeclaration := TRUE
END StartBuildingConstDeclaration ;


(*
   EndBuildingConstDeclaration - 
*)

PROCEDURE EndBuildingConstDeclaration ;
BEGIN
   IsBuildingConstDeclaration := FALSE
END EndBuildingConstDeclaration ;


BEGIN
   IsBuildingConstDeclaration := FALSE
END P2SymBuild.
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
IMPLEMENTATION MODULE SymbolTable ;


FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM M2Debug IMPORT Assert ;

FROM M2Options IMPORT Pedantic ;

FROM M2ALU IMPORT InitValue, PtrToValue, PushCard, PopCard, PopInto,
                  PushString, PushFrom, PushChar, PushInt, PopInt,
                  IsSolved ;
FROM M2Error IMPORT Error, NewError, ChainError, InternalError,
                    ErrorFormat0, ErrorFormat1, ErrorFormat2,
                    WriteFormat0, WriteFormat1, WriteFormat2, ErrorString ;

FROM M2LexBuf IMPORT GetTokenNo ;
FROM Strings IMPORT String, string, InitString, InitStringCharStar, Mark, KillString ;
FROM FormatStrings IMPORT Sprintf1 ;
FROM M2Printf IMPORT printf0, printf1, printf2, printf3, printf4 ;

FROM Lists IMPORT List, InitList, GetItemFromList, PutItemIntoList,
                  IsItemInList, IncludeItemIntoList, NoOfItemsInList,
                  RemoveItemFromList, ForeachItemInListDo ;

FROM NameKey IMPORT Name, MakeKey, makekey, NulName, WriteKey, LengthKey, GetKey, KeyToCharStar ;

FROM SymbolKey IMPORT NulKey, SymbolTree,
                      InitTree,
                      GetSymKey, PutSymKey, DelSymKey, IsEmptyTree,
                      DoesTreeContainAny, ForeachNodeDo ;

FROM M2Base IMPORT InitBase, Char, Integer, LongReal ;

FROM M2System IMPORT Address ;

FROM M2Comp IMPORT CompilingDefinitionModule,
                   CompilingImplementationModule ;


CONST
   MaxScopes  =    50 ; (* Maximum number of scopes at any one time.         *)
   MaxSymbols = 30000 ; (* Maximum number of symbols required for            *)
                        (* compilation.                                      *)

TYPE
   (* TypeOfSymbol denotes the type of symbol.                               *)

   TypeOfSymbol
              = (RecordSym, VarientSym, DummySym,
                 VarSym, EnumerationSym, SubrangeSym, ArraySym,
                 ConstStringSym, ConstVarSym, ConstLitSym,
                 VarParamSym, ParamSym, PointerSym,
                 UndefinedSym, TypeSym,
                 RecordFieldSym, VarientFieldSym, EnumerationFieldSym,
                 DefImpSym, ModuleSym, SetSym, ProcedureSym, ProcTypeSym,
                 SubscriptSym, UnboundedSym, GnuAsmSym, InterfaceSym) ;

   Where = RECORD
              Declared,
              FirstUsed: CARDINAL ;
           END ;

   SymUndefined = RECORD
                     name      : Name ;       (* Index into name array, name *)
                                              (* of record.                  *)
                     At        : Where ;      (* Where was sym declared/used *)
                  END ;

   SymGnuAsm    = RECORD
                     String    : CARDINAL ;   (* (ConstString) the assembly  *)
                                              (* instruction.                *)
                     At        : Where ;      (* Where was sym declared/used *)
                     Inputs,
                     Outputs,
                     Trashed   : CARDINAL ;   (* The interface symbols.      *)
                     Volatile  : BOOLEAN ;    (* Declared as ASM VOLATILE ?  *)
                  END ;

   SymInterface = RECORD
                     StringList: List ;       (* regnames or constraints     *)
                     ObjectList: List ;       (* list of M2 syms             *)
                     At        : Where ;      (* Where was sym declared/used *)
                  END ;

   SymVarient = RECORD
                   Size        : PtrToValue ; (* Size at runtime of symbol.  *)
                   ListOfSons  : List ;       (* ListOfSons contains a list  *)
                                              (* of SymRecordField and       *)
                                              (* SymVarients                 *)
                                              (* declared by the source      *)
                                              (* file.                       *)
                   Parent      : CARDINAL ;   (* Points to the Father Symbol *)
                   At          : Where ;      (* Where was sym declared/used *)
               END ;

   SymRecord = RECORD
                  name         : Name ;       (* Index into name array, name *)
                                              (* of record.                  *)
                  LocalSymbols : SymbolTree ; (* Contains all record fields. *)
                  Size         : PtrToValue ; (* Size at runtime of symbol.  *)
                  ListOfSons   : List ;       (* ListOfSons contains a list  *)
                                              (* of SymRecordField and       *)
                                              (* SymVarients                 *)
                                              (* declared by the source      *)
                                              (* file.                       *)
                  Parent       : CARDINAL ;   (* Points to the Father Symbol *)
                  At           : Where ;      (* Where was sym declared/used *)
               END ;

   SymSubrange = RECORD
                    name       : Name ;       (* Index into name array, name *)
                                              (* of subrange.                *)
                    Low        : CARDINAL ;   (* Index to symbol for lower   *)
                    High       : CARDINAL ;   (* Index to symbol for higher  *)
                    Size       : PtrToValue ; (* Size of subrange type.      *)
                    Type       : CARDINAL ;   (* Index to type symbol for    *)
                                              (* the type of subrange.       *)
                    At         : Where ;      (* Where was sym declared/used *)
                 END ;

   SymEnumeration =
                RECORD
                   name        : Name ;       (* Index into name array, name *)
                                              (* of enumeration.             *)
                   NoOfElements: CARDINAL ;   (* No elements in enumeration  *)
                   LocalSymbols: SymbolTree ; (* Contains all enumeration    *)
                                              (* fields.                     *)
                   Size        : PtrToValue ; (* Size at runtime of symbol.  *)
                   Parent      : CARDINAL ;   (* Parent is used as an index  *)
                                              (* to the parent block. The    *)
                                              (* enumeration type is a       *)
                                              (* pseudo block which has its  *)
                                              (* fields as LocalSymbols.     *)
                   At          : Where ;      (* Where was sym declared/used *)
                END ;

   SymArray = RECORD
                 name        : Name ;         (* Index into name array, name *)
                                              (* of array.                   *)
                 ListOfSubs  : List ;         (* Contains a list of all      *)
                                              (* subscripts for this array.  *)
                 Size        : PtrToValue ;   (* Size at runtime of symbol.  *)
                 Offset      : PtrToValue ;   (* Offset at runtime of symbol *)
                 Type        : CARDINAL ;     (* Type of the Array.          *)
                 At          : Where ;        (* Where was sym declared/used *)
              END ;

   SymSubscript = RECORD
                     Type       : CARDINAL ;   (* Index to a subrange symbol. *)
                     Size       : PtrToValue ; (* Size of this indice in*Size *)
                     Offset     : PtrToValue ; (* Offset at runtime of symbol *)
                                               (* Pseudo ie: Offset+Size*i    *)
                                               (* 1..n. The array offset is   *)
                                               (* the real memory offset.     *)
                                               (* This offset allows the a[i] *)
                                               (* to be calculated without    *)
                                               (* the need to perform         *)
                                               (* subtractions when a[4..10]  *)
                                               (* needs to be indexed.        *)
                     At         : Where ;      (* Where was sym declared/used *)
                  END ;

   SymUnbounded = RECORD
                     Type       : CARDINAL ;   (* Index to Simple type symbol *)
                     Size       : PtrToValue ; (* Max No of words ever        *)
                                               (* passed to this type.        *)
                     At         : Where ;      (* Where was sym declared/used *)
                  END ;

   SymProcedure
            = RECORD
                 name          : Name ;       (* Index into name array, name   *)
                                              (* of procedure.                 *)
                 ListOfParam   : List ;       (* Contains a list of all the    *)
                                              (* parameters in this procedure. *)
                 ParamDefined  : BOOLEAN ;    (* Have the parameters been      *)
                                              (* defined yet?                  *)
                 DefinedInDef  : BOOLEAN ;    (* Were the parameters defined   *)
                                              (* in the Definition module?     *)
                                              (* Note that this depends on     *)
                                              (* whether the compiler has read *)
                                              (* the .def or .mod first.       *)
                                              (* The second occurence is       *)
                                              (* compared to the first.        *)
                 DefinedInImp: BOOLEAN ;      (* Were the parameters defined   *)
                                              (* in the Implementation module? *)
                                              (* Note that this depends on     *)
                                              (* whether the compiler has read *)
                                              (* the .def or .mod first.       *)
                                              (* The second occurence is       *)
                                              (* compared to the first.        *)
                 Father        : CARDINAL ;   (* Father scope of procedure.    *)
                 StartQuad     : CARDINAL ;   (* Index into quads for start    *)
                                              (* of procedure.                 *)
                 EndQuad       : CARDINAL ;   (* Index into quads for end of   *)
                                              (* procedure.                    *)
                 Reachable     : BOOLEAN ;    (* Defines if procedure will     *)
                                              (* ever be called by the main    *)
                                              (* Module.                       *)
                 ReturnType    : CARDINAL ;   (* Return type for function.     *)
                 Offset        : CARDINAL ;   (* Location of procedure used    *)
                                              (* in Pass 2 and if procedure    *)
                                              (* is a syscall.                 *)
                 LocalSymbols: SymbolTree ;   (* Contains all symbols declared *)
                                              (* within this procedure.        *)
                 EnumerationScopeList: List ;
                                              (* Enumeration scope list which  *)
                                              (* contains a list of all        *)
                                              (* enumerations which are        *)
                                              (* visable within this scope.    *)
                 ListOfVars    : List ;       (* List of variables in this     *)
                                              (* scope.                        *)
                 Size          : PtrToValue ; (* Activation record size.       *)
                 TotalParamSize: PtrToValue ; (* size of all parameters.       *)
                 At            : Where ;      (* Where was sym declared/used   *)
              END ;

   SymProcType
            = RECORD
                 name          : Name ;       (* Index into name array, name   *)
                                              (* of procedure.                 *)
                 ListOfParam   : List ;       (* Contains a list of all the    *)
                                              (* parameters in this procedure. *)
                 ReturnType    : CARDINAL ;   (* Return type for function.     *)
                 Size          : PtrToValue ; (* Runtime size of symbol.       *)
                 TotalParamSize: PtrToValue ; (* size of all parameters.       *)
                 At            : Where ;      (* Where was sym declared/used *)
              END ;

   SymParam = RECORD
                 name        : Name ;         (* Index into name array, name *)
                                              (* of param.                   *)
                 Type        : CARDINAL ;     (* Index to the type of param. *)
                 At          : Where ;        (* Where was sym declared/used *)
              END ;

   SymVarParam = RECORD
                    name     : Name ;         (* Index into name array, name *)
                                              (* of param.                   *)
                    Type     : CARDINAL ;     (* Index to the type of param. *)
                    At       : Where ;        (* Where was sym declared/used *)
                 END ;

   SymConstString
               = RECORD
                    name     : Name ;         (* Index into name array, name *)
                                              (* of const.                   *)
                    String   : Name ;         (* Value of string.            *)
                    Length   : CARDINAL ;     (* StrLen(String)              *)
                    At       : Where ;        (* Where was sym declared/used *)
                 END ;

   SymConstLit = RECORD
                    name     : Name ;     (* Index into name array, name *)
                                              (* of const.                   *)
                    Value    : PtrToValue ;   (* Value of the constant.      *)
                    Type     : CARDINAL ;     (* TYPE of constant, char etc  *)
                    IsSet    : BOOLEAN ;      (* is the constant a set?      *)
                    At       : Where ;        (* Where was sym declared/used *)
                 END ;

   SymConstVar = RECORD
                    name     : Name ;     (* Index into name array, name *)
                                              (* of const.                   *)
                    Value    : PtrToValue ;   (* Value of the constant       *)
                    Type     : CARDINAL ;     (* TYPE of constant, char etc  *)
                    IsSet    : BOOLEAN ;      (* is the constant a set?      *)
                    At       : Where ;        (* Where was sym declared/used *)
                 END ;

   SymVar = RECORD
               name          : Name ;     (* Index into name array, name *)
                                              (* of const.                   *)
               Type          : CARDINAL ;     (* Index to a type symbol.     *)
               Size          : PtrToValue ;   (* Runtime size of symbol.     *)
               Offset        : PtrToValue ;   (* Offset at runtime of symbol *)
               AddrMode      : ModeOfAddr ;   (* Type of Addressing mode.    *)
               Father        : CARDINAL ;     (* Father scope of variable.   *)
               IsTemp        : BOOLEAN ;      (* Is variable a temporary?    *)
               IsParam       : BOOLEAN ;      (* Is variable a parameter?    *)
               At            : Where ;        (* Where was sym declared/used *)
               ReadUsageList : List ;         (* list of var read quads      *)
               WriteUsageList: List ;         (* list of var write quads     *)
            END ;

   SymType = RECORD
                name     : Name ;             (* Index into name array, name *)
                                              (* of type.                    *)
                Type     : CARDINAL ;         (* Index to a type symbol.     *)
                Size     : PtrToValue ;       (* Runtime size of symbol.     *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymPointer
           = RECORD
                name     : Name ;         (* Index into name array, name *)
                                              (* of pointer.                 *)
                Type     : CARDINAL ;         (* Index to a type symbol.     *)
                Size     : PtrToValue ;       (* Runtime size of symbol.     *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymRecordField =
             RECORD
                name     : Name ;         (* Index into name array, name *)
                                              (* of record field.            *)
                Type     : CARDINAL ;         (* Index to a type symbol.     *)
                Size     : PtrToValue ;       (* Runtime size of symbol.     *)
                Offset   : PtrToValue ;       (* Offset at runtime of symbol *)
                Parent   : CARDINAL ;         (* Index into symbol table to  *)
                                              (* determine the parent symbol *)
                                              (* for this record field. Used *)
                                              (* for BackPatching.           *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymVarientField =
             RECORD
                Size     : PtrToValue ;       (* Runtime size of symbol.     *)
                Offset   : PtrToValue ;       (* Offset at runtime of symbol *)
                Parent   : CARDINAL ;         (* Index into symbol table to  *)
                                              (* determine the parent symbol *)
                                              (* for this record field. Used *)
                                              (* for BackPatching.           *)
                ListOfSons: List ;            (* Contains a list of the      *)
                                              (* RecordField symbols.        *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymEnumerationField =
             RECORD
                name     : Name ;             (* Index into name array, name *)
                                              (* of enumeration field.       *)
                Value    : PtrToValue ;       (* Enumeration field value.    *)
                Type     : CARDINAL ;         (* Index to the father.        *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymSet  = RECORD
      	        name     : Name ;             (* Index into name array, name *)
                                              (* of set.                     *)
                Type     : CARDINAL ;         (* Index to a type symbol.     *)
      	       	     	      	       	      (* (subrange or enumeration).  *)
                Size     : PtrToValue ;       (* Runtime size of symbol.     *)
                At       : Where ;            (* Where was sym declared/used *)
             END ;

   SymDefImp =
            RECORD
               name          : Name ;   (* Index into name array, name   *)
                                            (* of record field.              *)
               Type          : CARDINAL ;   (* Index to a type symbol.       *)
               Size          : PtrToValue ; (* Runtime size of symbol.       *)
               Offset        : PtrToValue ; (* Offset at runtime of symbol   *)
               ExportQualifiedTree: SymbolTree ;
                                            (* Holds all the export          *)
                                            (* Qualified identifiers.        *)
                                            (* This tree may be              *)
                                            (* deleted at the end of Pass 1. *)
               ExportUnQualifiedTree: SymbolTree ;
                                            (* Holds all the export          *)
                                            (* UnQualified identifiers.      *)
                                            (* This tree may be              *)
                                            (* deleted at the end of Pass 1. *)
               ExportRequest : SymbolTree ; (* Contains all identifiers that *)
                                            (* have been requested by other  *)
                                            (* modules before this module    *)
                                            (* declared its export list.     *)
                                            (* This tree should be empty at  *)
                                            (* the end of the compilation.   *)
                                            (* Each time a symbol is         *)
                                            (* exported it is removed from   *)
                                            (* this list.                    *)
               IncludeList   : List ;       (* Contains all included symbols *)
                                            (* which are included by         *)
                                            (* IMPORT modulename ;           *)
                                            (* modulename.Symbol             *)
               ImportTree    : SymbolTree ; (* Contains all IMPORTed         *)
                                            (* identifiers.                  *)
               ExportUndeclared: SymbolTree ;
                                            (* ExportUndeclared contains all *)
                                            (* the identifiers which were    *)
                                            (* exported but have not yet     *)
                                            (* been declared.                *)
               NeedToBeImplemented: SymbolTree ;
                                            (* NeedToBeImplemented contains  *)
                                            (* the identifiers which have    *)
                                            (* been exported and declared    *)
                                            (* but have not yet been         *)
                                            (* implemented.                  *)
               LocalSymbols  : SymbolTree ; (* The LocalSymbols hold all the *)
                                            (* variables declared local to   *)
                                            (* the block. It contains the    *)
                                            (* IMPORT r ;                    *)
                                            (* FROM _ IMPORT x, y, x ;       *)
                                            (*    and also                   *)
                                            (* MODULE WeAreHere ;            *)
                                            (*    x y z visiable by localsym *)
                                            (*    MODULE Inner ;             *)
                                            (*       EXPORT x, y, z ;        *)
                                            (*    END Inner ;                *)
                                            (* END WeAreHere.                *)
               EnumerationScopeList: List ; (* Enumeration scope list which  *)
                                            (* contains a list of all        *)
                                            (* enumerations which are        *)
                                            (* visable within this scope.    *)
               Priority      : CARDINAL ;   (* Priority of the module. This  *)
                                            (* is an index to a constant.    *)
               Unresolved    : SymbolTree ; (* All symbols currently         *)
                                            (* unresolved in this module.    *)
               StartQuad     : CARDINAL ;   (* Signify the initialization    *)
                                            (* code.                         *)
               EndQuad       : CARDINAL ;   (* EndQuad should point to a     *)
                                            (* goto quad.                    *)
               ContainsHiddenType: BOOLEAN ;(* True if this module           *)
                                            (* implements a hidden type.     *)
               ListOfVars    : List ;       (* List of variables in this     *)
                                            (* scope.                        *)
               ListOfProcs   : List ;       (* List of all procedures        *)
                                            (* declared within this module.  *)
               ListOfModules : List ;       (* List of all inner modules.    *)
               At            : Where ;      (* Where was sym declared/used *)
            END ;

   SymModule =
            RECORD
               name          : Name ;   (* Index into name array, name   *)
                                            (* of record field.              *)
               Size          : PtrToValue ; (* Runtime size of symbol.       *)
               Offset        : PtrToValue ; (* Offset at runtime of symbol   *)
               LocalSymbols  : SymbolTree ; (* The LocalSymbols hold all the *)
                                            (* variables declared local to   *)
                                            (* the block. It contains the    *)
                                            (* IMPORT r ;                    *)
                                            (* FROM _ IMPORT x, y, x ;       *)
                                            (*    and also                   *)
                                            (* MODULE WeAreHere ;            *)
                                            (*    x y z visiable by localsym *)
                                            (*    MODULE Inner ;             *)
                                            (*       EXPORT x, y, z ;        *)
                                            (*    END Inner ;                *)
                                            (* END WeAreHere.                *)
               ExportTree    : SymbolTree ; (* Holds all the exported        *)
                                            (* identifiers.                  *)
                                            (* This tree may be              *)
                                            (* deleted at the end of Pass 1. *)
               IncludeList   : List ;       (* Contains all included symbols *)
                                            (* which are included by         *)
                                            (* IMPORT modulename ;           *)
                                            (* modulename.Symbol             *)
               ImportTree    : SymbolTree ; (* Contains all IMPORTed         *)
                                            (* identifiers.                  *)
               ExportUndeclared: SymbolTree ;
                                            (* ExportUndeclared contains all *)
                                            (* the identifiers which were    *)
                                            (* exported but have not yet     *)
                                            (* been declared.                *)
               EnumerationScopeList: List ; (* Enumeration scope list which  *)
                                            (* contains a list of all        *)
                                            (* enumerations which are        *)
                                            (* visable within this scope.    *)
               Father        : CARDINAL ;   (* Father scope of module.       *)
               Priority      : CARDINAL ;   (* Priority of the module. This  *)
                                            (* is an index to a constant.    *)
               Unresolved    : SymbolTree ; (* All symbols currently         *)
                                            (* unresolved in this module.    *)
               StartQuad     : CARDINAL ;   (* Signify the initialization    *)
                                            (* code.                         *)
               EndQuad       : CARDINAL ;   (* EndQuad should point to a     *)
                                            (* goto quad.                    *)
               ListOfVars    : List ;       (* List of variables in this     *)
                                            (* scope.                        *)
               ListOfProcs   : List ;       (* List of all procedures        *)
                                            (* declared within this module.  *)
               ListOfModules : List ;       (* List of all inner modules.    *)
               At            : Where ;      (* Where was sym declared/used   *)
            END ;

   SymDummy =
            RECORD
               NextFree     : CARDINAL ;    (* Link to the next free symbol. *)
            END ;


   Symbol = RECORD
               CASE SymbolType : TypeOfSymbol OF
                                            (* Determines the type of symbol *)

               RecordSym           : Record           : SymRecord |
               VarientSym          : Varient          : SymVarient |
               VarSym              : Var              : SymVar |
               EnumerationSym      : Enumeration      : SymEnumeration |
               SubrangeSym         : Subrange         : SymSubrange |
               SubscriptSym        : Subscript        : SymSubscript |
               ArraySym            : Array            : SymArray |
               UnboundedSym        : Unbounded        : SymUnbounded |
               ConstVarSym         : ConstVar         : SymConstVar |
               ConstLitSym         : ConstLit         : SymConstLit |
               ConstStringSym      : ConstString      : SymConstString |
               VarParamSym         : VarParam         : SymVarParam |
               ParamSym            : Param            : SymParam |
               UndefinedSym        : Undefined        : SymUndefined |
               TypeSym             : Type             : SymType |
               PointerSym          : Pointer          : SymPointer |
               RecordFieldSym      : RecordField      : SymRecordField |
               VarientFieldSym     : VarientField     : SymVarientField |
               EnumerationFieldSym : EnumerationField : SymEnumerationField |
               DefImpSym           : DefImp           : SymDefImp |
               ModuleSym           : Module           : SymModule |
               SetSym              : Set              : SymSet |
               ProcedureSym        : Procedure        : SymProcedure |
               ProcTypeSym         : ProcType         : SymProcType |
               GnuAsmSym           : GnuAsm           : SymGnuAsm |
               InterfaceSym        : Interface        : SymInterface |
               DummySym            : Dummy            : SymDummy

               END
            END ;

   CallFrame = RECORD
                  Main  : CARDINAL ;  (* Main scope for insertions        *)
                  Search: CARDINAL ;  (* Search scope for symbol searches *)
                  Start : CARDINAL ;  (* ScopePtr value before StartScope *)
                                      (* was called.                      *)
               END ;


VAR
   Symbols       : ARRAY [1..MaxSymbols] OF Symbol ;
   ScopeCallFrame: ARRAY [1..MaxScopes] OF CallFrame ;
   FreeSymbol    : CARDINAL ;    (* The Head of the free symbol list   *)
   DefModuleTree : SymbolTree ;
   ModuleTree    : SymbolTree ;  (* Tree of all modules ever used.     *)
   ConstLitStringTree
                 : SymbolTree ;  (* String Literal Constants only need *)
                                 (* to be declared once.               *)
   ConstLitTree  : SymbolTree ;  (* Numerical Literal Constants only   *)
                                 (* need to be declared once.          *)
   CurrentModule : CARDINAL ;    (* Index into symbols determining the *)
                                 (* current module being compiled.     *)
                                 (* This maybe an inner module.        *)
   MainModule    : CARDINAL ;    (* Index into symbols determining the *)
                                 (* module the user requested to       *)
                                 (* compile.                           *)
   FileModule    : CARDINAL ;    (* Index into symbols determining     *)
                                 (* which module (file) is being       *)
                                 (* compiled. (Maybe an import def)    *)
   ScopePtr      : CARDINAL ;    (* An index to the ScopeCallFrame.    *)
                                 (* ScopePtr determines the top of the *)
                                 (* ScopeCallFrame.                    *)
   BaseScopePtr  : CARDINAL ;    (* An index to the ScopeCallFrame of  *)
                                 (* the top of BaseModule. BaseModule  *)
                                 (* is always left at the bottom of    *)
                                 (* stack since it is used so          *)
                                 (* frequently. When the BaseModule    *)
                                 (* needs to be searched the ScopePtr  *)
                                 (* is temporarily altered to          *)
                                 (* BaseScopePtr and GetScopeSym is    *)
                                 (* called.                            *)
   BaseModule    : CARDINAL ;    (* Index to the symbol table of the   *)
                                 (* Base pseudo modeule declaration.   *)
   TemporaryNo   : CARDINAL ;    (* The next temporary number.         *)
   CurrentError  : Error ;       (* Current error chain.               *)


(* %%%FORWARD%%%
PROCEDURE CheckForSymbols (Tree: SymbolTree; a: ARRAY OF CHAR) ; FORWARD ;
PROCEDURE PushConstString (Sym: CARDINAL) ; FORWARD ;
PROCEDURE AddParameter (Sym: CARDINAL; ParSym: CARDINAL) ; FORWARD ;
PROCEDURE AddProcedureToList (Mod, Proc: CARDINAL) ; FORWARD ;
PROCEDURE AddSymToModuleScope (ModSym: CARDINAL; Sym: CARDINAL) ; FORWARD ;
PROCEDURE AddSymToScope (Sym: CARDINAL; name: Name) ; FORWARD ;
PROCEDURE AddSymToUnknownTree (name: Name; Sym: CARDINAL) ; FORWARD ;
PROCEDURE AddVarToList (Sym: CARDINAL) ; FORWARD ;
PROCEDURE CheckEnumerationInList (l: List; Sym: CARDINAL) ; FORWARD ;
PROCEDURE CheckForEnumerationInOuterModule (Sym: CARDINAL;
                                            OuterModule: CARDINAL) ; FORWARD ;
PROCEDURE CheckForExportedDeclaration (Sym: CARDINAL) ; FORWARD ;
PROCEDURE CheckForHiddenType (TypeName: Name) : CARDINAL ; FORWARD ;
PROCEDURE CheckForUnknowns (name: Name; Tree: SymbolTree;
                            a: ARRAY OF CHAR) ; FORWARD ;
PROCEDURE CheckIfEnumerationExported (Sym: CARDINAL; ScopeId: CARDINAL) ; FORWARD ;
PROCEDURE CheckLegal (Sym: CARDINAL) ; FORWARD ;
PROCEDURE CheckScopeForSym (ScopeSym: CARDINAL; name: Name) : CARDINAL ; FORWARD ;
PROCEDURE DeclareSym (name: Name) : CARDINAL ; FORWARD ;
PROCEDURE DisplayScopes ; FORWARD ;
PROCEDURE DisplayTrees (ModSym: CARDINAL) ; FORWARD ;
PROCEDURE DisposeSym (Sym: CARDINAL) ; FORWARD ;
PROCEDURE ExamineUnresolvedTree (ModSym: CARDINAL; name: Name) : CARDINAL ; FORWARD ;
PROCEDURE FetchUnknownFromDefImp (ModSym: CARDINAL;
                                  SymName: Name) : CARDINAL ; FORWARD ;
PROCEDURE FetchUnknownFromModule (ModSym: CARDINAL;
                                  SymName: Name) : CARDINAL ; FORWARD ;
PROCEDURE FetchUnknownSym (name: Name) : CARDINAL ; FORWARD ;
PROCEDURE GetConstLitType (Sym: CARDINAL) : CARDINAL ; FORWARD ;
PROCEDURE GetCurrentModule () : CARDINAL ; FORWARD ;
PROCEDURE GetModuleScopeId (Id: CARDINAL) : CARDINAL ; FORWARD ;
PROCEDURE GetRecord (Sym: CARDINAL) : CARDINAL ; FORWARD ;
PROCEDURE GetScopeSym (name: Name) : CARDINAL ; FORWARD ;
PROCEDURE GetSymFromUnknownTree (name: Name) : CARDINAL ; FORWARD ;
PROCEDURE Init ; FORWARD ;
PROCEDURE InitSymTable ; FORWARD ;
PROCEDURE IsAlreadyDeclaredSym (name: Name) : BOOLEAN ; FORWARD ;
PROCEDURE IsNthParamVar (Head: List; n: CARDINAL) : BOOLEAN ; FORWARD ;
PROCEDURE NewSym (VAR Sym: CARDINAL) ; FORWARD ;
PROCEDURE PlaceEnumerationListOntoScope (l: List) ; FORWARD ;
PROCEDURE PlaceMajorScopesEnumerationListOntoStack (Sym: CARDINAL) ; FORWARD ;
PROCEDURE PushParamSize (Sym: CARDINAL; ParamNo: CARDINAL) ; FORWARD ;
PROCEDURE PushParamSize (Sym: CARDINAL; ParamNo: CARDINAL) ;   FORWARD ;
PROCEDURE PushSumOfLocalVarSize (Sym: CARDINAL) ; FORWARD ;
PROCEDURE PutExportUndeclared (ModSym: CARDINAL; Sym: CARDINAL) ; FORWARD ;
PROCEDURE PutHiddenTypeDeclared ; FORWARD ;
PROCEDURE PutTypeSize (Sym: CARDINAL; SizeBytes, SizeBits: CARDINAL) ; FORWARD ;
PROCEDURE PutVarTypeAndSize (Sym: CARDINAL; VarType: CARDINAL; TypeSize: CARDINAL) ; FORWARD ;
PROCEDURE RemoveExportUnImplemented (ModSym: CARDINAL; Sym: CARDINAL) ; FORWARD ;
PROCEDURE RemoveExportUndeclared (ModSym: CARDINAL; Sym: CARDINAL) ; FORWARD ;
PROCEDURE RequestFromDefinition (ModSym: CARDINAL; SymName: Name) : CARDINAL ; FORWARD ;
PROCEDURE RequestFromModule (ModSym: CARDINAL; SymName: Name) : CARDINAL ; FORWARD ;
PROCEDURE SubSymFromUnknownTree (name: Name) ; FORWARD ;
PROCEDURE TransparentScope (Sym: CARDINAL) : BOOLEAN ; FORWARD ;
PROCEDURE UnImplementedSymbolError (Sym: WORD) ; FORWARD ;
PROCEDURE UndeclaredSymbolError (Sym: WORD) ; FORWARD ;
PROCEDURE UnknownSymbolError (Sym: WORD) ; FORWARD ;
   %%%FORWARD%%% *)


(*
   InitWhereDeclared - sets the Declared and FirstUsed fields of record, at.
*)

PROCEDURE InitWhereDeclared (VAR at: Where) ;
BEGIN
   WITH at DO
      Declared := GetTokenNo() ;
      FirstUsed := Declared   (* we assign this field to something legal *)
   END
END InitWhereDeclared ;


(*
   InitWhereFirstUsed - sets the FirstUsed field of record, at.
*)

PROCEDURE InitWhereFirstUsed (VAR at: Where) ;
BEGIN
   WITH at DO
      FirstUsed := GetTokenNo()
   END
END InitWhereFirstUsed ;


(*
   FinalSymbol - returns the highest number symbol used.
*)

PROCEDURE FinalSymbol () : CARDINAL ;
BEGIN
   RETURN( FreeSymbol-1 )
END FinalSymbol ;


(*
   NewSym - Sets Sym to a new symbol index.
*)

PROCEDURE NewSym (VAR Sym: CARDINAL) ;
BEGIN
   IF FreeSymbol=MaxSymbols
   THEN
      InternalError('increase MaxSymbols', __FILE__, __LINE__)
   ELSE
      Sym := FreeSymbol ;
      Symbols[Sym].SymbolType := DummySym ;
      INC(FreeSymbol)
   END
END NewSym ;


(*
   DisposeSym - Places Sym onto the FreeSymbol list.
*)

PROCEDURE DisposeSym (Sym: CARDINAL) ;
BEGIN
   InternalError('DisposeSym - not really working yet??? check with Evaluate',
                __FILE__, __LINE__) ;
   HALT ;
   WITH Symbols[Sym] DO
      SymbolType := DummySym ;
      Dummy.NextFree := FreeSymbol
   END ;
   FreeSymbol := Sym
END DisposeSym ;


(*
   AlreadyDeclaredError - generate an error message, a, and two areas of code showing
                          the places where the symbols were declared.
*)

PROCEDURE AlreadyDeclaredError (s: String; name: Name; OtherOccurance: CARDINAL) ;
VAR
   e: Error ;
BEGIN
   IF (OtherOccurance=0) OR (OtherOccurance=GetTokenNo())
   THEN
      e := NewError(GetTokenNo()) ;
      ErrorString(e, s)
   ELSE
      e := NewError(GetTokenNo()) ;
      ErrorString(e, s) ;
      e := ChainError(OtherOccurance, e) ;
      ErrorFormat1(e, 'and symbol (%a) is also declared here', name)
   END
END AlreadyDeclaredError ;


(*
   DeclareSym - returns a symbol which was either in the unknown tree or
                a New symbol, since name is about to be declared.
*)

PROCEDURE DeclareSym (name: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   IF name=NulName
   THEN
      NewSym(Sym)
   ELSIF IsAlreadyDeclaredSym(name)
   THEN
      AlreadyDeclaredError(Sprintf1(Mark(InitString('symbol (%s) is already declared in this scope, use a different name or remove the declaration')), Mark(InitStringCharStar(KeyToCharStar(name)))), name,
                           GetDeclared(GetLocalSym(ScopeCallFrame[ScopePtr].Main, name)))
   ELSE
      Sym := FetchUnknownSym(name) ;
      IF Sym=NulSym
      THEN
         NewSym(Sym)
      END ;
      CheckForExportedDeclaration(Sym)
   END ;
   RETURN( Sym )
END DeclareSym ;


(*
   InitSymTable - initializes the symbol table.
*)

PROCEDURE InitSymTable ;
BEGIN
   FreeSymbol := 1
END InitSymTable ;


(*
   Init - Initializes the data structures and variables in this module.
          Initialize the trees.
*)

PROCEDURE Init ;
BEGIN
   CurrentError := NIL ;
   InitSymTable ;
   InitTree(ConstLitTree) ;
   InitTree(ConstLitStringTree) ;
   InitTree(DefModuleTree) ;
   InitTree(ModuleTree) ;
   ScopePtr := 1 ;
   WITH ScopeCallFrame[ScopePtr] DO
      Main := NulSym ;
      Search := NulSym
   END ;
   CurrentModule := NulSym ;
   MainModule    := NulSym ;
   FileModule    := NulSym ;
   TemporaryNo   := 0 ;
   InitBase(BaseModule) ;
   StartScope(BaseModule) ;   (* BaseModule scope placed at the bottom of the stack *)
   BaseScopePtr := ScopePtr   (* BaseScopePtr points to the top of the BaseModule scope *)
END Init ;


(*
   AddSymToUnknownTree - adds a symbol with name, name, and Sym to the
                         unknown tree.
*)

PROCEDURE AddSymToUnknownTree (name: Name; Sym: CARDINAL) ;
BEGIN
   (* Add symbol to unknown tree *)
   WITH Symbols[CurrentModule] DO
      CASE SymbolType OF

      DefImpSym: PutSymKey(DefImp.Unresolved, name, Sym) |
      ModuleSym: PutSymKey(Module.Unresolved, name, Sym)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END AddSymToUnknownTree ;


(*
   SubSymFromUnknownTree - removes a symbol with name, name, from the
                           unknown tree.
*)

PROCEDURE SubSymFromUnknownTree (name: Name) ;
BEGIN
   (* Delete symbol from unknown tree *)
   WITH Symbols[CurrentModule] DO
      CASE SymbolType OF

      DefImpSym: DelSymKey(DefImp.Unresolved, name) |
      ModuleSym: DelSymKey(Module.Unresolved, name)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END SubSymFromUnknownTree ;


(*
   GetSymFromUnknownTree - returns a symbol with name, name, from the
                           unknown tree.
                           If no symbol with name is found then NulSym
                           is returned.
*)

PROCEDURE GetSymFromUnknownTree (name: Name) : CARDINAL ;
BEGIN
   (* Get symbol from unknown tree *)
   RETURN( ExamineUnresolvedTree(CurrentModule, name) )
END GetSymFromUnknownTree ;


(*
   ExamineUnresolvedTree - returns a symbol with name, name, from the
                           unresolved tree of module, ModSym.
                           If no symbol with name is found then NulSym
                           is returned.
*)

PROCEDURE ExamineUnresolvedTree (ModSym: CARDINAL; name: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   (* Get symbol from unknown tree *)
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: Sym := GetSymKey(DefImp.Unresolved, name) |
      ModuleSym: Sym := GetSymKey(Module.Unresolved, name)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END ExamineUnresolvedTree ;


(*
   FetchUnknownSym - returns a symbol from the unknown tree if one is
                     available. It also updates the unknown tree.
*)

PROCEDURE FetchUnknownSym (name: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := GetSymFromUnknownTree(name) ;
   IF Sym#NulSym
   THEN
      (* Such a symbol does exist, therefore must unhook it from the *)
      (* dependancies. Checking that the scopes where the symbol is  *)
      (* expected can see this declaration.                          *)
(*
      WriteKey(name) ; WriteString(' being resolved') ; WriteCard(Sym, 4) ;
      WriteLn ;
*)
      SubSymFromUnknownTree(name) ;
(*
      ; WriteKey(name) ; WriteString(' is now') ; WriteCard(Sym, 4) ; WriteLn ;
*)
   END ;
   RETURN( Sym )
END FetchUnknownSym ;


(*
   TransparentScope - returns true is the scope symbol Sym is allowed
                      to look to an outer level for a symbol.
                      ie is the symbol allowed to look to the parent
                      scope for a symbol.
*)

PROCEDURE TransparentScope (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( (SymbolType#DefImpSym) AND (SymbolType#ModuleSym) )
   END
END TransparentScope ;


(*
   AddSymToModuleScope - adds a symbol, Sym, to the scope of the module
                         ModSym.
*)

PROCEDURE AddSymToModuleScope (ModSym: CARDINAL; Sym: CARDINAL) ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym   : IF GetSymKey(DefImp.LocalSymbols, GetSymName(Sym))=NulKey
                    THEN
                       PutSymKey(DefImp.LocalSymbols, GetSymName(Sym), Sym)
                    ELSE
                       WriteFormat1('IMPORT name clash with symbol (%a) symbol already declared ', GetSymName(Sym))
                    END |
      ModuleSym   : IF GetSymKey(Module.LocalSymbols, GetSymName(Sym))=NulKey
                    THEN
                       PutSymKey(Module.LocalSymbols, GetSymName(Sym), Sym)
                    ELSE
                       WriteFormat1('IMPORT name clash with symbol (%a) symbol already declared ', GetSymName(Sym))
                    END

      ELSE
         InternalError('expecting Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END AddSymToModuleScope ;


(*
   GetCurrentModuleScope - returns the module symbol which forms the
                           current (possibly inner most) module.
*)

PROCEDURE GetCurrentModuleScope () : CARDINAL ;
VAR
   i  : CARDINAL ;
BEGIN
   i := ScopePtr ;
   WHILE (NOT IsModule(ScopeCallFrame[i].Search)) AND
         (NOT IsDefImp(ScopeCallFrame[i].Search)) DO
      Assert(i>0) ;
      DEC(i)
   END ;
   RETURN( ScopeCallFrame[i].Search )
END GetCurrentModuleScope ;


(*
   GetLastModuleScope - returns the last module scope encountered,
                        the module scope before the Current Module Scope.
*)

PROCEDURE GetLastModuleScope () : CARDINAL ;
VAR
   i  : CARDINAL ;
BEGIN
   i := ScopePtr ;
   WHILE (NOT IsModule(ScopeCallFrame[i].Search)) AND
         (NOT IsDefImp(ScopeCallFrame[i].Search)) DO
      Assert(i>0) ;
      DEC(i)
   END ;
   (* Found module at position, i. *)
   DEC(i) ;  (* Move to an outer level module scope *)
   WHILE (NOT IsModule(ScopeCallFrame[i].Search)) AND
         (NOT IsDefImp(ScopeCallFrame[i].Search)) DO
      Assert(i>0) ;
      DEC(i)
   END ;
   (* Found module at position, i. *)
   RETURN( ScopeCallFrame[i].Search )
END GetLastModuleScope ;


(*
   AddSymToScope - adds a symbol Sym with name name to
                   the current scope symbol tree.
*)

PROCEDURE AddSymToScope (Sym: CARDINAL; name: Name) ;
VAR
   ScopeId: CARDINAL ;
BEGIN
   ScopeId := ScopeCallFrame[ScopePtr].Main ;
   (*
      WriteString('Adding ') ; WriteKey(name) ; WriteString(' :') ; WriteCard(Sym, 4) ; WriteString(' to scope: ') ;
      WriteKey(GetSymName(ScopeId)) ; WriteLn ;
   *)
   WITH Symbols[ScopeId] DO
      CASE SymbolType OF

      DefImpSym   : IF name#NulName
                    THEN
                       PutSymKey(DefImp.LocalSymbols, name, Sym)
                    END ;
                    IF IsEnumeration(Sym)
                    THEN
                       CheckEnumerationInList(DefImp.EnumerationScopeList, Sym)
                    END |
      ModuleSym   : IF name#NulName
                    THEN
                       PutSymKey(Module.LocalSymbols, name, Sym)
                    END ;
                    IF IsEnumeration(Sym)
                    THEN
                       CheckEnumerationInList(Module.EnumerationScopeList, Sym)
                    END |
      ProcedureSym: IF name#NulName
                    THEN
                       PutSymKey(Procedure.LocalSymbols, name, Sym)
                    END ;
                    IF IsEnumeration(Sym)
                    THEN
                       CheckEnumerationInList(Procedure.EnumerationScopeList, Sym)
                    END

      ELSE
         InternalError('Should never get here', __FILE__, __LINE__)
      END
   END
END AddSymToScope ;


(*
   GetCurrentScope - returns the symbol who is responsible for the current
                     scope. Note that it ignore pseudo scopes.
*)

PROCEDURE GetCurrentScope () : CARDINAL ;
BEGIN
   RETURN( ScopeCallFrame[ScopePtr].Main )
END GetCurrentScope ;


(*
   StartScope - starts a block scope at Sym. Transparent determines
                whether the search for a symbol will look at the
                previous ScopeCallFrame if Sym does not contain the
                symbol that GetSym is searching.

                WITH statements are partially implemented by calling
                StartScope. Therefore we must retain the old Main from
                the previous ScopePtr when a record is added to the scope
                stack. (Main contains the symbol where all identifiers
                should be added.)
*)

PROCEDURE StartScope (Sym: CARDINAL) ;
BEGIN
   IF ScopePtr=MaxScopes
   THEN
      InternalError('too many scopes - increase MaxScopes', __FILE__, __LINE__)
   ELSE
(*
      WriteString('New scope is: ') ; WriteKey(GetSymName(Sym)) ; WriteLn ;
*)
      INC(ScopePtr) ;
      WITH ScopeCallFrame[ScopePtr] DO
         Start := ScopePtr-1 ;  (* Previous ScopePtr value before StartScope *)
         Search := Sym ;

         (* If Sym is a record then maintain the old Main scope for adding   *)
         (* new symbols to ie temporary variables.                           *)
         IF IsRecord(Sym)
         THEN
            Main := ScopeCallFrame[ScopePtr-1].Main
         ELSE
            Main := Sym ;
            PlaceMajorScopesEnumerationListOntoStack(Sym)
         END
      END
   END
   (* ; DisplayScopes *)
END StartScope ;


(*
   PlaceMajorScopesEnumerationListOntoStack - places the DefImp, Module and
                                              Procedure symbols enumeration
                                              list onto the scope stack.
*)

PROCEDURE PlaceMajorScopesEnumerationListOntoStack (Sym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym   : PlaceEnumerationListOntoScope(DefImp.EnumerationScopeList) |
      ModuleSym   : PlaceEnumerationListOntoScope(Module.EnumerationScopeList) |
      ProcedureSym: PlaceEnumerationListOntoScope(Procedure.EnumerationScopeList)

      ELSE
         InternalError('expecting - DefImp, Module or Procedure symbol', __FILE__, __LINE__)
      END
   END
END PlaceMajorScopesEnumerationListOntoStack ;


(*
   PlaceEnumerationListOntoScope - places an enumeration list, l, onto the
                                   scope stack. This list will automatically
                                   removed via one call to EndScope which
                                   matches the StartScope by which this
                                   procedure is invoked.
*)

PROCEDURE PlaceEnumerationListOntoScope (l: List) ;
VAR
   i, n: CARDINAL ;
BEGIN
   n := NoOfItemsInList(l) ;
   i := 1 ;
   WHILE i<=n DO
      PseudoScope(GetItemFromList(l, i)) ;
      INC(i)
   END
END PlaceEnumerationListOntoScope ;


(*
   EndScope - ends a block scope started by StartScope. The current
              head of the symbol scope reverts back to the symbol
              which was the Head of the symbol scope before the
              last StartScope was called.
*)

PROCEDURE EndScope ;
BEGIN
(*
   ; WriteString('EndScope - ending scope: ') ;
   ; WriteKey(GetSymName(ScopeCallFrame[ScopePtr].Search)) ; WriteLn ;
*)
   ScopePtr := ScopeCallFrame[ScopePtr].Start
   (* ; DisplayScopes *)
END EndScope ;


(*
   PseudoScope - starts a pseudo scope at Sym.
                 We always connect parent up to the last scope,
                 to determine the transparancy of a scope we call
                 TransparentScope.

                 A Pseudo scope has no end block,
                 but is terminated when the next EndScope is used.
                 The function of the pseudo scope is to provide an
                 automatic mechanism to solve enumeration types.
                 A declared enumeration type is a Pseudo scope and
                 identifiers used with the name of an enumeration
                 type field will find the enumeration symbol by
                 the scoping algorithm.
*)

PROCEDURE PseudoScope (Sym: CARDINAL) ;
BEGIN
   IF IsEnumeration(Sym)
   THEN
      IF ScopePtr<MaxScopes
      THEN
         INC(ScopePtr) ;
         WITH ScopeCallFrame[ScopePtr] DO
            Main := ScopeCallFrame[ScopePtr-1].Main ;
            Start := ScopeCallFrame[ScopePtr-1].Start ;
            Search := Sym
         END
      ELSE
         InternalError('increase MaxScopes', __FILE__, __LINE__)
      END
   ELSE
      InternalError('expecting EnumerationSym', __FILE__, __LINE__)
   END
END PseudoScope ;


(*
   GetScopeAuthor - returns the symbol where symbol, Sym, was declared.
                    The declared scope will be the first non transparent
                    scope. So enumeration fields will return the procedure,
                    module, or defimp where it was created.
*)

PROCEDURE GetScopeAuthor (Sym: CARDINAL) : CARDINAL ;
BEGIN
   IF IsDefImp(Sym)
   THEN
      RETURN( NulSym )
   END ;
   Sym := Father(Sym) ;
   IF Sym=NulSym
   THEN
      (* base scope *)
      RETURN( NulSym )
   ELSE
      WITH Symbols[Sym] DO
         CASE SymbolType OF

         DefImpSym   : RETURN( Sym ) |
         ModuleSym   : RETURN( Sym ) |
         ProcedureSym: RETURN( Sym )

         ELSE
            RETURN( GetScopeAuthor(Sym) )
         END
      END
   END
END GetScopeAuthor ;


(*
   MakeGnuAsm - create a GnuAsm symbol.
*)

PROCEDURE MakeGnuAsm () : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := GnuAsmSym ;
      WITH GnuAsm DO
         String   := NulSym ;
         InitWhereDeclared(At) ;
         Inputs   := NulSym ;
         Outputs  := NulSym ;
         Trashed  := NulSym ;
         Volatile := FALSE
      END
   END ;
   RETURN( Sym )
END MakeGnuAsm ;


(*
   PutGnuAsm - places the instruction textual name into the GnuAsm symbol.
*)

PROCEDURE PutGnuAsm (sym: CARDINAL; string: CARDINAL) ;
BEGIN
   Assert(IsConstString(string)) ;
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: GnuAsm.String := string

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END PutGnuAsm ;


(*
   GetGnuAsm - returns the string symbol, representing the instruction textual
               of the GnuAsm symbol. It will return a ConstString.
*)

PROCEDURE GetGnuAsm (sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: RETURN( GnuAsm.String )

      ELSE
         InternalError('expecting GnuAsm symbol', __FILE__, __LINE__)
      END
   END
END GetGnuAsm ;


(*
   PutGnuAsmOutput - places the interface object, out, into GnuAsm symbol, sym.
*)

PROCEDURE PutGnuAsmOutput (sym: CARDINAL; out: CARDINAL) ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: GnuAsm.Outputs := out

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END PutGnuAsmOutput ;


(*
   PutGnuAsmInput - places the interface object, in, into GnuAsm symbol, sym.
*)

PROCEDURE PutGnuAsmInput (sym: CARDINAL; in: CARDINAL) ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: GnuAsm.Inputs := in

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END PutGnuAsmInput ;


(*
   PutGnuAsmTrash - places the interface object, trash, into GnuAsm symbol, sym.
*)

PROCEDURE PutGnuAsmTrash (sym: CARDINAL; trash: CARDINAL) ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: GnuAsm.Trashed := trash

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END PutGnuAsmTrash ;


(*
   GetGnuAsmInput - returns the input list of registers.
*)

PROCEDURE GetGnuAsmInput (sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: RETURN( GnuAsm.Inputs )

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END GetGnuAsmInput ;


(*
   GetGnuAsmOutput - returns the output list of registers.
*)

PROCEDURE GetGnuAsmOutput (sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: RETURN( GnuAsm.Outputs )

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END GetGnuAsmOutput ;


(*
   GetGnuAsmTrash - returns the list of trashed registers.
*)

PROCEDURE GetGnuAsmTrash (sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      GnuAsmSym: RETURN( GnuAsm.Trashed )

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END GetGnuAsmTrash ;


(*
   PutGnuAsmVolatile - defines a GnuAsm symbol as VOLATILE.
*)

PROCEDURE PutGnuAsmVolatile (Sym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      GnuAsmSym: GnuAsm.Volatile := TRUE

      ELSE
         InternalError('expecting GnuAsm symbol', __FILE__, __LINE__)
      END
   END
END PutGnuAsmVolatile ;


(*
   MakeRegInterface - creates and returns a register interface symbol.
*)

PROCEDURE MakeRegInterface () : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := InterfaceSym ;
      WITH Interface DO
         InitList(StringList) ;
         InitList(ObjectList) ;
         InitWhereDeclared(At)
      END
   END ;
   RETURN( Sym )
END MakeRegInterface ;


(*
   PutRegInterface - places a, string, and, object, into the interface list, sym.
                     The string symbol will either be a register name or a constraint.
                     The object is an optional Modula-2 variable or constant symbol.
*)

PROCEDURE PutRegInterface (sym: CARDINAL; string, object: CARDINAL) ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      InterfaceSym: PutItemIntoList(Interface.StringList, string) ;
                    PutItemIntoList(Interface.ObjectList, object)

      ELSE
         InternalError('expecting Interface symbol', __FILE__, __LINE__)
      END
   END
END PutRegInterface ;


(*
   GetRegInterface - gets a, string, and, object, from the interface list, sym.
*)

PROCEDURE GetRegInterface (sym: CARDINAL; n: CARDINAL; VAR string, object: CARDINAL) ;
BEGIN
   WITH Symbols[sym] DO
      CASE SymbolType OF

      InterfaceSym: string := GetItemFromList(Interface.StringList, n) ;
                    object := GetItemFromList(Interface.ObjectList, n)

      ELSE
         InternalError('expecting Interface symbol', __FILE__, __LINE__)
      END
   END
END GetRegInterface ;


(*
   GetSubrange - returns HighSym and LowSym - two constants which make up the
                 subrange.
*)

PROCEDURE GetSubrange (Sym: CARDINAL; VAR HighSym, LowSym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      SubrangeSym: HighSym := Subrange.High ;
                   LowSym := Subrange.Low

      ELSE
         InternalError('expecting Subrange symbol', __FILE__, __LINE__)
      END
   END
END GetSubrange ;


(*
   PutSubrange - places LowSym and HighSym as two symbols
                 which provide the limits of the range.
*)

PROCEDURE PutSubrange (Sym: CARDINAL; LowSym, HighSym: CARDINAL;
                       TypeSymbol: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      SubrangeSym:  Subrange.Low := LowSym ;      (* Index to symbol for lower   *)
                    Subrange.High := HighSym ;    (* Index to symbol for higher  *)
                    Subrange.Type := TypeSymbol ; (* Index to type symbol for    *)
                                                  (* the type of subrange.       *)
      ELSE
         InternalError('expecting Subrange symbol', __FILE__, __LINE__)
      END
   END
END PutSubrange ;


(*
   SetCurrentModule - Used to set the CurrentModule to a symbol, Sym.
                      This Sym must represent the module name of the
                      file currently being compiled.
*)

PROCEDURE SetCurrentModule (Sym: CARDINAL) ;
BEGIN
   CurrentModule := Sym
END SetCurrentModule ;


(*
   GetCurrentModule - returns the current module Sym that is being
                      compiled.
*)

PROCEDURE GetCurrentModule () : CARDINAL ;
BEGIN
   RETURN( CurrentModule )
END GetCurrentModule ;


(*
   SetMainModule - Used to set the MainModule to a symbol, Sym.
                   This Sym must represent the main module which was
                   envoked by the user to be compiled.
*)

PROCEDURE SetMainModule (Sym: CARDINAL) ;
BEGIN
   MainModule := Sym
END SetMainModule ;


(*
   GetMainModule - returns the main module symbol that was requested by
                   the user to be compiled.
*) 
 
PROCEDURE GetMainModule () : CARDINAL ; 
BEGIN
   RETURN( MainModule )
END GetMainModule ;


(*
   SetFileModule - Used to set the FileModule to a symbol, Sym.
                   This Sym must represent the current program module
                   file which is being parsed.
*)

PROCEDURE SetFileModule (Sym: CARDINAL) ;
BEGIN
   FileModule := Sym
END SetFileModule ;


(*
   GetFileModule - returns the FileModule symbol that was requested by
                   the user to be compiled.
*) 
 
PROCEDURE GetFileModule () : CARDINAL ; 
BEGIN
   RETURN( FileModule )
END GetFileModule ;


(*
   GetBaseModule - returns the base module symbol that contains Modula-2
                   base types, procedures and functions.
*) 
 
PROCEDURE GetBaseModule () : CARDINAL ; 
BEGIN
   RETURN( BaseModule )
END GetBaseModule ;


(*
   GetSym - searches the current scope (and previous scopes if the
            scope tranparent allows) for a symbol with name.
*)

PROCEDURE GetSym (name: Name) : CARDINAL ;
VAR
   Sym        : CARDINAL ;
   OldScopePtr: CARDINAL ;
BEGIN
   Sym := GetScopeSym(name) ;
   IF Sym=NulSym
   THEN
      (* Check default base types for symbol *)
      OldScopePtr := ScopePtr ;  (* Save ScopePtr *)
      ScopePtr := BaseScopePtr ; (* Alter ScopePtr to point to top of BaseModule *)
      Sym := GetScopeSym(name) ; (* Search BaseModule for name *)
      ScopePtr := OldScopePtr    (* Restored ScopePtr *)
   END ;
   RETURN( Sym )
END GetSym ;


(*
   GetScopeSym - searches the current scope and below, providing that the
                 scopes are transparent, for a symbol with name, name.
*)

PROCEDURE GetScopeSym (name: Name) : CARDINAL ;
VAR
   ScopeSym,
   ScopeId ,
   Sym     : CARDINAL ;
BEGIN
   (* DisplayScopes ; *)
   ScopeId := ScopePtr ;
   ScopeSym := ScopeCallFrame[ScopeId].Search ;
   (* WriteString(' scope: ') ; WriteKey(GetSymName(ScopeSym)) ; *)
   Sym := CheckScopeForSym(ScopeSym, name) ;
   WHILE (ScopeId>0) AND (Sym=NulSym) AND TransparentScope(ScopeSym) DO
      DEC(ScopeId) ;
      ScopeSym := ScopeCallFrame[ScopeId].Search ;
      Sym := CheckScopeForSym(ScopeSym, name) ;
      (* WriteString(' scope: ') ; WriteKey(GetSymName(ScopeSym)) *)
   END ;
   (* IF Sym#NulSym THEN WriteKey(GetSymName(Sym)) END ; WriteLn ; *)
   RETURN( Sym )
END GetScopeSym ;


(*
   CheckScopeForSym - checks the scope, ScopeSym, for an identifier
                      of name, name. CheckScopeForSym checks for
                      the symbol by the GetLocalSym and also
                      ExamineUnresolvedTree.
*)

PROCEDURE CheckScopeForSym (ScopeSym: CARDINAL; name: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := GetLocalSym(ScopeSym, name) ;
   IF (Sym=NulSym) AND (IsModule(ScopeSym) OR IsDefImp(ScopeSym))
   THEN
      Sym := ExamineUnresolvedTree(ScopeSym, name)
   END ;
   RETURN( Sym )
END CheckScopeForSym ;


(*
   DisplayScopes - displays the scopes that will be searched to find
                   a requested symbol.
*)

PROCEDURE DisplayScopes ;
VAR
   i  : CARDINAL ;
   Sym: CARDINAL ;
BEGIN
   i := ScopePtr ;
   printf0('Displaying scopes\n') ;
   WHILE i>=1 DO
      Sym := ScopeCallFrame[i].Search ;
      printf1('Symbol %4d', Sym) ;
      IF Sym#NulSym
      THEN
         printf1(' : name %a is ', GetSymName(Sym)) ;
         IF NOT TransparentScope(Sym)
         THEN
            printf0('not')
         END ;
         printf0(' transparent\n')
      END ;
      DEC(i)
   END ;
   printf0('\n')
END DisplayScopes ;


(*
   GetModuleScopeId - returns the scope index to the next module starting
                      at index, Id.
                      Id will either point to a null scope (NulSym) or
                      alternatively point to a Module or DefImp symbol.
*)

PROCEDURE GetModuleScopeId (Id: CARDINAL) : CARDINAL ;
VAR
   s: CARDINAL ;  (* Substitute s for ScopeCallFrame[Id], when we have better compiler! *)
BEGIN
   s := ScopeCallFrame[Id].Search ;
   WHILE (Id>0) AND (s#NulSym) AND
         ((NOT IsModule(s)) AND
          (NOT IsDefImp(s))) DO
      DEC(Id) ;
      s := ScopeCallFrame[Id].Search ;
   END ;
   RETURN( Id )
END GetModuleScopeId ;


(*
   IsAlreadyDeclaredSym - returns true if Sym has already been declared
                          in the current main scope.
*)

PROCEDURE IsAlreadyDeclaredSym (name: Name) : BOOLEAN ;
BEGIN
   WITH ScopeCallFrame[ScopePtr] DO
      RETURN( GetLocalSym(ScopeCallFrame[ScopePtr].Main, name)#NulSym )
   END
END IsAlreadyDeclaredSym ;


(*
   MakeModule - creates a module sym with ModuleName. It returns the
                symbol index.
*)

PROCEDURE MakeModule (ModuleName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   (*
      Make a new symbol since we are at the outer scope level.
      DeclareSym examines the current scope level for any symbols
      that have the correct name, but are yet undefined.
      Therefore we must not call DeclareSym but create a symbol
      directly.
   *)
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := ModuleSym ;
      WITH Module DO
         name := ModuleName ;               (* Index into name array, name   *)
                                            (* of record field.              *)
         Size := InitValue() ;              (* Runtime size of symbol.       *)
         Offset := InitValue() ;            (* Offset at runtime of symbol   *)
         InitTree(LocalSymbols) ;           (* The LocalSymbols hold all the *)
                                            (* variables declared local to   *)
                                            (* the block. It contains the    *)
                                            (* FROM _ IMPORT x, y, x ;       *)
                                            (* IMPORT A ;                    *)
                                            (*    and also                   *)
                                            (* MODULE WeAreHere ;            *)
                                            (*    x y z visiable by localsym *)
                                            (*    MODULE Inner ;             *)
                                            (*       EXPORT x, y, z ;        *)
                                            (*    END Inner ;                *)
                                            (* END WeAreHere.                *)
         InitTree(ExportTree) ;             (* Holds all the exported        *)
                                            (* identifiers.                  *)
                                            (* This tree may be              *)
                                            (* deleted at the end of Pass 1. *)
         InitTree(ImportTree) ;             (* Contains all IMPORTed         *)
                                            (* identifiers.                  *)
         InitList(IncludeList) ;            (* Contains all included symbols *)
                                            (* which are included by         *)
                                            (* IMPORT modulename ;           *)
                                            (* modulename.Symbol             *)
         InitTree(ExportUndeclared) ;       (* ExportUndeclared contains all *)
                                            (* the identifiers which were    *)
                                            (* exported but have not yet     *)
                                            (* been declared.                *)
         InitList(EnumerationScopeList) ;   (* Enumeration scope list which  *)
                                            (* contains a list of all        *)
                                            (* enumerations which are        *)
                                            (* visable within this scope.    *)
                                            (* Outer Module.                 *)
         Priority := NulSym ;               (* Priority of the module. This  *)
                                            (* is an index to a constant.    *)
         InitTree(Unresolved) ;             (* All symbols currently         *)
                                            (* unresolved in this module.    *)
         StartQuad := 0 ;                   (* Signify the initialization    *)
                                            (* code.                         *)
         EndQuad := 0 ;                     (* EndQuad should point to a     *)
                                            (* goto quad.                    *)
         InitList(ListOfVars) ;             (* List of variables in this     *)
                                            (* scope.                        *)
         InitList(ListOfProcs) ;            (* List of all procedures        *)
                                            (* declared within this module.  *)
         InitList(ListOfModules) ;          (* List of all inner modules.    *)
         InitWhereDeclared(At) ;            (* Where symbol declared.        *)
         InitWhereFirstUsed(At) ;           (* Where symbol first used.      *)
         IF ScopeCallFrame[ScopePtr].Main=GetBaseModule()
         THEN
            Father := NulSym
         ELSE
            Father := ScopeCallFrame[ScopePtr].Main
         END
      END
   END ;
   PutSymKey(ModuleTree, ModuleName, Sym) ;
   RETURN( Sym )
END MakeModule ;


(*
   AddModuleToParent - adds symbol, Sym, to module, Father.
*)

PROCEDURE AddModuleToParent (Sym: CARDINAL; Father: CARDINAL) ;
BEGIN
   WITH Symbols[Father] DO
      CASE SymbolType OF

      DefImpSym:  PutItemIntoList(DefImp.ListOfModules, Sym) |
      ModuleSym:  PutItemIntoList(Module.ListOfModules, Sym)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END AddModuleToParent ;


(*
   MakeInnerModule - creates an inner module sym with ModuleName. It returns the
                     symbol index.
*)

PROCEDURE MakeInnerModule (ModuleName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(ModuleName) ;
   WITH Symbols[Sym] DO
      SymbolType := ModuleSym ;
      WITH Module DO
         name := ModuleName ;               (* Index into name array, name   *)
                                            (* of record field.              *)
         Size := InitValue() ;              (* Runtime size of symbol.       *)
         Offset := InitValue() ;            (* Offset at runtime of symbol   *)
         InitTree(LocalSymbols) ;           (* The LocalSymbols hold all the *)
                                            (* variables declared local to   *)
                                            (* the block. It contains the    *)
                                            (* FROM _ IMPORT x, y, x ;       *)
                                            (* IMPORT A ;                    *)
                                            (*    and also                   *)
                                            (* MODULE WeAreHere ;            *)
                                            (*    x y z visiable by localsym *)
                                            (*    MODULE Inner ;             *)
                                            (*       EXPORT x, y, z ;        *)
                                            (*    END Inner ;                *)
                                            (* END WeAreHere.                *)
         InitTree(ExportTree) ;             (* Holds all the exported        *)
                                            (* identifiers.                  *)
                                            (* This tree may be              *)
                                            (* deleted at the end of Pass 1. *)
         InitTree(ImportTree) ;             (* Contains all IMPORTed         *)
                                            (* identifiers.                  *)
         InitList(IncludeList) ;            (* Contains all included symbols *)
                                            (* which are included by         *)
                                            (* IMPORT modulename ;           *)
                                            (* modulename.Symbol             *)
         InitTree(ExportUndeclared) ;       (* ExportUndeclared contains all *)
                                            (* the identifiers which were    *)
                                            (* exported but have not yet     *)
                                            (* been declared.                *)
         InitList(EnumerationScopeList) ;   (* Enumeration scope list which  *)
                                            (* contains a list of all        *)
                                            (* enumerations which are        *)
                                            (* visable within this scope.    *)
         Priority := NulSym ;               (* Priority of the module. This  *)
                                            (* is an index to a constant.    *)
         InitTree(Unresolved) ;             (* All symbols currently         *)
                                            (* unresolved in this module.    *)
         StartQuad := 0 ;                   (* Signify the initialization    *)
                                            (* code.                         *)
         EndQuad := 0 ;                     (* EndQuad should point to a     *)
                                            (* goto quad.                    *)
         InitList(ListOfVars) ;             (* List of variables in this     *)
                                            (* scope.                        *)
         InitList(ListOfProcs) ;            (* List of all procedures        *)
                                            (* declared within this module.  *)
         InitList(ListOfModules) ;          (* List of all inner modules.    *)
         InitWhereDeclared(At) ;            (* Where symbol declared.        *)
         InitWhereFirstUsed(At) ;           (* Where symbol first used.      *)
         IF ScopeCallFrame[ScopePtr].Main=GetBaseModule()
         THEN
            Father := NulSym
         ELSE
            Father := ScopeCallFrame[ScopePtr].Main ;
            AddModuleToParent(Sym, Father)
         END
      END ;
   END ;
   PutSymKey(ModuleTree, ModuleName, Sym) ;
   (* Now add module to the outer level scope *)
   AddSymToScope(Sym, ModuleName) ;
   RETURN( Sym )
END MakeInnerModule ;


(*
   MakeDefImp - creates a definition and implementation module sym
                with name DefImpName. It returns the symbol index.
*)

PROCEDURE MakeDefImp (DefImpName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   (*
      Make a new symbol since we are at the outer scope level.
      DeclareSym examines the current scope level for any symbols
      that have the correct name, but are yet undefined.
      Therefore we must not call DeclareSym but create a symbol
      directly.
   *)
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := DefImpSym ;
      WITH DefImp DO
         name := DefImpName ;         (* Index into name array, name   *)
                                      (* of record field.              *)
         Type := NulSym ;             (* Index to a type symbol.       *)
         Size := InitValue() ;        (* Runtime size of symbol.       *)
         Offset := InitValue() ;      (* Offset at runtime of symbol   *)
         InitTree(ExportQualifiedTree) ;
                                      (* Holds all the EXPORT          *)
                                      (* QUALIFIED identifiers.        *)
                                      (* This tree may be              *)
                                      (* deleted at the end of Pass 1. *)
         InitTree(ExportUnQualifiedTree) ;
                                      (* Holds all the EXPORT          *)
                                      (* UNQUALIFIED identifiers.      *)
                                      (* This tree may be              *)
                                      (* deleted at the end of Pass 1. *)
         InitTree(ExportRequest) ;    (* Contains all identifiers that *)
                                      (* have been requested by other  *)
                                      (* modules before this module    *)
                                      (* declared its export list.     *)
                                      (* This tree should be empty at  *)
                                      (* the end of the compilation.   *)
                                      (* Each time a symbol is         *)
                                      (* exported it is removed from   *)
                                      (* this list.                    *)
         InitTree(ImportTree) ;       (* Contains all IMPORTed         *)
                                      (* identifiers.                  *)
         InitList(IncludeList) ;      (* Contains all included symbols *)
                                      (* which are included by         *)
                                      (* IMPORT modulename ;           *)
                                      (* modulename.Symbol             *)
         InitTree(ExportUndeclared) ; (* ExportUndeclared contains all *)
                                      (* the identifiers which were    *)
                                      (* exported but have not yet     *)
                                      (* been declared.                *)
         InitTree(NeedToBeImplemented) ;
                                      (* NeedToBeImplemented contains  *)
                                      (* the identifiers which have    *)
                                      (* been exported and declared    *)
                                      (* but have not yet been         *)
                                      (* implemented.                  *)
         InitTree(LocalSymbols) ;     (* The LocalSymbols hold all the *)
                                      (* variables declared local to   *)
                                      (* the block. It contains the    *)
                                      (* IMPORT r ;                    *)
                                      (* FROM _ IMPORT x, y, x ;       *)
                                      (*    and also                   *)
                                      (* MODULE WeAreHere ;            *)
                                      (*    x y z visiable by localsym *)
                                      (*    MODULE Inner ;             *)
                                      (*       EXPORT x, y, z ;        *)
                                      (*    END Inner ;                *)
                                      (* END WeAreHere.                *)
         InitList(EnumerationScopeList) ;
                                      (* Enumeration scope list which  *)
                                      (* contains a list of all        *)
                                      (* enumerations which are        *)
                                      (* visable within this scope.    *)
         Priority := NulSym ;         (* Priority of the module. This  *)
                                      (* is an index to a constant.    *)
         InitTree(Unresolved) ;       (* All symbols currently         *)
                                      (* unresolved in this module.    *)
         StartQuad := 0 ;             (* Signify the initialization    *)
                                      (* code.                         *)
         EndQuad := 0 ;               (* EndQuad should point to a     *)
                                      (* goto quad.                    *)
         ContainsHiddenType := FALSE ;(* True if this module           *)
                                      (* implements a hidden type.     *)
         InitList(ListOfVars) ;       (* List of variables in this     *)
                                      (* scope.                        *)
         InitList(ListOfProcs) ;      (* List of all procedures        *)
                                      (* declared within this module.  *)
         InitList(ListOfModules) ;    (* List of all inner modules.    *)
         InitWhereDeclared(At) ;      (* Where symbol declared.        *)
         InitWhereFirstUsed(At) ;     (* Where symbol first used.      *)
      END
   END ;
   PutSymKey(ModuleTree, DefImpName, Sym) ;
   RETURN( Sym )
END MakeDefImp ;


(*
   MakeProcedure - creates a procedure sym with name. It returns
                   the symbol index.
*)

PROCEDURE MakeProcedure (ProcedureName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(ProcedureName) ;
   WITH Symbols[Sym] DO
      SymbolType := ProcedureSym ;
      WITH Procedure DO
         name := ProcedureName ;
         InitList(ListOfParam) ;      (* Contains a list of all the    *)
                                      (* parameters in this procedure. *)
         ParamDefined := FALSE ;      (* Have the parameters been      *)
                                      (* defined yet?                  *)
         DefinedInDef := FALSE ;      (* Were the parameters defined   *)
                                      (* in the Definition module?     *)
                                      (* Note that this depends on     *)
                                      (* whether the compiler has read *)
                                      (* the .def or .mod first.       *)
                                      (* The second occurence is       *)
                                      (* compared to the first.        *)
         DefinedInImp := FALSE ;      (* Were the parameters defined   *)
                                      (* in the Implementation module? *)
                                      (* Note that this depends on     *)
                                      (* whether the compiler has read *)
                                      (* the .def or .mod first.       *)
                                      (* The second occurence is       *)
                                      (* compared to the first.        *)
         Father := GetCurrentScope() ;
                                      (* Father scope of procedure.    *)
         StartQuad := 0 ;             (* Index into list of quads.     *)
         EndQuad := 0 ;
         Reachable := FALSE ;         (* Procedure not known to        *)
                                      (* reachable.                    *)
         ReturnType := NulSym ;       (* Not a function yet!           *)
         Offset := 0 ;                (* Location of procedure.        *)
         InitTree(LocalSymbols) ;
         InitList(EnumerationScopeList) ;
                                      (* Enumeration scope list which  *)
                                      (* contains a list of all        *)
                                      (* enumerations which are        *)
                                      (* visable within this scope.    *)
         InitList(ListOfVars) ;       (* List of variables in this     *)
                                      (* scope.                        *)
         Size := InitValue() ;        (* Activation record size.       *)
         TotalParamSize
                    := InitValue() ;  (* size of all parameters.       *)
         InitWhereDeclared(At) ;      (* Where symbol declared.        *)
      END
   END ;
   (* Now add this procedure to the symbol table of the current scope *)
   AddSymToScope(Sym, ProcedureName) ;
   AddProcedureToList(CurrentModule, Sym) ;
   RETURN( Sym )
END MakeProcedure ;


(*
   AddProcedureToList - adds a procedure, Proc, to the list of procedures
                        in module, Mod.
*)

PROCEDURE AddProcedureToList (Mod, Proc: CARDINAL) ;
BEGIN
   WITH Symbols[Mod] DO
      CASE SymbolType OF

      DefImpSym: PutItemIntoList(DefImp.ListOfProcs, Proc) |
      ModuleSym: PutItemIntoList(Module.ListOfProcs, Proc)

      ELSE
         InternalError('expecting ModuleSym or DefImpSym symbol', __FILE__, __LINE__)
      END
   END
END AddProcedureToList ;


(*
   AddVarToList - add a variable symbol to the list of variables maintained
                  by the inner most scope. (Procedure or Module).
*)

PROCEDURE AddVarToList (Sym: CARDINAL) ;
VAR
   m: CARDINAL ;
BEGIN
   m := ScopeCallFrame[ScopePtr].Main ;
   WITH Symbols[m] DO
      CASE SymbolType OF

      ProcedureSym: PutItemIntoList(Procedure.ListOfVars, Sym) |
      ModuleSym   : PutItemIntoList(Module.ListOfVars, Sym) |
      DefImpSym   : PutItemIntoList(DefImp.ListOfVars, Sym)

      ELSE
         InternalError('expecting Procedure or Module symbol', __FILE__, __LINE__)
      END
   END
END AddVarToList ;


(*
   MakeVar - creates a variable sym with VarName. It returns the
             symbol index.
*)

PROCEDURE MakeVar (VarName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(VarName) ;
   WITH Symbols[Sym] DO
      SymbolType := VarSym ;
      WITH Var DO
         name := VarName ;
         Size := InitValue() ;
         Offset := InitValue() ;
         AddrMode := RightValue ;
         Father := ScopeCallFrame[ScopePtr].Main ;  (* Procedure or Module ? *)
         IsTemp := FALSE ;
         IsParam := FALSE ;
         InitWhereDeclared(At) ;
         InitWhereFirstUsed(At) ;          (* Where symbol first used.      *)
         InitList(ReadUsageList) ;
         InitList(WriteUsageList)
      END
   END ;
   (* Add Var to Procedure or Module variable list *)
   AddVarToList(Sym) ;
   (* Now add this Var to the symbol table of the current scope *)
   AddSymToScope(Sym, VarName) ;
   RETURN( Sym )
END MakeVar ;


(*
   MakeRecord - makes the a Record symbol with name RecordName.
*)

PROCEDURE MakeRecord (RecordName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(RecordName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(RecordName) ;
      (* Now add this Record to the symbol table of the current scope *)
      AddSymToScope(Sym, RecordName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := RecordSym ;
      WITH Record DO
         name := RecordName ;
         InitTree(LocalSymbols) ;
         Size := InitValue() ;
         InitList(ListOfSons) ;   (* List of RecordFieldSym and VarientSym *)
         Parent := NulSym ;
         InitWhereDeclared(At)
      END
   END ;
   RETURN( Sym )
END MakeRecord ;


(*
   MakeVarient - creates a new symbol, a varient symbol for record symbol,
                 RecSym.
*)

PROCEDURE MakeVarient (RecSym: CARDINAL) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := VarientSym ;
      WITH Varient DO
         Size := InitValue() ;
         Parent := GetRecord(RecSym) ;
         InitList(ListOfSons) ;
         InitWhereDeclared(At)
      END
   END ;
   (* Now add Sym to the record RecSym field list *)
   WITH Symbols[RecSym] DO
      CASE SymbolType OF

      RecordSym: PutItemIntoList(Record.ListOfSons, Sym)

      ELSE
         InternalError('expecting Record symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END MakeVarient ;


(*
   GetRecord - fetches the record symbol from the parent of Sym.
               Sym maybe a varient symbol in which case its father if searched
               etc.
*)

PROCEDURE GetRecord (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      RecordSym      : RETURN( Sym ) |
      VarientSym     : RETURN( GetRecord(Varient.Parent) ) |
      VarientFieldSym: RETURN( GetRecord(VarientField.Parent) )

      ELSE
         InternalError('expecting Record or Varient symbol', __FILE__, __LINE__)
      END
   END
END GetRecord ;


(*
   MakeEnumeration - places a new symbol in the current scope, the symbol
                     is an enumeration symbol. The symbol index is returned.
*)

PROCEDURE MakeEnumeration (EnumerationName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(EnumerationName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(EnumerationName) ;
      Symbols[Sym].SymbolType := EnumerationSym ; (* To satisfy AddSymToScope *)
      (* Now add this type to the symbol table of the current scope *)
      AddSymToScope(Sym, EnumerationName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := EnumerationSym ;
      WITH Enumeration DO
         name := EnumerationName ;      (* Name of enumeration.   *)
         NoOfElements := 0 ;            (* No of elements in the  *)
                                        (* enumeration type.      *)
         Size := InitValue() ;          (* Size at runtime of sym *)
         InitTree(LocalSymbols) ;       (* Enumeration fields.    *)
         Parent := GetCurrentScope() ;  (* Which scope created it *)
         InitWhereDeclared(At)          (* Declared here          *)
      END
   END ;
   CheckIfEnumerationExported(Sym, ScopePtr) ;
   RETURN( Sym )
END MakeEnumeration ;


(*
   MakeType - makes a type symbol with name TypeName.
*)

PROCEDURE MakeType (TypeName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(TypeName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(TypeName) ;
      (* Now add this type to the symbol table of the current scope *)
      AddSymToScope(Sym, TypeName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := TypeSym ;
      WITH Type DO
         name := TypeName ;    (* Index into name array, name *)
                               (* of type.                    *)
         Type := NulSym ;      (* Index to a type symbol.     *)
         Size := InitValue() ; (* Runtime size of symbol.     *)
         InitWhereDeclared(At) (* Declared here               *)
      END
   END ;
   RETURN( Sym )
END MakeType ;


(*
   MakeHiddenType - makes a type symbol that is hidden from the
                    definition module.
                    This symbol is placed into the UnImplemented list of
                    the definition/implementation module.
                    The type will be filled in when the implementation module
                    is reached.
*)

PROCEDURE MakeHiddenType (TypeName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(TypeName) ;
   WITH Symbols[Sym] DO
      SymbolType := TypeSym ;
      WITH Type DO
         name := TypeName ;    (* Index into name array, name *)
                               (* of type.                    *)
         Type := NulSym ;      (* Index to a type symbol.     *)
         Size := InitValue() ; (* Runtime size of symbol.     *)
         InitWhereDeclared(At) (* Declared here               *)
      END
   END ;
   PutExportUnImplemented(Sym) ;
   PutHiddenTypeDeclared ;
   (* Now add this type to the symbol table of the current scope *)
   AddSymToScope(Sym, TypeName) ;
   RETURN( Sym )
END MakeHiddenType ;


(*
   MakeConstLit - put a constant which has the string described by ConstName
                  into the ConstantTree. The symbol number is returned.
                  If the constant already exits
                  then a duplicate constant is not entered in the tree.
                  All values of constant literals
                  are ignored in Pass 1 and evaluated in Pass 2 via
                  character manipulation.
*)

PROCEDURE MakeConstLit (ConstName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := GetSymKey(ConstLitTree, ConstName) ;
   IF Sym=NulSym
   THEN
      NewSym(Sym) ;
      PutSymKey(ConstLitTree, ConstName, Sym) ;
      WITH Symbols[Sym] DO
         SymbolType := ConstLitSym ;
         CASE SymbolType OF

         ConstLitSym : ConstLit.name := ConstName ;
                       ConstLit.Value := InitValue() ;
                       PushString(ConstName) ;
                       PopInto(ConstLit.Value) ;
                       ConstLit.Type := GetConstLitType(Sym) ;
                       ConstLit.IsSet := FALSE ;
                       InitWhereDeclared(ConstLit.At)

         ELSE
            InternalError('expecting ConstLit symbol', __FILE__, __LINE__)
         END
      END
   END ;
   RETURN( Sym )
END MakeConstLit ;


(*
   MakeConstVar - makes a ConstVar type with
                  name ConstVarName.
*)

PROCEDURE MakeConstVar (ConstVarName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(ConstVarName) ;
   WITH Symbols[Sym] DO
      SymbolType := ConstVarSym ;
      WITH ConstVar DO
         name  := ConstVarName ;
         Value := InitValue() ;
         Type  := NulSym ;
         IsSet := FALSE ;
         InitWhereDeclared(At)
      END
   END ;
   (* Now add this constant to the symbol table of the current scope *)
   AddSymToScope(Sym, ConstVarName) ;
   RETURN( Sym )
END MakeConstVar ;


(*
   MakeConstLitString - put a constant which has the string described by
                        ConstName into the ConstantTree.
                        The symbol number is returned.
                        This symbol is known as a String Constant rather than a
                        ConstLit which indicates a number.
                        If the constant already exits
                        then a duplicate constant is not entered in the tree.
                        All values of constant strings
                        are ignored in Pass 1 and evaluated in Pass 2 via
                        character manipulation.
                        In this procedure ConstName is the string.
*)

PROCEDURE MakeConstLitString (ConstName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := GetSymKey(ConstLitStringTree, ConstName) ;
   IF Sym=NulSym
   THEN
      NewSym(Sym) ;
      PutSymKey(ConstLitStringTree, ConstName, Sym) ;
      WITH Symbols[Sym] DO
         SymbolType := ConstStringSym ;
         CASE SymbolType OF

         ConstStringSym : ConstString.name := ConstName ;
                          PutConstString(Sym, ConstName) ;
                          InitWhereDeclared(ConstString.At)

         ELSE
            InternalError('expecting ConstString symbol', __FILE__, __LINE__)
         END
      END
   END ;
   RETURN( Sym )
END MakeConstLitString ;


(*
   MakeConstString - puts a constant into the symboltable which is a string.
                     The string value is unknown at this time and will be
                     filled in later by PutString.
*)
   
PROCEDURE MakeConstString (ConstName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   PutSymKey(ConstLitStringTree, ConstName, Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := ConstStringSym ;
      CASE SymbolType OF

      ConstStringSym : ConstString.name := ConstName ;
                       ConstString.Length := 0 ;
                       ConstString.String := NulKey ;
                       InitWhereDeclared(ConstString.At)

      ELSE
         InternalError('expecting ConstString symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END MakeConstString ;


(*
   PutConstString - places a string, String, into a constant symbol, Sym.
                    Sym maybe a ConstString or a ConstVar. If the later is
                    true then the ConstVar is converted to a ConstString.
*)

PROCEDURE PutConstString (Sym: CARDINAL; String: Name) ;
VAR
   n: Name ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstStringSym: ConstString.Length := LengthKey(String) ;
                      ConstString.String := String ;
                      InitWhereFirstUsed(ConstString.At) |

      ConstVarSym   : (* ok altering this to ConstString *)
                      n := ConstVar.name ;
                      (* copy name and alter symbol.     *)
                      SymbolType := ConstStringSym ;
                      ConstString.name := n ;
                      PutConstString(Sym, String)

      ELSE
         InternalError('expecting ConstString or ConstVar symbol', __FILE__, __LINE__)
      END
   END
END PutConstString ;


(*
   GetString - returns the string of the symbol Sym, note that
               this is not the same as GetName since the name of a
               CONST declared string will be different to its value.
*)

PROCEDURE GetString (Sym: CARDINAL) : Name ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstStringSym: RETURN( ConstString.String )

      ELSE
         InternalError('expecting ConstString symbol', __FILE__, __LINE__)
      END
   END
END GetString ;


(*
   GetStringLength - returns the length of the string symbol Sym.
*)

PROCEDURE GetStringLength (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstStringSym: RETURN( ConstString.Length )

      ELSE
         InternalError('expecting ConstString symbol', __FILE__, __LINE__)
      END
   END
END GetStringLength ;


(*
   PutConstSet - informs the const var symbol, sym, that it is or will contain
                    a set value.
*)

PROCEDURE PutConstSet (Sym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstVarSym:  ConstVar.IsSet := TRUE |
      ConstLitSym:  ConstLit.IsSet := TRUE

      ELSE
         InternalError('expecting ConstVar symbol', __FILE__, __LINE__)
      END
   END
END PutConstSet ;


(*
   IsConstSet - returns TRUE if the constant is declared as a set.
*)

PROCEDURE IsConstSet (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstVarSym:  RETURN( ConstVar.IsSet ) |
      ConstLitSym:  RETURN( ConstLit.IsSet )

      ELSE
         RETURN( FALSE )
      END
   END
END IsConstSet ;


(*
   MakeSubrange - makes a new symbol into a subrange type with
                  name SubrangeName.
*)

PROCEDURE MakeSubrange (SubrangeName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(SubrangeName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(SubrangeName) ;
      (* Now add this type to the symbol table of the current scope *)
      AddSymToScope(Sym, SubrangeName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := SubrangeSym ;
      WITH Subrange DO
         name := SubrangeName ;
         Low := NulSym ;             (* Index to a symbol determining *)
                                     (* the lower bound of subrange.  *)
                                     (* Points to a constant -        *)
                                     (* possibly created by           *)
                                     (* ConstExpression.              *)
         High := NulSym ;            (* Index to a symbol determining *)
                                     (* the lower bound of subrange.  *)
                                     (* Points to a constant -        *)
                                     (* possibly created by           *)
                                     (* ConstExpression.              *)
         Type := NulSym ;            (* Index to a type. Determines   *)
                                     (* the type of subrange.         *)
         Size := InitValue() ;       (* Size determines the type size *)
         InitWhereDeclared(At)       (* Declared here                 *)
      END
   END ;
   RETURN( Sym )
END MakeSubrange ;


(*
   MakeArray - makes an Array symbol with name ArrayName.
*)

PROCEDURE MakeArray (ArrayName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(ArrayName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(ArrayName) ;
      (* Now add this array to the symbol table of the current scope *)
      AddSymToScope(Sym, ArrayName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := ArraySym ;
      WITH Array DO
         name := ArrayName ;
         InitList(ListOfSubs) ;  (* Contains a list of the array        *)
                                 (* subscripts.                         *)
         Size := InitValue() ;   (* Size of array.                      *)
         Offset := InitValue() ; (* Offset of array.                    *)
         Type := NulSym ;        (* The Array Type. ARRAY OF Type.      *)
         InitWhereDeclared(At)   (* Declared here                       *)
      END
   END ;
   RETURN( Sym )
END MakeArray ;


(*
   GetModule - Returns the Module symbol for the module with name, name.
*)

PROCEDURE GetModule (name: Name) : CARDINAL ;
BEGIN
   RETURN( GetSymKey(ModuleTree, name) )
END GetModule ;


(*
   GetLowestType - Returns the lowest type in the type chain of
                   symbol Sym.
                   If NulSym is returned then we assume type unknown.
*)

PROCEDURE GetLowestType (Sym: CARDINAL) : CARDINAL ;
VAR
   type: CARDINAL ;
BEGIN
   Assert(Sym#NulSym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym              : type := Var.Type |
      ConstLitSym         : type := ConstLit.Type |
      ConstVarSym         : type := ConstVar.Type |
      ConstStringSym      : type := NulSym |  (* No type for a string *)
      TypeSym             : type := Type.Type |
      RecordFieldSym      : type := RecordField.Type |
      RecordSym           : type := NulSym |  (* No type for a record *)
      EnumerationFieldSym : type := EnumerationField.Type |
      EnumerationSym      : type := NulSym |  (* No type for enumeration *)
      PointerSym          : type := Sym |     (* we don't go to Pointer.Type *)
      ProcedureSym        : type := Procedure.ReturnType |
      ProcTypeSym         : type := ProcType.ReturnType |
      ParamSym            : type := Param.Type |
      VarParamSym         : type := VarParam.Type |
      SubrangeSym         : type := Subrange.Type |
      ArraySym            : type := Array.Type |
      SubscriptSym        : type := Subscript.Type |
      SetSym              : type := Set.Type |
      UnboundedSym        : type := Unbounded.Type |
      UndefinedSym        : type := NulSym

      ELSE
         InternalError('not implemented yet', __FILE__, __LINE__)
      END
   END ;
   IF (Symbols[Sym].SymbolType=TypeSym) AND (type=NulSym)
   THEN
      type := Sym             (* Base Type *)
   ELSIF (type#NulSym) AND
         (IsType(type) OR IsSet(type))
   THEN
      (* ProcType is an inbuilt base type *)
      IF Symbols[type].SymbolType#ProcTypeSym
      THEN
         type := GetLowestType(type)   (* Type def *)
      END
   END ;
   IF type>MaxSymbols
   THEN
      InternalError('type not declared', __FILE__, __LINE__)
   END ;
   RETURN( type )
END GetLowestType ;


(*
   GetType - Returns the symbol that is the TYPE symbol to Sym.
             If zero is returned then we assume type unknown.
*)

PROCEDURE GetType (Sym: CARDINAL) : CARDINAL ;
VAR
   type: CARDINAL ;
BEGIN
   Assert(Sym#NulSym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym              : type := Var.Type |
      ConstLitSym         : type := ConstLit.Type |
      ConstVarSym         : type := ConstVar.Type |
      ConstStringSym      : type := NulSym |  (* No type for a string *)
      TypeSym             : type := Type.Type |
      RecordFieldSym      : type := RecordField.Type |
      RecordSym           : type := NulSym |  (* No type for a record *)
      VarientSym          : type := NulSym |  (* No type for a record *)
      EnumerationFieldSym : type := EnumerationField.Type |
      EnumerationSym      : type := NulSym |  (* No type for enumeration *)
      PointerSym          : type := Pointer.Type |
      ProcedureSym        : type := Procedure.ReturnType |
      ProcTypeSym         : type := ProcType.ReturnType |
      ParamSym            : type := Param.Type |
      VarParamSym         : type := VarParam.Type |
      SubrangeSym         : type := Subrange.Type |
      ArraySym            : type := Array.Type |
      SubscriptSym        : type := Subscript.Type |
      SetSym              : type := Set.Type |
      UnboundedSym        : type := Unbounded.Type |
      UndefinedSym        : type := NulSym

      ELSE
         InternalError('not implemented yet', __FILE__, __LINE__)
      END
   END ;
   IF type>MaxSymbols
   THEN
      InternalError('type not declared', __FILE__, __LINE__)
   END ;
   RETURN( type )
END GetType ;


(*
   GetConstLitType - returns the type of the constant, Sym.
                     All constants have type NulSym except CHARACTER constants
                     ie 00C 012C etc and floating point constants which have type LONGREAL.
*)

PROCEDURE GetConstLitType (Sym: CARDINAL) : CARDINAL ;
CONST
   Max = 4096 ;
VAR
   a   : ARRAY [0..Max] OF CHAR ;
   i,
   High: CARDINAL ;
BEGIN
   GetKey(GetSymName(Sym), a) ;
   High := LengthKey(GetSymName(Sym)) ;
   IF a[High-1]='C'
   THEN
      RETURN( Char )
   ELSE
      i := 0 ;
      WHILE i<High DO
         IF (a[i]='.') OR (a[i]='+')
         THEN
            RETURN( LongReal )
         ELSE
            INC(i)
         END
      END ;
      RETURN( Integer )
   END
END GetConstLitType ;


(*
   GetLocalSym - only searches the scope Sym for a symbol with name
                 and returns the index to the symbol.
*)

PROCEDURE GetLocalSym (Sym: CARDINAL; name: Name) : CARDINAL ;
VAR
   LocalSym: CARDINAL ;
BEGIN
   (*
   WriteString('Attempting to retrieve symbol from ') ; WriteKey(GetSymName(Sym)) ;
   WriteString(' local symbol table') ; WriteLn ;
   *)
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      EnumerationSym : LocalSym := GetSymKey(Enumeration.LocalSymbols, name) |
      RecordSym      : LocalSym := GetSymKey(Record.LocalSymbols, name) |
      ProcedureSym   : LocalSym := GetSymKey(Procedure.LocalSymbols, name) |
      ModuleSym      : LocalSym := GetSymKey(Module.LocalSymbols, name) |
      DefImpSym      : LocalSym := GetSymKey(DefImp.LocalSymbols, name)

      ELSE
         InternalError('symbol does not have a LocalSymbols field', __FILE__, __LINE__)
      END
   END ;
   RETURN( LocalSym )
END GetLocalSym ;


(*
   GetNth - returns the n th symbol in the list of father Sym.
            Sym may be a Module, DefImp, Procedure or Record symbol.
*)

PROCEDURE GetNth (Sym: CARDINAL; n: CARDINAL) : CARDINAL ;
VAR
   i: CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      RecordSym       : i := GetItemFromList(Record.ListOfSons, n) |
      VarientSym      : i := GetItemFromList(Varient.ListOfSons, n) |
      VarientFieldSym : i := GetItemFromList(VarientField.ListOfSons, n) |
      ArraySym        : i := GetItemFromList(Array.ListOfSubs, n) |
      ProcedureSym    : i := GetItemFromList(Procedure.ListOfVars, n) |
      DefImpSym       : i := GetItemFromList(DefImp.ListOfVars, n) |
      ModuleSym       : i := GetItemFromList(Module.ListOfVars, n)

      ELSE
         InternalError('cannot GetNth from this symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( i )
END GetNth ;


(*
   GetNthParam - returns the n th parameter of a procedure Sym.
*)

PROCEDURE GetNthParam (Sym: CARDINAL; ParamNo: CARDINAL) : CARDINAL ;
VAR
   i: CARDINAL ;
BEGIN
   IF ParamNo=0
   THEN
      (* Demands the return type of the function *)
      i := GetType(Sym)
   ELSE
      WITH Symbols[Sym] DO
         CASE SymbolType OF

         ProcedureSym: i := GetItemFromList(Procedure.ListOfParam, ParamNo) |
         ProcTypeSym : i := GetItemFromList(ProcType.ListOfParam, ParamNo)

         ELSE
            InternalError('expecting ProcedureSym or ProcTypeSym', __FILE__, __LINE__)
         END
      END
   END ;
   RETURN( i )
END GetNthParam ;


(*
   The Following procedures fill in the symbol table with the
   symbol entities.
*)

(*
   PutVar - gives the VarSym symbol Sym a type Type.
*)

PROCEDURE PutVar (Sym: CARDINAL; VarType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym     : Var.Type := VarType |
      ConstVarSym: ConstVar.Type := VarType

      ELSE
         InternalError('expecting VarSym or ConstVarSym', __FILE__, __LINE__)
      END
   END
END PutVar ;


(*
   PutVarTypeAndSize - gives the variable symbol a type VarType but with a size
                       TypeSize. TypeSize is a symbol from which we copy the size.

                       NOTE - that the variable need NOT have the same size
                              as its corresponding type.
                              The only time this exception is used should
                              be with Temporary variables which have a
                              ModeOfAddr = LeftValue ie pointers to a
                              record structure.
*)

PROCEDURE PutVarTypeAndSize (Sym: CARDINAL; VarType: CARDINAL; TypeSize: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym : Var.Type := VarType ;
               PushSize(TypeSize) ;
               PopInto(Var.Size)

      ELSE
         InternalError('expecting VarSym', __FILE__, __LINE__)
      END
   END
END PutVarTypeAndSize ;


(*
   PutConst - gives the constant symbol Sym a type ConstType.
*)

PROCEDURE PutConst (Sym: CARDINAL; ConstType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE Symbols[Sym].SymbolType OF

      ConstVarSym: ConstVar.Type := ConstType

      ELSE
         InternalError('expecting ConstVarSym', __FILE__, __LINE__)
      END
   END
END PutConst ;


(*
   PutFieldRecord - places a field, FieldName and FieldType into a
                    record Sym.
*)

PROCEDURE PutFieldRecord (Sym: CARDINAL;
                          FieldName: Name; FieldType: CARDINAL) ;
VAR
   ParSym,
   SonSym: CARDINAL ;
BEGIN
   NewSym(SonSym) ; (* Cannot be used before declared since use occurs *)
                    (* in pass 3 and it will be declared in pass 2.    *)
   (* Fill in the SonSym and connect it to its Brothers (if any) and   *)
   (* ensure that it is connected to the Father.                       *)
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      RecordSym       : WITH Record DO
                           PutItemIntoList(ListOfSons, SonSym) ;
                           (* Ensure that the Field is in the Fathers Local Symbols *)
                           PutSymKey(LocalSymbols, FieldName, SonSym)
                        END |
      VarientFieldSym : WITH VarientField DO
                           PutItemIntoList(ListOfSons, SonSym) ;
                           ParSym := Parent
                        END ;
                        Assert(Symbols[ParSym].SymbolType=RecordSym) ;
                        PutSymKey(Symbols[ParSym].Record.LocalSymbols, FieldName, SonSym)

(* is the same as below, but -pedantic warns against having nested WITH statements referencing the same type
   (I've been burnt by this before, so I respect -pedantic warnings..)

                        WITH Symbols[ParSym] DO
                        (* Ensure that the Field is in the Fathers Local Symbols *)
                           CASE SymbolType OF

                           RecordSym: PutSymKey(Record.LocalSymbols, FieldName, SonSym)
                           END
                        END
*)


      ELSE
         InternalError('expecting Record symbol', __FILE__, __LINE__)
      END    
   END ;
   (* Fill in SonSym *)
   WITH Symbols[SonSym] DO
      SymbolType := RecordFieldSym ;
      WITH RecordField DO
         Type := FieldType ;
         name := FieldName ;
         Parent := GetRecord(Sym) ;
         Size := InitValue() ;
         Offset := InitValue()
      END
   END
END PutFieldRecord ;


(*
   MakeFieldVarient - returns a FieldVarient symbol which has been
                      assigned to the Varient symbol, Sym.
*)

PROCEDURE MakeFieldVarient (Sym: CARDINAL) : CARDINAL ;
VAR
   SonSym: CARDINAL ;
BEGIN
   Assert(IsVarient(Sym)) ;
   NewSym(SonSym) ; (* Cannot be used before declared since use occurs *)
                    (* in pass 3 and it will be declared in pass 2.    *)
   (* Fill in the SonSym and connect it to its Brothers (if any) and   *)
   (* ensure that it is connected to the Father.                       *)
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarientSym : PutItemIntoList(Varient.ListOfSons, SonSym)

      ELSE
         InternalError('expecting Varient symbol', __FILE__, __LINE__)
      END    
   END ;
   (* Fill in SonSym *)
   WITH Symbols[SonSym] DO
      SymbolType := VarientFieldSym ;
      WITH VarientField DO
         InitList(ListOfSons) ;
         Parent := GetRecord(Sym) ;
         Size := InitValue() ;
         Offset := InitValue() ;
         InitWhereDeclared(At)
      END
   END ;
   RETURN( SonSym )
END MakeFieldVarient ;


(*
   IsFieldVarient - returns true if the symbol, Sym, is a
                    varient field.
*)

PROCEDURE IsFieldVarient (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=VarientFieldSym )
END IsFieldVarient ;


(*
   IsFieldEnumeration - returns true if the symbol, Sym, is an
                        enumeration field.
*)

PROCEDURE IsFieldEnumeration (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=EnumerationFieldSym )
END IsFieldEnumeration ;


(*
   IsVarient - returns true if the symbol, Sym, is a
               varient symbol.
*)

PROCEDURE IsVarient (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=VarientSym )
END IsVarient ;


(*
   PutFieldEnumeration - places a field into the enumeration type
                         Sym. The field has a name FieldName and a
                         value FieldVal.
*)

PROCEDURE PutFieldEnumeration (Sym: CARDINAL; FieldName: Name) ;
VAR
   Field: CARDINAL ;
BEGIN
   Field := CheckForHiddenType(FieldName) ;
   IF Field=NulSym
   THEN
      Field := DeclareSym(FieldName) ;
   END ;
   WITH Symbols[Field] DO
      SymbolType := EnumerationFieldSym ;
      WITH EnumerationField DO
         name := FieldName ;  (* Index into name array, name *)
                              (* of type.                    *)
         PushCard(Symbols[Sym].Enumeration.NoOfElements) ;
         Value := InitValue() ;
         PopInto(Value) ;
         Type := Sym ;
         InitWhereDeclared(At)  (* Declared here *)
      END
   END ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      EnumerationSym: WITH Enumeration DO
                         INC(NoOfElements) ;
                         IF GetSymKey(LocalSymbols, FieldName)#NulSym
                         THEN
                            AlreadyDeclaredError(Sprintf1(Mark(InitString('enumeration field (%s) is already declared elsewhere, use a different name or remove the declaration')), Mark(InitStringCharStar(KeyToCharStar(FieldName)))),
                                                 FieldName,
                                                 GetDeclared(GetSymKey(LocalSymbols, FieldName)))
                         ELSE
                            PutSymKey(LocalSymbols, FieldName, Field)
                         END
                      END

      ELSE
         InternalError('expecting Sym=Enumeration', __FILE__, __LINE__)
      END
   END
END PutFieldEnumeration ;


(*
   PutType - gives a type symbol Sym type TypeSymbol.
*)

PROCEDURE PutType (Sym: CARDINAL; TypeSymbol: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      TypeSym: Type.Type := TypeSymbol

      ELSE
         InternalError('expecting a Type symbol', __FILE__, __LINE__)
      END
   END
END PutType ;


(*
   IsDefImp - returns true is the Sym is a DefImp symbol.
              Definition/Implementation module symbol.
*)

PROCEDURE IsDefImp (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=DefImpSym )
END IsDefImp ;


(*
   IsModule - returns true is the Sym is a Module symbol.
              Program module symbol.
*)

PROCEDURE IsModule (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=ModuleSym )
END IsModule ;


(*
   IsInnerModule - returns true if the symbol, Sym, is an inner module.
*)

PROCEDURE IsInnerModule (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   IF IsModule(Sym)
   THEN
      RETURN( GetScopeAuthor(Sym)#NulSym )
   ELSE
      RETURN( FALSE )
   END
END IsInnerModule ;

                   
(*
   GetSymName - returns the symbol name.
*)

PROCEDURE GetSymName (Sym: CARDINAL) : Name ;
VAR
   n: Name ;
BEGIN
   IF Sym=NulSym
   THEN
      n := NulKey
   ELSE
      WITH Symbols[Sym] DO
         CASE SymbolType OF

         DefImpSym           : n := DefImp.name |
         ModuleSym           : n := Module.name |
         TypeSym             : n := Type.name |
         VarSym              : n := Var.name |
         ConstLitSym         : n := ConstLit.name |
         ConstVarSym         : n := ConstVar.name |
         ConstStringSym      : n := ConstString.name |
         EnumerationSym      : n := Enumeration.name |
         EnumerationFieldSym : n := EnumerationField.name |
         UndefinedSym        : n := Undefined.name |
         ProcedureSym        : n := Procedure.name |
         ProcTypeSym         : n := ProcType.name |
         RecordFieldSym      : n := RecordField.name |
         RecordSym           : n := Record.name |
         VarientSym          : n := NulName |
         VarParamSym         : n := VarParam.name |
         ParamSym            : n := Param.name |
         PointerSym          : n := Pointer.name |
         ArraySym            : n := Array.name |
         UnboundedSym        : n := NulName |
         SubrangeSym         : n := Subrange.name |
      	 SetSym              : n := Set.name |
         SubscriptSym        : n := NulName |
         DummySym            : n := NulName

         ELSE
            InternalError('unexpected symbol type', __FILE__, __LINE__)
         END
      END
   END ;
   RETURN( n )
END GetSymName ;


(*
   MakeTemporary - Makes a new temporary variable at the heighest real scope.
                   The addressing mode of the temporary is set to NoValue.
*)

PROCEDURE MakeTemporary (Mode: ModeOfAddr) : CARDINAL ;
VAR
   s  : String ;
   Sym: CARDINAL ;
BEGIN
   INC(TemporaryNo) ;
   (* Make the name *)
   s := Sprintf1(Mark(InitString('_T%d')), TemporaryNo) ;
   IF Mode=ImmediateValue
   THEN
      Sym := MakeConstVar(makekey(string(s)))
   ELSE
      Sym := MakeVar(makekey(string(s))) ;
      WITH Symbols[Sym] DO
         CASE SymbolType OF

         VarSym : Var.AddrMode := Mode ;
                  Var.IsTemp := TRUE ;       (* Variable is a temporary var *)
                  InitWhereDeclared(Var.At)  (* Declared here               *)

         ELSE
            InternalError('expecting a Var symbol', __FILE__, __LINE__)
         END
      END
   END ;
   s := KillString(s) ;
   RETURN( Sym )
END MakeTemporary ;


(*
   PutMode - Puts the addressing mode, SymMode, into symbol Sym.
             The mode may only be altered if the mode
             is None.
*)

PROCEDURE PutMode (Sym: CARDINAL; SymMode: ModeOfAddr) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym : (* IF Var.AddrMode#NoValue
               THEN
                  WriteError('Warning altering ModeOfAddr') ; HALT
               END ; *)
               Var.AddrMode := SymMode

      ELSE
         InternalError('Expecting VarSym', __FILE__, __LINE__)
      END
   END
END PutMode ;


(*
   GetMode - Returns the addressing mode of a symbol.
*)

PROCEDURE GetMode (Sym: CARDINAL) : ModeOfAddr ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym             : RETURN( Var.AddrMode ) |
      ConstLitSym        : RETURN( ImmediateValue ) |
      ConstVarSym        : RETURN( ImmediateValue ) |
      ConstStringSym     : RETURN( ImmediateValue ) |
      EnumerationFieldSym: RETURN( ImmediateValue ) |
      ProcedureSym       : RETURN( ImmediateValue ) |
      RecordFieldSym     : RETURN( ImmediateValue ) |
      VarientFieldSym    : RETURN( ImmediateValue ) |
      TypeSym            : RETURN( NoValue ) |
      ArraySym           : RETURN( NoValue ) |
      SubrangeSym        : RETURN( NoValue ) |
      EnumerationSym     : RETURN( NoValue ) |
      RecordSym          : RETURN( NoValue ) |
      PointerSym         : RETURN( NoValue ) |
      SetSym             : RETURN( NoValue ) |
      ProcTypeSym        : RETURN( NoValue ) |
      UnboundedSym       : RETURN( NoValue ) |
      UndefinedSym       : RETURN( NoValue )

      ELSE
         InternalError('not expecting this type', __FILE__, __LINE__)
      END
   END
END GetMode ;


(*
   RenameSym - renames a symbol, Sym, with SymName.
               It also checks the unknown tree for a symbol
               with this new name. Must only be renamed in
               the same scope of being declared.
*)

PROCEDURE RenameSym (Sym: CARDINAL; SymName: Name) ;
BEGIN
   IF GetSymName(Sym)=NulName
   THEN
      WITH Symbols[Sym] DO
         CASE SymbolType OF

         TypeSym             : Type.name      := SymName |
         VarSym              : Var.name       := SymName |
         ConstLitSym         : ConstLit.name  := SymName |
         ConstVarSym         : ConstVar.name  := SymName |
         UndefinedSym        : Undefined.name := SymName |
         RecordSym           : Record.name    := SymName |
         PointerSym          : Pointer.name   := SymName

         ELSE
            InternalError('not implemented yet', __FILE__, __LINE__)
         END
      END ;
      AddSymToScope(Sym, SymName)
   ELSE
      InternalError('old name of symbol must be nul', __FILE__, __LINE__)
   END
END RenameSym ;


(*
   IsUnknown - returns true is the symbol Sym is unknown.
*)

PROCEDURE IsUnknown (Sym: WORD) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=UndefinedSym )
END IsUnknown ;


(*
   CheckLegal - determines whether the Sym is a legal symbol.
*)

PROCEDURE CheckLegal (Sym: CARDINAL) ;
BEGIN
   IF (Sym<1) OR (Sym>FinalSymbol())
   THEN
      InternalError('illegal symbol', __FILE__, __LINE__)
   END
END CheckLegal ;


(*
   CheckForHiddenType - scans the NeedToBeImplemented tree providing
                        that we are currently compiling an implementation
                        module. If a symbol is found with TypeName
                        then its Sym is returned.
                        Otherwise NulSym is returned.
                        CheckForHiddenType is called before any type is
                        created, therefore the compiler allows hidden
                        types to be implemented using any type schema.
*)

PROCEDURE CheckForHiddenType (TypeName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := NulSym ;
   IF CompilingImplementationModule() AND IsHiddenTypeDeclared(CurrentModule)
   THEN
      (* Check to see whether we are declaring a HiddenType. *)
      WITH Symbols[CurrentModule] DO
         CASE SymbolType OF

         DefImpSym: Sym := GetSymKey(DefImp.NeedToBeImplemented, TypeName)

         ELSE
            InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
         END
      END
   END ;
   RETURN( Sym )
END CheckForHiddenType ;


(*
   RequestSym - searches for a symbol with a name SymName in the
                current and previous scopes.
                If the symbol is found then it is returned
                else an unknown symbol is returned.
*)

PROCEDURE RequestSym (SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   (*
      WriteString('RequestSym for: ') ; WriteKey(SymName) ; WriteLn ;
   *)
   Sym := GetSym(SymName) ;
   IF Sym=NulSym
   THEN
      Sym := GetSymFromUnknownTree(SymName) ;
      IF Sym=NulSym
      THEN
         (* Make unknown *)
         NewSym(Sym) ;
         WITH Symbols[Sym] DO
            SymbolType := UndefinedSym ;
            WITH Undefined DO
               name := SymName ;
               InitWhereFirstUsed(At)
            END
         END ;
         (* Add to unknown tree *)
         AddSymToUnknownTree(SymName, Sym)
         (*
           ; WriteKey(SymName) ; WriteString(' unknown demanded') ; WriteLn
         *)
      END
   END ;
   RETURN( Sym )
END RequestSym ;


(*
   PutImported - places a symbol, Sym, into the current main scope.
*)

PROCEDURE PutImported (Sym: CARDINAL) ;
VAR
   ModSym: CARDINAL ;
BEGIN
   (*
      We have currently imported Sym, now place it into the current module.
   *)
   ModSym := GetCurrentModuleScope() ;
   Assert(IsDefImp(ModSym) OR IsModule(ModSym)) ;
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      ModuleSym: IF GetSymKey(Module.ImportTree, GetSymName(Sym))=Sym
                 THEN
                    IF Pedantic
                    THEN
                       WriteFormat1('symbol (%a) has already been imported', GetSymName(Sym))
                    END
                 ELSIF GetSymKey(Module.ImportTree, GetSymName(Sym))=NulKey
                 THEN
                    PutSymKey(Module.ImportTree, GetSymName(Sym), Sym) ;
                    AddSymToModuleScope(ModSym, Sym)
                 ELSE
                    WriteFormat1('name clash when trying to import (%a)', GetSymName(Sym))
                 END |
      DefImpSym: IF GetSymKey(DefImp.ImportTree, GetSymName(Sym))=Sym
                 THEN
                    IF Pedantic
                    THEN
                       WriteFormat1('symbol (%a) has already been imported', GetSymName(Sym))
                    END
                 ELSIF GetSymKey(DefImp.ImportTree, GetSymName(Sym))=NulKey
                 THEN
                    PutSymKey(DefImp.ImportTree, GetSymName(Sym), Sym) ;
                    AddSymToModuleScope(ModSym, Sym)
                 ELSE
                    WriteFormat1('name clash when trying to import (%a)', GetSymName(Sym))
                 END

      ELSE
         InternalError('expecting a Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutImported ;


(*
   PutIncluded - places a symbol, Sym, into the included list of the
                 current module.
                 Symbols that are placed in this list are indirectly declared
                 by:

                 IMPORT modulename ;

                 modulename.identifier
*)

PROCEDURE PutIncluded (Sym: CARDINAL) ;
VAR
   ModSym: CARDINAL ;
BEGIN
   (*
      We have referenced Sym, via modulename.Sym
      now place it into the current module include list.
   *)
   ModSym := GetCurrentModuleScope() ;
   Assert(IsDefImp(ModSym) OR IsModule(ModSym)) ;
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      ModuleSym: IncludeItemIntoList(Module.IncludeList, Sym) |
      DefImpSym: IncludeItemIntoList(DefImp.IncludeList, Sym)

      ELSE
         InternalError('expecting a Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutIncluded ;


(*
   PutExported - places a symbol, Sym into the the next level out module.
                 Sym is also placed in the ExportTree of the current inner
                 module.
*)

PROCEDURE PutExported (Sym: CARDINAL) ;
BEGIN
(*
   WriteString('PutExported') ; WriteLn ;
*)
   AddSymToModuleScope(GetLastModuleScope(), Sym) ;
   WITH Symbols[GetCurrentModuleScope()] DO
      CASE SymbolType OF

      ModuleSym: PutSymKey(Module.ExportTree, GetSymName(Sym), Sym) ;
                 IF IsUnknown(Sym)
                 THEN
                    PutExportUndeclared(GetCurrentModuleScope(), Sym)
                 END
(*
                 ; WriteKey(Module.name) ; WriteString(' exports ') ;
                 ; WriteKey(GetSymName(Sym)) ; WriteLn ;
*)

      ELSE
         InternalError('expecting a Module symbol', __FILE__, __LINE__)
      END
   END
END PutExported ;


(*
   PutExportQualified - places a symbol with the name, SymName,
                        into the export tree of the
                        Definition module being compiled.
                        The symbol with name has been EXPORT QUALIFIED
                        by the definition module and therefore any reference
                        to this symbol in the code generation phase
                        will be in the form _Module_Name.
*)

PROCEDURE PutExportQualified (SymName: Name) ;
VAR
   Sym,
   ModSym: CARDINAL ;
BEGIN
   ModSym := GetCurrentModule() ;
   Assert(IsDefImp(ModSym)) ;
   Assert(CompilingDefinitionModule()) ;
(*
   WriteString('1st MODULE ') ; WriteKey(GetSymName(ModSym)) ;
   WriteString(' identifier ') ; WriteKey(SymName) ; WriteLn ;
*)
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    IF (GetSymKey(ExportQualifiedTree, SymName)#NulKey) AND
                       (GetSymKey(ExportRequest, SymName)=NulKey)
                    THEN
                       WriteFormat2('identifier (%a) has already been exported from MODULE %a',
                                    SymName, GetSymName(ModSym))
                    ELSIF GetSymKey(ExportRequest, SymName)#NulKey
                    THEN
                       Sym := GetSymKey(ExportRequest, SymName) ;
                       DelSymKey(ExportRequest, SymName) ;
                       PutSymKey(ExportQualifiedTree, SymName, Sym) ;
                       PutExportUndeclared(ModSym, Sym)
                    ELSE
                       Sym := RequestSym(SymName) ;
                       PutSymKey(ExportQualifiedTree, SymName, Sym) ;
                       PutExportUndeclared(ModSym, Sym)
                    END
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutExportQualified ;


(*
   PutExportUnQualified - places a symbol with the name, SymName,
                          into the export tree of the
                          Definition module being compiled.
                          The symbol with Name has been EXPORT UNQUALIFIED
                          by the definition module and therefore any reference
                          to this symbol in the code generation phase
                          will be in the form _Name.
*)

PROCEDURE PutExportUnQualified (SymName: Name) ;
VAR
   Sym,
   ModSym: CARDINAL ;
BEGIN
   ModSym := GetCurrentModule() ;
   Assert(IsDefImp(ModSym)) ;
   Assert(CompilingDefinitionModule()) ;
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    IF (GetSymKey(ExportUnQualifiedTree, SymName)#NulKey) AND
                       (GetSymKey(ExportRequest, SymName)=NulKey)
                    THEN
                       WriteFormat2('identifier (%a) has already been exported from MODULE %a',
                                    SymName, GetSymName(ModSym))
                    ELSIF GetSymKey(ExportRequest, SymName)#NulKey
                    THEN
                       Sym := GetSymKey(ExportRequest, SymName) ;
                       DelSymKey(ExportRequest, SymName) ;
                       PutSymKey(ExportUnQualifiedTree, SymName, Sym) ;
                       PutExportUndeclared(ModSym, Sym)
                    ELSE
                       Sym := RequestSym(SymName) ;
                       PutSymKey(ExportUnQualifiedTree, SymName, Sym) ;
                       PutExportUndeclared(ModSym, Sym)
                    END
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutExportUnQualified ;


(*
   GetExported - returns the symbol which has a name SymName,
                 and is exported from the definition module ModSym.

*)

PROCEDURE GetExported (ModSym: CARDINAL;
                       SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: Sym := RequestFromDefinition(ModSym, SymName)

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END GetExported ;


(*
   RequestFromModule - returns a symbol from module ModSym with name, SymName.
*)

PROCEDURE RequestFromModule (ModSym: CARDINAL; SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    Sym := GetSymKey(LocalSymbols, SymName) ;
                    IF Sym=NulSym
                    THEN
                       Sym := FetchUnknownFromDefImp(ModSym, SymName)
                    END
                 END |

      ModuleSym: WITH Module DO
                    Sym := GetSymKey(LocalSymbols, SymName) ;
                    IF Sym=NulSym
                    THEN
                       Sym := FetchUnknownFromModule(ModSym, SymName)
                    END
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END RequestFromModule ;


(*
   RequestFromDefinition - returns a symbol from module ModSym with name,
                           SymName.
*)

PROCEDURE RequestFromDefinition (ModSym: CARDINAL; SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    Sym := GetSymKey(ExportQualifiedTree, SymName) ;
                    IF Sym=NulSym
                    THEN
                       Sym := GetSymKey(ExportUnQualifiedTree, SymName) ;
                       IF Sym=NulSym
                       THEN
                          Sym := GetSymKey(ExportRequest, SymName) ;
                          IF Sym=NulSym
                          THEN
                             Sym := FetchUnknownFromDefImp(ModSym, SymName) ;
                             PutSymKey(ExportRequest, SymName, Sym)
                          END
                       END
                    END
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END RequestFromDefinition ;


(*
   DisplaySymbol - displays the name of a symbol
*)

PROCEDURE DisplaySymbol (sym: CARDINAL) ;
BEGIN
   printf1('   %s', Mark(InitStringCharStar(KeyToCharStar(GetSymName(sym)))))
END DisplaySymbol ;


(*
   DisplayTrees - displays the SymbolTrees for Module symbol, ModSym.
*)

PROCEDURE DisplayTrees (ModSym: CARDINAL) ;
BEGIN
(*
   WriteString('Symbol trees for module: ') ; WriteKey(GetSymName(ModSym)) ; WriteLn ;
*)
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
(*
                    WriteKey(GetSymName(ModSym)) ; WriteString('  UndefinedTree') ;
                    ForeachNodeDo(Unresolved, DisplaySymbol) ;  WriteLn ;
                    WriteKey(GetSymName(ModSym)) ; WriteString('  Local symbols') ;
                    ForeachNodeDo(LocalSymbols, DisplaySymbol) ; WriteLn ;
                    WriteKey(GetSymName(ModSym)) ; WriteString('  ExportRequest') ;
                    ForeachNodeDo(ExportRequest, DisplaySymbol) ; WriteLn ;
                    WriteKey(GetSymName(ModSym)) ; WriteString('  ExportQualified') ;
                    ForeachNodeDo(ExportQualifiedTree, DisplaySymbol) ; WriteLn ;
                    WriteKey(GetSymName(ModSym)) ; WriteString('  ExportUnQualified') ;
                    ForeachNodeDo(ExportUnQualifiedTree, DisplaySymbol) ; WriteLn
*)
                 END

      ELSE
         InternalError('expecting DefImp symbol', __FILE__, __LINE__)
      END
   END
END DisplayTrees ;


(*
   FetchUnknownFromModule - returns an Unknown symbol from module, ModSym.
*)

PROCEDURE FetchUnknownFromModule (ModSym: CARDINAL;
                                  SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF
         ModuleSym: WITH Module DO
                       Sym := GetSymKey(Unresolved , SymName) ;
                       IF Sym=NulSym
                       THEN
                          NewSym(Sym) ;
                          Symbols[Sym].SymbolType := UndefinedSym ;
                          Symbols[Sym].Undefined.name := SymName ;
                          InitWhereFirstUsed(Symbols[Sym].Undefined.At) ;
                          PutSymKey(Unresolved, SymName, Sym)
                       END
                    END
      ELSE
         InternalError('expecting a Module symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END FetchUnknownFromModule ;


(*
   FetchUnknownFromDefImp - returns an Unknown symbol from module, ModSym.
*)

PROCEDURE FetchUnknownFromDefImp (ModSym: CARDINAL;
                                  SymName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF
         DefImpSym: WITH DefImp DO
                       Sym := GetSymKey(Unresolved , SymName) ;
                       IF Sym=NulSym
                       THEN
                          NewSym(Sym) ;
                          Symbols[Sym].SymbolType := UndefinedSym ;
                          Symbols[Sym].Undefined.name := SymName ;
                          InitWhereFirstUsed(Symbols[Sym].Undefined.At) ;
                          PutSymKey(Unresolved, SymName, Sym)
                       END
                    END
      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END FetchUnknownFromDefImp ;


(*
   GetFromOuterModule - returns a symbol with name, SymName, which comes
                        from an outer level module.
                        Only works with one level of internal module!
*)

PROCEDURE GetFromOuterModule (SymName: Name) : CARDINAL ;
BEGIN
   RETURN( RequestFromModule(GetLastModuleScope(), SymName) )
END GetFromOuterModule ;


(*
   IsExportUnQualified - returns true if a symbol, Sym, was defined as
                         being EXPORT UNQUALIFIED.
                         Sym is expected to be either a procedure or a
                         variable.
*)

PROCEDURE IsExportUnQualified (Sym: CARDINAL) : BOOLEAN ;
VAR
   OuterModule: CARDINAL ;
BEGIN
   Assert(IsVar(Sym) OR IsProcedure(Sym)) ;
   OuterModule := Sym ;
   REPEAT
      OuterModule := GetScopeAuthor(OuterModule)
   UNTIL GetScopeAuthor(OuterModule)=NulSym ;
   WITH Symbols[OuterModule] DO
      CASE SymbolType OF

      ModuleSym: RETURN( FALSE ) |
      DefImpSym: RETURN( GetSymKey(
                                    DefImp.ExportUnQualifiedTree,
                                    GetSymName(Sym)
                                  )=Sym
                       )

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END IsExportUnQualified ;


(*
   IsExportQualified - returns true if a symbol, Sym, was defined as
                       being EXPORT QUALIFIED.
                       Sym is expected to be either a procedure or a
                       variable.
*)

PROCEDURE IsExportQualified (Sym: CARDINAL) : BOOLEAN ;
VAR
   OuterModule: CARDINAL ;
BEGIN
   Assert(IsVar(Sym) OR IsProcedure(Sym)) ;
   OuterModule := Sym ;
   REPEAT
      OuterModule := GetScopeAuthor(OuterModule)
   UNTIL GetScopeAuthor(OuterModule)=NulSym ;
   WITH Symbols[OuterModule] DO
      CASE SymbolType OF

      ModuleSym: RETURN( FALSE ) |
      DefImpSym: RETURN( GetSymKey(
                                    DefImp.ExportQualifiedTree,
                                    GetSymName(Sym)
                                  )=Sym
                       )

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END IsExportQualified ;


(*
   ForeachImportedDo - calls a procedure, P, foreach imported symbol
                       in module, ModSym.
*)

PROCEDURE ForeachImportedDo (ModSym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    ForeachNodeDo( ImportTree, P ) ;
                    ForeachItemInListDo( IncludeList, P )
                 END |
      ModuleSym: WITH Module DO
                    ForeachNodeDo( ImportTree, P ) ;
                    ForeachItemInListDo( IncludeList, P )
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END ForeachImportedDo ;


(*
   ForeachExportedDo - calls a procedure, P, foreach imported symbol
                       in module, ModSym.
*)

PROCEDURE ForeachExportedDo (ModSym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    ForeachNodeDo( ExportQualifiedTree, P ) ;
                    ForeachNodeDo( ExportUnQualifiedTree, P )
                 END |
      ModuleSym: WITH Module DO
                    ForeachNodeDo( ExportTree, P )
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END ForeachExportedDo ;


(*
   ForeachLocalSymDo - foreach local symbol in module, Sym, or procedure, Sym,
                       perform the procedure, P.
*)

PROCEDURE ForeachLocalSymDo (Sym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym:    WITH DefImp DO
                       ForeachNodeDo( LocalSymbols, P )
                    END |
      ModuleSym:    WITH Module DO
                       ForeachNodeDo( LocalSymbols, P )
                    END |
      ProcedureSym: WITH Procedure DO
                       ForeachNodeDo( LocalSymbols, P )
                    END

      ELSE
         InternalError('expecting a DefImp, Module or Procedure symbol', __FILE__, __LINE__)
      END
   END
END ForeachLocalSymDo ;


(*
   CheckForUnknownInModule - checks for any unknown symbols in the
                             current module.
                             If any unknown symbols are found then
                             an error message is displayed.
*)

PROCEDURE CheckForUnknownInModule ;
BEGIN
   WITH Symbols[GetCurrentModuleScope()] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    CheckForUnknowns( name, ExportQualifiedTree,
                                      'EXPORT QUALIFIED' ) ;
                    CheckForUnknowns( name, ExportUnQualifiedTree,
                                      'EXPORT UNQUALIFIED' ) ;
                    CheckForSymbols ( ExportRequest,
                                      'requested by another modules import (symbols have not been EXPORTed by the appropriate definition module)' ) ;
                    CheckForUnknowns( name, Unresolved, 'unresolved' ) ;
                    CheckForUnknowns( name, LocalSymbols, 'locally used' )
                 END |
      ModuleSym: WITH Module DO
                    CheckForUnknowns( name, Unresolved, 'unresolved' ) ;
                    CheckForUnknowns( name, ExportUndeclared, 'EXPORT' ) ;
                    CheckForUnknowns( name, ExportTree, 'EXPORT pass 1' ) ;
                    CheckForUnknowns( name, LocalSymbols, 'locally used' )
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END CheckForUnknownInModule ;


(*
   UnknownSymbolError - displays symbol name for symbol, Sym.
*)

PROCEDURE UnknownSymbolError (Sym: WORD) ;
VAR
   e: Error ;
BEGIN
   IF IsUnknown(Sym)
   THEN
      e := ChainError(GetFirstUsed(Sym), CurrentError) ;
      ErrorFormat1(e, 'unknown symbol (%a) found', GetSymName(Sym))
   END
END UnknownSymbolError ;


(*
   CheckForUnknowns - checks a binary tree, Tree, to see whether it contains
                      an unknown symbol. All unknown symbols are displayed
                      together with an error message.
*)

PROCEDURE CheckForUnknowns (name: Name; Tree: SymbolTree;
                            a: ARRAY OF CHAR) ;
BEGIN
   IF DoesTreeContainAny(Tree, IsUnknown)
   THEN
      CurrentError := NewError(GetTokenNo()) ;
      ErrorFormat2(CurrentError, 'the following symbols are unknown in module %a which were %a',
                   name, MakeKey(a)) ;      
      ForeachNodeDo(Tree, UnknownSymbolError)
   END
END CheckForUnknowns ;


(*
   SymbolError - displays symbol name for symbol, Sym.
*)

PROCEDURE SymbolError (Sym: WORD) ;
VAR
   e: Error ;
BEGIN
   e := ChainError(GetFirstUsed(Sym), CurrentError) ;
   ErrorFormat1(e, 'unknown symbol (%a) found', GetSymName(Sym))
END SymbolError ;


(*
   CheckForSymbols  - checks a binary tree, Tree, to see whether it contains
                      any symbol. The tree is expected to be empty, if not
                      then an error has occurred.
*)

PROCEDURE CheckForSymbols (Tree: SymbolTree; a: ARRAY OF CHAR) ;
BEGIN
   IF NOT IsEmptyTree(Tree)
   THEN
      WriteFormat2('the following symbols are unknown at the end of module %a when %a',
                   GetSymName(MainModule), MakeKey(a)) ;
      ForeachNodeDo(Tree, SymbolError) ;
   END
END CheckForSymbols ;


(*
   PutExportUndeclared - places a symbol, Sym, into module, ModSym,
                         ExportUndeclared list provided that Sym
                         is unknown.
*)

PROCEDURE PutExportUndeclared (ModSym: CARDINAL; Sym: CARDINAL) ;
BEGIN
   IF IsUnknown(Sym)
   THEN
      WITH Symbols[ModSym] DO
         CASE SymbolType OF

         ModuleSym: PutSymKey(Module.ExportUndeclared, GetSymName(Sym), Sym) |
         DefImpSym: PutSymKey(DefImp.ExportUndeclared, GetSymName(Sym), Sym)

         ELSE
            InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
         END
      END
   END
END PutExportUndeclared ;


(*
   RemoveExportUndeclared - removes a symbol, Sym, from the module, ModSym,
                            ExportUndeclaredTree.
*)

PROCEDURE RemoveExportUndeclared (ModSym: CARDINAL; Sym: CARDINAL) ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      ModuleSym: IF GetSymKey(Module.ExportUndeclared, GetSymName(Sym))=Sym
                 THEN
                    DelSymKey(Module.ExportUndeclared, GetSymName(Sym))
                 END |
      DefImpSym: IF GetSymKey(DefImp.ExportUndeclared, GetSymName(Sym))=Sym
                 THEN
                    DelSymKey(DefImp.ExportUndeclared, GetSymName(Sym))
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END RemoveExportUndeclared ;


(*
   CheckForExportedDeclaration - checks to see whether a definition module
                                 is currently being compiled, if so,
                                 symbol, Sym, is removed from the
                                 ExportUndeclared list.
                                 This procedure is called whenever a symbol
                                 is declared, thus attempting to reduce
                                 the ExportUndeclared list.
*)

PROCEDURE CheckForExportedDeclaration (Sym: CARDINAL) ;
BEGIN
   IF CompilingDefinitionModule()
   THEN
      RemoveExportUndeclared(GetCurrentModule(), Sym)
   END
END CheckForExportedDeclaration ;


(*
   CheckForUndeclaredExports - displays an error and the offending symbols
                               which have been EXPORTed but not declared
                               from module, ModSym.
*)

PROCEDURE CheckForUndeclaredExports (ModSym: CARDINAL) ;
BEGIN
   (* WriteString('Inside CheckForUndeclaredExports') ; WriteLn ; *)
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      ModuleSym: IF NOT IsEmptyTree(Module.ExportUndeclared)
                 THEN
                    WriteFormat0('undeclared identifier(s) in EXPORT list of MODULE') ;
                    ForeachNodeDo(Module.ExportUndeclared, UndeclaredSymbolError)
                 END |
      DefImpSym: IF NOT IsEmptyTree(DefImp.ExportUndeclared)
                 THEN
                    WriteFormat0('undeclared identifier(s) in EXPORT list of DEFINITION MODULE') ;
                    ForeachNodeDo(DefImp.ExportUndeclared, UndeclaredSymbolError)
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END CheckForUndeclaredExports ;


(*
   UndeclaredSymbolError - displays symbol name for symbol, Sym.
*)

PROCEDURE UndeclaredSymbolError (Sym: WORD) ;
VAR
   e: Error ;
BEGIN
   e := ChainError(GetFirstUsed(Sym), CurrentError) ;
   ErrorFormat1(e, 'undeclared symbol (%a)', GetSymName(Sym))
END UndeclaredSymbolError ;


(*
   PutExportUnImplemented - places a symbol, Sym, into the currently compiled
                            DefImp module NeedToBeImplemented list.
*)

PROCEDURE PutExportUnImplemented (Sym: CARDINAL) ;
BEGIN
   WITH Symbols[CurrentModule] DO
      CASE SymbolType OF

      DefImpSym: IF GetSymKey(DefImp.NeedToBeImplemented, GetSymName(Sym))=Sym
                 THEN
                    WriteFormat2('symbol (%a) already exported from module (%a)',
                                 GetSymName(Sym), GetSymName(CurrentModule))
                 ELSE
                    PutSymKey(DefImp.NeedToBeImplemented, GetSymName(Sym), Sym)
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutExportUnImplemented ;


(*
   RemoveExportUnImplemented - removes a symbol, Sym, from the module, ModSym,
                               NeedToBeImplemented list.
*)

PROCEDURE RemoveExportUnImplemented (ModSym: CARDINAL; Sym: CARDINAL) ;
BEGIN
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: IF GetSymKey(DefImp.NeedToBeImplemented, GetSymName(Sym))=Sym
                 THEN
                    DelSymKey(DefImp.NeedToBeImplemented, GetSymName(Sym))
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END RemoveExportUnImplemented ;


(*
   CheckForExportedImplementation - checks to see whether an implementation
                                    module is currently being compiled, if so,
                                    symbol, Sym, is removed from the
                                    NeedToBeImplemented list.
                                    This procedure is called whenever a symbol
                                    is declared, thus attempting to reduce
                                    the NeedToBeImplemented list.
                                    Only needs to be called when a TYPE or
                                    PROCEDURE is built since the implementation
                                    module can only implement these objects
                                    declared in the definition module.
*)

PROCEDURE CheckForExportedImplementation (Sym: CARDINAL) ;
BEGIN
   IF CompilingImplementationModule()
   THEN
      RemoveExportUnImplemented(GetCurrentModule(), Sym)
   END
END CheckForExportedImplementation ;


(*
   CheckForUnImplementedExports - displays an error and the offending symbols
                                  which have been EXPORTed but not implemented
                                  from the current compiled module.
*)

PROCEDURE CheckForUnImplementedExports ;
BEGIN
   (* WriteString('Inside CheckForImplementedExports') ; WriteLn ; *)
   WITH Symbols[CurrentModule] DO
      CASE SymbolType OF

      DefImpSym: IF NOT IsEmptyTree(DefImp.NeedToBeImplemented)
                 THEN
                    CurrentError := NewError(GetTokenNo()) ;
                    ErrorFormat1(CurrentError, 'unimplemented identifier(s) in EXPORT list of DEFINITION MODULE %a\nthe implementation module fails to implement the following exported identifier(s)', DefImp.name) ;
                    ForeachNodeDo( DefImp.NeedToBeImplemented, UnImplementedSymbolError )
                 END

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END CheckForUnImplementedExports ;


(*
   UnImplementedSymbolError - displays symbol name for symbol, Sym.
*)

PROCEDURE UnImplementedSymbolError (Sym: WORD) ;
BEGIN
   CurrentError := ChainError(GetFirstUsed(Sym), CurrentError) ;
   IF IsType(Sym)
   THEN
      ErrorFormat1(CurrentError, 'hidden type is undeclared (%a)', GetSymName(Sym))
   ELSIF IsProcedure(Sym)
   THEN
      ErrorFormat1(CurrentError, 'procedure is undeclared (%a)', GetSymName(Sym))
   ELSE
      InternalError('expecting Type or Procedure symbols', __FILE__, __LINE__)
   END
END UnImplementedSymbolError ;


(*
   PutHiddenTypeDeclared - sets a flag in the current compiled module which
                           indicates that a Hidden Type is declared within
                           the implementation part of the module.
                           This procedure is expected to be called while
                           compiling the associated definition module.
*)

PROCEDURE PutHiddenTypeDeclared ;
BEGIN
   WITH Symbols[CurrentModule] DO
      CASE SymbolType OF

      DefImpSym: DefImp.ContainsHiddenType := TRUE

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutHiddenTypeDeclared ;


(*
   IsHiddenTypeDeclared - returns true if a Hidden Type was declared in
                          the module, Sym.
*)

PROCEDURE IsHiddenTypeDeclared (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym: RETURN( DefImp.ContainsHiddenType )

      ELSE
         InternalError('expecting a DefImp symbol', __FILE__, __LINE__)
      END
   END
END IsHiddenTypeDeclared ;


(*
   CheckForEnumerationInCurrentModule - checks to see whether the enumeration
                                        type symbol, Sym, has been entered into
                                        the current modules scope list.
*)

PROCEDURE CheckForEnumerationInCurrentModule (Sym: CARDINAL) ;
VAR
   ModSym: CARDINAL ;
BEGIN
   IF IsEnumeration(Sym)
   THEN
      ModSym := GetCurrentModuleScope() ;
      WITH Symbols[ModSym] DO
         CASE SymbolType OF

         DefImpSym: CheckEnumerationInList(DefImp.EnumerationScopeList, Sym) |
         ModuleSym: CheckEnumerationInList(Module.EnumerationScopeList, Sym)

         ELSE
            InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
         END
      END
   END
END CheckForEnumerationInCurrentModule ;


(*
   CheckEnumerationInList - places symbol, Sym, in the list, l,
                            providing it does not already exist.
                            PseudoScope(Sym) is called if Sym needs to
                            be added to the enumeration list, l.
*)

PROCEDURE CheckEnumerationInList (l: List; Sym: CARDINAL) ;
BEGIN
   IF NOT IsItemInList(l, Sym)
   THEN
      PutItemIntoList(l, Sym) ;
      PseudoScope(Sym)
   END
END CheckEnumerationInList ;


(*
   CheckIfEnumerationExported - An outer module may use an enumeration that
                                is declared inside an inner module. The usage
                                may occur before definition. The first pass
                                exports a symbol, later the symbol is declared
                                as an emumeration type. At this stage the
                                CheckIfEnumerationExported procedure should be
                                called. This procedure ripples from the current
                                (inner) module to outer module and every time
                                it is exported it must be added to the outer
                                module EnumerationScopeList.
*)

PROCEDURE CheckIfEnumerationExported (Sym: CARDINAL; ScopeId: CARDINAL) ;
VAR
   InnerModId,
   OuterModId : CARDINAL ;
   InnerModSym,
   OuterModSym: CARDINAL ;
BEGIN
   InnerModId := GetModuleScopeId(ScopeId) ;
   IF InnerModId>0
   THEN
      OuterModId := GetModuleScopeId(InnerModId-1) ;
      IF OuterModId>0
      THEN
         InnerModSym := ScopeCallFrame[InnerModId].Search ;
         OuterModSym := ScopeCallFrame[OuterModId].Search ;
         IF (InnerModSym#NulSym) AND (OuterModSym#NulSym)
         THEN
            IF IsExported(InnerModSym, Sym)
            THEN
               CheckForEnumerationInOuterModule(Sym, OuterModSym) ;
               CheckIfEnumerationExported(Sym, OuterModId)
            END
         END
      END
   END
END CheckIfEnumerationExported ;


(*
   CheckForEnumerationInOuterModule - checks to see whether the enumeration
                                      type symbol, Sym, has been entered into
                                      the outer module, OuterModule, scope list.
                                      OuterModule may be internal to the
                                      program module.
*)

PROCEDURE CheckForEnumerationInOuterModule (Sym: CARDINAL;
                                            OuterModule: CARDINAL) ;
BEGIN
   WITH Symbols[OuterModule] DO
      CASE SymbolType OF

      DefImpSym: IncludeItemIntoList(DefImp.EnumerationScopeList, Sym) |
      ModuleSym: IncludeItemIntoList(Module.EnumerationScopeList, Sym)

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END CheckForEnumerationInOuterModule ;


(*
   IsExported - returns true if a symbol, Sym, is exported
                from module, ModSym.
                If ModSym is a DefImp symbol then its
                ExportQualified and ExportUnQualified lists are examined.
*)

PROCEDURE IsExported (ModSym: CARDINAL; Sym: CARDINAL) : BOOLEAN ;
VAR
   SymName: Name ;
BEGIN
   SymName := GetSymName(Sym) ;
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    RETURN(
                            (GetSymKey(ExportQualifiedTree, SymName)=Sym) OR
                            (GetSymKey(ExportUnQualifiedTree, SymName)=Sym)
                          )
                 END |
      ModuleSym: WITH Module DO
                    RETURN( GetSymKey(ExportTree, SymName)=Sym )
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END IsExported ;


(*
   IsImported - returns true if a symbol, Sym, in module, ModSym,
                was imported.
*)

PROCEDURE IsImported (ModSym: CARDINAL; Sym: CARDINAL) : BOOLEAN ;
VAR
   SymName: Name ;
BEGIN
   SymName := GetSymName(Sym) ;
   WITH Symbols[ModSym] DO
      CASE SymbolType OF

      DefImpSym: WITH DefImp DO
                    RETURN(
                            (GetSymKey(ImportTree, SymName)=Sym) OR
                            IsItemInList(IncludeList, Sym)
                          )
                 END |
      ModuleSym: WITH Module DO
                    RETURN(
                            (GetSymKey(ImportTree, SymName)=Sym) OR
                            IsItemInList(IncludeList, Sym)
                          )
                 END

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END IsImported ;


(*
   IsType - returns true if the Sym is a type symbol.
*)

PROCEDURE IsType (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=TypeSym )
END IsType ;


(*
   PutFunction - Places a TypeSym as the return type to a procedure Sym.
*)

PROCEDURE PutFunction (Sym: CARDINAL; TypeSym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Procedure.ReturnType := TypeSym |
      ProcTypeSym : ProcType.ReturnType := TypeSym

      ELSE
         InternalError('expecting a Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END
END PutFunction ;


(*
   PutParam - Places a Non VAR parameter ParamName with type ParamType into
              procedure Sym. The parameter number is ParamNo.
              If the procedure Sym already has this parameter then
              the parameter is checked for consistancy and the
              consistancy test is returned.
*)

PROCEDURE PutParam (Sym: CARDINAL; ParamNo: CARDINAL;
                    ParamName: Name; ParamType: CARDINAL) : BOOLEAN ;
VAR
   ParSym     : CARDINAL ;
   VariableSym: CARDINAL ;
BEGIN
   IF ParamNo<=NoOfParam(Sym)
   THEN
      InternalError('why are we trying to put parameters again', __FILE__, __LINE__)
   ELSE
      (* Add a new parameter *)
      NewSym(ParSym) ;
      WITH Symbols[ParSym] DO
         SymbolType := ParamSym ;
         WITH Param DO
            name := ParamName ;
            Type := ParamType ;
            InitWhereDeclared(At)
         END
      END ;
      AddParameter(Sym, ParSym) ;
      VariableSym := MakeVar(ParamName) ;
      WITH Symbols[VariableSym] DO
         CASE SymbolType OF

         VarSym : Var.IsParam := TRUE        (* Variable is really a parameter *)

         ELSE
            InternalError('expecting a Var symbol', __FILE__, __LINE__)
         END
      END ;

      (* Note that the parameter is now treated as a local variable *)
      PutVar(VariableSym, ParamType) ;
      PutMode(VariableSym, RightValue) ;
      RETURN( TRUE )
   END
END PutParam ;


(*
   PutVarParam - Places a Non VAR parameter ParamName with type
                 ParamType into procedure Sym.
                 The parameter number is ParamNo.
                 If the procedure Sym already has this parameter then
                 the parameter is checked for consistancy and the
                 consistancy test is returned.
*)

PROCEDURE PutVarParam (Sym: CARDINAL; ParamNo: CARDINAL;
                       ParamName: Name; ParamType: CARDINAL) : BOOLEAN ;
VAR
   ParSym     : CARDINAL ;
   VariableSym: CARDINAL ;
BEGIN
   IF ParamNo<=NoOfParam(Sym)
   THEN
      (* Check the parameter *)
      (* RETURN ...          *)
   ELSE
      (* Add a new parameter *)
      NewSym(ParSym) ;
      WITH Symbols[ParSym] DO
         SymbolType := VarParamSym ;
         WITH VarParam DO
            name := ParamName ;
            Type := ParamType ;
            InitWhereDeclared(At)
         END
      END ;
      AddParameter(Sym, ParSym) ;
      VariableSym := MakeVar(ParamName) ;
      (* Note that the parameter is now treated as a local variable *)
      PutVar(VariableSym, ParamType) ;
      (*
         Normal VAR parameters have LeftValue,
         however Unbounded parameters have RightValue.
      *)
      IF IsUnbounded(ParamType)
      THEN
         PutMode(VariableSym, RightValue)
      ELSE
         PutMode(VariableSym, LeftValue)
      END ;
      RETURN( TRUE )
   END
END PutVarParam ;


(*
   AddParameter - adds a parameter ParSym to a procedure Sym.
*)

PROCEDURE AddParameter (Sym: CARDINAL; ParSym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: PutItemIntoList(Procedure.ListOfParam, ParSym) |
      ProcTypeSym : PutItemIntoList(ProcType.ListOfParam, ParSym)

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END AddParameter ;


(*
   IsVarParam - Returns a conditional depending whether parameter ParamNo
                is a VAR parameter.
*)

PROCEDURE IsVarParam (Sym: CARDINAL; ParamNo: CARDINAL) : BOOLEAN ;
VAR
   IsVar: BOOLEAN ;
BEGIN
   IsVar := FALSE ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: IsVar := IsNthParamVar(Procedure.ListOfParam, ParamNo) |
      ProcTypeSym:  IsVar := IsNthParamVar(ProcType.ListOfParam, ParamNo)

      ELSE
         InternalError('expecting a Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( IsVar )
END IsVarParam ;


(*
   IsNthParamVar - returns true if the n th parameter of the parameter list,
                   List, is a VAR parameter.
*)

PROCEDURE IsNthParamVar (Head: List; n: CARDINAL) : BOOLEAN ;
VAR
   p: CARDINAL ;
BEGIN
   p := GetItemFromList(Head, n) ;
   IF p=NulSym
   THEN
      InternalError('parameter does not exist', __FILE__, __LINE__)
   ELSE
      WITH Symbols[p] DO
         CASE SymbolType OF

         VarParamSym: RETURN( TRUE ) |
         ParamSym   : RETURN( FALSE )

         ELSE
            InternalError('expecting Param or VarParam symbol', __FILE__, __LINE__)
         END
      END
   END
END IsNthParamVar ;


(*
   NoOfParam - Returns the number of parameters that procedure Sym contains.
*)

PROCEDURE NoOfParam (Sym: CARDINAL) : CARDINAL ;
VAR
   n: CARDINAL ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: n := NoOfItemsInList(Procedure.ListOfParam) |
      ProcTypeSym : n := NoOfItemsInList(ProcType.ListOfParam)

      ELSE
         InternalError('expecting a Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( n )
END NoOfParam ;


(*
   NoOfLocalVar - returns the number of local variables that exist in
                  procedure Sym. Parameters are NOT included in the
                  count.
*)

PROCEDURE NoOfLocalVar (Sym: CARDINAL) : CARDINAL ;
VAR
   n: CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: n := NoOfItemsInList(Procedure.ListOfVars)
 
      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END ;
   (*
      Parameters are actually included in the list of local varaibles,
      therefore we must subtract the Parameter Number from local variable
      total.
   *)
   RETURN( n-NoOfParam(Sym) )
END NoOfLocalVar ;


(*
   IsUnboundedParam - Returns a conditional depending whether parameter
                      ParamNo is an unbounded array procedure parameter.
*)

PROCEDURE IsUnboundedParam (Sym: CARDINAL; ParamNo: CARDINAL) : BOOLEAN ;
BEGIN
   Assert(IsProcedure(Sym) OR IsProcType(Sym)) ;
   RETURN( IsUnbounded(GetType(GetNthParam(Sym, ParamNo))) )
END IsUnboundedParam ;


(*
   IsParameter - returns true if Sym is a parameter symbol.
*)

PROCEDURE IsParameter (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ParamSym,
      VarParamSym:  RETURN( TRUE )

      ELSE
         RETURN( FALSE )
      END
   END
END IsParameter ;


(*
   IsProcedure - returns true if Sym is a procedure symbol.
*)

PROCEDURE IsProcedure (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=ProcedureSym )
END IsProcedure ;


(*
   ProcedureParametersDefined - dictates to procedure symbol, Sym,
                                that its parameters have been defined.
*)

PROCEDURE ProcedureParametersDefined (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Assert(NOT Procedure.ParamDefined) ;
                    Procedure.ParamDefined := TRUE

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END ProcedureParametersDefined ;


(*
   AreProcedureParametersDefined - returns true if the parameters to procedure
                                   symbol, Sym, have been defined.
*)

PROCEDURE AreProcedureParametersDefined (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: RETURN( Procedure.ParamDefined )

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END AreProcedureParametersDefined ;


(*
   ParametersDefinedInDefinition - dictates to procedure symbol, Sym,
                                   that its parameters have been defined in
                                   a definition module.
*)

PROCEDURE ParametersDefinedInDefinition (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Assert(NOT Procedure.DefinedInDef) ;
                    Procedure.DefinedInDef := TRUE

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END ParametersDefinedInDefinition ;


(*
   AreParametersDefinedInDefinition - returns true if procedure symbol, Sym,
                                      has had its parameters been defined in
                                      a definition module.
*)

PROCEDURE AreParametersDefinedInDefinition (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: RETURN( Procedure.DefinedInDef )

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END AreParametersDefinedInDefinition ;


(*
   ParametersDefinedInImplementation - dictates to procedure symbol, Sym,
                                       that its parameters have been defined in
                                       a implemtation module.
*)

PROCEDURE ParametersDefinedInImplementation (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Assert(NOT Procedure.DefinedInImp) ;
                    Procedure.DefinedInImp := TRUE

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END ParametersDefinedInImplementation ;


(*
   AreParametersDefinedInImplementation - returns true if procedure symbol, Sym,
                                          has had its parameters been defined in
                                          an implementation module.
*)

PROCEDURE AreParametersDefinedInImplementation (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: RETURN( Procedure.DefinedInImp )

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END AreParametersDefinedInImplementation ;


(*
   MakePointer - returns a pointer symbol with PointerName.
*)

PROCEDURE MakePointer (PointerName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(PointerName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(PointerName) ;
      (* Now add this pointer to the symbol table of the current scope *)
      AddSymToScope(Sym, PointerName)
   END ;
   WITH Symbols[Sym] DO
      SymbolType := PointerSym ;
      CASE SymbolType OF

      PointerSym: Pointer.Type := NulSym ;
                  Pointer.name := PointerName ;
                  Pointer.Size := InitValue()

      ELSE
         InternalError('expecting a Pointer symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( Sym )
END MakePointer ;


(*
   PutPointer - gives a pointer symbol a type, PointerType.
*)

PROCEDURE PutPointer (Sym: CARDINAL; PointerType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      PointerSym: Pointer.Type := PointerType

      ELSE
         InternalError('expecting a Pointer symbol', __FILE__, __LINE__)
      END
   END
END PutPointer ;


(*
   IsPointer - returns true is Sym is a pointer type symbol.
*)

PROCEDURE IsPointer (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=PointerSym )
END IsPointer ;


(*
   IsRecord - returns true is Sym is a record type symbol.
*)

PROCEDURE IsRecord (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=RecordSym )
END IsRecord ;


(*
   IsArray - returns true is Sym is an array type symbol.
*)

PROCEDURE IsArray (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=ArraySym )
END IsArray ;


(*
   IsEnumeration - returns true if Sym is an enumeration symbol.
*)

PROCEDURE IsEnumeration (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=EnumerationSym )
END IsEnumeration ;


(*
   IsUnbounded - returns true if Sym is an unbounded symbol.
*)

PROCEDURE IsUnbounded (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=UnboundedSym )
END IsUnbounded ;


(*
   GetVarFather - returns the symbol which is the father to variable Sym.
                  ie a Module, DefImp or Procedure Symbol.
*)

PROCEDURE GetVarFather (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: RETURN( Var.Father )

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END GetVarFather ;


(*
   NoOfElements - Returns the number of elements in array Sym,
                  or the number of elements in an enumeration Sym or
                  the number of interface symbols in an Interface list.
*)

PROCEDURE NoOfElements (Sym: CARDINAL) : CARDINAL ;
VAR
   n: CARDINAL ;                 
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ArraySym:       n := NoOfItemsInList(Array.ListOfSubs) |
      UnboundedSym:   n := 1 |   (* Standard language limitation *)
      EnumerationSym: n := Symbols[Sym].Enumeration.NoOfElements |
      InterfaceSym:   n := NoOfItemsInList(Interface.ObjectList)

      ELSE
         InternalError('expecting an Array or UnBounded symbol', __FILE__, __LINE__)
      END
   END ;
   RETURN( n )
END NoOfElements ;


(*
   PutFieldArray - places an index field into the array Sym. The
                   index field is a subrange sym.
*)

PROCEDURE PutFieldArray (Sym: CARDINAL; SubrangeSymbol: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ArraySym: PutItemIntoList(Array.ListOfSubs, SubrangeSymbol)

      ELSE
         InternalError('expecting an Array symbol', __FILE__, __LINE__)
      END
   END
END PutFieldArray ;


(*
   MakeSubscript - makes a subscript Symbol.
                   No name is required.
*)

PROCEDURE MakeSubscript () : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := SubscriptSym ;
      WITH Subscript DO
         Type := NulSym ;        (* Index to a subrange symbol. *)
         Size := InitValue() ;   (* Size of this indice in*Size *)
         Offset := InitValue() ; (* Offset at runtime of symbol *)
                                 (* Pseudo ie: Offset+Size*i    *)
                                 (* 1..n. The array offset is   *)
                                 (* the real memory offset.     *)
                                 (* This offset allows the a[i] *)
                                 (* to be calculated without    *)
                                 (* the need to perform         *)
                                 (* subtractions when a[4..10]  *)
                                 (* needs to be indexed.        *)
         InitWhereDeclared(At)   (* Declared here               *)
      END
   END ;
   RETURN( Sym )
END MakeSubscript ;


(*
   PutSubscript - gives a subscript symbol a type, SimpleType.
*)

PROCEDURE PutSubscript (Sym: CARDINAL; SimpleType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      SubscriptSym: Subscript.Type := SimpleType ;

      ELSE
         InternalError('expecting a SubScript symbol', __FILE__, __LINE__)
      END
   END
END PutSubscript ;


(*
   MakeSet - makes a set Symbol with name, SetName.
*)

PROCEDURE MakeSet (SetName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := CheckForHiddenType(SetName) ;
   IF Sym=NulSym
   THEN
      Sym := DeclareSym(SetName) ;
      (* Now add this set to the symbol table of the current scope *)
      AddSymToScope(Sym, SetName) ;
   END ;
   WITH Symbols[Sym] DO
      SymbolType := SetSym ;
      WITH Set DO
      	 name := SetName ;      (* The name of the set.        *)
         Type := NulSym ;       (* Index to a subrange symbol. *)
         Size := InitValue() ;  (* Size of this set            *)
         InitWhereDeclared(At)  (* Declared here               *)
      END
   END ;
   RETURN( Sym )
END MakeSet ;


(*
   PutSet - places SimpleType as the type for set, Sym.
*)

PROCEDURE PutSet (Sym: CARDINAL; SimpleType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      SetSym: WITH Set DO
      	         Type := SimpleType    (* Index to a subrange symbol  *)
      	       	     	      	       (* or an enumeration type.     *)
              END
      ELSE
         InternalError('expecting a Set symbol', __FILE__, __LINE__)
      END
   END
END PutSet ;


(*
   IsSet - returns TRUE if Sym is a set symbol.
*)

PROCEDURE IsSet (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( Symbols[Sym].SymbolType=SetSym )
END IsSet ;


(*
   MakeUnbounded - makes an unbounded array Symbol.
                   No name is required.
*)

PROCEDURE MakeUnbounded () : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   NewSym(Sym) ;
   WITH Symbols[Sym] DO
      SymbolType := UnboundedSym ;
      WITH Unbounded DO
         Type := NulSym ;      (* Index to a simple type.     *)
         Size := InitValue() ; (* Size in bytes for this sym  *)
         InitWhereDeclared(At) (* Declared here               *)
      END
   END ;
   RETURN( Sym )
END MakeUnbounded ;


(*
   PutUnbounded - gives an unbounded symbol a type, SimpleType.
*)

PROCEDURE PutUnbounded (Sym: CARDINAL; SimpleType: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      UnboundedSym: Unbounded.Type := SimpleType ;

      ELSE
         InternalError('expecting an UnBounded symbol', __FILE__, __LINE__)
      END
   END
END PutUnbounded ;


(*
   PutArray - places a type symbol into an Array.
*)

PROCEDURE PutArray (Sym, TypeSymbol: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ArraySym: WITH Array DO
                   Type := TypeSymbol (* The Array Type. ARRAY OF Type.      *)
                END
      ELSE
         InternalError('expecting an Array symbol', __FILE__, __LINE__)
      END
   END
END PutArray ;


(*
   Father - returns the father of a type.
*)

PROCEDURE Father (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym          : RETURN( Module.Father ) |
      VarSym             : RETURN( Var.Father ) |
      ProcedureSym       : RETURN( Procedure.Father ) |
      RecordFieldSym     : RETURN( RecordField.Parent ) |
      VarientSym         : RETURN( Varient.Parent ) |
      VarientFieldSym    : RETURN( VarientField.Parent ) |
      EnumerationSym     : RETURN( Enumeration.Parent ) |
      EnumerationFieldSym: RETURN( EnumerationField.Type )

      ELSE
         InternalError('not implemented yet', __FILE__, __LINE__)
      END
   END
END Father ;


(*
   IsRecordField - returns true if Sym is a record field.
*)

PROCEDURE IsRecordField (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=RecordFieldSym )
END IsRecordField ;


(*
   MakeProcType - returns a procedure type symbol with ProcTypeName.
*)

PROCEDURE MakeProcType (ProcTypeName: Name) : CARDINAL ;
VAR
   Sym: CARDINAL ;
BEGIN
   Sym := DeclareSym(ProcTypeName) ;
   WITH Symbols[Sym] DO
      SymbolType := ProcTypeSym ;
      CASE SymbolType OF

      ProcTypeSym: ProcType.ReturnType := NulSym ;
                   ProcType.name := ProcTypeName ;
                   InitList(ProcType.ListOfParam) ;
                   ProcType.Size := InitValue() ;
                   ProcType.TotalParamSize := InitValue() ;  (* size of all parameters.       *)
                   InitWhereDeclared(ProcType.At)  (* Declared here *)

      ELSE
         InternalError('expecting ProcType symbol', __FILE__, __LINE__)
      END
   END ;
   (* Now add this ProcType to the symbol table of the current scope *)
   AddSymToScope(Sym, ProcTypeName) ;
   RETURN( Sym )
END MakeProcType ;


(*
   PutProcTypeParam - Places a Non VAR parameter ParamName with type
                      ParamType into ProcType Sym.
*)

PROCEDURE PutProcTypeParam (Sym: CARDINAL; ParamType: CARDINAL) ;
VAR
   ParSym: CARDINAL ;
BEGIN
   NewSym(ParSym) ;
   WITH Symbols[ParSym] DO
      SymbolType := ParamSym ;
      WITH Param DO
         name := NulName ;
         Type := ParamType
      END
   END ;
   AddParameter(Sym, ParSym)
END PutProcTypeParam ;


(*
   PutProcTypeVarParam - Places a Non VAR parameter ParamName with type
                         ParamType into ProcType Sym.
*)

PROCEDURE PutProcTypeVarParam (Sym: CARDINAL; ParamType: CARDINAL) ;
VAR
   ParSym: CARDINAL ;
BEGIN
   NewSym(ParSym) ;
   WITH Symbols[ParSym] DO
      SymbolType := VarParamSym ;
      WITH Param DO
         name := NulName ;
         Type := ParamType
      END
   END ;
   AddParameter(Sym, ParSym)
END PutProcTypeVarParam ;


(*
   PutProcedureReachable - Sets the procedure, Sym, to be reachable by the
                           main Module.
*)

PROCEDURE PutProcedureReachable (Sym: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Procedure.Reachable := TRUE

      ELSE
         InternalError('expecting Procedure symbol', __FILE__, __LINE__)
      END
   END
END PutProcedureReachable ;


(*
   PutModuleStartQuad - Places QuadNumber into the Module symbol, Sym.
                        QuadNumber is the start quad of Module,
                        Sym.
*)

PROCEDURE PutModuleStartQuad (Sym: CARDINAL; QuadNumber: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym: Module.StartQuad := QuadNumber |
      DefImpSym: DefImp.StartQuad := QuadNumber

      ELSE
         InternalError('expecting a Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutModuleStartQuad ;


(*
   PutModuleEndQuad - Places QuadNumber into the Module symbol, Sym.
                      QuadNumber is the end quad of Module,
                      Sym.
*)

PROCEDURE PutModuleEndQuad (Sym: CARDINAL; QuadNumber: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym: Module.EndQuad := QuadNumber |
      DefImpSym: DefImp.EndQuad := QuadNumber

      ELSE
         InternalError('expecting a Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END PutModuleEndQuad ;


(*
   GetModuleQuads - Returns, Start and End, Quads of a Module, Sym.
                    Start and End represent the initialization code
                    of the Module, Sym.
*)

PROCEDURE GetModuleQuads (Sym: CARDINAL; VAR Start, End: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym: WITH Module DO
                    Start := StartQuad ;
                    End := EndQuad
                 END |
      DefImpSym: WITH DefImp DO
                    Start := StartQuad ;
                    End := EndQuad
                 END

      ELSE
         InternalError('expecting a Module or DefImp symbol', __FILE__, __LINE__)
      END
   END
END GetModuleQuads ;


(*
   PutProcedureStartQuad - Places QuadNumber into the Procedure symbol, Sym.
                           QuadNumber is the start quad of procedure,
                           Sym.
*)

PROCEDURE PutProcedureStartQuad (Sym: CARDINAL; QuadNumber: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Procedure.StartQuad := QuadNumber

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END PutProcedureStartQuad ;


(*
   PutProcedureEndQuad - Places QuadNumber into the Procedure symbol, Sym.
                         QuadNumber is the end quad of procedure,
                         Sym.
*)

PROCEDURE PutProcedureEndQuad (Sym: CARDINAL; QuadNumber: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: Procedure.EndQuad := QuadNumber

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END PutProcedureEndQuad ;


(*
   GetProcedureQuads - Returns, Start and End, Quads of a procedure, Sym.
*)

PROCEDURE GetProcedureQuads (Sym: CARDINAL; VAR Start, End: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: WITH Procedure DO
                       Start := StartQuad ;
                       End := EndQuad
                    END

      ELSE
         InternalError('expecting a Procedure symbol', __FILE__, __LINE__)
      END
   END
END GetProcedureQuads ;


(*
   GetVarReadQuads - assigns Start and End to the beginning and end of
                     symbol, Sym, read history usage.
*)

PROCEDURE GetVarReadQuads (Sym: CARDINAL; VAR Start, End: CARDINAL) ;
BEGIN
   GetVarReadLimitQuads(Sym, 0, 0, Start, End)
END GetVarReadQuads ;


(*
   GetVarWriteQuads - assigns Start and End to the beginning and end of
                      symbol, Sym, usage.
*)

PROCEDURE GetVarWriteQuads (Sym: CARDINAL; VAR Start, End: CARDINAL) ;
BEGIN
   GetVarWriteLimitQuads(Sym, 0, 0, Start, End)
END GetVarWriteQuads ;


(*
   Max - 
*)

PROCEDURE Max (a, b: CARDINAL) : CARDINAL ;
BEGIN
   IF a>b
   THEN
      RETURN( a )
   ELSE
      RETURN( b )
   END
END Max ;


(*
   Min - 
*)

PROCEDURE Min (a, b: CARDINAL) : CARDINAL ;
BEGIN
   IF a<b
   THEN
      RETURN( a )
   ELSE
      RETURN( b )
   END
END Min ;


(*
   GetVarQuads - assigns Start and End to the beginning and end of
                 symbol, Sym, usage.
*)

PROCEDURE GetVarQuads (Sym: CARDINAL; VAR Start, End: CARDINAL) ;
VAR
   StartRead, EndRead,
   StartWrite, EndWrite: CARDINAL ;
BEGIN
   GetVarReadQuads(Sym, StartRead, EndRead) ;
   GetVarWriteQuads(Sym, StartWrite, EndWrite) ;
   IF StartRead=0
   THEN
      Start := StartWrite
   ELSIF StartWrite=0
   THEN
      Start := StartRead
   ELSE
      Start := Min(StartRead, StartWrite)
   END ;
   IF EndRead=0
   THEN
      End := EndWrite
   ELSIF EndWrite=0
   THEN
      End := EndRead
   ELSE
      End := Max(EndRead, EndWrite)
   END
END GetVarQuads ;


(*
   PutVarQuad - places Quad into the list of symbol usage.
*)

PROCEDURE PutVarReadQuad (Sym: CARDINAL; Quad: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: IncludeItemIntoList(Var.ReadUsageList, Quad)

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END PutVarReadQuad ;


(*
   RemoveVarReadQuad - places Quad into the list of symbol usage.
*)

PROCEDURE RemoveVarReadQuad (Sym: CARDINAL; Quad: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: RemoveItemFromList(Var.ReadUsageList, Quad)

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END RemoveVarReadQuad ;


(*
   PutVarWriteQuad - places Quad into the list of symbol usage.
*)

PROCEDURE PutVarWriteQuad (Sym: CARDINAL; Quad: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: IncludeItemIntoList(Var.WriteUsageList, Quad)

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END PutVarWriteQuad ;


(*
   RemoveVarWriteQuad - places Quad into the list of symbol usage.
*)

PROCEDURE RemoveVarWriteQuad (Sym: CARDINAL; Quad: CARDINAL) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: RemoveItemFromList(Var.WriteUsageList, Quad)

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END RemoveVarWriteQuad ;


(*
   GetVarReadLimitQuads - returns Start and End which have been assigned
                          the start and end of when the symbol was read
                          to within: StartLimit..EndLimit.
*)

PROCEDURE GetVarReadLimitQuads (Sym: CARDINAL; StartLimit, EndLimit: CARDINAL;
                                VAR Start, End: CARDINAL) ;
VAR
   i, j, n: CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: End := 0 ;
              Start := 0 ;
              i := 1 ;
              n := NoOfItemsInList(Var.ReadUsageList) ;
              WHILE i<=n DO
                 j := GetItemFromList(Var.ReadUsageList, i) ;
                 IF (j>End) AND (j>=StartLimit) AND ((j<=EndLimit) OR (EndLimit=0))
                 THEN
                    End := j
                 END ;
                 IF ((Start=0) OR (j<Start)) AND (j#0) AND (j>=StartLimit) AND
                    ((j<=EndLimit) OR (EndLimit=0))
                 THEN
                    Start := j
                 END ;
                 INC(i)
              END

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END GetVarReadLimitQuads ;


(*
   GetVarWriteLimitQuads - returns Start and End which have been assigned
                           the start and end of when the symbol was written
                           to within: StartLimit..EndLimit.
*)

PROCEDURE GetVarWriteLimitQuads (Sym: CARDINAL; StartLimit, EndLimit: CARDINAL;
                                 VAR Start, End: CARDINAL) ;
VAR
   i, j, n: CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: End := 0 ;
              Start := 0 ;
              i := 1 ;
              n := NoOfItemsInList(Var.WriteUsageList) ;
              WHILE i<=n DO
                 j := GetItemFromList(Var.WriteUsageList, i) ;
                 IF (j>End) AND (j>=StartLimit) AND ((j<=EndLimit) OR (EndLimit=0))
                 THEN
                    End := j
                 END ;
                 IF ((Start=0) OR (j<Start)) AND (j#0) AND (j>=StartLimit) AND
                    ((j<=EndLimit) OR (EndLimit=0))
                 THEN
                    Start := j
                 END ;
                 INC(i)
              END

      ELSE
         InternalError('expecting a Var symbol', __FILE__, __LINE__)
      END
   END
END GetVarWriteLimitQuads ;


(*
   GetNthProcedure - Returns the Nth procedure in Module, Sym.
*)

PROCEDURE GetNthProcedure (Sym: CARDINAL; n: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym: RETURN( GetItemFromList(DefImp.ListOfProcs, n) ) |
      ModuleSym: RETURN( GetItemFromList(Module.ListOfProcs, n) )

      ELSE
         InternalError('expecting a DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END GetNthProcedure ;


(*
   GetDeclared - returns the token where this symbol was declared.
*)

PROCEDURE GetDeclared (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarientSym         : RETURN( Varient.At.Declared ) |
      RecordSym          : RETURN( Record.At.Declared ) |
      SubrangeSym        : RETURN( Subrange.At.Declared ) |
      EnumerationSym     : RETURN( Enumeration.At.Declared ) |
      ArraySym           : RETURN( Array.At.Declared ) |
      SubscriptSym       : RETURN( Subscript.At.Declared ) |
      UnboundedSym       : RETURN( Unbounded.At.Declared ) |
      ProcedureSym       : RETURN( Procedure.At.Declared ) |
      ProcTypeSym        : RETURN( ProcType.At.Declared ) |
      ParamSym           : RETURN( Param.At.Declared ) |
      VarParamSym        : RETURN( VarParam.At.Declared ) |
      ConstStringSym     : RETURN( ConstString.At.Declared ) |
      ConstLitSym        : RETURN( ConstLit.At.Declared ) |
      ConstVarSym        : RETURN( ConstVar.At.Declared ) |
      VarSym             : RETURN( Var.At.Declared ) |
      TypeSym            : RETURN( Type.At.Declared ) |
      PointerSym         : RETURN( Pointer.At.Declared ) |
      RecordFieldSym     : RETURN( RecordField.At.Declared ) |
      VarientFieldSym    : RETURN( VarientField.At.Declared ) |
      EnumerationFieldSym: RETURN( EnumerationField.At.Declared ) |
      SetSym             : RETURN( Set.At.Declared ) |
      DefImpSym          : RETURN( DefImp.At.Declared ) |
      ModuleSym          : RETURN( Module.At.Declared ) |
      UndefinedSym       : RETURN( GetFirstUsed(Sym) )

      ELSE
         InternalError('not expecting this type of symbol', __FILE__, __LINE__)
      END
   END
END GetDeclared ;


(*
   GetFirstUsed - returns the token where this symbol was first used.
*)

PROCEDURE GetFirstUsed (Sym: CARDINAL) : CARDINAL ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      UndefinedSym       : RETURN( Undefined.At.FirstUsed ) |
      VarientSym         : RETURN( Varient.At.FirstUsed ) |
      RecordSym          : RETURN( Record.At.FirstUsed ) |
      SubrangeSym        : RETURN( Subrange.At.FirstUsed ) |
      EnumerationSym     : RETURN( Enumeration.At.FirstUsed ) |
      ArraySym           : RETURN( Array.At.FirstUsed ) |
      SubscriptSym       : RETURN( Subscript.At.FirstUsed ) |
      UnboundedSym       : RETURN( Unbounded.At.FirstUsed ) |
      ProcedureSym       : RETURN( Procedure.At.FirstUsed ) |
      ProcTypeSym        : RETURN( ProcType.At.FirstUsed ) |
      ParamSym           : RETURN( Param.At.FirstUsed ) |
      VarParamSym        : RETURN( VarParam.At.FirstUsed ) |
      ConstStringSym     : RETURN( ConstString.At.FirstUsed ) |
      ConstLitSym        : RETURN( ConstLit.At.FirstUsed ) |
      ConstVarSym        : RETURN( ConstVar.At.FirstUsed ) |
      VarSym             : RETURN( Var.At.FirstUsed ) |
      TypeSym            : RETURN( Type.At.FirstUsed ) |
      PointerSym         : RETURN( Pointer.At.FirstUsed ) |
      RecordFieldSym     : RETURN( RecordField.At.FirstUsed ) |
      VarientFieldSym    : RETURN( VarientField.At.FirstUsed ) |
      EnumerationFieldSym: RETURN( EnumerationField.At.FirstUsed ) |
      SetSym             : RETURN( Set.At.FirstUsed ) |
      DefImpSym          : RETURN( DefImp.At.FirstUsed ) |
      ModuleSym          : RETURN( Module.At.FirstUsed )

      ELSE
         InternalError('not expecting this type of symbol', __FILE__, __LINE__)
      END
   END
END GetFirstUsed ;


(*
   ForeachProcedureDo - for each procedure in module, Sym, do procedure, P.
*)

PROCEDURE ForeachProcedureDo (Sym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym: ForeachItemInListDo( DefImp.ListOfProcs, P) |
      ModuleSym: ForeachItemInListDo( Module.ListOfProcs, P)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END ForeachProcedureDo ;


(*
   ForeachInnerModuleDo - for each inner module in module, Sym,
                          do procedure, P.
*)

PROCEDURE ForeachInnerModuleDo (Sym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      DefImpSym: ForeachItemInListDo( DefImp.ListOfModules, P) |
      ModuleSym: ForeachItemInListDo( Module.ListOfModules, P)

      ELSE
         InternalError('expecting DefImp or Module symbol', __FILE__, __LINE__)
      END
   END
END ForeachInnerModuleDo ;


(*
   ForeachModuleDo - for each module do procedure, P.
*)

PROCEDURE ForeachModuleDo (P: PerformOperation) ;
BEGIN
   ForeachNodeDo(ModuleTree, P)
END ForeachModuleDo ;


(*
   ForeachFieldEnumerationDo - for each field in enumeration, Sym,
                               do procedure, P.
*)

PROCEDURE ForeachFieldEnumerationDo (Sym: CARDINAL; P: PerformOperation) ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      EnumerationSym: ForeachNodeDo( Enumeration.LocalSymbols, P)

      ELSE
         InternalError('expecting Enumeration symbol', __FILE__, __LINE__)
      END
   END
END ForeachFieldEnumerationDo ;


(*
   IsProcedureReachable - Returns true if the procedure, Sym, is
                          reachable from the main Module.
*)

PROCEDURE IsProcedureReachable (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: RETURN( Procedure.Reachable )

      ELSE
         InternalError('expecting Procedure symbol', __FILE__, __LINE__)
      END
   END
END IsProcedureReachable ;


(*
   IsProcType - returns true if Sym is a ProcType Symbol.
*)

PROCEDURE IsProcType (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=ProcTypeSym )
END IsProcType ;


(*
   IsVar - returns true if Sym is a Var Symbol.
*)

PROCEDURE IsVar (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=VarSym )
END IsVar ;


(*
   IsConst - returns true if Sym contains a constant value.
*)

PROCEDURE IsConst (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( (SymbolType=ConstVarSym) OR
              (SymbolType=ConstLitSym) OR
              (SymbolType=ConstStringSym) OR
              ((SymbolType=VarSym) AND (Var.AddrMode=ImmediateValue)) OR
              (SymbolType=EnumerationFieldSym)
            )
   END
END IsConst ;


(*
   IsConstString - returns true if Sym is a string.
*)

PROCEDURE IsConstString (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( SymbolType=ConstStringSym )
   END
END IsConstString ;


(*
   IsConstLit - returns true if Sym is a literal constant.
*)

PROCEDURE IsConstLit (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( SymbolType=ConstLitSym )
   END
END IsConstLit ;


(*
   IsDummy - returns true if Sym is a Dummy symbol.
*)

PROCEDURE IsDummy (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=DummySym )
END IsDummy ;


(*
   IsTemporary - returns true if Sym is a Temporary symbol.
*)

PROCEDURE IsTemporary (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: RETURN( Var.IsTemp )

      ELSE
         RETURN( FALSE )
      END
   END
END IsTemporary ;


(*
   IsVarAParam - returns true if Sym is a variable declared as a parameter.
*)

PROCEDURE IsVarAParam (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      VarSym: RETURN( Var.IsParam )

      ELSE
         RETURN( FALSE )
      END
   END
END IsVarAParam ;


(*
   IsSubscript - returns true if Sym is a subscript symbol.
*)

PROCEDURE IsSubscript (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=SubscriptSym )
END IsSubscript ;


(*
   IsSubrange - returns true if Sym is a subrange symbol.
*)

PROCEDURE IsSubrange (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( Symbols[Sym].SymbolType=SubrangeSym )
END IsSubrange ;


(*
   IsProcedureVariable - returns true if a Sym is a variable and
                         it was declared within a procedure.
*)

PROCEDURE IsProcedureVariable (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN( IsVar(Sym) AND IsProcedure(GetVarFather(Sym)) )
END IsProcedureVariable ;


(*
   IsProcedureNested - returns TRUE if procedure, Sym, was
                       declared as a nested procedure.
*)

PROCEDURE IsProcedureNested (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN( IsProcedure(Sym) AND (IsProcedure(GetScopeAuthor(Sym))) )
END IsProcedureNested ;


(*
   IsAModula2Type - returns true if Sym, is a:
                    IsType, IsPointer, IsRecord, IsEnumeration,
                    IsSubrange, IsArray, IsUnbounded, IsProcType.
                    NOTE that it different from IsType.
                    IsType is used for:
                    TYPE
                       a = CARDINAL ;  (* IsType(a)=TRUE *)
*)

PROCEDURE IsAModula2Type (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   RETURN(
           IsType(Sym) OR IsRecord(Sym) OR IsPointer(Sym) OR
           IsEnumeration(Sym) OR IsSubrange(Sym) OR IsArray(Sym) OR
           IsUnbounded(Sym) OR IsProcType(Sym) OR IsSet(Sym)
         )
END IsAModula2Type ;


(*
   IsGnuAsmVolatile - returns TRUE if a GnuAsm symbol was defined as VOLATILE.
*)

PROCEDURE IsGnuAsmVolatile (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      GnuAsmSym: RETURN( GnuAsm.Volatile )

      ELSE
         InternalError('expecting PutGnuAsm symbol', __FILE__, __LINE__)
      END
   END
END IsGnuAsmVolatile ;


(*
   IsGnuAsm - returns TRUE if Sym is a GnuAsm symbol.
*)

PROCEDURE IsGnuAsm (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( SymbolType=GnuAsmSym )
   END
END IsGnuAsm ;


(*
   IsRegInterface - returns TRUE if Sym is a RegInterface symbol.
*)

PROCEDURE IsRegInterface (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   WITH Symbols[Sym] DO
      RETURN( SymbolType=InterfaceSym )
   END
END IsRegInterface ;


(*
   GetParam - returns the ParamNo parameter from procedure ProcSym
*)

PROCEDURE GetParam (Sym: CARDINAL; ParamNo: CARDINAL) : CARDINAL ;
BEGIN
   CheckLegal(Sym) ;
   IF ParamNo=0
   THEN
      (* Parameter Zero is the return argument for the Function *)
      RETURN(GetType(Sym))
   ELSE
      RETURN(GetNthParam(Sym, ParamNo))
   END
END GetParam ;


(*
   IsSizeSolved - returns true if the size of Sym is solved.
*)

PROCEDURE IsSizeSolved (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym    : RETURN( IsSolved(Procedure.Size) ) |
      ModuleSym       : RETURN( IsSolved(Module.Size) ) |
      VarSym          : RETURN( IsSolved(Var.Size) ) |
      TypeSym         : RETURN( IsSolved(Type.Size) ) |
      SetSym          : RETURN( IsSolved(Set.Size) ) |
      RecordSym       : RETURN( IsSolved(Record.Size) ) |
      VarientSym      : RETURN( IsSolved(Varient.Size) ) |
      EnumerationSym  : RETURN( IsSolved(Enumeration.Size) ) |
      DefImpSym       : RETURN( IsSolved(DefImp.Size) ) |
      PointerSym      : RETURN( IsSolved(Pointer.Size) ) |
      ArraySym        : RETURN( IsSolved(Array.Size) ) |
      RecordFieldSym  : RETURN( IsSolved(RecordField.Size) ) |
      VarientFieldSym : RETURN( IsSolved(VarientField.Size) ) |
      SubrangeSym     : RETURN( IsSolved(Subrange.Size) ) |
      SubscriptSym    : RETURN( IsSolved(Subscript.Size) ) |
      ProcTypeSym     : RETURN( IsSolved(ProcType.Size) ) |
      UnboundedSym    : RETURN( IsSolved(Unbounded.Size) )

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END IsSizeSolved ;


(*
   IsOffsetSolved - returns true if the Offset of Sym is solved.
*)

PROCEDURE IsOffsetSolved (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym       : RETURN( IsSolved(Module.Offset) ) |
      VarSym          : RETURN( IsSolved(Var.Offset) ) |
      DefImpSym       : RETURN( IsSolved(DefImp.Offset) ) |
      RecordFieldSym  : RETURN( IsSolved(RecordField.Offset) ) |
      VarientFieldSym : RETURN( IsSolved(VarientField.Offset) )

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END IsOffsetSolved ;


(*
   IsValueSolved - returns true if the value of Sym is solved.
*)

PROCEDURE IsValueSolved (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstLitSym         : RETURN( IsSolved(ConstLit.Value) ) |
      ConstVarSym         : RETURN( IsSolved(ConstVar.Value) ) |
      EnumerationFieldSym : RETURN( IsSolved(EnumerationField.Value) ) |
      ConstStringSym      : RETURN( TRUE )

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END IsValueSolved ;


(*
   IsSumOfParamSizeSolved - has the sum of parameters been solved yet?
*)

PROCEDURE IsSumOfParamSizeSolved (Sym: CARDINAL) : BOOLEAN ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: RETURN( IsSolved(Procedure.TotalParamSize) ) |
      ProcTypeSym : RETURN( IsSolved(ProcType.TotalParamSize) )

      ELSE
         InternalError('expecting Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END
END IsSumOfParamSizeSolved ;


(*
   PushSize - pushes the size of Sym.
*)

PROCEDURE PushSize (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym    : PushFrom(Procedure.Size) |
      ModuleSym       : PushFrom(Module.Size) |
      VarSym          : PushFrom(Var.Size) |
      TypeSym         : PushFrom(Type.Size) |
      SetSym          : PushFrom(Set.Size) |
      VarientSym      : PushFrom(Varient.Size) |
      RecordSym       : PushFrom(Record.Size) |
      EnumerationSym  : PushFrom(Enumeration.Size) |
      DefImpSym       : PushFrom(DefImp.Size) |
      PointerSym      : PushFrom(Pointer.Size) |
      ArraySym        : PushFrom(Array.Size) |
      RecordFieldSym  : PushFrom(RecordField.Size) |
      VarientFieldSym : PushFrom(VarientField.Size) |
      SubrangeSym     : PushFrom(Subrange.Size) |
      SubscriptSym    : PushFrom(Subscript.Size) |
      ProcTypeSym     : PushFrom(ProcType.Size) |
      UnboundedSym    : PushFrom(Unbounded.Size)

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END PushSize ;


(*
   PushOffset - pushes the Offset of Sym.
*)

PROCEDURE PushOffset (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym       : PushFrom(Module.Offset) |
      VarSym          : PushFrom(Var.Offset) |
      DefImpSym       : PushFrom(DefImp.Offset) |
      RecordFieldSym  : PushFrom(RecordField.Offset) |
      VarientFieldSym : PushFrom(VarientField.Offset)

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END PushOffset ;


(*
   PushValue - pushes the Value of Sym onto the ALU stack.
*)

PROCEDURE PushValue (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstLitSym         : PushFrom(ConstLit.Value) |
      ConstVarSym         : PushFrom(ConstVar.Value) |
      EnumerationFieldSym : PushFrom(EnumerationField.Value) |
      ConstStringSym      : PushConstString(Sym)

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END PushValue ;


(*
   PushConstString - pushes the character string onto the ALU stack.
                     It assumes that the character string is only
                     one character long.
*)

PROCEDURE PushConstString (Sym: CARDINAL) ;
VAR
   a: ARRAY [0..10] OF CHAR ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstStringSym: WITH ConstString DO
                         IF Length=1
                         THEN
                            GetKey(String, a) ;
                            PushChar(a[0])
                         ELSE
                            WriteFormat0('ConstString must be length 1')
                         END
                      END

      ELSE
         InternalError('expecting ConstString symbol', __FILE__, __LINE__)
      END
   END
END PushConstString ;
   
   
(* 
   PushParamSize - push the size of parameter, ParamNo,
                   of procedure Sym onto the ALU stack.
*) 
 
PROCEDURE PushParamSize (Sym: CARDINAL; ParamNo: CARDINAL) ;  
VAR
   p, Type: CARDINAL ;
BEGIN
   CheckLegal(Sym) ;
   Assert(IsProcedure(Sym) OR IsProcType(Sym)) ;
   IF ParamNo=0
   THEN
      PushSize(GetType(Sym))
   ELSE
      (*
         can use GetNthParam but 1..n returns parameter.
         But 0 yields the function return type.

         Note that VAR Unbounded parameters and non VAR Unbounded parameters
              contain the unbounded descriptor. VAR unbounded parameters
              do NOT JUST contain an address re: other VAR parameters.
      *)
      IF IsVarParam(Sym, ParamNo) AND (NOT IsUnboundedParam(Sym, ParamNo))
      THEN
         PushSize(Address)     (* VAR parameters point to the variable *)
      ELSE
         p := GetNthParam(Sym, ParamNo) ; (* nth Parameter *)
         (*
            N.B. chose to get the Type of the parameter rather than the Var
            because ProcType's have Type but no Var associated with them.
         *)
         Type := GetType(p) ;  (* ie Variable from Procedure Sym *)
         Assert(p#NulSym) ;    (* If this fails then ParamNo is out of range *)
         PushSize(Type)
      END
   END
END PushParamSize ;

 
(*
   PushSumOfLocalVarSize - push the total size of all local variables
                           onto the ALU stack. 
*)
 
PROCEDURE PushSumOfLocalVarSize (Sym: CARDINAL) ;
VAR
   i: INTEGER ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym,
      DefImpSym,
      ModuleSym   : PushSize(Sym)

      ELSE
         InternalError('expecting Procedure, DefImp or Module symbol', __FILE__, __LINE__)
      END
   END ;
   i := PopInt() ;
   IF i<0
   THEN
      PushInt(-i)
   ELSE
      PushInt(i)
   END
END PushSumOfLocalVarSize ;


(*
   PushSumOfParamSize - push the total size of all parameters onto
                        the ALU stack.
*)

PROCEDURE PushSumOfParamSize (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: PushFrom(Procedure.TotalParamSize) |
      ProcTypeSym : PushFrom(ProcType.TotalParamSize)

      ELSE
         InternalError('expecting Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END
END PushSumOfParamSize ;


(*
   PushVarSize - pushes the size of a variable, Sym.
                 The runtime size of Sym will depend upon its addressing mode,
                 RightValue has size PushSize(GetType(Sym)) and
                 LeftValue has size PushSize(Address) since it points to a
                 variable.
*)

PROCEDURE PushVarSize (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   Assert(IsVar(Sym)) ;
   IF GetMode(Sym)=LeftValue
   THEN
      PushSize(Address)
   ELSE
      Assert(GetMode(Sym)=RightValue) ;
      PushSize(GetType(Sym))
   END
END PushVarSize ;


(*
   PopValue - pops the ALU stack into Value of Sym.
*)

PROCEDURE PopValue (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ConstLitSym         : PopInto(ConstLit.Value) |
      ConstVarSym         : PopInto(ConstVar.Value) |
      EnumerationFieldSym : InternalError('cannot pop into an enumeration field', __FILE__, __LINE__)

      ELSE
         InternalError('symbol type not expected', __FILE__, __LINE__)
      END
   END
END PopValue ;


(*
   PopSize - pops the ALU stack into Size of Sym.
*)

PROCEDURE PopSize (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym    : PopInto(Procedure.Size) |
      ModuleSym       : PopInto(Module.Size) |
      VarSym          : PopInto(Var.Size) |
      TypeSym         : PopInto(Type.Size) |
      RecordSym       : PopInto(Record.Size) |
      VarientSym      : PopInto(Varient.Size) |
      EnumerationSym  : PopInto(Enumeration.Size) |
      DefImpSym       : PopInto(DefImp.Size) |
      PointerSym      : PopInto(Pointer.Size) |
      ArraySym        : PopInto(Array.Size) |
      RecordFieldSym  : PopInto(RecordField.Size) |
      VarientFieldSym : PopInto(VarientField.Size) |
      SubrangeSym     : PopInto(Subrange.Size) |
      SubscriptSym    : PopInto(Subscript.Size) |
      ProcTypeSym     : PopInto(ProcType.Size) |
      UnboundedSym    : PopInto(Unbounded.Size) |
      SetSym          : PopInto(Set.Size)

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END PopSize ;


(*
   PopOffset - pops the ALU stack into Offset of Sym.
*)

PROCEDURE PopOffset (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ModuleSym       : PopInto(Module.Offset) |
      VarSym          : PopInto(Var.Offset) |
      DefImpSym       : PopInto(DefImp.Offset) |
      RecordFieldSym  : PopInto(RecordField.Offset) |
      VarientFieldSym : PopInto(VarientField.Offset)

      ELSE
         InternalError('not expecting this kind of symbol', __FILE__, __LINE__)
      END
   END
END PopOffset ;


(*
   PopSumOfParamSize - pop the total value on the ALU stack as the
                       sum of all parameters.
*)

PROCEDURE PopSumOfParamSize (Sym: CARDINAL) ;
BEGIN
   CheckLegal(Sym) ;
   WITH Symbols[Sym] DO
      CASE SymbolType OF

      ProcedureSym: PopInto(Procedure.TotalParamSize) |
      ProcTypeSym : PopInto(ProcType.TotalParamSize)

      ELSE
         InternalError('expecting Procedure or ProcType symbol', __FILE__, __LINE__)
      END
   END
END PopSumOfParamSize ;


BEGIN
   Init
END SymbolTable.
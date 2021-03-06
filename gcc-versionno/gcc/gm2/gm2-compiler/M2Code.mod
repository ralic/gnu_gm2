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

IMPLEMENTATION MODULE M2Code ;


FROM SYSTEM IMPORT WORD ;
FROM M2Options IMPORT Statistics, DisplayQuadruples, OptimizeUncalledProcedures,
                      (* OptimizeDynamic, *) OptimizeCommonSubExpressions,
                      StudentChecking, Optimizing, WholeProgram ;

FROM M2Error IMPORT InternalError ;
FROM M2Students IMPORT StudentVariableCheck ;

FROM SymbolTable IMPORT GetMainModule, IsProcedure,
                        IsModuleWithinProcedure,
                        CheckHiddenTypeAreAddress, IsModule, IsDefImp,
                        ForeachProcedureDo,
                        ForeachInnerModuleDo, GetSymName ;

FROM M2Printf IMPORT printf2, printf1, printf0 ;
FROM NameKey IMPORT Name ;
FROM M2Batch IMPORT ForeachSourceModuleDo ;

FROM M2Quads IMPORT CountQuads, GetFirstQuad, DisplayQuadList, DisplayQuadRange,
                    BackPatchSubrangesAndOptParam, VariableAnalysis,
                    LoopAnalysis, ForLoopAnalysis, GetQuad, QuadOperator ;

FROM M2Pass IMPORT SetPassToNoPass, SetPassToCodeGeneration ;
FROM M2SubExp IMPORT RemoveCommonSubExpressions ;

FROM M2BasicBlock IMPORT BasicBlock,
                         InitBasicBlocks, InitBasicBlocksFromRange, KillBasicBlocks,
                         ForeachBasicBlockDo ;

FROM M2Optimize IMPORT FoldBranches, RemoveProcedures ;
FROM M2GenGCC IMPORT ConvertQuadsToTree ;

FROM M2GCCDeclare IMPORT FoldConstants, StartDeclareScope,
                         DeclareProcedure, InitDeclarations,
                         DeclareModuleVariables, MarkExported ;

FROM M2Scope IMPORT ScopeBlock, InitScopeBlock, KillScopeBlock, ForeachScopeBlockDo ;
FROM m2top IMPORT InitGlobalContext, SetFlagUnitAtATime ;
FROM M2Error IMPORT FlushErrors, FlushWarnings ;
FROM M2Swig IMPORT GenerateSwigFile ;
FROM m2flex IMPORT GetTotalLines ;
FROM FIO IMPORT FlushBuffer, StdOut ;
FROM M2Quiet IMPORT qprintf0 ;


CONST
   MaxOptimTimes = 10 ;   (* upper limit of no of times we run through all optimization *)
   Debugging     = TRUE ;


VAR
   Total,
   Count,
   OptimTimes,
   DeltaProc,
   Proc,
   DeltaConst,
   Const,
   DeltaJump,
   Jump,
   DeltaBasicB,
   BasicB,
   DeltaCse,
   Cse        : CARDINAL ;


(*
   Percent - calculates the percentage from numerator and divisor
*)

PROCEDURE Percent (numerator, divisor: CARDINAL) ;
VAR
   value: CARDINAL ;
BEGIN
   printf0('  (') ;
   IF divisor=0
   THEN
      printf0('overflow error')
   ELSE
      value := numerator*100 DIV divisor ;
      printf1('%3d', value)
   END ;
   printf0('\%)')
END Percent ;


(*
   OptimizationAnalysis - displays some simple front end optimization statistics.
*)

PROCEDURE OptimizationAnalysis ;
VAR
   value: CARDINAL ;
BEGIN
   IF Statistics
   THEN
      Count := CountQuads() ;

      printf1('M2 initial number of quadruples: %6d', Total) ;
      Percent(Total, Total) ; printf0('\n');
      printf1('M2 constant folding achieved   : %6d', Const) ;
      Percent(Const, Total) ; printf0('\n');
      printf1('M2 branch folding achieved     : %6d', Jump) ;
      Percent(Jump, Total) ; printf0('\n');
      IF BasicB+Proc+Cse>0
      THEN
         (* there is no point making the front end attempt basic block, cse
            and dead code elimination as the back end will do this for us
            and it will do a better and faster job.  The code is left here
            just in case this changes, but reporting 0 for these three
            is likely to cause confusion.
         *)
         printf1('M2 basic block optimization    : %6d', BasicB) ;
         Percent(BasicB, Total) ; printf0('\n') ;
         printf1('M2 uncalled procedures removed : %6d', Proc) ;
         Percent(Proc, Total) ; printf0('\n') ;
         printf1('M2 common subexpession removed : %6d', Cse) ;
         Percent(Cse, Total) ; printf0('\n')
      END ;
      value := Const+Jump+BasicB+Proc+Cse ;
      printf1('Front end optimization removed : %6d', value) ;
      Percent(value, Total) ; printf0('\n') ;
      printf1('Front end final                : %6d', Count) ;
      Percent(Count, Total) ; printf0('\n') ;
      Count := GetTotalLines() ;
      printf1('Total source lines compiled    : %6d\n', Count) ;
      FlushBuffer(StdOut)
   END ;
   IF DisplayQuadruples
   THEN
      printf0('after all front end optimization\n') ;
      DisplayQuadList
   END
END OptimizationAnalysis ;


(*
   RemoveUnreachableCode - 
*)

PROCEDURE RemoveUnreachableCode ;
BEGIN
   IF WholeProgram
   THEN
      ForeachSourceModuleDo(RemoveProcedures)
   ELSE
      RemoveProcedures(GetMainModule())
   END
END RemoveUnreachableCode ;


(*
   DoModuleDeclare - declare all constants, types, variables, procedures for the
                     main module or all modules.
*)

PROCEDURE DoModuleDeclare ;
BEGIN
   IF WholeProgram
   THEN
      ForeachSourceModuleDo(StartDeclareScope)
   ELSE
      StartDeclareScope(GetMainModule())
   END
END DoModuleDeclare ;


(*
   PrintModule - 
*)

PROCEDURE PrintModule (sym: CARDINAL) ;
VAR
   n: Name ;
BEGIN
   n := GetSymName(sym) ;
   printf1('module %a\n', n)
END PrintModule ;


(*
   DoCodeBlock - generate code for the main module or all modules.
*)

PROCEDURE DoCodeBlock ;
BEGIN
   IF WholeProgram
   THEN
      (* ForeachSourceModuleDo(PrintModule) ; *)
      CodeBlock(GetMainModule())
   ELSE
      CodeBlock(GetMainModule())
   END
END DoCodeBlock ;


(*
   Code - calls procedures to generates trees from the quadruples.
          All front end quadruple optimization is performed via this call.
*)

PROCEDURE Code ;
BEGIN
   CheckHiddenTypeAreAddress ;
   SetPassToNoPass ;
   BackPatchSubrangesAndOptParam ;
   Total := CountQuads() ;

   ForLoopAnalysis ;   (* must be done before any optimization as the index variable increment quad might change *)

   IF DisplayQuadruples
   THEN
      printf0('before any optimization\n') ;
      DisplayQuadList
   END ;

   (* now is a suitable time to check for student errors as *)
   (* we know all the front end symbols must be resolved.   *)

   IF StudentChecking
   THEN
      StudentVariableCheck      
   END ;

   SetPassToCodeGeneration ;
   SetFlagUnitAtATime(Optimizing) ;
   InitGlobalContext ;
   InitDeclarations ;

   RemoveUnreachableCode ;

   IF DisplayQuadruples
   THEN
      printf0('after dead procedure elimination\n') ;
      DisplayQuadList
   END ;

   qprintf0('        symbols to gcc trees\n') ;
   DoModuleDeclare ;

   FlushWarnings ;
   FlushErrors ;
   qprintf0('        statements to gcc trees\n') ;
   DoCodeBlock ;

   MarkExported(GetMainModule()) ;
   GenerateSwigFile(GetMainModule()) ;
   qprintf0('        gcc trees given to the gcc backend\n') ;

   OptimizationAnalysis
END Code ;


(*
   InitialDeclareAndCodeBlock - declares all objects within scope, 
*)

PROCEDURE InitialDeclareAndOptimize (start, end: CARDINAL) ;
VAR
   bb: BasicBlock ;
BEGIN
   Count := CountQuads() ;
   bb := KillBasicBlocks(InitBasicBlocksFromRange(start, end)) ;
   BasicB := Count - CountQuads() ;
   Count := CountQuads() ;

   FoldBranches(start, end) ;
   Jump := Count - CountQuads() ;
   Count := CountQuads()
END InitialDeclareAndOptimize ;


(*
   DeclareAndCodeBlock - declares all objects within scope, 
*)

PROCEDURE SecondDeclareAndOptimize (start, end: CARDINAL) ;
VAR
   bb: BasicBlock ;
BEGIN
   REPEAT
      FoldConstants(start, end) ;
      DeltaConst := Count - CountQuads() ;
      Count := CountQuads() ;

      bb := KillBasicBlocks(InitBasicBlocksFromRange(start, end)) ;

      DeltaBasicB := Count - CountQuads() ;
      Count := CountQuads() ;

      bb := KillBasicBlocks(InitBasicBlocksFromRange(start, end)) ;
      FoldBranches(start, end) ;
      DeltaJump := Count - CountQuads() ;
      Count := CountQuads() ;

      bb := KillBasicBlocks(InitBasicBlocksFromRange(start, end)) ;
      INC(DeltaBasicB, Count - CountQuads()) ;
      Count := CountQuads() ;

      IF FALSE AND OptimizeCommonSubExpressions
      THEN
         bb := InitBasicBlocksFromRange(start, end) ;
         ForeachBasicBlockDo(bb, RemoveCommonSubExpressions) ;
         bb := KillBasicBlocks(bb) ;

         bb := KillBasicBlocks(InitBasicBlocksFromRange(start, end)) ;

         DeltaCse := Count - CountQuads() ;
         Count := CountQuads() ;

         FoldConstants(start, end) ;       (* now attempt to fold more constants *)
         INC(DeltaConst, Count-CountQuads()) ;
         Count := CountQuads()
      END ;
      (* now total the optimization components *)
      INC(Proc, DeltaProc) ;
      INC(Const, DeltaConst) ;
      INC(Jump, DeltaJump) ;
      INC(BasicB, DeltaBasicB) ;
      INC(Cse, DeltaCse)
   UNTIL (OptimTimes>=MaxOptimTimes) OR
         ((DeltaProc=0) AND (DeltaConst=0) AND (DeltaJump=0) AND (DeltaBasicB=0) AND (DeltaCse=0)) ;

   IF (DeltaProc#0) OR (DeltaConst#0) OR (DeltaJump#0) OR (DeltaBasicB#0) OR (DeltaCse#0)
   THEN
      printf0('optimization finished although more reduction may be possible (increase MaxOptimTimes)\n')
   END
END SecondDeclareAndOptimize ;


(*
   InitOptimizeVariables - 
*)

PROCEDURE InitOptimizeVariables ;
BEGIN
   Count       := CountQuads() ;
   OptimTimes  := 0 ;
   DeltaProc   := 0 ;
   DeltaConst  := 0 ;
   DeltaJump   := 0 ;
   DeltaBasicB := 0 ;
   DeltaCse    := 0
END InitOptimizeVariables ;


(*
   Init - 
*)

PROCEDURE Init ;
BEGIN
   Proc   := 0 ;
   Const  := 0 ;
   Jump   := 0 ;
   BasicB := 0 ;
   Cse    := 0
END Init ;


(*
   BasicBlockVariableAnalysis - 
*)

PROCEDURE BasicBlockVariableAnalysis (start, end: CARDINAL) ;
VAR
   bb: BasicBlock ;
BEGIN
   bb := InitBasicBlocksFromRange(start, end) ;
   ForeachBasicBlockDo(bb, VariableAnalysis) ;
   bb := KillBasicBlocks(bb)
END BasicBlockVariableAnalysis ;


(*
   DisplayQuadsInScope - 
*)

PROCEDURE DisplayQuadsInScope (sb: ScopeBlock) ;
BEGIN
   printf0('Quads in scope\n') ;
   ForeachScopeBlockDo(sb, DisplayQuadRange) ;
   printf0('===============\n')
END DisplayQuadsInScope ;


(*
   OptimizeScopeBlock - 
*)

PROCEDURE OptimizeScopeBlock (sb: ScopeBlock) ;
VAR
   OptimTimes,
   Previous,
   Current   : CARDINAL ;
BEGIN
   InitOptimizeVariables ;
   OptimTimes := 1 ;
   Current := CountQuads() ;
   ForeachScopeBlockDo(sb, InitialDeclareAndOptimize) ;
   ForeachScopeBlockDo(sb, BasicBlockVariableAnalysis) ;
   REPEAT
      ForeachScopeBlockDo(sb, SecondDeclareAndOptimize) ;
      Previous := Current ;
      Current := CountQuads() ;
      INC(OptimTimes)
   UNTIL (OptimTimes=MaxOptimTimes) OR (Current=Previous) ;
   ForeachScopeBlockDo(sb, LoopAnalysis)
END OptimizeScopeBlock ;


(*
   DisplayQuadNumbers - the range, start..end.
*)

PROCEDURE DisplayQuadNumbers (start, end: CARDINAL) ;
BEGIN
   IF DisplayQuadruples
   THEN
      printf2('Coding [%d..%d]\n', start, end)
   END
END DisplayQuadNumbers ;


(*
   CodeProceduresWithinBlock - codes the procedures within the module scope.
*)

PROCEDURE CodeProceduresWithinBlock (scope: CARDINAL) ;
BEGIN
   ForeachProcedureDo(scope, CodeBlock)
END CodeProceduresWithinBlock ;


(*
   CodeProcedures - 
*)

PROCEDURE CodeProcedures (scope: CARDINAL) ;
BEGIN
   IF IsDefImp(scope) OR IsModule(scope)
   THEN
      ForeachProcedureDo(scope, CodeBlock)
   END
END CodeProcedures ;


(*
   CodeBlock - generates all code for this block and also declares
               all types and procedures for this block. It will
               also optimize quadruples within this scope.
*)

PROCEDURE CodeBlock (scope: WORD) ;
VAR
   sb: ScopeBlock ;
   n : Name ;
BEGIN
   IF DisplayQuadruples
   THEN
      n := GetSymName(scope) ;
      printf1('before coding block %a\n', n)
   END ;
   sb := InitScopeBlock(scope) ;
   OptimizeScopeBlock(sb) ;
   IF IsProcedure(scope)
   THEN
      IF DisplayQuadruples
      THEN
         n := GetSymName(scope) ;
         printf1('before coding procedure %a\n', n) ;
         ForeachScopeBlockDo(sb, DisplayQuadRange) ;
         printf0('===============\n')
      END ;
      ForeachScopeBlockDo(sb, ConvertQuadsToTree)
   ELSIF IsModuleWithinProcedure(scope)
   THEN
      IF DisplayQuadruples
      THEN
         n := GetSymName(scope) ;
         printf1('before coding module %a within procedure\n', n) ;
         ForeachScopeBlockDo(sb, DisplayQuadRange) ;
         printf0('===============\n')
      END ;
      ForeachScopeBlockDo(sb, ConvertQuadsToTree) ;
      ForeachProcedureDo(scope, CodeBlock)
   ELSE
      IF DisplayQuadruples
      THEN
         n := GetSymName(scope) ;
         printf1('before coding module %a\n', n) ;
         ForeachScopeBlockDo(sb, DisplayQuadRange) ;
         printf0('===============\n')
      END ;
      ForeachScopeBlockDo(sb, ConvertQuadsToTree) ;
      IF WholeProgram
      THEN
         ForeachSourceModuleDo(CodeProcedures)
      ELSE
         ForeachProcedureDo(scope, CodeBlock)
      END ;
      ForeachInnerModuleDo(scope, CodeProceduresWithinBlock)
   END ;
   sb := KillScopeBlock(sb)
END CodeBlock ;


BEGIN
   Init
END M2Code.

(* Copyright (C) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009,
                 2010, 2011, 2012, 2013
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

MODULE gm2lcc ;

(*
   Author     : Gaius Mulley
   Title      : gm2lcc
   Date       : Fri Jul 24 11:45:08 BST 1992
   Description: Generates the cc command for linking all the modules.
*)

FROM libc IMPORT system, exit ;
FROM SYSTEM IMPORT ADR ;
FROM NameKey IMPORT Name, MakeKey, WriteKey, GetKey ;
FROM M2Search IMPORT FindSourceFile, PrependSearchPath ;
FROM M2FileName IMPORT CalculateFileName ;
FROM SArgs IMPORT GetArg ;
FROM StrLib IMPORT StrEqual, StrLen, StrCopy, StrConCat, StrRemoveWhitePrefix, IsSubString ;
FROM FIO IMPORT File, StdIn, StdErr, StdOut, Close, IsNoError, EOF, WriteString, WriteLine ;
FROM SFIO IMPORT OpenToRead, WriteS, ReadS ;
FROM ASCII IMPORT nul ;
FROM M2FileName IMPORT ExtractExtension ;
FROM DynamicStrings IMPORT String, InitString, KillString, ConCat, ConCatChar, Length, Slice, Equal, EqualArray, RemoveWhitePrefix, RemoveWhitePostfix, RemoveComment, string, Mark, InitStringChar, Dup, Mult, Index, RIndex, Assign, char ;
FROM FormatStrings IMPORT Sprintf0, Sprintf1, Sprintf2 ;
FROM M2Printf IMPORT fprintf0, fprintf1, fprintf2, fprintf3, fprintf4 ;


(* %%%FORWARD%%%
PROCEDURE ScanSources ; FORWARD ;
PROCEDURE ScanImport (s: CARDINAL) ; FORWARD ;
PROCEDURE MakeModule (ModuleName: CARDINAL) ; FORWARD ;
PROCEDURE WriteFileName (FileName: ARRAY OF CHAR) ; FORWARD ;
PROCEDURE CalculateDepth ; FORWARD ;
PROCEDURE SortSources ; FORWARD ;
PROCEDURE DisplaySources ; FORWARD ;
   %%%FORWARD%%% *)

CONST
   Comment     =     '#' ;      (* Comment leader.                 *)
   MaxSpaces   =      20 ;      (* Maximum spaces after a module   *)
                                (* name.                           *)

VAR
   DebugFound    : BOOLEAN ;
   CheckFound    : BOOLEAN ;
   VerboseFound  : BOOLEAN ;
   ProfileFound  : BOOLEAN ;
   LibrariesFound: BOOLEAN ;
   TargetFound   : BOOLEAN ;
   PathFound     : BOOLEAN ;
   ExecCommand   : BOOLEAN ;    (* should we execute the final cmd *)
   UseAr         : BOOLEAN ;    (* use 'ar' and create archive     *)
   UseRanlib     : BOOLEAN ;    (* use 'ranlib' to index archive   *)
   IgnoreMain    : BOOLEAN ;    (* ignore main module when linking *)
   UseLibtool    : BOOLEAN ;    (* use libtool and suffixes?       *)
   Shared        : BOOLEAN ;    (* is a shared library required?   *)
   BOption,
   FOptions,
   CompilerDir,
   RanlibProgram,
   ArProgram,
   Archives,
   Path,
   StartupFile,
   Objects,
   Libraries,
   MainModule,
   Command,
   Target        : String ;
   fi, fo        : File ;       (* the input and output files      *)


(*
   FlushCommand - flush the command to the output file,
                  or execute the command.
*)

PROCEDURE FlushCommand () : INTEGER ;
BEGIN
   IF ExecCommand
   THEN
      IF VerboseFound
      THEN
         Command := WriteS(StdOut, Command) ;
         fprintf0(StdOut, '\n')
      END ;
      RETURN( system(string(Command)) )
   ELSE
      Command := WriteS(fo, Command)
   END ;
   RETURN( 0 )
END FlushCommand ;


(*
   GenerateLinkCommand - generate the appropriate linkage command
                         with the correct options.
*)

PROCEDURE GenerateLinkCommand ;
BEGIN
   IF UseAr
   THEN
      Command := ConCat(ArProgram, InitString(' rc ')) ;
      IF TargetFound
      THEN
         Command := ConCat(Command, Target) ;
         Command := ConCatChar(Command, ' ')
      ELSE
         WriteString(StdErr, 'need target with ar') ; WriteLine(StdErr) ; Close(StdErr) ;
         exit(1)
      END
   ELSIF UseLibtool
   THEN
      Command := InitString('libtool --tag=CC --mode=link gcc ') ;
      IF BOption#NIL
      THEN
         Command := ConCat(Command, Dup(BOption)) ;
         Command := ConCatChar(Command, ' ')
      END ;
      IF DebugFound
      THEN
         Command := ConCat(Command, Mark(InitString('-g ')))
      END ;
      IF ProfileFound
      THEN
         Command := ConCat(Command, Mark(InitString('-p ')))
      END ;
      Command := ConCat(Command, FOptions) ;
      IF Shared
      THEN
         Command := ConCat(Command, Mark(InitString('-shared ')))
      END ;
      IF TargetFound
      THEN
         Command := ConCat(Command, Mark(InitString('-o '))) ;
         Command := ConCat(Command, Target) ;
         Command := ConCatChar(Command, ' ')
      END ;
      IF ProfileFound
      THEN
         Command := ConCat(Command, Mark(InitString('-lgmon ')))
      END
   END
END GenerateLinkCommand ;


(*
   GenerateRanlibCommand - generate the appropriate ranlib command.
*)

PROCEDURE GenerateRanlibCommand ;
BEGIN
   Command := ConCat(RanlibProgram, Mark(InitStringChar(' '))) ;
   IF TargetFound
   THEN
      Command := ConCat(Command, Target) ;
      Command := ConCatChar(Command, ' ')
   ELSE
      WriteString(StdErr, 'need target with ranlib') ; WriteLine(StdErr) ; Close(StdErr) ;
      exit(1)
   END
END GenerateRanlibCommand ;


(*
   RemoveLinkOnly - removes the <onlylink> prefix, if present.
                    Otherwise, s, is returned.
*)

PROCEDURE RemoveLinkOnly (s: String) : String ;
VAR
   t: String ;
BEGIN
   t := InitString('<onlylink>') ;
   IF Equal(Mark(Slice(s, 0, Length(t)-1)), t)
   THEN
      RETURN( RemoveWhitePrefix(Slice(Mark(s), Length(t), 0)) )
   ELSE
      RETURN( s )
   END
END RemoveLinkOnly ;


(*
   ConCatStartupFile - 
*)

PROCEDURE ConCatStartupFile ;
BEGIN
   IF UseLibtool
   THEN
      Command := ConCat(Command, Mark(Sprintf1(Mark(InitString('%s.lo')),
                                               StartupFile)))
   ELSE
      Command := ConCat(Command, Mark(Sprintf1(Mark(InitString('%s.o')),
                                               StartupFile)))
   END
END ConCatStartupFile ;


(*
   GenObjectSuffix - 
*)

PROCEDURE GenObjectSuffix () : String ;
BEGIN
   IF UseLibtool
   THEN
      RETURN( InitString('lo') )
   ELSE
      RETURN( InitString('o') )
   END
END GenObjectSuffix ;


(*
   GenArchiveSuffix - 
*)

PROCEDURE GenArchiveSuffix () : String ;
BEGIN
   IF UseLibtool
   THEN
      RETURN( InitString('la') )
   ELSE
      RETURN( InitString('a') )
   END
END GenArchiveSuffix ;


(*
   ConCatObject - 
*)

PROCEDURE ConCatObject (s: String) ;
VAR
   t, u: String ;
BEGIN
   t := CalculateFileName(s, Mark(GenObjectSuffix())) ;
   IF FindSourceFile(t, u)
   THEN
      Command := ConCat(ConCatChar(Command, ' '), u) ;
      u := KillString(u)
   ELSE
      t := KillString(t) ;
      (* try finding .a or .la archive *)
      t := CalculateFileName(s, Mark(GenArchiveSuffix())) ;
      IF FindSourceFile(t, u)
      THEN
         Archives := ConCatChar(ConCat(Archives, u), ' ') ;
         u := KillString(u)
      END
   END ;
   t := KillString(t)   
END ConCatObject ;


(*
   GenCC - writes out the linkage command for the C compiler.
*)

PROCEDURE GenCC ;
VAR
   s    : String ;
   Error: INTEGER ;
BEGIN
   GenerateLinkCommand ;
   ConCatStartupFile ;
   REPEAT
      s := RemoveComment(RemoveWhitePrefix(ReadS(fi)), Comment) ;
      IF (NOT EqualArray(s, '')) AND (NOT (IgnoreMain AND Equal(s, MainModule)))
      THEN
         s := RemoveLinkOnly(s) ;
         ConCatObject(s)
      END
   UNTIL EOF(fi) ;
   Command := ConCat(Command, Archives) ;
   IF Objects#NIL
   THEN
      Command := ConCat(Command, Objects)
   END ;
   IF LibrariesFound
   THEN
      Command := ConCat(ConCatChar(Command, ' '), Libraries)
   END ;
   Error := FlushCommand() ;
   IF Error=0
   THEN
      IF UseRanlib
      THEN
         GenerateRanlibCommand ;
         Error := FlushCommand() ;
         IF Error#0
         THEN
            fprintf1(StdErr, 'ranlib failed with exit code %d\n', Error) ;
            Close(StdErr) ;
            exit(Error)
         END
      END
   ELSE
      fprintf1(StdErr, 'ar failed with exit code %d\n', Error) ;
      Close(StdErr) ;
      exit(Error)
   END
END GenCC ;


(*
   WriteModuleName - displays a module name, ModuleName, with formatted spaces
                     after the string.
*)

PROCEDURE WriteModuleName (ModuleName: String) ;
BEGIN
   ModuleName := WriteS(fo, ModuleName) ;
   IF KillString(WriteS(fo, Mark(Mult(Mark(InitString(' ')), MaxSpaces-Length(ModuleName)))))=NIL
   THEN
   END
END WriteModuleName ;


(*
   CheckCC - checks to see whether all the object files can be found
             for each module.
*)

PROCEDURE CheckCC ;
VAR
   s, t, u: String ;
   Error  : INTEGER ;
BEGIN
   Error := 0 ;
   REPEAT
      s := RemoveComment(RemoveWhitePrefix(ReadS(fi)), Comment) ;
      IF NOT EqualArray(s, '')
      THEN
         s := RemoveLinkOnly(s) ;
         t := Dup(s) ;
         t := CalculateFileName(s, Mark(GenObjectSuffix())) ;
         IF FindSourceFile(t, u)
         THEN
            IF KillString(WriteS(fo, Mark(Sprintf2(Mark(InitString('%-20s : %s\n')), t, u))))=NIL
            THEN
            END ;
            u := KillString(u)
         ELSE
            t := KillString(t) ;
            (* try finding .a archive *)
            t := CalculateFileName(s, Mark(GenArchiveSuffix())) ;
            IF FindSourceFile(t, u)
            THEN
               IF KillString(WriteS(fo, Mark(Sprintf2(Mark(InitString('%-20s : %s\n')), t, u))))=NIL
               THEN
               END ;
               u := KillString(u)
            ELSE
               IF KillString(WriteS(fo, Mark(Sprintf1(InitString('%-20s : distinct object or archive not found\n'), t))))=NIL
               THEN
               END ;
               Error := 1
            END
         END
      END
   UNTIL EOF(fi) ;
   Close(fo) ;
   exit(Error)
END CheckCC ;


(*
   ProcessTarget - copies the specified target file into Target
                   and sets the boolean TargetFound.
*)

PROCEDURE ProcessTarget (i: CARDINAL) ;
BEGIN
   IF NOT GetArg(Target, i)
   THEN
      fprintf0(StdErr, 'cannot get target argument after -o\n') ;
      Close(StdErr) ;
      exit(1)
   END ;
   TargetFound := TRUE
END ProcessTarget ;


(*
   StripModuleExtension - returns a String without an extension from, s.
                          It only considers '.obj', '.o' and '.lo' as
                          extensions.
*)

PROCEDURE StripModuleExtension (s: String) : String ;
VAR
   t: String ;
BEGIN
   t := ExtractExtension(s, Mark(InitString('.lo'))) ;
   IF s=t
   THEN
      t := ExtractExtension(s, Mark(InitString('.obj'))) ;
      IF s=t
      THEN
         RETURN( ExtractExtension(s, Mark(InitString('.o'))) )
      END
   END ;
   RETURN( t )
END StripModuleExtension ;


(*
   ProcessStartupFile - copies the specified startup file name into StartupFile.
*)

PROCEDURE ProcessStartupFile (i: CARDINAL) ;
BEGIN
   IF GetArg(StartupFile, i)
   THEN
      StartupFile := StripModuleExtension(StartupFile)
   ELSE
      fprintf0(StdErr, 'cannot get startup argument after --startup\n') ;
      Close(StdErr) ;
      exit(1)
   END
END ProcessStartupFile ;


(*
   IsALibrary - returns TRUE if, a, is a library. If TRUE we add it to the
                Libraries string.
*)

PROCEDURE IsALibrary (s: String) : BOOLEAN ;
BEGIN
   IF EqualArray(Mark(Slice(s, 0, 2)), '-l')
   THEN
      LibrariesFound := TRUE ;
      Libraries := ConCat(ConCatChar(Libraries, ' '), s) ;
      RETURN( TRUE )
   ELSE
      RETURN( FALSE )
   END
END IsALibrary ;


(*
   IsALibraryPath - 
*)

PROCEDURE IsALibraryPath (s: String) : BOOLEAN ;
BEGIN
   IF EqualArray(Mark(Slice(s, 0, 2)), '-L')
   THEN
      IF UseLibtool
      THEN
         LibrariesFound := TRUE ;
         Libraries := ConCat(ConCatChar(Libraries, ' '), s)
      END ;
      RETURN( TRUE )
   ELSE
      RETURN( FALSE )
   END
END IsALibraryPath ;


(*
   IsAnObject - returns TRUE if, a, is a library. If TRUE we add it to the
                Libraries string.
*)

PROCEDURE IsAnObject (s: String) : BOOLEAN ;
BEGIN
   IF ((Length(s)>2) AND EqualArray(Mark(Slice(s, -2, 0)), '.o')) OR
      ((Length(s)>4) AND EqualArray(Mark(Slice(s, -4, 0)), '.obj'))
   THEN
      Objects := ConCat(ConCatChar(Objects, ' '), s) ;
      RETURN( TRUE )
   ELSE
      RETURN( FALSE )
   END
END IsAnObject ;


(*
   AdditionalFOptions - add an -f option to the compiler.
*)

PROCEDURE AdditionalFOptions (s: String) ;
BEGIN
   FOptions := ConCat(FOptions, Mark(s)) ;
   FOptions := ConCatChar(FOptions, ' ')
END AdditionalFOptions ;


(*
   ScanArguments - scans arguments for flags: -fobject-path= -g and -B
*)

PROCEDURE ScanArguments ;
VAR
   filename,
   s        : String ;
   i        : CARDINAL ;
   FoundFile: BOOLEAN ;
BEGIN
   FoundFile := FALSE ;
   filename := NIL ;
   i := 1 ;
   WHILE GetArg(s, i) DO
      IF EqualArray(s, '-g')
      THEN
         DebugFound := TRUE
      ELSIF EqualArray(s, '-c')
      THEN
         CheckFound := TRUE
      ELSIF EqualArray(s, '--main')
      THEN
         INC(i) ;
         IF NOT GetArg(MainModule, i)
         THEN
            fprintf0(StdErr, 'expecting modulename after -main option\n') ;
            Close(StdErr) ;
            exit(1)
         END
      ELSIF EqualArray(Mark(Slice(s, 0, 2)), '-B')
      THEN
         CompilerDir := KillString(CompilerDir) ;
         IF Length(s)=2
         THEN
            INC(i) ;
            IF NOT GetArg(CompilerDir, i)
            THEN
               fprintf0(StdErr, 'expecting path after -B option\n') ;
               Close(StdErr) ;
               exit(1)
            END
         ELSE
            CompilerDir := Slice(s, 2, 0)
         END ;
         BOption := Dup(s)
      ELSIF EqualArray(s, '-p')
      THEN
         ProfileFound := TRUE
      ELSIF EqualArray(s, '-v')
      THEN
         VerboseFound := TRUE
      ELSIF EqualArray(s, '--exec')
      THEN
         ExecCommand := TRUE
      ELSIF EqualArray(s, '-fshared')
      THEN
         Shared := TRUE
      ELSIF EqualArray(s, '--ignoremain')
      THEN
         IgnoreMain := TRUE
      ELSIF EqualArray(s, '--ar')
      THEN
         UseAr := TRUE ;
         UseRanlib := TRUE ;
         UseLibtool := FALSE
      ELSIF EqualArray(Mark(Slice(s, 0, 14)), '-fobject-path=')
      THEN
         PrependSearchPath(Slice(s, 14, 0))
      ELSIF EqualArray(Mark(Slice(s, 0, 12)), '-ftarget-ar=')
      THEN
         ArProgram := KillString(ArProgram) ;
         ArProgram := Slice(s, 12, 0)
      ELSIF EqualArray(Mark(Slice(s, 0, 16)), '-ftarget-ranlib=')
      THEN
         RanlibProgram := KillString(RanlibProgram) ;
         RanlibProgram := Slice(s, 16, 0)
      ELSIF EqualArray(s, '-o')
      THEN
         INC(i) ;                 (* Target found *)
         ProcessTarget(i)
      ELSIF EqualArray(s, '--startup')
      THEN
         INC(i) ;                 (* Target found *)
         ProcessStartupFile(i)
      ELSIF EqualArray(Mark(Slice(s, 0, 2)), '-f')
      THEN
         AdditionalFOptions(s)
      ELSIF IsALibrary(s) OR IsALibraryPath(s) OR IsAnObject(s)
      THEN
      ELSE
         IF FoundFile
         THEN
            fprintf2(StdErr, 'already specified input filename (%s), unknown option (%s)\n', filename, s) ;
            Close(StdErr) ;
            exit(1)
         ELSE
            (* must be input filename *)
            Close(StdIn) ;
            fi := OpenToRead(s) ;
            IF NOT IsNoError(fi)
            THEN
               fprintf1(StdErr, 'failed to open %s\n', s) ;
               Close(StdErr) ;
               exit(1)
            END ;
            FoundFile := TRUE ;
            filename := Dup(s) ;
         END
      END ;
      INC(i)
   END
END ScanArguments ;


(*
   Init - initializes the global variables.
*)

PROCEDURE Init ;
BEGIN
   DebugFound    := FALSE ;
   CheckFound    := FALSE ;
   TargetFound   := FALSE ;
   ProfileFound  := FALSE ;
   IgnoreMain    := FALSE ;
   UseAr         := FALSE ;
   UseLibtool    := FALSE ;
   UseRanlib     := FALSE ;
   VerboseFound  := FALSE ;
   Shared        := FALSE ;
   ArProgram     := InitString('ar') ;
   RanlibProgram := InitString('ranlib') ;
   MainModule    := InitString('') ;
   StartupFile   := InitString('mod_init') ;
   fi            := StdIn ;
   fo            := StdOut ;
   ExecCommand   := FALSE ;

   CompilerDir   := InitString('') ;

   FOptions      := InitString('') ;
   Archives      := NIL ;
   Path          := NIL ;
   LibrariesFound:= FALSE ;
   Libraries     := InitString('') ;
   Objects       := InitString('') ;
   Command       := NIL ;
   Target        := NIL ;
   BOption       := NIL ;

   ScanArguments ;
   IF CheckFound
   THEN
      CheckCC
   ELSE
      GenCC
   END ;
   Close(fo)
END Init ;


BEGIN
   Init
END gm2lcc.

(* Copyright (C) 2003 Free Software Foundation, Inc. *)
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

MODULE testselect ;

FROM pth IMPORT pth_sleep, pth_event_t, pth_t, pth_attr_t, pth_init, pth_attr_new,
                pth_attr_set, PTH_ATTR_NAME, pth_spawn, pth_attr_destroy, pth_yield,
                pth_event, PTH_EVENT_TIME, PTH_MODE_REUSE, pth_timeout, pth_select_ev,
                pth_read, pth_time_t ;
FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM Strings IMPORT InitString, string ;
FROM FormatStrings IMPORT Sprintf0 ;
FROM libcextra IMPORT exit, fprintf, sleep, errno, stderr ;
FROM Selective IMPORT SetOfFd, Timeval,
                      InitSet, KillSet, InitTime, KillTime,
                      FdZero, FdSet, FdClr, FdIsSet, Select,
                      MaxFdsPlusOne, WriteCharRaw, ReadCharRaw ;
FROM wrapc IMPORT strtime ;


CONST
   STDIN_FILENO = 0 ;
   EINTR = 4 ;


PROCEDURE die (str: ARRAY OF CHAR) ;
BEGIN
   fprintf(stderr, string(InitString("**die: %s: errno=%d\n")), string(InitString(str)), errno) ;
   exit(1)
END die ;

(* a useless ticker thread *)
PROCEDURE ticker (arg: ADDRESS) : ADDRESS ;
VAR
   c: CARDINAL ;
BEGIN
   fprintf(stderr, string(Sprintf0(InitString("ticker: start\n"))));
   LOOP
      c := pth_sleep(5);
      fprintf(stderr, string(Sprintf0(InitString("ticker was woken up on %s\n"))), strtime());
   END ;
   RETURN NIL
END ticker ;


VAR
   evt     : pth_event_t;
   t_ticker: pth_t ;
   t_attr  : pth_attr_t ;
   rfds    : SetOfFd ;
   c       : CHAR ;
   n, i    : INTEGER ;
   tv      : pth_time_t ;
BEGIN
   i := pth_init() ;

   fprintf(stderr, string(Sprintf0(InitString("This is TEST_SELECT, a Pth test using select.\n"))));
   fprintf(stderr, string(Sprintf0(InitString("\n"))));
   fprintf(stderr, string(Sprintf0(InitString("Enter data. Hit CTRL-C to stop this test.\n"))));
   fprintf(stderr, string(Sprintf0(InitString("\n"))));

   t_attr := pth_attr_new();
   i := pth_attr_set(t_attr, PTH_ATTR_NAME, "ticker");
   t_ticker := pth_spawn(t_attr, ticker, NIL);
   fprintf(stderr, string(Sprintf0(InitString("main: after spawn\n"))));
   i := pth_attr_destroy(t_attr);
   i := pth_yield(NIL);

   fprintf(stderr, string(Sprintf0(InitString("main: before loop\n"))));
   rfds := InitSet() ;
   evt := NIL;
   LOOP
      fprintf(stderr, string(Sprintf0(InitString("main: in loop\n"))));
      IF evt = NIL
      THEN
         (* evt := pth_event(VAL(CARDINAL, PTH_EVENT_TIME), pth_timeout(10,0)); fails *)
         evt := pth_event(CARDINAL({4}), pth_timeout(10,0));
      ELSE
         (* CARDINAL(PTH_EVENT_TIME+PTH_MODE_REUSE) *)
         evt := pth_event(CARDINAL({4, 20}), evt, pth_timeout(10,0));
      END ;
      fprintf(stderr, string(Sprintf0(InitString("main: after event\n"))));
      FdZero(rfds);
      FdSet(STDIN_FILENO, rfds);
      n := pth_select_ev(STDIN_FILENO+1, rfds, NIL, NIL, NIL, evt);
      IF (n = -1) AND (errno = EINTR)
      THEN
         fprintf(stderr, string(Sprintf0(InitString("main: timeout - repeating\n"))))
      ELSE
         IF NOT FdIsSet(STDIN_FILENO, rfds)
         THEN
            die("main: Hmmmm... strange situation: bit not set\n")
         END ;
         fprintf(stderr, string(Sprintf0(InitString("main: select returned %d\n"))), n);
         WHILE pth_read(STDIN_FILENO, ADR(c), 1) > 0 DO
            fprintf(stderr, string(Sprintf0(InitString("main: read stdin '%c'\n"))), c)
         END
      END
   END ;
   (* unreachable ?
    pth_cancel(t_ticker);
    pth_join(t_ticker, NULL);
    pth_event_free(evt, PTH_FREE_THIS);
    pth_kill();
    return 0;
   *)
END testselect.
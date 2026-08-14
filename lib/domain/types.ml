(** Domain Value Objects and Primitive Types for AArch64 Target *)

type reg =
  | X0 | X1 | X2 | X3 | X4 | X5 | X6 | X7
  | X8 | X9 | X10 | X11 | X12 | X13 | X14 | X15
  | X16 | X17 | X18 | X19 | X20 | X21 | X22 | X23
  | X24 | X25 | X26 | X27 | X28 | X29 | X30
  | XZR
  | SP

let reg_to_int = function
  | X0 -> 0 | X1 -> 1 | X2 -> 2 | X3 -> 3 | X4 -> 4 | X5 -> 5 | X6 -> 6 | X7 -> 7
  | X8 -> 8 | X9 -> 9 | X10 -> 10 | X11 -> 11 | X12 -> 12 | X13 -> 13 | X14 -> 14 | X15 -> 15
  | X16 -> 16 | X17 -> 17 | X18 -> 18 | X19 -> 19 | X20 -> 20 | X21 -> 21 | X22 -> 22 | X23 -> 23
  | X24 -> 24 | X25 -> 25 | X26 -> 26 | X27 -> 27 | X28 -> 28 | X29 -> 29 | X30 -> 30
  | XZR -> 31
  | SP -> 31

let reg_name = function
  | X0 -> "x0" | X1 -> "x1" | X2 -> "x2" | X3 -> "x3" | X4 -> "x4" | X5 -> "x5" | X6 -> "x6" | X7 -> "x7"
  | X8 -> "x8" | X9 -> "x9" | X10 -> "x10" | X11 -> "x11" | X12 -> "x12" | X13 -> "x13" | X14 -> "x14" | X15 -> "x15"
  | X16 -> "x16" | X17 -> "x17" | X18 -> "x18" | X19 -> "x19" | X20 -> "x20" | X21 -> "x21" | X22 -> "x22" | X23 -> "x23"
  | X24 -> "x24" | X25 -> "x25" | X26 -> "x26" | X27 -> "x28" | X28 -> "x28" | X29 -> "x29" | X30 -> "x30"
  | XZR -> "xzr"
  | SP -> "sp"

type label = string

type condition =
  | EQ (* Equal *)
  | NE (* Not equal *)
  | CS (* Carry set / unsigned higher or same *)
  | CC (* Carry clear / unsigned lower *)
  | MI (* Minus / negative *)
  | PL (* Plus / positive or zero *)
  | VS (* Overflow *)
  | VC (* No overflow *)
  | HI (* Unsigned higher *)
  | LS (* Unsigned lower or same *)
  | GE (* Signed greater than or equal *)
  | LT (* Signed less than *)
  | GT (* Signed greater than *)
  | LE (* Signed less than or equal *)
  | AL (* Always *)

let cond_to_code = function
  | EQ -> 0b0000
  | NE -> 0b0001
  | CS -> 0b0010
  | CC -> 0b0011
  | MI -> 0b0100
  | PL -> 0b0101
  | VS -> 0b0110
  | VC -> 0b0111
  | HI -> 0b1000
  | LS -> 0b1001
  | GE -> 0b1010
  | LT -> 0b1011
  | GT -> 0b1100
  | LE -> 0b1101
  | AL -> 0b1110

let cond_invert = function
  | EQ -> NE | NE -> EQ
  | CS -> CC | CC -> CS
  | MI -> PL | PL -> MI
  | VS -> VC | VC -> VS
  | HI -> LS | LS -> HI
  | GE -> LT | LT -> GE
  | GT -> LE | LE -> GT
  | AL -> AL

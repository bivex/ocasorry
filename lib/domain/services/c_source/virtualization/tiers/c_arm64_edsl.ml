(** Domain Service: Complete Typed Embedded DSL (EDSL) for Native AArch64 / ARM64
    Full support for:
    - Arithmetic (ADD, SUB, MUL, MADD, MSUB, NEG, UDIV, SDIV)
    - Bitwise & Shifts (AND, ORR, EOR, BIC, ORN, EON, MVN, LSL, LSR, ASR, ROR, REV, CLZ)
    - Memory Load/Store (LDR, STR, LDRB, STRB, LDRH, STRH, LDRSW, LDP, STP with pre/post-index)
    - Conditionals & Selects (CMP, CMN, TST, CSET, CSEL, CSINC, CSINV, CSNEG)
    - Branching & Control Flow (B, BCOND, CBZ, CBNZ, BL, BLR, BR, RET, BRK)
    - Address Generation (ADR PC-relative)
    - System & Security (MRS CNTVCT_EL0, ISB, DSB, DMB)
    - Polymorphic safe decoys, label resolution & session encryption.
*)

type reg =
  | X0  | X1  | X2  | X3  | X4  | X5  | X6  | X7
  | X8  | X9  | X10 | X11 | X12 | X13 | X14 | X15
  | X16 | X17 | X18 | X19 | X20 | X21 | X22 | X23
  | X24 | X25 | X26 | X27 | X28 | X29 | X30 | XZR | SP
  | W0  | W1  | W2  | W3  | W4  | W5  | W6  | W7
  | W8  | W9  | W10 | W11 | W12 | W13 | W14 | W15
  | W16 | W17 | W18 | W19 | W20 | W21 | W22 | W23
  | W24 | W25 | W26 | W27 | W28 | W29 | W30 | WZR | WSP

let reg_to_int = function
  | X0 | W0 -> 0 | X1 | W1 -> 1 | X2 | W2 -> 2 | X3 | W3 -> 3
  | X4 | W4 -> 4 | X5 | W5 -> 5 | X6 | W6 -> 6 | X7 | W7 -> 7
  | X8 | W8 -> 8 | X9 | W9 -> 9 | X10 | W10 -> 10 | X11 | W11 -> 11
  | X12 | W12 -> 12 | X13 | W13 -> 13 | X14 | W14 -> 14 | X15 | W15 -> 15
  | X16 | W16 -> 16 | X17 | W17 -> 17 | X18 | W18 -> 18 | X19 | W19 -> 19
  | X20 | W20 -> 20 | X21 | W21 -> 21 | X22 | W22 -> 22 | X23 | W23 -> 23
  | X24 | W24 -> 24 | X25 | W25 -> 25 | X26 | W26 -> 26 | X27 | W27 -> 27
  | X28 | W28 -> 28 | X29 | W29 -> 29 | X30 | W30 -> 30
  | XZR | WZR | SP | WSP -> 31

let is_64bit = function
  | X0 | X1 | X2 | X3 | X4 | X5 | X6 | X7
  | X8 | X9 | X10 | X11 | X12 | X13 | X14 | X15
  | X16 | X17 | X18 | X19 | X20 | X21 | X22 | X23
  | X24 | X25 | X26 | X27 | X28 | X29 | X30 | XZR | SP -> true
  | _ -> false

type cond =
  | Eq | Ne | Cs | Cc | Mi | Pl | Vs | Vc | Hi | Ls | Ge | Lt | Gt | Le | Al

let cond_to_code = function
  | Eq -> 0x0 | Ne -> 0x1 | Cs -> 0x2 | Cc -> 0x3
  | Mi -> 0x4 | Pl -> 0x5 | Vs -> 0x6 | Vc -> 0x7
  | Hi -> 0x8 | Ls -> 0x9 | Ge -> 0xA | Lt -> 0xB
  | Gt -> 0xC | Le -> 0xD | Al -> 0xE

type mem_op =
  | Addr of reg * int              (** [base, #offset] *)
  | PreIndex of reg * int          (** [base, #offset]! *)
  | PostIndex of reg * int         (** [base], #offset *)

type insn =
  | Raw of int32
  | Label of string
  (* Data Movement *)
  | MovReg of reg * reg
  | MovImm of reg * int
  | Adr of reg * string            (** adr rd, label *)
  (* Arithmetic *)
  | Add of reg * reg * reg
  | AddImm of reg * reg * int
  | Sub of reg * reg * reg
  | SubImm of reg * reg * int
  | Mul of reg * reg * reg
  | Madd of reg * reg * reg * reg  (** madd rd, rn, rm, ra -> ra + rn*rm *)
  | Msub of reg * reg * reg * reg  (** msub rd, rn, rm, ra -> ra - rn*rm *)
  | Udiv of reg * reg * reg        (** unsigned divide *)
  | Sdiv of reg * reg * reg        (** signed divide *)
  | Neg of reg * reg
  (* Bitwise & Logical *)
  | And of reg * reg * reg
  | Orr of reg * reg * reg
  | Eor of reg * reg * reg
  | Bic of reg * reg * reg         (** bic rd, rn, rm -> rn & ~rm *)
  | Orn of reg * reg * reg         (** orn rd, rn, rm -> rn | ~rm *)
  | Eon of reg * reg * reg         (** eon rd, rn, rm -> rn ^ ~rm *)
  | Mvn of reg * reg
  | LslImm of reg * reg * int
  | LsrImm of reg * reg * int
  | AsrImm of reg * reg * int
  | RorReg of reg * reg * reg
  | Rev of reg * reg               (** reverse bytes *)
  | Clz of reg * reg               (** count leading zeros *)
  (* Memory Operations *)
  | Ldr of reg * mem_op
  | Str of reg * mem_op
  | Ldrb of reg * mem_op
  | Strb of reg * mem_op
  | Ldrh of reg * mem_op
  | Strh of reg * mem_op
  | Ldp of reg * reg * mem_op      (** ldp rt1, rt2, [base, #imm] *)
  | Stp of reg * reg * mem_op      (** stp rt1, rt2, [base, #imm] *)
  (* Conditionals & Comparison *)
  | Cmp of reg * reg
  | CmpImm of reg * int
  | Cset of reg * cond
  | Csel of reg * reg * reg * cond (** csel rd, rn, rm, cond *)
  | Csinc of reg * reg * reg * cond
  | Csinv of reg * reg * reg * cond
  | Csneg of reg * reg * reg * cond
  (* Branches & Control Flow *)
  | B of string
  | BCond of cond * string
  | Cbz of reg * string            (** cbz rt, label *)
  | Cbnz of reg * string           (** cbnz rt, label *)
  | Bl of string                   (** bl label *)
  | Blr of reg                     (** blr rn *)
  | Br of reg                      (** br rn *)
  | Ret
  | Brk of int                     (** brk #imm *)
  (* System & Barriers *)
  | MrsCntvct of reg               (** mrs rd, cntvct_el0 *)
  | Isb
  | Dmb
  | Nop
  | Decoy of [ `ZeroLogic | `Nop ]

type prog = insn list

(* DSL Combinators *)
let empty : prog = []
let emit (i : insn) : prog = [ i ]
let ( <+> ) (p : prog) (i : insn) : prog = p @ [ i ]
let ( <++> ) (p1 : prog) (p2 : prog) : prog = p1 @ p2

(* Instruction Encoding Primitives *)
let enc_mov_imm (rd : reg) (imm : int) : int32 list =
  let r = reg_to_int rd in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let u16_0 = imm land 0xFFFF in
  let u16_1 = (imm lsr 16) land 0xFFFF in
  let movz_base = Int32.logor 0x52800000l sf_bit in
  let movz = Int32.logor movz_base (Int32.of_int ((u16_0 lsl 5) lor (r land 0x1F))) in
  if u16_1 = 0 then [ movz ]
  else
    let movk_base = Int32.logor 0x72A00000l sf_bit in
    let movk = Int32.logor movk_base (Int32.of_int ((u16_1 lsl 5) lor (r land 0x1F))) in
    [ movz; movk ]

let enc_mov_reg (rd : reg) (rm : reg) : int32 =
  let d = reg_to_int rd in
  let m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x2A0003E0l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (d land 0x1F)))

let enc_add (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x0B000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_add_imm (rd : reg) (rn : reg) (imm : int) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let imm12 = imm land 0xFFF in
  Int32.logor (Int32.logor 0x11000000l sf_bit) (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_sub (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x4B000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_sub_imm (rd : reg) (rn : reg) (imm : int) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let imm12 = imm land 0xFFF in
  Int32.logor (Int32.logor 0x51000000l sf_bit) (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_mul (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1B007C00l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_madd (rd : reg) (rn : reg) (rm : reg) (ra : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm and a = reg_to_int ra in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1B000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((a land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_msub (rd : reg) (rn : reg) (rm : reg) (ra : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm and a = reg_to_int ra in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1B008000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((a land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_udiv (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1AC00800l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_sdiv (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1AC00C00l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_and (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x0A000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_orr (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x2A000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_eor (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x4A000000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_bic (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x0A200000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_orn (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x2A200000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_eon (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x4A200000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_mvn (rd : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x2A2003E0l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (d land 0x1F)))

let enc_neg (rd : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x4B0003E0l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (d land 0x1F)))

let enc_lsl_imm (rd : reg) (rn : reg) (shift : int) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let s = shift land (if is_64bit rd then 63 else 31) in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let mask = if is_64bit rd then 63 else 31 in
  let immr = (mask + 1 - s) land mask in
  let imms = mask - s in
  Int32.logor (Int32.logor 0x53000000l sf_bit) (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_lsr_imm (rd : reg) (rn : reg) (shift : int) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let mask = if is_64bit rd then 63 else 31 in
  let immr = shift land mask in
  let imms = mask in
  Int32.logor (Int32.logor 0x53000000l sf_bit) (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_asr_imm (rd : reg) (rn : reg) (shift : int) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let mask = if is_64bit rd then 63 else 31 in
  let immr = shift land mask in
  let imms = mask in
  Int32.logor (Int32.logor 0x13000000l sf_bit) (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_ror_reg (rd : reg) (rn : reg) (rm : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x1AC02800l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_rev (rd : reg) (rn : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  if is_64bit rd then
    Int32.logor 0xDAC00C00l (Int32.of_int (((n land 0x1F) lsl 5) lor (d land 0x1F)))
  else
    Int32.logor 0x5AC00800l (Int32.of_int (((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_clz (rd : reg) (rn : reg) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x5AC01000l sf_bit) (Int32.of_int (((n land 0x1F) lsl 5) lor (d land 0x1F)))

(* Memory Encoders *)
let enc_ldr (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  let bit64 = is_64bit rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn in
      if bit64 then
        let imm12 = (offset lsr 3) land 0xFFF in
        Int32.logor 0xF9400000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
      else
        let imm12 = (offset lsr 2) land 0xFFF in
        Int32.logor 0xB9400000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm9 = offset land 0x1FF in
      let base = if bit64 then 0xF8400C00l else 0xB8400C00l in
      Int32.logor base (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm9 = offset land 0x1FF in
      let base = if bit64 then 0xF8400400l else 0xB8400400l in
      Int32.logor base (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_str (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  let bit64 = is_64bit rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn in
      if bit64 then
        let imm12 = (offset lsr 3) land 0xFFF in
        Int32.logor 0xF9000000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
      else
        let imm12 = (offset lsr 2) land 0xFFF in
        Int32.logor 0xB9000000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm9 = offset land 0x1FF in
      let base = if bit64 then 0xF8000C00l else 0xB8000C00l in
      Int32.logor base (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm9 = offset land 0x1FF in
      let base = if bit64 then 0xF8000400l else 0xB8000400l in
      Int32.logor base (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_ldrb (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn and imm12 = offset land 0xFFF in
      Int32.logor 0x39400000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x38400C00l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x38400400l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_strb (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn and imm12 = offset land 0xFFF in
      Int32.logor 0x39000000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x38000C00l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x38000400l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_ldrh (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn and imm12 = (offset lsr 1) land 0xFFF in
      Int32.logor 0x79400000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x78400C00l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x78400400l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_strh (rt : reg) (mem : mem_op) : int32 =
  let t = reg_to_int rt in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn and imm12 = (offset lsr 1) land 0xFFF in
      Int32.logor 0x79000000l (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x78000C00l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn and imm9 = offset land 0x1FF in
      Int32.logor 0x78000400l (Int32.of_int ((imm9 lsl 12) lor ((n land 0x1F) lsl 5) lor (t land 0x1F)))

let enc_ldp (rt1 : reg) (rt2 : reg) (mem : mem_op) : int32 =
  let t1 = reg_to_int rt1 and t2 = reg_to_int rt2 in
  let bit64 = is_64bit rt1 in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA9400000l else 0x29400000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA9C00000l else 0x29C00000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA8C00000l else 0x28C00000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))

let enc_stp (rt1 : reg) (rt2 : reg) (mem : mem_op) : int32 =
  let t1 = reg_to_int rt1 and t2 = reg_to_int rt2 in
  let bit64 = is_64bit rt1 in
  match mem with
  | Addr (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA9000000l else 0x29000000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))
  | PreIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA9800000l else 0x29800000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))
  | PostIndex (rn, offset) ->
      let n = reg_to_int rn in
      let imm7 = (offset lsr (if bit64 then 3 else 2)) land 0x7F in
      let opc = if bit64 then 0xA8800000l else 0x28800000l in
      Int32.logor opc (Int32.of_int ((imm7 lsl 15) lor ((t2 land 0x1F) lsl 10) lor ((n land 0x1F) lsl 5) lor (t1 land 0x1F)))

(* Comparison, Select & Conditional Moves *)
let enc_cmp (rn : reg) (rm : reg) : int32 =
  let n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rn then 0x80000000l else 0x00000000l in
  Int32.logor (Int32.logor 0x6B00001Fl sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor ((n land 0x1F) lsl 5)))

let enc_cmp_imm (rn : reg) (imm : int) : int32 =
  let n = reg_to_int rn in
  let sf_bit = if is_64bit rn then 0x80000000l else 0x00000000l in
  let imm12 = imm land 0xFFF in
  Int32.logor (Int32.logor 0x7100001Fl sf_bit) (Int32.of_int ((imm12 lsl 10) lor ((n land 0x1F) lsl 5)))

let enc_cset (rd : reg) (cond : cond) : int32 =
  let d = reg_to_int rd in
  let inv_code = match cond with
    | Eq -> 0x1 (* NE *) | Ne -> 0x0 (* EQ *) | Ge -> 0xB (* LT *)
    | Lt -> 0xA (* GE *) | Gt -> 0xD (* LE *) | Le -> 0xC (* GT *)
    | _  -> cond_to_code cond lxor 1
  in
  Int32.logor 0x1A9F07E0l (Int32.of_int ((inv_code lsl 12) lor (d land 0x1F)))

let enc_csel (rd : reg) (rn : reg) (rm : reg) (cond : cond) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let c = cond_to_code cond in
  Int32.logor (Int32.logor 0x1A800000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (c lsl 12) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_csinc (rd : reg) (rn : reg) (rm : reg) (cond : cond) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let c = cond_to_code cond in
  Int32.logor (Int32.logor 0x1A800400l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (c lsl 12) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_csinv (rd : reg) (rn : reg) (rm : reg) (cond : cond) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let c = cond_to_code cond in
  Int32.logor (Int32.logor 0x5A800000l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (c lsl 12) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

let enc_csneg (rd : reg) (rn : reg) (rm : reg) (cond : cond) : int32 =
  let d = reg_to_int rd and n = reg_to_int rn and m = reg_to_int rm in
  let sf_bit = if is_64bit rd then 0x80000000l else 0x00000000l in
  let c = cond_to_code cond in
  Int32.logor (Int32.logor 0x5A800400l sf_bit) (Int32.of_int (((m land 0x1F) lsl 16) lor (c lsl 12) lor ((n land 0x1F) lsl 5) lor (d land 0x1F)))

(* Branching, Calls, and System Registers *)
let enc_ret : int32 = 0xD65F03C0l
let enc_nop : int32 = 0xD503201Fl
let enc_isb : int32 = 0xD5033FDFl
let enc_dmb : int32 = 0xD50339BFl

let enc_blr (rn : reg) : int32 =
  Int32.logor 0xD63F0000l (Int32.of_int ((reg_to_int rn land 0x1F) lsl 5))

let enc_br (rn : reg) : int32 =
  Int32.logor 0xD61F0000l (Int32.of_int ((reg_to_int rn land 0x1F) lsl 5))

let enc_brk (imm : int) : int32 =
  Int32.logor 0xD4200000l (Int32.of_int ((imm land 0xFFFF) lsl 5))

let enc_mrs_cntvct (rd : reg) : int32 =
  Int32.logor 0xD53BE020l (Int32.of_int (reg_to_int rd land 0x1F))

type flat_item =
  | F_Word of int32
  | F_Label of string
  | F_BCond of cond * string
  | F_B of string
  | F_Cbz of reg * string
  | F_Cbnz of reg * string
  | F_Bl of string
  | F_Adr of reg * string

(** Assembles a typed AST program into a list of 32-bit words, resolving labels and branches. *)
let assemble ?(insert_decoys : bool = true) (prog : prog) : int32 list =
  let flat_items = ref [] in
  List.iter
    (fun insn ->
      match insn with
      | Raw w -> flat_items := F_Word w :: !flat_items
      | Label lbl -> flat_items := F_Label lbl :: !flat_items
      | MovImm (rd, imm) ->
          let words = enc_mov_imm rd imm in
          List.iter (fun w -> flat_items := F_Word w :: !flat_items) words
      | MovReg (rd, rm) -> flat_items := F_Word (enc_mov_reg rd rm) :: !flat_items
      | Adr (rd, target) -> flat_items := F_Adr (rd, target) :: !flat_items
      | Add (rd, rn, rm) -> flat_items := F_Word (enc_add rd rn rm) :: !flat_items
      | AddImm (rd, rn, imm) -> flat_items := F_Word (enc_add_imm rd rn imm) :: !flat_items
      | Sub (rd, rn, rm) -> flat_items := F_Word (enc_sub rd rn rm) :: !flat_items
      | SubImm (rd, rn, imm) -> flat_items := F_Word (enc_sub_imm rd rn imm) :: !flat_items
      | Mul (rd, rn, rm) -> flat_items := F_Word (enc_mul rd rn rm) :: !flat_items
      | Madd (rd, rn, rm, ra) -> flat_items := F_Word (enc_madd rd rn rm ra) :: !flat_items
      | Msub (rd, rn, rm, ra) -> flat_items := F_Word (enc_msub rd rn rm ra) :: !flat_items
      | Udiv (rd, rn, rm) -> flat_items := F_Word (enc_udiv rd rn rm) :: !flat_items
      | Sdiv (rd, rn, rm) -> flat_items := F_Word (enc_sdiv rd rn rm) :: !flat_items
      | And (rd, rn, rm) -> flat_items := F_Word (enc_and rd rn rm) :: !flat_items
      | Orr (rd, rn, rm) -> flat_items := F_Word (enc_orr rd rn rm) :: !flat_items
      | Eor (rd, rn, rm) -> flat_items := F_Word (enc_eor rd rn rm) :: !flat_items
      | Bic (rd, rn, rm) -> flat_items := F_Word (enc_bic rd rn rm) :: !flat_items
      | Orn (rd, rn, rm) -> flat_items := F_Word (enc_orn rd rn rm) :: !flat_items
      | Eon (rd, rn, rm) -> flat_items := F_Word (enc_eon rd rn rm) :: !flat_items
      | Mvn (rd, rm) -> flat_items := F_Word (enc_mvn rd rm) :: !flat_items
      | Neg (rd, rm) -> flat_items := F_Word (enc_neg rd rm) :: !flat_items
      | LslImm (rd, rn, s) -> flat_items := F_Word (enc_lsl_imm rd rn s) :: !flat_items
      | LsrImm (rd, rn, s) -> flat_items := F_Word (enc_lsr_imm rd rn s) :: !flat_items
      | AsrImm (rd, rn, s) -> flat_items := F_Word (enc_asr_imm rd rn s) :: !flat_items
      | RorReg (rd, rn, rm) -> flat_items := F_Word (enc_ror_reg rd rn rm) :: !flat_items
      | Rev (rd, rn) -> flat_items := F_Word (enc_rev rd rn) :: !flat_items
      | Clz (rd, rn) -> flat_items := F_Word (enc_clz rd rn) :: !flat_items
      | Ldr (rt, mem) -> flat_items := F_Word (enc_ldr rt mem) :: !flat_items
      | Str (rt, mem) -> flat_items := F_Word (enc_str rt mem) :: !flat_items
      | Ldrb (rt, mem) -> flat_items := F_Word (enc_ldrb rt mem) :: !flat_items
      | Strb (rt, mem) -> flat_items := F_Word (enc_strb rt mem) :: !flat_items
      | Ldrh (rt, mem) -> flat_items := F_Word (enc_ldrh rt mem) :: !flat_items
      | Strh (rt, mem) -> flat_items := F_Word (enc_strh rt mem) :: !flat_items
      | Ldp (rt1, rt2, mem) -> flat_items := F_Word (enc_ldp rt1 rt2 mem) :: !flat_items
      | Stp (rt1, rt2, mem) -> flat_items := F_Word (enc_stp rt1 rt2 mem) :: !flat_items
      | Cmp (rn, rm) -> flat_items := F_Word (enc_cmp rn rm) :: !flat_items
      | CmpImm (rn, imm) -> flat_items := F_Word (enc_cmp_imm rn imm) :: !flat_items
      | Cset (rd, c) -> flat_items := F_Word (enc_cset rd c) :: !flat_items
      | Csel (rd, rn, rm, c) -> flat_items := F_Word (enc_csel rd rn rm c) :: !flat_items
      | Csinc (rd, rn, rm, c) -> flat_items := F_Word (enc_csinc rd rn rm c) :: !flat_items
      | Csinv (rd, rn, rm, c) -> flat_items := F_Word (enc_csinv rd rn rm c) :: !flat_items
      | Csneg (rd, rn, rm, c) -> flat_items := F_Word (enc_csneg rd rn rm c) :: !flat_items
      | B target -> flat_items := F_B target :: !flat_items
      | BCond (c, target) -> flat_items := F_BCond (c, target) :: !flat_items
      | Cbz (rt, target) -> flat_items := F_Cbz (rt, target) :: !flat_items
      | Cbnz (rt, target) -> flat_items := F_Cbnz (rt, target) :: !flat_items
      | Bl target -> flat_items := F_Bl target :: !flat_items
      | Blr rn -> flat_items := F_Word (enc_blr rn) :: !flat_items
      | Br rn -> flat_items := F_Word (enc_br rn) :: !flat_items
      | Ret -> flat_items := F_Word enc_ret :: !flat_items
      | Brk imm -> flat_items := F_Word (enc_brk imm) :: !flat_items
      | MrsCntvct rd -> flat_items := F_Word (enc_mrs_cntvct rd) :: !flat_items
      | Isb -> flat_items := F_Word enc_isb :: !flat_items
      | Dmb -> flat_items := F_Word enc_dmb :: !flat_items
      | Nop -> flat_items := F_Word enc_nop :: !flat_items
      | Decoy `ZeroLogic -> flat_items := F_Word (enc_eor XZR XZR XZR) :: !flat_items
      | Decoy `Nop -> flat_items := F_Word enc_nop :: !flat_items)
    prog;

  let items = List.rev !flat_items in

  (* Optional Phase 2: Decoy expansion *)
  let items_with_decoys =
    if not insert_decoys then items
    else
      List.concat_map
        (fun item ->
          match item with
          | F_Word w ->
              if Random.int 100 < 20 then
                let decoy = if Random.bool () then enc_eor XZR XZR XZR else enc_nop in
                [ F_Word w; F_Word decoy ]
              else [ F_Word w ]
          | other -> [ other ])
        items
  in

  (* Phase 3: Label Address Resolution *)
  let label_pos = Hashtbl.create 16 in
  let current_pc = ref 0 in
  List.iter
    (fun item ->
      match item with
      | F_Label lbl -> Hashtbl.replace label_pos lbl !current_pc
      | F_Word _ | F_BCond _ | F_B _ | F_Cbz _ | F_Cbnz _ | F_Bl _ | F_Adr _ -> incr current_pc)
    items_with_decoys;

  (* Phase 4: Final Emission and Branch/Address Target Calculation *)
  let final_words = ref [] in
  let pc = ref 0 in
  List.iter
    (fun item ->
      match item with
      | F_Label _ -> ()
      | F_Word w ->
          final_words := w :: !final_words;
          incr pc
      | F_BCond (c, target) ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm19 = offset land 0x7FFFF in
          let code = cond_to_code c in
          let b_word = Int32.logor 0x54000000l (Int32.of_int ((imm19 lsl 5) lor code)) in
          final_words := b_word :: !final_words;
          incr pc
      | F_B target ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm26 = offset land 0x03FFFFFF in
          let b_word = Int32.logor 0x14000000l (Int32.of_int imm26) in
          final_words := b_word :: !final_words;
          incr pc
      | F_Bl target ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm26 = offset land 0x03FFFFFF in
          let bl_word = Int32.logor 0x94000000l (Int32.of_int imm26) in
          final_words := bl_word :: !final_words;
          incr pc
      | F_Cbz (rt, target) ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm19 = offset land 0x7FFFF in
          let sf_bit = if is_64bit rt then 0x80000000l else 0x00000000l in
          let cbz_word = Int32.logor (Int32.logor 0x34000000l sf_bit) (Int32.of_int ((imm19 lsl 5) lor (reg_to_int rt land 0x1F))) in
          final_words := cbz_word :: !final_words;
          incr pc
      | F_Cbnz (rt, target) ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm19 = offset land 0x7FFFF in
          let sf_bit = if is_64bit rt then 0x80000000l else 0x00000000l in
          let cbnz_word = Int32.logor (Int32.logor 0x35000000l sf_bit) (Int32.of_int ((imm19 lsl 5) lor (reg_to_int rt land 0x1F))) in
          final_words := cbnz_word :: !final_words;
          incr pc
      | F_Adr (rd, target) ->
          let target_pc = Hashtbl.find label_pos target in
          let offset = target_pc - !pc in
          let imm21 = offset land 0x1FFFFF in
          let immlo = imm21 land 0x3 in
          let immhi = (imm21 lsr 2) land 0x7FFFF in
          let adr_word = Int32.logor 0x10000000l (Int32.of_int ((immlo lsl 29) lor (immhi lsl 5) lor (reg_to_int rd land 0x1F))) in
          final_words := adr_word :: !final_words;
          incr pc)
    items_with_decoys;

  List.rev !final_words

(** Formats an instruction list into an encrypted C array with session key *)
let to_encrypted_c_array ?(key : int32 option) (words : int32 list) : (string * int32 * int) =
  let session_key =
    match key with
    | Some k -> k
    | None -> Int32.logor (Int32.of_int (Random.bits ())) 0x10000001l
  in
  let enc_words = List.map (fun w -> Int32.logxor w session_key) words in
  let array_str =
    List.map (fun w -> Printf.sprintf "0x%08lXU" w) enc_words
    |> String.concat ", "
  in
  (array_str, session_key, List.length enc_words)

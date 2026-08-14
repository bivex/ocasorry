open Types
open Ast
open Cil_opcodes

type intermediate_cil_item =
  | Byte of int
  | Int32Val of int32
  | Int64Val of int64
  | TargetLabel of label
  | CondBranch of condition * label

let reg_to_loc (r : reg) : int = reg_to_int r

let translate_instruction (instr : instruction) : intermediate_cil_item list =
  match instr with
  | MovReg (d, s) ->
      [ Byte ldloc; Byte (reg_to_loc s); Byte stloc; Byte (reg_to_loc d) ]

  | MovImm (d, imm) ->
      [ Byte ldc_i8; Int64Val imm; Byte stloc; Byte (reg_to_loc d) ]

  | Add (d, n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m);
        Byte add_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | AddImm (d, n, imm) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldc_i4; Int32Val (Int32.of_int imm);
        Byte conv_i8;
        Byte add_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Sub (d, n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m);
        Byte sub_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | SubImm (d, n, imm) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldc_i4; Int32Val (Int32.of_int imm);
        Byte conv_i8;
        Byte sub_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | And (d, n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m);
        Byte and_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Orr (d, n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m);
        Byte or_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Eor (d, n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m);
        Byte xor_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Mvn (d, m) ->
      [ Byte ldloc; Byte (reg_to_loc m);
        Byte not_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Lsl (d, n, shift) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldc_i4; Int32Val (Int32.of_int shift);
        Byte shl_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Lsr (d, n, shift) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldc_i4; Int32Val (Int32.of_int shift);
        Byte shr_un_op;
        Byte stloc; Byte (reg_to_loc d) ]

  | Cmp (n, m) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldloc; Byte (reg_to_loc m) ]

  | CmpImm (n, imm) ->
      [ Byte ldloc; Byte (reg_to_loc n);
        Byte ldc_i4; Int32Val (Int32.of_int imm);
        Byte conv_i8 ]

  | B label ->
      [ Byte br_s; TargetLabel label ]

  | Bcc (cond, label) ->
      [ CondBranch (cond, label) ]

  | Ret None ->
      [ Byte ldloc; Byte (reg_to_loc X0); Byte ret_op ]

  | Ret (Some r) ->
      [ Byte ldloc; Byte (reg_to_loc r); Byte ret_op ]

  | Nop ->
      [ Byte nop_op ]

  | Raw32 w ->
      [ Byte ldc_i4; Int32Val w; Byte pop_op ]

open Types
open Ast

type intermediate_op =
  | Concrete of int32
  | BranchUncond of label
  | BranchCond of condition * label

let encode_reg (r : reg) : int = reg_to_int r

let emit_mov_imm (d : reg) (imm : int64) : int32 list =
  let rd = encode_reg d in
  let chunk0 = Int64.to_int (Int64.logand imm 0xFFFFL) in
  let chunk1 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 16) 0xFFFFL) in
  let chunk2 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 32) 0xFFFFL) in
  let chunk3 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 48) 0xFFFFL) in

  let movz = Int32.logor 0xD2800000l (Int32.of_int ((chunk0 lsl 5) lor rd)) in
  let instrs = ref [ movz ] in

  let emit_movk chunk hw =
    if chunk <> 0 then
      let base = Int32.logor 0xF2800000l (Int32.shift_left (Int32.of_int hw) 21) in
      let op = Int32.logor base (Int32.of_int ((chunk lsl 5) lor rd)) in
      instrs := !instrs @ [ op ]
  in
  emit_movk chunk1 1;
  emit_movk chunk2 2;
  emit_movk chunk3 3;
  !instrs

let translate_instruction (instr : instruction) : intermediate_op list =
  match instr with
  | MovReg (d, m) ->
      let rd = encode_reg d in
      let rm = encode_reg m in
      let op = Int32.logor 0xAA0003E0l (Int32.of_int ((rm lsl 16) lor rd)) in
      [ Concrete op ]

  | MovImm (d, imm) ->
      List.map (fun op -> Concrete op) (emit_mov_imm d imm)

  | Add (d, n, m) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0x8B000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | AddImm (d, n, imm) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let imm12 = imm land 0xFFF in
      let op = Int32.logor 0x91000000l (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Sub (d, n, m) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0xCB000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | SubImm (d, n, imm) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let imm12 = imm land 0xFFF in
      let op = Int32.logor 0xD1000000l (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | And (d, n, m) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0x8A000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Orr (d, n, m) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0xAA000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Eor (d, n, m) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0xCA000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Mvn (d, m) ->
      let rd = encode_reg d in
      let rm = encode_reg m in
      let op = Int32.logor 0xAA2003E0l (Int32.of_int ((rm lsl 16) lor rd)) in
      [ Concrete op ]

  | Lsl (d, n, shift) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let immr = (64 - (shift land 63)) land 63 in
      let imms = 63 - (shift land 63) in
      let op = Int32.logor 0xD3400000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Lsr (d, n, shift) ->
      let rd = encode_reg d in
      let rn = encode_reg n in
      let immr = shift land 63 in
      let imms = 63 in
      let op = Int32.logor 0xD3400000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor (rn lsl 5) lor rd)) in
      [ Concrete op ]

  | Cmp (n, m) ->
      let rn = encode_reg n in
      let rm = encode_reg m in
      let op = Int32.logor 0xEB00001Fl (Int32.of_int ((rm lsl 16) lor (rn lsl 5))) in
      [ Concrete op ]

  | CmpImm (n, imm) ->
      let rn = encode_reg n in
      let imm12 = imm land 0xFFF in
      let op = Int32.logor 0xF100001Fl (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5))) in
      [ Concrete op ]

  | B label -> [ BranchUncond label ]
  | Bcc (cond, label) -> [ BranchCond (cond, label) ]

  | Ret None -> [ Concrete 0xD65F03C0l ]
  | Ret (Some r) ->
      let rn = encode_reg r in
      let op = Int32.logor 0xD65F0000l (Int32.of_int (rn lsl 5)) in
      [ Concrete op ]

  | Nop -> [ Concrete 0xD503201Fl ]
  | Raw32 w -> [ Concrete w ]

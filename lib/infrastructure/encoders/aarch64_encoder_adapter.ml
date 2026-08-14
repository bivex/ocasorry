open Types
open Ast
open Cfg

module Adapter : Encoder_port.S = struct
  let architecture_name = "AArch64 (ARM64)"

  let encode_reg (r : reg) : int = reg_to_int r

  (** Emits 64-bit MOV immediate sequence via MOVZ + MOVK *)
  let emit_mov_imm (d : reg) (imm : int64) : int32 list =
    let rd = encode_reg d in
    let chunk0 = Int64.to_int (Int64.logand imm 0xFFFFL) in
    let chunk1 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 16) 0xFFFFL) in
    let chunk2 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 32) 0xFFFFL) in
    let chunk3 = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 48) 0xFFFFL) in

    (* MOVZ Xd, #chunk0, LSL 0 -> 0xD2800000 | (0 << 21) | (chunk0 << 5) | rd *)
    let movz = Int32.logor 0xD2800000l (Int32.of_int ((chunk0 lsl 5) lor rd)) in
    let instrs = ref [ movz ] in

    let emit_movk chunk hw =
      if chunk <> 0 then
        (* MOVK Xd, #chunk, LSL (hw * 16) -> 0xF2800000 | (hw << 21) | (chunk << 5) | rd *)
        let base = Int32.logor 0xF2800000l (Int32.shift_left (Int32.of_int hw) 21) in
        let op = Int32.logor base (Int32.of_int ((chunk lsl 5) lor rd)) in
        instrs := !instrs @ [ op ]
    in
    emit_movk chunk1 1;
    emit_movk chunk2 2;
    emit_movk chunk3 3;
    !instrs

  type intermediate_op =
    | Concrete of int32
    | BranchUncond of label
    | BranchCond of condition * label

  let translate_instruction (instr : instruction) : intermediate_op list =
    match instr with
    | MovReg (d, m) ->
        (* ORR Xd, XZR, Xm (64-bit) -> 0xAA0003E0 | (Xm << 16) | Xd *)
        let rd = encode_reg d in
        let rm = encode_reg m in
        let op = Int32.logor 0xAA0003E0l (Int32.of_int ((rm lsl 16) lor rd)) in
        [ Concrete op ]

    | MovImm (d, imm) ->
        List.map (fun op -> Concrete op) (emit_mov_imm d imm)

    | Add (d, n, m) ->
        (* ADD Xd, Xn, Xm -> 0x8B000000 | (Rm << 16) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0x8B000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | AddImm (d, n, imm) ->
        (* ADD Xd, Xn, #imm12 -> 0x91000000 | ((imm & 0xFFF) << 10) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let imm12 = imm land 0xFFF in
        let op = Int32.logor 0x91000000l (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Sub (d, n, m) ->
        (* SUB Xd, Xn, Xm -> 0xCB000000 | (Rm << 16) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0xCB000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | SubImm (d, n, imm) ->
        (* SUB Xd, Xn, #imm12 -> 0xD1000000 | ((imm & 0xFFF) << 10) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let imm12 = imm land 0xFFF in
        let op = Int32.logor 0xD1000000l (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | And (d, n, m) ->
        (* AND Xd, Xn, Xm -> 0x8A000000 | (Rm << 16) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0x8A000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Orr (d, n, m) ->
        (* ORR Xd, Xn, Xm -> 0xAA000000 | (Rm << 16) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0xAA000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Eor (d, n, m) ->
        (* EOR Xd, Xn, Xm -> 0xCA000000 | (Rm << 16) | (Rn << 5) | Rd *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0xCA000000l (Int32.of_int ((rm lsl 16) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Mvn (d, m) ->
        (* ORN Xd, XZR, Xm -> 0xAA2003E0 | (Xm << 16) | Xd *)
        let rd = encode_reg d in
        let rm = encode_reg m in
        let op = Int32.logor 0xAA2003E0l (Int32.of_int ((rm lsl 16) lor rd)) in
        [ Concrete op ]

    | Lsl (d, n, shift) ->
        (* UBFM Xd, Xn, #(-shift mod 64), #(63 - shift) *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let immr = (64 - (shift land 63)) land 63 in
        let imms = 63 - (shift land 63) in
        let op = Int32.logor 0xD3400000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Lsr (d, n, shift) ->
        (* UBFM Xd, Xn, #shift, #63 *)
        let rd = encode_reg d in
        let rn = encode_reg n in
        let immr = shift land 63 in
        let imms = 63 in
        let op = Int32.logor 0xD3400000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor (rn lsl 5) lor rd)) in
        [ Concrete op ]

    | Cmp (n, m) ->
        (* SUBS XZR, Xn, Xm -> 0xEB00001F | (Rm << 16) | (Rn << 5) *)
        let rn = encode_reg n in
        let rm = encode_reg m in
        let op = Int32.logor 0xEB00001Fl (Int32.of_int ((rm lsl 16) lor (rn lsl 5))) in
        [ Concrete op ]

    | CmpImm (n, imm) ->
        (* SUBS XZR, Xn, #imm12 -> 0xF100001F | ((imm & 0xFFF) << 10) | (Rn << 5) *)
        let rn = encode_reg n in
        let imm12 = imm land 0xFFF in
        let op = Int32.logor 0xF100001Fl (Int32.of_int ((imm12 lsl 10) lor (rn lsl 5))) in
        [ Concrete op ]

    | B label -> [ BranchUncond label ]
    | Bcc (cond, label) -> [ BranchCond (cond, label) ]

    | Ret None ->
        (* RET X30 -> 0xD65F03C0 *)
        [ Concrete 0xD65F03C0l ]
    | Ret (Some r) ->
        let rn = encode_reg r in
        let op = Int32.logor 0xD65F0000l (Int32.of_int (rn lsl 5)) in
        [ Concrete op ]

    | Nop -> [ Concrete 0xD503201Fl ]
    | Raw32 w -> [ Concrete w ]

  let write_int32_le buf offset (w : int32) =
    Bytes.set_int32_ne buf offset w

  let encode_block (block : BasicBlock.t) : bytes =
    let ops = List.concat_map translate_instruction block.instructions in
    let buf = Bytes.create (List.length ops * 4) in
    List.iteri
      (fun i op ->
        match op with
        | Concrete w -> write_int32_le buf (i * 4) w
        | BranchUncond _ | BranchCond _ ->
            write_int32_le buf (i * 4) 0xD503201Fl)
      ops;
    buf

  let encode_cfg (cfg : CFG.t) : (bytes, string) result =
    let entry_block =
      match CFG.find_block cfg cfg.entry with
      | Some b -> b
      | None -> BasicBlock.create ~id:cfg.entry ~instructions:[]
    in
    let other_blocks =
      List.filter (fun (b : BasicBlock.t) -> b.id <> cfg.entry) cfg.blocks
    in
    let ordered_blocks = entry_block :: other_blocks in

    let label_offsets = Hashtbl.create 16 in
    let flattened_ops = ref [] in
    let current_pc = ref 0 in

    List.iter
      (fun (block : BasicBlock.t) ->
        Hashtbl.add label_offsets block.id !current_pc;
        let ops = List.concat_map translate_instruction block.instructions in
        List.iter
          (fun op ->
            flattened_ops := !flattened_ops @ [ (!current_pc, op) ];
            current_pc := !current_pc + 4)
          ops)
      ordered_blocks;

    let total_bytes = !current_pc in
    let buf = Bytes.create total_bytes in
    let encode_error = ref None in

    List.iter
      (fun (pc, op) ->
        match op with
        | Concrete w -> write_int32_le buf pc w
        | BranchUncond target_lbl -> (
            match Hashtbl.find_opt label_offsets target_lbl with
            | None -> encode_error := Some ("Undefined label: " ^ target_lbl)
            | Some target_pc ->
                let delta_bytes = target_pc - pc in
                let delta_words = delta_bytes / 4 in
                let imm26 = delta_words land 0x03FFFFFF in
                let w = Int32.logor 0x14000000l (Int32.of_int imm26) in
                write_int32_le buf pc w)
        | BranchCond (cond, target_lbl) -> (
            match Hashtbl.find_opt label_offsets target_lbl with
            | None -> encode_error := Some ("Undefined label: " ^ target_lbl)
            | Some target_pc ->
                let delta_bytes = target_pc - pc in
                let delta_words = delta_bytes / 4 in
                let imm19 = delta_words land 0x7FFFF in
                let cond_code = cond_to_code cond land 0xF in
                let w =
                  Int32.logor
                    0x54000000l
                    (Int32.of_int ((imm19 lsl 5) lor cond_code))
                in
                write_int32_le buf pc w))
      !flattened_ops;

    match !encode_error with
    | Some err -> Error err
    | None -> Ok buf
end

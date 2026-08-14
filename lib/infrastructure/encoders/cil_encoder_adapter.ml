open Types
open Ast
open Cfg
open Cil_opcodes

module Adapter : Encoder_port.S = struct
  let architecture_name = "Common Intermediate Language (CIL / ECMA-335)"

  type cil_byte_item =
    | RawByte of int
    | RawInt32 of int32
    | RawInt64 of int64
    | BranchTarget of cil_opcode * label

  let reg_index (r : reg) =
    match r with
    | X0 -> 0
    | X1 -> 1
    | X2 -> 2
    | X3 -> 3
    | X15 -> 4
    | X16 -> 5
    | X17 -> 6
    | _ -> 7

  let emit_ldreg r =
    match r with
    | X0 -> [ RawByte 0x02 ] (* ldarg.0 *)
    | X1 -> [ RawByte 0x03 ] (* ldarg.1 *)
    | X2 -> [ RawByte 0x04 ] (* ldarg.2 / ldloc.0 *)
    | _ ->
        let idx = reg_index r in
        [ RawByte 0x0E; RawByte idx ] (* ldarg.s idx *)

  let emit_streg r =
    let idx = reg_index r in
    match idx with
    | 0 -> [ RawByte 0x0A ] (* starg.s 0 *)
    | 1 -> [ RawByte 0x0B ] (* starg.s 1 *)
    | _ -> [ RawByte 0x10; RawByte idx ] (* starg.s idx *)

  let translate_instruction (instr : instruction) : cil_byte_item list =
    match instr with
    | MovReg (d, m) ->
        emit_ldreg m @ emit_streg d

    | MovImm (d, imm) ->
        [ RawByte 0x21; RawInt64 imm ] @ emit_streg d

    | Add (d, n, m) ->
        emit_ldreg n @ emit_ldreg m @ [ RawByte 0x58 ] @ emit_streg d

    | AddImm (d, n, imm) ->
        emit_ldreg n @ [ RawByte 0x20; RawInt32 (Int32.of_int imm); RawByte 0x58 ] @ emit_streg d

    | Sub (d, n, m) ->
        emit_ldreg n @ emit_ldreg m @ [ RawByte 0x59 ] @ emit_streg d

    | SubImm (d, n, imm) ->
        emit_ldreg n @ [ RawByte 0x20; RawInt32 (Int32.of_int imm); RawByte 0x59 ] @ emit_streg d

    | And (d, n, m) ->
        emit_ldreg n @ emit_ldreg m @ [ RawByte 0x5F ] @ emit_streg d

    | Orr (d, n, m) ->
        emit_ldreg n @ emit_ldreg m @ [ RawByte 0x60 ] @ emit_streg d

    | Eor (d, n, m) ->
        emit_ldreg n @ emit_ldreg m @ [ RawByte 0x61 ] @ emit_streg d

    | Mvn (d, m) ->
        emit_ldreg m @ [ RawByte 0x66 ] @ emit_streg d

    | Lsl (d, n, shift) ->
        emit_ldreg n @ [ RawByte 0x20; RawInt32 (Int32.of_int shift); RawByte 0x62 ] @ emit_streg d

    | Lsr (d, n, shift) ->
        emit_ldreg n @ [ RawByte 0x20; RawInt32 (Int32.of_int shift); RawByte 0x63 ] @ emit_streg d

    | Cmp (n, m) ->
        emit_ldreg n @ emit_ldreg m

    | CmpImm (n, imm) ->
        emit_ldreg n @ [ RawByte 0x20; RawInt32 (Int32.of_int imm) ]

    | B label ->
        [ BranchTarget (Br label, label) ]

    | Bcc (cond, label) ->
        let op =
          match cond with
          | EQ -> Beq label
          | NE -> Bne_un label
          | LT -> Blt label
          | LE -> Ble label
          | GT -> Bgt label
          | GE -> Bge label
          | _ -> Br label
        in
        [ BranchTarget (op, label) ]

    | Ret _ ->
        emit_ldreg X0 @ [ RawByte 0x2A ] (* ldarg.0; ret *)

    | Nop ->
        [ RawByte 0x00 ]

    | Raw32 w ->
        [ RawByte 0x20; RawInt32 w; RawByte 0x26 ] (* ldc.i4 w; pop *)

  let item_size = function
    | RawByte _ -> 1
    | RawInt32 _ -> 4
    | RawInt64 _ -> 8
    | BranchTarget _ -> 5 (* 1 opcode + 4 bytes int32 relative offset *)

  let encode_block (block : BasicBlock.t) : bytes =
    let items = List.concat_map translate_instruction block.instructions in
    let total_size = List.fold_left (fun acc it -> acc + item_size it) 0 items in
    let buf = Bytes.create total_size in
    let offset = ref 0 in
    List.iter
      (function
        | RawByte b ->
            Bytes.set_uint8 buf !offset b;
            offset := !offset + 1
        | RawInt32 i ->
            Bytes.set_int32_ne buf !offset i;
            offset := !offset + 4
        | RawInt64 i ->
            Bytes.set_int64_ne buf !offset i;
            offset := !offset + 8
        | BranchTarget _ ->
            Bytes.set_uint8 buf !offset 0x00;
            offset := !offset + 5)
      items;
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
    let flattened_items = ref [] in
    let current_offset = ref 0 in

    List.iter
      (fun (block : BasicBlock.t) ->
        Hashtbl.add label_offsets block.id !current_offset;
        let items = List.concat_map translate_instruction block.instructions in
        List.iter
          (fun item ->
            flattened_items := !flattened_items @ [ (!current_offset, item) ];
            current_offset := !current_offset + item_size item)
          items)
      ordered_blocks;

    let total_bytes = !current_offset in
    let buf = Bytes.create total_bytes in
    let encode_error = ref None in
    let write_ptr = ref 0 in

    List.iter
      (fun (pc, item) ->
        match item with
        | RawByte b ->
            Bytes.set_uint8 buf !write_ptr b;
            write_ptr := !write_ptr + 1
        | RawInt32 i ->
            Bytes.set_int32_ne buf !write_ptr i;
            write_ptr := !write_ptr + 4
        | RawInt64 i ->
            Bytes.set_int64_ne buf !write_ptr i;
            write_ptr := !write_ptr + 8
        | BranchTarget (op, target_lbl) -> (
            match Hashtbl.find_opt label_offsets target_lbl with
            | None -> encode_error := Some ("Undefined CIL label: " ^ target_lbl)
            | Some target_pc ->
                let branch_instr_size = 5 in
                let next_instr_pc = pc + branch_instr_size in
                let rel_offset = Int32.of_int (target_pc - next_instr_pc) in
                let opcode_byte =
                  match op with
                  | Br _ -> 0x38
                  | Beq _ -> 0x3B
                  | Bge _ -> 0x3C
                  | Bgt _ -> 0x3D
                  | Ble _ -> 0x3E
                  | Blt _ -> 0x3F
                  | Bne_un _ -> 0x40
                  | _ -> 0x38
                in
                Bytes.set_uint8 buf !write_ptr opcode_byte;
                Bytes.set_int32_ne buf (!write_ptr + 1) rel_offset;
                write_ptr := !write_ptr + 5))
      !flattened_items;

    match !encode_error with
    | Some err -> Error err
    | None -> Ok buf
end

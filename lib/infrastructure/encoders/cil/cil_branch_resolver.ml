open Types
open Cfg
open Cil_opcodes
open Cil_translator

let cond_to_cil_branch_op (c : condition) : int =
  match c with
  | EQ -> beq_s
  | NE -> bne_un_s
  | GE -> bge_s
  | GT -> bgt_s
  | LE -> ble_s
  | LT -> blt_s
  | CS | HI -> bge_un_s
  | CC | LS -> blt_un_s
  | _ -> br_s

let item_size (item : intermediate_cil_item) : int =
  match item with
  | Byte _ -> 1
  | Int32Val _ -> 4
  | Int64Val _ -> 8
  | TargetLabel _ -> 4
  | CondBranch _ -> 5

let resolve_and_emit (cfg : CFG.t) : bytes =
  let block_offsets = Hashtbl.create 16 in
  let current_pc = ref 0 in
  let intermediate_stream = ref [] in

  List.iter
    (fun (b : BasicBlock.t) ->
      Hashtbl.add block_offsets b.id !current_pc;
      List.iter
        (fun instr ->
          let items = translate_instruction instr in
          List.iter
            (fun it ->
              let sz = item_size it in
              intermediate_stream := (!current_pc, it) :: !intermediate_stream;
              current_pc := !current_pc + sz)
            items)
        b.instructions)
    cfg.blocks;

  let stream = List.rev !intermediate_stream in
  let total_bytes = !current_pc in
  let buf = Bytes.create total_bytes in

  List.iter
    (fun (pc, item) ->
      match item with
      | Byte b -> Bytes.set_uint8 buf pc b
      | Int32Val v -> Bytes.set_int32_le buf pc v
      | Int64Val v -> Bytes.set_int64_le buf pc v
      | TargetLabel target_lbl ->
          let target_pc = Hashtbl.find block_offsets target_lbl in
          let next_pc = pc + 4 in
          let offset = Int32.of_int (target_pc - next_pc) in
          Bytes.set_int32_le buf pc offset
      | CondBranch (cond, target_lbl) ->
          let op = cond_to_cil_branch_op cond in
          Bytes.set_uint8 buf pc op;
          let target_pc = Hashtbl.find block_offsets target_lbl in
          let next_pc = pc + 5 in
          let offset = Int32.of_int (target_pc - next_pc) in
          Bytes.set_int32_le buf (pc + 1) offset)
    stream;

  buf

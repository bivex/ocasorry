open Types
open Cfg
open Arm64_opcodes

let condition_to_int (c : condition) : int =
  match c with
  | EQ -> 0x0
  | NE -> 0x1
  | CS -> 0x2
  | CC -> 0x3
  | MI -> 0x4
  | PL -> 0x5
  | VS -> 0x6
  | VC -> 0x7
  | HI -> 0x8
  | LS -> 0x9
  | GE -> 0xA
  | LT -> 0xB
  | GT -> 0xC
  | LE -> 0xD
  | AL -> 0xE

let resolve_and_emit (cfg : CFG.t) : bytes =
  let block_offsets = Hashtbl.create 16 in
  let current_pc = ref 0 in
  let intermediate_stream = ref [] in

  List.iter
    (fun (b : BasicBlock.t) ->
      Hashtbl.add block_offsets b.id !current_pc;
      List.iter
        (fun instr ->
          let ops = translate_instruction instr in
          List.iter
            (fun op ->
              intermediate_stream := (!current_pc, op) :: !intermediate_stream;
              current_pc := !current_pc + 4)
            ops)
        b.instructions)
    cfg.blocks;

  let stream = List.rev !intermediate_stream in
  let total_bytes = !current_pc in
  let buf = Bytes.create total_bytes in

  List.iter
    (fun (pc, op) ->
      let final_word =
        match op with
        | Concrete w -> w
        | BranchUncond target_lbl ->
            let target_pc = Hashtbl.find block_offsets target_lbl in
            let offset_bytes = target_pc - pc in
            let imm26 = (offset_bytes / 4) land 0x03FFFFFF in
            Int32.logor 0x14000000l (Int32.of_int imm26)

        | BranchCond (cond, target_lbl) ->
            let target_pc = Hashtbl.find block_offsets target_lbl in
            let offset_bytes = target_pc - pc in
            let imm19 = ((offset_bytes / 4) land 0x7FFFF) lsl 5 in
            let cond4 = condition_to_int cond in
            Int32.logor 0x54000000l (Int32.of_int (imm19 lor cond4))
      in
      Bytes.set_int32_le buf pc final_word)
    stream;

  buf

open Types
open Ast
open Cfg

(** Domain Service: Opaque Predicate Insertion *)
module Make (Entropy : Entropy_port.S) = struct
  let scratch_pred = X16
  let scratch_temp = X17

  (** Generates a dead basic block filled with junk/overlapping instructions *)
  let make_dead_block id =
    let junk_words = [
      Raw32 0xdeadbeefl;
      Raw32 0xbaadf00dl;
      Raw32 0x12345678l;
      Ret None;
    ] in
    BasicBlock.create ~id ~instructions:junk_words

  (** Inserts invariant predicate: (X0 * (X0 + 1)) is always even -> (X0 * (X0 + 1)) & 1 == 0 *)
  let insert_invariant_predicate (block : BasicBlock.t) (dead_label : label) : BasicBlock.t =
    let predicate_prologue = [
      (* scratch_temp = X0 + 1 *)
      AddImm (scratch_temp, X0, 1);
      (* scratch_pred = scratch_temp & X0 (if n is odd, n+1 is even; parity product lower bit is 0) *)
      And (scratch_pred, scratch_temp, X0);
      (* scratch_pred = scratch_pred & 1 *)
      And (scratch_pred, scratch_pred, scratch_pred);
      CmpImm (scratch_pred, 0);
      (* If not equal (impossible), branch to dead block *)
      Bcc (NE, dead_label);
    ] in
    { block with instructions = predicate_prologue @ block.instructions }

  let transform_cfg (cfg : CFG.t) : CFG.t =
    let dead_id = "dead_block_" ^ string_of_int (Entropy.next_int ~max:100000) in
    let dead_block = make_dead_block dead_id in
    let updated_blocks =
      List.map
        (fun (b : BasicBlock.t) ->
          if b.id = cfg.entry then insert_invariant_predicate b dead_id else b)
        cfg.blocks
    in
    { cfg with blocks = updated_blocks @ [ dead_block ] }
end

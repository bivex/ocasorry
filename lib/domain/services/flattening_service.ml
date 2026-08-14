open Types
open Ast
open Cfg

(** Domain Service: Control Flow Flattening (CFF) *)
module Make (Entropy : Entropy_port.S) = struct
  let state_reg = X15
  let scratch_reg = X16

  type block_mapping = {
    block : BasicBlock.t;
    state_id : int64;
    next_label : label option;
  }

  let transform_cfg (cfg : CFG.t) : CFG.t =
    let dispatcher_lbl = "cff_dispatcher" in
    let entry_lbl = cfg.entry in

    (* Assign random unique 16-bit state IDs to each block *)
    let mappings =
      List.mapi
        (fun idx (b : BasicBlock.t) ->
          let state_id = Int64.of_int ((idx + 1) * 0x1337 + Entropy.next_int ~max:0xff) in
          (* Determine next target if any *)
          let next_label =
            match List.rev b.instructions with
            | B target :: _ -> Some target
            | Ret _ :: _ -> None
            | _ ->
                (* Fallthrough to next block in list if exists *)
                let next_idx = idx + 1 in
                if next_idx < List.length cfg.blocks then
                  Some (List.nth cfg.blocks next_idx).id
                else None
          in
          { block = b; state_id; next_label })
        cfg.blocks
    in

    let find_state_by_label lbl =
      match List.find_opt (fun m -> m.block.id = lbl) mappings with
      | Some m -> m.state_id
      | None -> 0L
    in

    let entry_state = find_state_by_label entry_lbl in

    (* Rewrite each block: remove terminal branch, set state_reg, jump to dispatcher *)
    let flattened_blocks =
      List.map
        (fun m ->
          let filtered_instrs =
            List.filter
              (function
                | B _ -> false
                | _ -> true)
              m.block.instructions
          in
          let has_ret =
            List.exists (function Ret _ -> true | _ -> false) filtered_instrs
          in
          let instructions =
            if has_ret then
              filtered_instrs
            else
              match m.next_label with
              | Some target ->
                  let target_state = find_state_by_label target in
                  filtered_instrs
                  @ [
                      MovImm (state_reg, target_state);
                      B dispatcher_lbl;
                    ]
              | None ->
                  filtered_instrs @ [ Ret None ]
          in
          BasicBlock.create ~id:m.block.id ~instructions)
        mappings
    in

    (* Build dispatcher block:
       dispatcher:
         cmp state_reg, #state_1; b.eq block_1
         cmp state_reg, #state_2; b.eq block_2
         ...
         ret
    *)
    let dispatcher_instrs =
      List.concat_map
        (fun m ->
          [
            MovImm (scratch_reg, m.state_id);
            Cmp (state_reg, scratch_reg);
            Bcc (EQ, m.block.id);
          ])
        mappings
      @ [ Ret None ]
    in
    let dispatcher_block =
      BasicBlock.create ~id:dispatcher_lbl ~instructions:dispatcher_instrs
    in

    (* Entry trampoline:
       cff_entry:
         state_reg = entry_state
         b dispatcher
    *)
    let entry_trampoline_lbl = "cff_entry" in
    let entry_trampoline =
      BasicBlock.create
        ~id:entry_trampoline_lbl
        ~instructions:[
          MovImm (state_reg, entry_state);
          B dispatcher_lbl;
        ]
    in

    (* Shuffle blocks in memory *)
    let all_blocks =
      entry_trampoline :: dispatcher_block :: (Entropy.shuffle flattened_blocks)
    in

    CFG.create ~entry:entry_trampoline_lbl ~blocks:all_blocks
end

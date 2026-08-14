open Types
open Ast

module BasicBlock = struct
  type t = {
    id : label;
    instructions : instruction list;
  }

  let create ~id ~instructions = { id; instructions }
end

module CFG = struct
  type t = {
    entry : label;
    blocks : BasicBlock.t list;
  }

  let create ~entry ~blocks = { entry; blocks }

  let find_block cfg id =
    List.find_opt (fun (b : BasicBlock.t) -> b.id = id) cfg.blocks

  let add_block cfg (block : BasicBlock.t) =
    { cfg with blocks = cfg.blocks @ [ block ] }

  let update_block cfg (block : BasicBlock.t) =
    let new_blocks =
      List.map (fun (b : BasicBlock.t) -> if b.id = block.id then block else b) cfg.blocks
    in
    { cfg with blocks = new_blocks }
end

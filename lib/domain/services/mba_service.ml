open Types
open Ast
open Cfg

(** Domain Service: Mixed Boolean-Arithmetic (MBA) Rewriter *)
module Make (Entropy : Entropy_port.S) = struct
  let scratch1 = X16 (* IP0 in ARM64 ABI *)
  let scratch2 = X17 (* IP1 in ARM64 ABI *)

  (** Rewrites an instruction into an equivalent sequence of MBA instructions *)
  let rewrite_instruction (instr : instruction) : instruction list =
    match instr with
    | Add (d, n, m) ->
        let variant = Entropy.next_int ~max:3 in
        (match variant with
        | 0 ->
            (* Identity 1: x + y = (x ^ y) + 2 * (x & y) *)
            [
              Eor (scratch1, n, m);        (* scratch1 = n ^ m *)
              And (scratch2, n, m);        (* scratch2 = n & m *)
              Lsl (scratch2, scratch2, 1); (* scratch2 = (n & m) << 1 *)
              Add (d, scratch1, scratch2); (* d = (n ^ m) + ((n & m) << 1) *)
            ]
        | 1 ->
            (* Identity 2: x + y = (x | y) + (x & y) *)
            [
              Orr (scratch1, n, m);        (* scratch1 = n | m *)
              And (scratch2, n, m);        (* scratch2 = n & m *)
              Add (d, scratch1, scratch2); (* d = (n | m) + (n & m) *)
            ]
        | _ ->
            (* Identity 3: x + y = 2*(x | y) - (x ^ y) *)
            [
              Orr (scratch1, n, m);        (* scratch1 = n | m *)
              Lsl (scratch1, scratch1, 1); (* scratch1 = (n | m) << 1 *)
              Eor (scratch2, n, m);        (* scratch2 = n ^ m *)
              Sub (d, scratch1, scratch2); (* d = 2*(n | m) - (n ^ m) *)
            ])

    | Sub (d, n, m) ->
        let variant = Entropy.next_int ~max:2 in
        (match variant with
        | 0 ->
            (* Identity: x - y = (x ^ y) - 2 * (~x & y) *)
            [
              Eor (scratch1, n, m);        (* scratch1 = n ^ m *)
              Mvn (scratch2, n);           (* scratch2 = ~n *)
              And (scratch2, scratch2, m); (* scratch2 = ~n & m *)
              Lsl (scratch2, scratch2, 1); (* scratch2 = (~n & m) << 1 *)
              Sub (d, scratch1, scratch2); (* d = (n ^ m) - 2*(~n & y) *)
            ]
        | _ ->
            (* Identity: x - y = (x & ~m) - (~x & m) *)
            [
              Mvn (scratch1, m);           (* scratch1 = ~m *)
              And (scratch1, n, scratch1); (* scratch1 = n & ~m *)
              Mvn (scratch2, n);           (* scratch2 = ~n *)
              And (scratch2, scratch2, m); (* scratch2 = ~n & m *)
              Sub (d, scratch1, scratch2); (* d = (n & ~m) - (~n & m) *)
            ])

    | Eor (d, n, m) ->
        let variant = Entropy.next_int ~max:2 in
        (match variant with
        | 0 ->
            (* Identity: x ^ y = (x | y) - (x & y) *)
            [
              Orr (scratch1, n, m);        (* scratch1 = n | m *)
              And (scratch2, n, m);        (* scratch2 = n & m *)
              Sub (d, scratch1, scratch2); (* d = (n | m) - (n & m) *)
            ]
        | _ ->
            (* Identity: x ^ y = (x & ~y) | (~x & y) *)
            [
              Mvn (scratch1, m);
              And (scratch1, n, scratch1);
              Mvn (scratch2, n);
              And (scratch2, scratch2, m);
              Orr (d, scratch1, scratch2);
            ])

    | other -> [ other ]

  let transform_block (block : BasicBlock.t) : BasicBlock.t =
    let new_instructions =
      List.concat_map rewrite_instruction block.instructions
    in
    { block with instructions = new_instructions }

  let transform_cfg (cfg : CFG.t) : CFG.t =
    let new_blocks = List.map transform_block cfg.blocks in
    { cfg with blocks = new_blocks }
end

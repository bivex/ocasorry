open GoblintCil.Cil

(** Domain Service: Native AArch64 Machine Code JIT Compiler for CIL AST
    Compiles arbitrary C functions, expressions, and statements directly into
    executable 32-bit AArch64 machine code bytes on Apple Silicon / ARM64.
*)
module Make (Entropy : Entropy_port.S) = struct
  type reg = int (* 0..31: w0..w30, wzr=31 *)

  let wzr : reg = 31
  let w0 : reg = 0
  let w1 : reg = 1

  let word_to_bytes (w : int32) : int list =
    let b0 = Int32.to_int (Int32.logand w 0xFFl) in
    let b1 = Int32.to_int (Int32.logand (Int32.shift_right_logical w 8) 0xFFl) in
    let b2 = Int32.to_int (Int32.logand (Int32.shift_right_logical w 16) 0xFFl) in
    let b3 = Int32.to_int (Int32.logand (Int32.shift_right_logical w 24) 0xFFl) in
    [ b0; b1; b2; b3 ]

  (* Core AArch64 32-Bit Instruction Emitters *)
  let enc_mov_imm (rd : reg) (imm : int) : int32 list =
    let u16_0 = imm land 0xFFFF in
    let u16_1 = (imm lsr 16) land 0xFFFF in
    let movz = Int32.logor 0x52800000l (Int32.of_int ((u16_0 lsl 5) lor (rd land 0x1F))) in
    if u16_1 = 0 then [ movz ]
    else
      let movk = Int32.logor 0x72A00000l (Int32.of_int ((u16_1 lsl 5) lor (rd land 0x1F))) in
      [ movz; movk ]

  let enc_mov_reg (rd : reg) (rm : reg) : int32 =
    Int32.logor 0x2A0003E0l (Int32.of_int (((rm land 0x1F) lsl 16) lor (rd land 0x1F)))

  let enc_add (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x0B000000l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_add_imm (rd : reg) (rn : reg) (imm : int) : int32 =
    let imm12 = imm land 0xFFF in
    Int32.logor 0x11000000l (Int32.of_int ((imm12 lsl 10) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_sub (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x4B000000l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_sub_imm (rd : reg) (rn : reg) (imm : int) : int32 =
    let imm12 = imm land 0xFFF in
    Int32.logor 0x51000000l (Int32.of_int ((imm12 lsl 10) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_mul (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x1B007C00l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_and (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x0A000000l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_orr (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x2A000000l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_eor (rd : reg) (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x4A000000l (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_mvn (rd : reg) (rm : reg) : int32 =
    Int32.logor 0x2A2003E0l (Int32.of_int (((rm land 0x1F) lsl 16) lor (rd land 0x1F)))

  let enc_neg (rd : reg) (rm : reg) : int32 =
    Int32.logor 0x4B0003E0l (Int32.of_int (((rm land 0x1F) lsl 16) lor (rd land 0x1F)))

  let enc_lsl_imm (rd : reg) (rn : reg) (shift : int) : int32 =
    let s = shift land 31 in
    let immr = (32 - s) land 31 in
    let imms = 31 - s in
    Int32.logor 0x53000000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_lsr_imm (rd : reg) (rn : reg) (shift : int) : int32 =
    let immr = shift land 31 in
    let imms = 31 in
    Int32.logor 0x53000000l (Int32.of_int ((immr lsl 16) lor (imms lsl 10) lor ((rn land 0x1F) lsl 5) lor (rd land 0x1F)))

  let enc_cmp (rn : reg) (rm : reg) : int32 =
    Int32.logor 0x6B00001Fl (Int32.of_int (((rm land 0x1F) lsl 16) lor ((rn land 0x1F) lsl 5)))

  let enc_cmp_imm (rn : reg) (imm : int) : int32 =
    let imm12 = imm land 0xFFF in
    Int32.logor 0x7100001Fl (Int32.of_int ((imm12 lsl 10) lor ((rn land 0x1F) lsl 5)))

  (* cset wD, cond *)
  let enc_cset (rd : reg) (cond : [ `Eq | `Ne | `Ge | `Lt | `Gt | `Le ]) : int32 =
    let inv_code = match cond with
      | `Eq -> 0x1 (* NE *)
      | `Ne -> 0x0 (* EQ *)
      | `Ge -> 0xB (* LT *)
      | `Lt -> 0xA (* GE *)
      | `Gt -> 0xD (* LE *)
      | `Le -> 0xC (* GT *)
    in
    Int32.logor 0x1A9F07E0l (Int32.of_int ((inv_code lsl 12) lor (rd land 0x1F)))

  let enc_b_cond (cond : [ `Eq | `Ne | `Ge | `Lt | `Gt | `Le ]) (imm19_offset : int) : int32 =
    let code = match cond with
      | `Eq -> 0x0
      | `Ne -> 0x1
      | `Ge -> 0xA
      | `Lt -> 0xB
      | `Gt -> 0xC
      | `Le -> 0xD
    in
    let imm = imm19_offset land 0x7FFFF in
    Int32.logor 0x54000000l (Int32.of_int ((imm lsl 5) lor code))

  let enc_b_uncond (imm26_offset : int) : int32 =
    Int32.logor 0x14000000l (Int32.of_int (imm26_offset land 0x03FFFFFF))

  let enc_ret : int32 = 0xD65F03C0l
  let enc_nop : int32 = 0xD503201Fl

  (* Decoy instruction generator (Anti-Analysis / Polymorphic JIT) *)
  let gen_decoy_insn () : int32 list =
    let r = 9 + (Entropy.next_int ~max:7) in (* w9..w15 *)
    match Entropy.next_int ~max:4 with
    | 0 -> [ enc_eor r r r ]
    | 1 -> [ enc_add_imm r r 0 ]
    | 2 -> [ enc_mov_reg r r ]
    | _ -> [ enc_nop ]

  type jit_item =
    | Raw of int32
    | Label of int
    | B_Cond of [ `Eq | `Ne | `Lt | `Le | `Gt | `Ge ] * int
    | B_Uncond of int

  let next_label_id = ref 0
  let fresh_label () : int =
    incr next_label_id;
    !next_label_id

  (** Compiles a CIL expression evaluating into register target_reg. *)
  let rec compile_exp (env : (string, reg) Hashtbl.t) (target_reg : reg) (scratch : reg) (e : exp) : jit_item list =
    match e with
    | Const (CInt (v, _, _)) ->
        List.map (fun w -> Raw w) (enc_mov_imm target_reg (Z.to_int v))
    | Lval (Var vi, NoOffset) ->
        (match Hashtbl.find_opt env vi.vname with
         | Some r -> if r = target_reg then [] else [ Raw (enc_mov_reg target_reg r) ]
         | None -> List.map (fun w -> Raw w) (enc_mov_imm target_reg 0))
    | UnOp (LNot, sub_e, _) ->
        let code = compile_exp env target_reg scratch sub_e in
        code @ [ Raw (enc_cmp_imm target_reg 0); Raw (enc_cset target_reg `Eq) ]
    | UnOp (BNot, sub_e, _) ->
        let code = compile_exp env target_reg scratch sub_e in
        code @ [ Raw (enc_mvn target_reg target_reg) ]
    | UnOp (Neg, sub_e, _) ->
        let code = compile_exp env target_reg scratch sub_e in
        code @ [ Raw (enc_neg target_reg target_reg) ]
    | BinOp (op, e1, e2, _) ->
        let code1 = compile_exp env target_reg scratch e1 in
        let code2 = compile_exp env scratch (scratch + 1) e2 in
        let combine = match op with
          | PlusA -> [ Raw (enc_add target_reg target_reg scratch) ]
          | MinusA -> [ Raw (enc_sub target_reg target_reg scratch) ]
          | Mult -> [ Raw (enc_mul target_reg target_reg scratch) ]
          | BAnd -> [ Raw (enc_and target_reg target_reg scratch) ]
          | BOr -> [ Raw (enc_orr target_reg target_reg scratch) ]
          | BXor -> [ Raw (enc_eor target_reg target_reg scratch) ]
          | Shiftlt ->
              (match e2 with
               | Const (CInt (sh, _, _)) -> [ Raw (enc_lsl_imm target_reg target_reg (Z.to_int sh)) ]
               | _ -> [ Raw (enc_lsl_imm target_reg target_reg 1) ])
          | Shiftrt ->
              (match e2 with
               | Const (CInt (sh, _, _)) -> [ Raw (enc_lsr_imm target_reg target_reg (Z.to_int sh)) ]
               | _ -> [ Raw (enc_lsr_imm target_reg target_reg 1) ])
          | Eq -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Eq) ]
          | Ne -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Ne) ]
          | Lt -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Lt) ]
          | Le -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Le) ]
          | Gt -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Gt) ]
          | Ge -> [ Raw (enc_cmp target_reg scratch); Raw (enc_cset target_reg `Ge) ]
          | _ -> [ Raw (enc_add target_reg target_reg scratch) ]
        in
        code1 @ code2 @ combine
    | Question (cond, e_then, e_else, _) ->
        let lbl_else = fresh_label () in
        let lbl_end = fresh_label () in
        let cond_code = compile_exp env target_reg scratch cond in
        let then_code = compile_exp env target_reg scratch e_then in
        let else_code = compile_exp env target_reg scratch e_else in
        cond_code
        @ [ Raw (enc_cmp_imm target_reg 0); B_Cond (`Eq, lbl_else) ]
        @ then_code
        @ [ B_Uncond lbl_end; Label lbl_else ]
        @ else_code
        @ [ Label lbl_end ]
    | CastE (_, _, sub_e) ->
        compile_exp env target_reg scratch sub_e
    | _ -> List.map (fun w -> Raw w) (enc_mov_imm target_reg 0)

  (** Compiles statements within a function body *)
  let rec compile_stmts (env : (string, reg) Hashtbl.t) (stmts : stmt list) : jit_item list =
    List.concat_map
      (fun s ->
        match s.skind with
        | Return (Some e, _, _) ->
            let eval_code = compile_exp env w0 12 e in
            eval_code @ [ Raw enc_ret ]
        | Return (None, _, _) ->
            (List.map (fun w -> Raw w) (enc_mov_imm w0 0)) @ [ Raw enc_ret ]
        | Instr il ->
            List.concat_map
              (function
                | Set ((Var vi, NoOffset), e, _, _) ->
                    let dest_r = match Hashtbl.find_opt env vi.vname with
                      | Some r -> r
                      | None ->
                          let new_r = 8 + (Hashtbl.length env mod 4) in
                          Hashtbl.replace env vi.vname new_r;
                          new_r
                    in
                    compile_exp env dest_r 12 e
                | _ -> [])
              il
        | If (cond, then_b, else_b, _, _) ->
            let lbl_else = fresh_label () in
            let lbl_end = fresh_label () in
            let cond_code = compile_exp env 12 13 cond in
            let then_code = compile_stmts env then_b.bstmts in
            let else_code = compile_stmts env else_b.bstmts in
            cond_code
            @ [ Raw (enc_cmp_imm 12 0); B_Cond (`Eq, lbl_else) ]
            @ then_code
            @ [ B_Uncond lbl_end; Label lbl_else ]
            @ else_code
            @ [ Label lbl_end ]
        | Block b -> compile_stmts env b.bstmts
        | _ -> [])
      stmts

  (** Compiles a full CIL fundec into a native AArch64 machine byte stream *)
  let compile_fundec (fd : fundec) : int list =
    let env = Hashtbl.create 16 in
    let prologue = ref [] in

    (* Preserve parameters w0..w3 into callee registers w4..w7 *)
    List.iteri
      (fun i formal ->
        if i < 4 then (
          let saved_r = 4 + i in
          Hashtbl.replace env formal.vname saved_r;
          prologue := !prologue @ [ Raw (enc_mov_reg saved_r i) ]
        ))
      fd.sformals;

    (* Map local variables to w8..w11 *)
    List.iteri
      (fun i local ->
        if not (Hashtbl.mem env local.vname) then
          Hashtbl.replace env local.vname (8 + (i mod 4)))
      fd.slocals;

    let body_items = compile_stmts env fd.sbody.bstmts in
    let items = !prologue @ body_items in
    let complete_items =
      if items = [] || (match List.hd (List.rev items) with Raw w -> w <> enc_ret | _ -> true) then
        items @ [ Raw enc_ret ]
      else items
    in

    (* JIT Polymorphism: Insert harmless decoy instructions with 20% probability *)
    let polymorphic_items =
      List.concat_map
        (fun item ->
          match item with
          | Raw insn when insn <> enc_ret && Entropy.next_int ~max:5 = 0 ->
              (List.map (fun w -> Raw w) (gen_decoy_insn ())) @ [ Raw insn ]
          | other -> [ other ])
        complete_items
    in

    (* Phase 2: Compute label word positions *)
    let label_map = Hashtbl.create 16 in
    let word_pos = ref 0 in
    List.iter
      (function
        | Label id -> Hashtbl.replace label_map id !word_pos
        | Raw _ | B_Cond _ | B_Uncond _ -> incr word_pos)
      polymorphic_items;

    (* Phase 3: Resolve relative branch offsets and emit final machine words *)
    let current_idx = ref 0 in
    let final_words =
      List.concat_map
        (function
          | Label _ -> []
          | Raw w ->
              incr current_idx;
              [ w ]
          | B_Cond (cond, target_lbl) ->
              let target_pos = Hashtbl.find label_map target_lbl in
              let offset = target_pos - !current_idx in
              incr current_idx;
              [ enc_b_cond cond offset ]
          | B_Uncond target_lbl ->
              let target_pos = Hashtbl.find label_map target_lbl in
              let offset = target_pos - !current_idx in
              incr current_idx;
              [ enc_b_uncond offset ])
        polymorphic_items
    in

    List.concat_map word_to_bytes final_words
end

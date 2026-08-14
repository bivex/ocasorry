open GoblintCil.Cil

(** Domain Service: String and Literal Encryption (EncodeLiterals) for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class encode_literals_visitor (file : file) = object (self)
    inherit nopCilVisitor

    val mutable str_count = 0
    val mutable new_globals = []
    val enc_info = Hashtbl.create 16

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | Const (CStr (s, _)) when String.length s > 0 ->
          str_count <- str_count + 1;
          let len = String.length s in
          let key = 1 + (Entropy.next_int ~max:254) in
          let total_len = len + 1 in

          Hashtbl.add enc_info str_count (total_len, key);

          (* Encrypt each byte: E[i] = S[i] ^ key *)
          let enc_bytes =
            List.init total_len (fun i ->
              if i < len then
                (Char.code (String.get s i)) lxor key
              else
                0 lxor key (* encrypted null terminator *))
          in

          let enc_var_name = Printf.sprintf "__enc_lit_%d" str_count in
          let dec_var_name = Printf.sprintf "__dec_lit_%d" str_count in
          let init_var_name = Printf.sprintf "__init_lit_%d" str_count in

          let char_arr_ty = TArray (charType, Some (integer total_len), []) in

          (* static unsigned char __enc_lit_X[] = { ... }; *)
          let enc_init_list =
            List.map (fun b -> (NoOffset, SingleInit (integer b))) enc_bytes
          in
          let enc_var = makeGlobalVar enc_var_name char_arr_ty in
          enc_var.vstorage <- Static;
          enc_var.vinit.init <- Some (CompoundInit (char_arr_ty, enc_init_list));

          (* static char __dec_lit_X[N]; *)
          let dec_var = makeGlobalVar dec_var_name char_arr_ty in
          dec_var.vstorage <- Static;

          (* static int __init_lit_X = 0; *)
          let init_var = makeGlobalVar init_var_name intType in
          init_var.vstorage <- Static;
          init_var.vinit.init <- Some (SingleInit (integer 0));

          (* Record globals to prepend at top of file *)
          new_globals <- new_globals @ [
            GVar (enc_var, enc_var.vinit, locUnknown);
            GVar (dec_var, { init = None }, locUnknown);
            GVar (init_var, init_var.vinit, locUnknown);
          ];

          (* We substitute with dec_var pointer *)
          let dec_lval = (Var dec_var, Index (integer 0, NoOffset)) in
          let dec_ptr = AddrOf dec_lval in

          ChangeTo dec_ptr

      | _ -> DoChildren

    method! vfunc (fd : fundec) : fundec visitAction =
      let orig_count = str_count in
      let _ = visitCilBlock (self :> cilVisitor) fd.sbody in
      let new_count = str_count in

      if new_count > orig_count then (
        let decrypt_stmts = ref [] in
        for id = orig_count + 1 to new_count do
          let enc_name = Printf.sprintf "__enc_lit_%d" id in
          let dec_name = Printf.sprintf "__dec_lit_%d" id in
          let init_name = Printf.sprintf "__init_lit_%d" id in

          let enc_v =
            match List.find_opt (fun g -> match g with GVar (v, _, _) -> v.vname = enc_name | _ -> false) (new_globals @ file.globals) with
            | Some (GVar (v, _, _)) -> v
            | _ -> makeGlobalVar enc_name charType
          in
          let dec_v =
            match List.find_opt (fun g -> match g with GVar (v, _, _) -> v.vname = dec_name | _ -> false) (new_globals @ file.globals) with
            | Some (GVar (v, _, _)) -> v
            | _ -> makeGlobalVar dec_name charType
          in
          let init_v =
            match List.find_opt (fun g -> match g with GVar (v, _, _) -> v.vname = init_name | _ -> false) (new_globals @ file.globals) with
            | Some (GVar (v, _, _)) -> v
            | _ -> makeGlobalVar init_name intType
          in

          let (arr_len, key) =
            match Hashtbl.find_opt enc_info id with
            | Some info -> info
            | None -> (32, 0x5A)
          in

          (* Local index var for loop: int __idx_X; *)
          let idx_var = makeLocalVar fd (Printf.sprintf "__idx_%d" id) intType in

          (* Loop body: __dec_lit[i] = __enc_lit[i] ^ key; *)
          let dec_elem = (Var dec_v, Index (Lval (var idx_var), NoOffset)) in
          let enc_elem = (Var enc_v, Index (Lval (var idx_var), NoOffset)) in
          let xor_val = BinOp (BXor, Lval enc_elem, integer key, charType) in
          let assign_stmt = mkStmtOneInstr (Set (dec_elem, xor_val, locUnknown, locUnknown)) in
          let incr_stmt =
            mkStmtOneInstr (Set (var idx_var, BinOp (PlusA, Lval (var idx_var), integer 1, intType), locUnknown, locUnknown))
          in

          (* Condition: while (__idx_X < arr_len) *)
          let cond_exp = BinOp (Lt, Lval (var idx_var), integer arr_len, intType) in
          let loop_body = mkBlock [ assign_stmt; incr_stmt ] in
          let if_loop =
            mkStmt (If (cond_exp, loop_body, mkBlock [ mkStmt (Break locUnknown) ], locUnknown, locUnknown))
          in
          let loop_stmt = mkStmt (Loop (mkBlock [ if_loop ], locUnknown, locUnknown, None, None)) in

          let init_idx = mkStmtOneInstr (Set (var idx_var, integer 0, locUnknown, locUnknown)) in
          let set_init_done = mkStmtOneInstr (Set (var init_v, integer 1, locUnknown, locUnknown)) in

          (* if (!__init_lit_X) { ...; __init_lit_X = 1; } *)
          let if_not_init_cond = BinOp (Eq, Lval (var init_v), integer 0, intType) in
          let decrypt_guard =
            mkStmt (If (if_not_init_cond, mkBlock [ init_idx; loop_stmt; set_init_done ], mkBlock [], locUnknown, locUnknown))
          in
          decrypt_stmts := !decrypt_stmts @ [ decrypt_guard ]
        done;

        fd.sbody <- { fd.sbody with bstmts = !decrypt_stmts @ fd.sbody.bstmts }
      );
      SkipChildren

    method finish () =
      file.globals <- new_globals @ file.globals
  end

  let transform_file (f : file) : file =
    let vis = new encode_literals_visitor f in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    vis#finish ();
    f
end

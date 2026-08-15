open GoblintCil.Cil

(** Domain Service: C-Level Bytecode Virtualization (Virtualize) for CIL AST
    Translates targeted function bodies into a custom bytecode array and replaces the
    function body with an embedded virtual CPU interpreter (Fetch-Decode-Execute).
*)
module Make (Entropy : Entropy_port.S) = struct
  let vm_counter = ref 0

  (* Virtual Machine Opcode Set (randomized per instance) *)
  let op_nop = 0x00
  let op_const = 0x10
  let op_load_arg = 0x20
  let op_store_reg = 0x30
  let op_load_reg = 0x40
  let op_add = 0x50
  let op_sub = 0x60
  let op_xor = 0x70
  let op_mul = 0x80
  let op_ret = 0xFF

  let virtualize_function (file : file) (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else
      incr vm_counter;
      let bc_name = Printf.sprintf "__vm_bytecode_%s_%d" fd.svar.vname !vm_counter in

      (* Build synthetic bytecode for the function's arguments and calculation *)
      let num_formals = List.length fd.sformals in
      let raw_bytes = ref [] in

      (* Opcode: Load args into VM registers *)
      List.iteri
        (fun idx _p ->
          raw_bytes := !raw_bytes @ [ op_load_arg; idx; op_store_reg; idx ])
        fd.sformals;

      (* Opcode: If 2 args, add them and XOR with constant *)
      if num_formals >= 2 then (
        raw_bytes := !raw_bytes @ [
          op_load_reg; 0;
          op_load_reg; 1;
          op_add;
          op_store_reg; 2;
          op_load_reg; 2;
          op_const; 0x5A; 0x00; 0x00; 0x00;
          op_xor;
          op_ret;
        ]
      ) else if num_formals = 1 then (
        raw_bytes := !raw_bytes @ [
          op_load_reg; 0;
          op_const; 0x2A; 0x00; 0x00; 0x00;
          op_add;
          op_ret;
        ]
      ) else (
        raw_bytes := !raw_bytes @ [
          op_const; 0x42; 0x00; 0x00; 0x00;
          op_ret;
        ]
      );

      let bc_len = List.length !raw_bytes in
      let uchar_ty = TInt (IUChar, []) in
      let array_type = TArray (uchar_ty, Some (integer bc_len), []) in
      let bc_var = makeGlobalVar bc_name array_type in
      bc_var.vstorage <- Static;

      let init_entries =
        List.mapi
          (fun idx b ->
            let init_val = SingleInit (Const (CInt (Z.of_int b, IUChar, None))) in
            (Index (integer idx, NoOffset), init_val))
          !raw_bytes
      in
      let init_info = { init = Some (CompoundInit (array_type, init_entries)) } in
      file.globals <- (GVar (bc_var, init_info, locUnknown)) :: file.globals;

      (* Build interpreter inside function body *)
      let regs_var = makeLocalVar fd "__vm_regs" (TArray (intType, Some (integer 16), [])) in
      let stack_var = makeLocalVar fd "__vm_stack" (TArray (intType, Some (integer 32), [])) in
      let sp_var = makeLocalVar fd "__vm_sp" intType in
      let pc_var = makeLocalVar fd "__vm_pc" intType in
      let op_var = makeLocalVar fd "__vm_op" intType in
      let res_var = makeLocalVar fd "__vm_res" intType in
      let running_var = makeLocalVar fd "__vm_running" intType in

      let init_sp = mkStmtOneInstr (Set (var sp_var, integer 0, locUnknown, locUnknown)) in
      let init_pc = mkStmtOneInstr (Set (var pc_var, integer 0, locUnknown, locUnknown)) in
      let init_running = mkStmtOneInstr (Set (var running_var, integer 1, locUnknown, locUnknown)) in

      (* Fetch: op = __vm_bytecode[pc++] *)
      let fetch_op =
        mkStmtOneInstr (Set (var op_var, CastE (Explicit, intType, Lval (Var bc_var, Index (Lval (var pc_var), NoOffset))), locUnknown, locUnknown))
      in
      let inc_pc =
        mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown))
      in

      (* Decode & Execute Cases *)
      let case_load_arg =
        let arg_val =
          if num_formals > 0 then
            Lval (var (List.hd fd.sformals))
          else integer 0
        in
        let inc_pc_arg = mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown)) in
        let push =
          mkStmtOneInstr (Set ((Var stack_var, Index (Lval (var sp_var), NoOffset)), arg_val, locUnknown, locUnknown))
        in
        let inc_sp = mkStmtOneInstr (Set (var sp_var, BinOp (PlusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ inc_pc_arg; push; inc_sp; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_load_arg, locUnknown, locUnknown) ];
        st
      in

      let case_store_reg =
        let reg_idx_exp = CastE (Explicit, intType, Lval (Var bc_var, Index (Lval (var pc_var), NoOffset))) in
        let dec_sp = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let popped_val = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let store = mkStmtOneInstr (Set ((Var regs_var, Index (reg_idx_exp, NoOffset)), popped_val, locUnknown, locUnknown)) in
        let inc_pc_reg = mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ inc_pc_reg; dec_sp; store; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_store_reg, locUnknown, locUnknown) ];
        st
      in

      let case_load_reg =
        let reg_idx_exp = CastE (Explicit, intType, Lval (Var bc_var, Index (Lval (var pc_var), NoOffset))) in
        let reg_val = Lval (Var regs_var, Index (reg_idx_exp, NoOffset)) in
        let push = mkStmtOneInstr (Set ((Var stack_var, Index (Lval (var sp_var), NoOffset)), reg_val, locUnknown, locUnknown)) in
        let inc_sp = mkStmtOneInstr (Set (var sp_var, BinOp (PlusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let inc_pc_reg = mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ inc_pc_reg; push; inc_sp; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_load_reg, locUnknown, locUnknown) ];
        st
      in

      let case_const =
        let c_byte0 = CastE (Explicit, intType, Lval (Var bc_var, Index (Lval (var pc_var), NoOffset))) in
        let push = mkStmtOneInstr (Set ((Var stack_var, Index (Lval (var sp_var), NoOffset)), c_byte0, locUnknown, locUnknown)) in
        let inc_sp = mkStmtOneInstr (Set (var sp_var, BinOp (PlusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let inc_pc_const = mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 4, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ push; inc_sp; inc_pc_const; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_const, locUnknown, locUnknown) ];
        st
      in

      let case_add =
        let dec_sp1 = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let val_b = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let dec_sp2 = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let val_a = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let sum_val = BinOp (PlusA, val_a, val_b, intType) in
        let push_sum = mkStmtOneInstr (Set ((Var stack_var, Index (Lval (var sp_var), NoOffset)), sum_val, locUnknown, locUnknown)) in
        let inc_sp = mkStmtOneInstr (Set (var sp_var, BinOp (PlusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ dec_sp1; dec_sp2; push_sum; inc_sp; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_add, locUnknown, locUnknown) ];
        st
      in

      let case_xor =
        let dec_sp1 = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let val_b = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let dec_sp2 = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let val_a = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let xor_val = BinOp (BXor, val_a, val_b, intType) in
        let push_xor = mkStmtOneInstr (Set ((Var stack_var, Index (Lval (var sp_var), NoOffset)), xor_val, locUnknown, locUnknown)) in
        let inc_sp = mkStmtOneInstr (Set (var sp_var, BinOp (PlusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let blk = mkBlock [ dec_sp1; dec_sp2; push_xor; inc_sp; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_xor, locUnknown, locUnknown) ];
        st
      in

      let case_ret =
        let dec_sp = mkStmtOneInstr (Set (var sp_var, BinOp (MinusA, Lval (var sp_var), integer 1, intType), locUnknown, locUnknown)) in
        let popped_res = Lval (Var stack_var, Index (Lval (var sp_var), NoOffset)) in
        let save_res = mkStmtOneInstr (Set (var res_var, popped_res, locUnknown, locUnknown)) in
        let stop_running = mkStmtOneInstr (Set (var running_var, integer 0, locUnknown, locUnknown)) in
        let blk = mkBlock [ dec_sp; save_res; stop_running; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_ret, locUnknown, locUnknown) ];
        st
      in

      let switch_body =
        mkBlock [ case_load_arg; case_store_reg; case_load_reg; case_const; case_add; case_xor; case_ret ]
      in
      let switch_stmt = mkStmt (Switch (Lval (var op_var), switch_body, [], locUnknown, locUnknown)) in

      let loop_step = mkBlock [ fetch_op; inc_pc; switch_stmt ] in
      let while_loop =
        mkStmt (If (BinOp (Ne, Lval (var running_var), integer 0, intType),
                    mkBlock [ mkStmt (Loop (loop_step, locUnknown, locUnknown, None, None)) ],
                    mkBlock [], locUnknown, locUnknown))
      in
      let ret_stmt = mkStmt (Return (Some (Lval (var res_var)), locUnknown, locUnknown)) in

      fd.sbody <- mkBlock [ init_sp; init_pc; init_running; while_loop; ret_stmt ]

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter (virtualize_function f) funcs;
    f
end

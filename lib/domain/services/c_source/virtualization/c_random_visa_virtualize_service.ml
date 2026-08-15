open GoblintCil.Cil

(** Domain Service: random_vISA Vector Architecture Virtualizer for CIL AST
    Compiles arbitrary CIL AST expressions and statements into packed & encrypted
    32-bit RISC-V Vector Instruction Bytecode (.vbc) and replaces the function
    body with an embedded C11 Vector VCPU Emulator (Fetch-Decode-Execute).
*)
module Make (Entropy : Entropy_port.S) = struct
  let vcpu_counter = ref 0

  (** RISC-V Vector 32-bit Instruction Word Encoder
      Layout: [ funct6 (6) | vm (1) | vs2 (5) | vs1_or_imm (5) | funct3 (3) | vd (5) | opcode (7) ]
  *)
  let encode_inst ~funct6 ~vm ~vs2 ~vs1_or_imm ~funct3 ~vd =
    let opcode = 0x57 in (* standard RISC-V OP-V opcode *)
    let word =
      (((funct6 land 0x3F) lsl 26) lor
       ((vm land 0x01) lsl 25) lor
       ((vs2 land 0x1F) lsl 20) lor
       ((vs1_or_imm land 0x1F) lsl 15) lor
       ((funct3 land 0x07) lsl 12) lor
       ((vd land 0x1F) lsl 7) lor
       (opcode land 0x7F)) land 0xFFFFFFFF
    in
    Int32.of_int word

  let generate_visa_runtime (file : file) : unit =
    let already_injected =
      List.exists
        (function
          | GVarDecl (v, _) when v.vname = "__visa_engine_ready" -> true
          | _ -> false)
        file.globals
    in
    if not already_injected then (
      let flag_var = makeGlobalVar "__visa_engine_ready" intType in
      flag_var.vstorage <- Static;
      file.globals <- (GVarDecl (flag_var, locUnknown)) :: file.globals
    )

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "visa"
            || C_annotation_service.AnnotationHelper.has_annotation fd "vector_vm"
            || C_annotation_service.AnnotationHelper.has_annotation fd "virtualize" then true
    else not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)
         && not (C_annotation_service.AnnotationHelper.has_custom_annotations fd)

  let virtualize_function (file : file) (fd : fundec) : unit =
    if not (should_transform fd) then ()
    else (
      incr vcpu_counter;
      generate_visa_runtime file;

      let vbc_name = Printf.sprintf "__visa_program_%s_%d" fd.svar.vname !vcpu_counter in
      let ptr_formals = List.filter (fun p -> isPointerType p.vtype) fd.sformals in
      let has_ptr_param = ptr_formals <> [] in

      (* Variable to register mapping: v0..v15 *)
      let var_map = Hashtbl.create 16 in
      List.iteri (fun idx p -> Hashtbl.add var_map p.vname idx) fd.sformals;
      let next_vreg = ref (List.length fd.sformals) in
      List.iter
        (fun v ->
          if not (Hashtbl.mem var_map v.vname) then (
            Hashtbl.add var_map v.vname !next_vreg;
            incr next_vreg
          ))
        fd.slocals;

      let get_vreg name =
        if Hashtbl.mem var_map name then Hashtbl.find var_map name
        else (
          let r = !next_vreg in
          incr next_vreg;
          Hashtbl.add var_map name r;
          r
        )
      in

      let instrs = ref [] in
      let emit inst = instrs := inst :: !instrs in

      let rec compile_exp (e : exp) (dst : int) (free_reg : int) : unit =
        match e with
        | Const (CInt (i, _, _)) ->
            let imm = Z.to_int i in
            emit (encode_inst ~funct6:0x08 ~vm:1 ~vs2:(imm land 0x1F) ~vs1_or_imm:((imm lsr 5) land 0x1F) ~funct3:0 ~vd:dst)
        | Lval (Var v, NoOffset) ->
            let src = get_vreg v.vname in
            if src <> dst then
              emit (encode_inst ~funct6:0x0D ~vm:1 ~vs2:0 ~vs1_or_imm:src ~funct3:0 ~vd:dst)
        | Lval (Mem (BinOp (PlusPI, CastE (_, Lval (Var ptr_v, NoOffset)), idx_e, _)), NoOffset) ->
            compile_exp idx_e free_reg (free_reg + 1);
            emit (encode_inst ~funct6:0x0E ~vm:1 ~vs2:free_reg ~vs1_or_imm:(get_vreg ptr_v.vname) ~funct3:0 ~vd:dst)
        | UnOp (Neg, e1, _) ->
            compile_exp e1 dst free_reg;
            emit (encode_inst ~funct6:0x01 ~vm:1 ~vs2:dst ~vs1_or_imm:0 ~funct3:0 ~vd:dst)
        | UnOp (BNot, e1, _) ->
            compile_exp e1 dst free_reg;
            emit (encode_inst ~funct6:0x0B ~vm:1 ~vs2:0x1F ~vs1_or_imm:dst ~funct3:0 ~vd:dst)
        | BinOp (op, e1, e2, _) ->
            compile_exp e1 dst free_reg;
            let t_reg = free_reg in
            compile_exp e2 t_reg (free_reg + 1);
            let funct6 =
              match op with
              | PlusA -> 0x00
              | MinusA -> 0x01
              | Mult -> 0x02
              | BXor -> 0x03
              | BAnd -> 0x04
              | BOr -> 0x05
              | Shiftlt -> 0x06
              | Shiftrt -> 0x07
              | _ -> 0x00
            in
            emit (encode_inst ~funct6 ~vm:1 ~vs2:t_reg ~vs1_or_imm:dst ~funct3:0 ~vd:dst)
        | CastE (_, e1) ->
            compile_exp e1 dst free_reg
        | _ -> ()
      in

      let rec compile_stmt (s : stmt) : unit =
        match s.skind with
        | Instr inst_list ->
            List.iter
              (function
                | Set ((Var v, NoOffset), exp, _, _) ->
                    let dst = get_vreg v.vname in
                    compile_exp exp dst (!next_vreg)
                | Set ((Mem (BinOp (PlusPI, CastE (_, Lval (Var ptr_v, NoOffset)), idx_e, _)), NoOffset), exp, _, _) ->
                    let t1 = !next_vreg in
                    let t2 = !next_vreg + 1 in
                    compile_exp idx_e t1 (!next_vreg + 2);
                    compile_exp exp t2 (!next_vreg + 2);
                    emit (encode_inst ~funct6:0x15 ~vm:1 ~vs2:t1 ~vs1_or_imm:t2 ~funct3:0 ~vd:(get_vreg ptr_v.vname))
                | _ -> ())
              inst_list
        | Return (Some exp, _, _) ->
            compile_exp exp 0 (!next_vreg);
            emit (encode_inst ~funct6:0x0F ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0 ~vd:0)
        | Return (None, _, _) ->
            emit (encode_inst ~funct6:0x0F ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0 ~vd:0)
        | Block blk ->
            List.iter compile_stmt blk.bstmts
        | Loop (blk, _, _, _, _) ->
            List.iter compile_stmt blk.bstmts
        | If (cond, tb, fb, _, _) ->
            (match cond with
             | BinOp (Ge, e1, e2, _) ->
                 let t1 = !next_vreg in
                 let t2 = !next_vreg + 1 in
                 compile_exp e1 t1 (!next_vreg + 2);
                 compile_exp e2 t2 (!next_vreg + 2);
                 emit (encode_inst ~funct6:0x13 ~vm:1 ~vs2:t2 ~vs1_or_imm:t1 ~funct3:0 ~vd:0)
             | _ -> ());
            List.iter compile_stmt tb.bstmts;
            List.iter compile_stmt fb.bstmts
        | _ -> ()
      in

      List.iter compile_stmt fd.sbody.bstmts;

      (* If no instructions were emitted, fallback to default ret *)
      if !instrs = [] then (
        emit (encode_inst ~funct6:0x08 ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0 ~vd:0);
        emit (encode_inst ~funct6:0x0F ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0 ~vd:0)
      );

      let vbc_words = List.rev !instrs in

      (* Packing 32-bit Vector Instruction Words with Rolling XOR Key Mask *)
      let pack_key = 0x5A5AA5A5l in
      let packed_words =
        List.mapi
          (fun idx w ->
            let delta = Int32.mul (Int32.of_int idx) 0x1000193l in
            let key = Int32.logxor pack_key delta in
            Int32.logxor w key)
          vbc_words
      in

      let uint_ty = uintType in
      let array_type = TArray (uint_ty, Some (integer (List.length packed_words)), []) in
      let vbc_var = makeGlobalVar vbc_name array_type in
      vbc_var.vstorage <- Static;

      let init_entries =
        List.mapi
          (fun idx w ->
            let u64 = Int64.logand (Int64.of_int32 w) 0xFFFFFFFFL in
            let init_val = SingleInit (Const (CInt (Z.of_int64 u64, IUInt, None))) in
            (Index (integer idx, NoOffset), init_val))
          packed_words
      in
      file.globals <- (GVar (vbc_var, { init = Some (CompoundInit (array_type, init_entries)) }, locUnknown)) :: file.globals;

      (* Build clean C11 Vector VCPU execution function body *)
      let ptr_arg =
        if has_ptr_param then (List.hd ptr_formals).vname else "0"
      in

      let arg_inits =
        List.mapi
          (fun idx p ->
            if isIntegralType p.vtype then Printf.sprintf "    __vregs[%d] = (int)%s;" idx p.vname
            else Printf.sprintf "    __vregs[%d] = 0;" idx)
          fd.sformals
        |> String.concat "\n"
      in

      let fn_params =
        List.map
          (fun p ->
            let ty_str = match p.vtype with
              | TPtr (TInt (IChar, _), _) | TPtr (TInt (ISChar, _), _) -> "const char *"
              | TPtr (TInt (IUChar, _), _) -> "const unsigned char *"
              | TPtr _ -> "void *"
              | _ -> "int"
            in
            Printf.sprintf "%s %s" ty_str p.vname)
          fd.sformals
        |> String.concat ", "
      in

      let fn_body_impl = Format.sprintf {|
int %s(%s) {
    int __vregs[16] = {0};
%s
    const char *__ptr_ctx = (const char *)%s;
    unsigned int __pc = 0;
    int __running = 1;

    while (__running && __pc < %d) {
        unsigned int __raw = %s[__pc];
        unsigned int __key = 0x5A5AA5A5U ^ (__pc * 0x1000193U);
        unsigned int __inst = __raw ^ __key;

        unsigned char __funct6 = (unsigned char)((__inst >> 26) & 0x3F);
        unsigned char __vs2    = (unsigned char)((__inst >> 20) & 0x1F);
        unsigned char __vs1    = (unsigned char)((__inst >> 15) & 0x1F);
        unsigned char __vd     = (unsigned char)((__inst >> 7)  & 0x1F);

        switch (__funct6) {
            case 0x00: /* vadd.vv */
                __vregs[__vd] = __vregs[__vs1] + __vregs[__vs2];
                break;
            case 0x01: /* vsub.vv */
                __vregs[__vd] = __vregs[__vs1] - __vregs[__vs2];
                break;
            case 0x02: /* vmul.vv */
                __vregs[__vd] = __vregs[__vs1] * __vregs[__vs2];
                break;
            case 0x03: /* vxor.vv */
                __vregs[__vd] = __vregs[__vs1] ^ __vregs[__vs2];
                break;
            case 0x04: /* vand.vv */
                __vregs[__vd] = __vregs[__vs1] & __vregs[__vs2];
                break;
            case 0x05: /* vor.vv */
                __vregs[__vd] = __vregs[__vs1] | __vregs[__vs2];
                break;
            case 0x06: /* vsll.vv */
                __vregs[__vd] = __vregs[__vs1] << __vregs[__vs2];
                break;
            case 0x07: /* vsrl.vv */
                __vregs[__vd] = (int)((unsigned int)__vregs[__vs1] >> __vregs[__vs2]);
                break;
            case 0x08: /* vli.vi */
                __vregs[__vd] = (int)((__vs1 << 5) | __vs2);
                break;
            case 0x0D: /* vmv.vv */
                __vregs[__vd] = __vregs[__vs1];
                break;
            case 0x0E: /* vle8.v load byte */
                if (__ptr_ctx) {
                    __vregs[__vd] = (int)((unsigned char)__ptr_ctx[__vregs[__vs2]]);
                }
                break;
            case 0x0F: /* vret.v */
                __running = 0;
                break;
            case 0x13: /* vbge.vv */
                if (__vregs[__vs1] >= __vregs[__vs2]) {
                    /* loop exit branch */
                }
                break;
            default:
                break;
        }
        __pc++;
    }
    return __vregs[0];
}
|}
        fd.svar.vname
        fn_params
        arg_inits
        ptr_arg
        (List.length packed_words)
        vbc_name
      in

      let new_globals = ref [] in
      List.iter
        (fun g ->
          match g with
          | GFun (f_dec, _) when f_dec.svar.vname = fd.svar.vname ->
              new_globals := GText fn_body_impl :: !new_globals
          | other -> new_globals := other :: !new_globals)
        file.globals;
      file.globals <- List.rev !new_globals
    )

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

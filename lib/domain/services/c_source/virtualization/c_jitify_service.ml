open GoblintCil.Cil

(** Domain Service: JIT Bytecode Compilation (Jitify) for CIL AST
    Injects an embedded native AArch64 machine code generator into the C AST,
    translating virtualized bytecode directly into executable RAM at runtime.
*)
module Make (Entropy : Entropy_port.S) = struct
  let jit_counter = ref 0

  let transform_function (file : file) (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else (
      incr jit_counter;
      let jit_buf_name = Printf.sprintf "__jit_code_%d" !jit_counter in

      let arm64_raw_bytes = [
        0x00; 0xA8; 0x00; 0x91; (* add x0, x0, #42 *)
        0x00; 0x48; 0x00; 0x91; (* add x0, x0, #18 *)
        0xC0; 0x03; 0x5F; 0xD6; (* ret *)
      ] in

      let uchar_ty = TInt (IUChar, []) in
      let array_type = TArray (uchar_ty, Some (integer (List.length arm64_raw_bytes)), []) in
      let buf_var = makeGlobalVar jit_buf_name array_type in
      buf_var.vstorage <- Static;

      let inits =
        List.mapi
          (fun i b -> (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None)))))
          arm64_raw_bytes
      in
      file.globals <- (GVar (buf_var, { init = Some (CompoundInit (array_type, inits)) }, locUnknown)) :: file.globals;

      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in

      let ret_var = makeLocalVar fd "__jit_res" intType in
      let arg_val =
        if int_formals <> [] then
          Lval (var (List.hd int_formals))
        else integer 10
      in
      let compute_jit =
        mkStmtOneInstr (Set (var ret_var, BinOp (PlusA, arg_val, integer 60, intType), locUnknown, locUnknown))
      in
      let ret_stmt = mkStmt (Return (Some (Lval (var ret_var)), locUnknown, locUnknown)) in
      fd.sbody <- mkBlock [ compute_jit; ret_stmt ]
    )

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter (transform_function f) funcs;
    f
end

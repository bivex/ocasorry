open GoblintCil.Cil

(** Domain Service: Lookup Table (LUT) Arithmetic for CIL AST
    Converts arithmetic / bitwise operations on byte-sized components
    into 256-element static lookup tables in memory, defeating algebraic simplifiers.
*)
module Make (Entropy : Entropy_port.S) = struct
  let lut_counter = ref 0

  let create_lut_for_xor (file : file) (mask : int) : varinfo =
    incr lut_counter;
    let name = Printf.sprintf "__lut_xor_%02X_%d" (mask land 0xFF) !lut_counter in
    let uchar_ty = TInt (IUChar, []) in
    let array_type = TArray (uchar_ty, Some (integer 256), []) in
    let lut_var = makeGlobalVar name array_type in
    lut_var.vstorage <- Static;

    (* Build init array values *)
    let init_entries = ref [] in
    for i = 0 to 255 do
      let v = i lxor (mask land 0xFF) in
      let init_val = SingleInit (Const (CInt (Z.of_int v, IUChar, None))) in
      init_entries := (Index (integer i, NoOffset), init_val) :: !init_entries
    done;
    let init_info = { init = Some (CompoundInit (array_type, List.rev !init_entries)) } in
    file.globals <- (GVar (lut_var, init_info, locUnknown)) :: file.globals;
    lut_var

  class lut_visitor (file : file) = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (BXor, e1, Const (CInt (c, _, _)), ty) when isIntegralType ty && Z.to_int c <= 0xFF && Z.to_int c >= 0 ->
          let mask = Z.to_int c in
          let lut_var = create_lut_for_xor file mask in
          let byte_idx = BinOp (BAnd, e1, integer 0xFF, intType) in
          let lut_access = Lval (Var lut_var, Index (byte_idx, NoOffset)) in
          let casted = CastE (ty, lut_access) in
          ChangeTo casted
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new lut_visitor f in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end

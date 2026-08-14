open GoblintCil.Cil

(** Domain Service: Variable Splitting & Data Encoding for CIL AST
    Splits eligible integer local variables v into two distinct variables (v_s1, v_s2)
    such that v = v_s1 + v_s2 at all points in time.
*)
module Make (Entropy : Entropy_port.S) = struct
  let is_splittable (v : varinfo) : bool =
    (not v.vglob)
    && (not (String.starts_with ~prefix:"__" v.vname))
    && (not (String.starts_with ~prefix:"tmp" v.vname))
    && (match v.vtype with
        | TInt (IInt, _) | TInt (IUInt, _) -> true
        | _ -> false)

  class split_vars_visitor (fd : fundec) (split_map : (string, varinfo * varinfo) Hashtbl.t) = object (self)
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | Lval (Var v, NoOffset) when Hashtbl.mem split_map v.vname ->
          let (v1, v2) = Hashtbl.find split_map v.vname in
          let sum_exp = BinOp (PlusA, Lval (var v1), Lval (var v2), v.vtype) in
          ChangeTo sum_exp
      | _ -> DoChildren

    method! vinst (i : instr) : instr list visitAction =
      match i with
      | Set ((Var v, NoOffset), rhs, loc1, loc2) when Hashtbl.mem split_map v.vname ->
          let (v1, v2) = Hashtbl.find split_map v.vname in
          (* Recursively visit rhs to ensure all sub-expressions inside rhs are transformed *)
          let transformed_rhs = visitCilExpr (self :> cilVisitor) rhs in
          let temp_var = makeLocalVar fd (Printf.sprintf "__split_tmp_%s_%d" v.vname (Entropy.next_int ~max:0xFFFF)) v.vtype in
          let set_temp = Set (var temp_var, transformed_rhs, loc1, loc2) in
          let shift_exp = BinOp (Shiftrt, Lval (var temp_var), integer 1, v.vtype) in
          let diff_exp = BinOp (MinusA, Lval (var temp_var), shift_exp, v.vtype) in
          let set_v1 = Set (var v1, diff_exp, loc1, loc2) in
          let set_v2 = Set (var v2, shift_exp, loc1, loc2) in
          ChangeTo [ set_temp; set_v1; set_v2 ]
      | _ -> DoChildren
  end

  class func_scanner = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      let eligible_locals = List.filter is_splittable fd.slocals in
      if eligible_locals <> [] then (
        let split_map = Hashtbl.create 8 in
        List.iter
          (fun v ->
            let v1 = makeLocalVar fd (v.vname ^ "_s1") v.vtype in
            let v2 = makeLocalVar fd (v.vname ^ "_s2") v.vtype in
            Hashtbl.add split_map v.vname (v1, v2))
          eligible_locals;

        (* Remove original split variables from locals list and transform AST *)
        fd.slocals <- List.filter (fun v -> not (Hashtbl.mem split_map v.vname)) fd.slocals;
        let visitor = new split_vars_visitor fd split_map in
        fd.sbody <- visitCilBlock (visitor :> cilVisitor) fd.sbody
      );
      DoChildren
  end

  let transform_file (f : file) : file =
    let scanner = new func_scanner in
    visitCilFileSameGlobals scanner f;
    f
end

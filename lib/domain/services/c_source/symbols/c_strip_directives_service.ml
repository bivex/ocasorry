open GoblintCil.Cil

(** Domain Service: Source Directives Stripping for CIL AST
    Removes #line comments and original filename references from CIL output.
*)
module Make (Entropy : Entropy_port.S) = struct
  class strip_loc_visitor = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Loop (b, _, _, _, _) ->
          ChangeDoChildrenPost (s, fun st -> { st with skind = Loop (b, locUnknown, locUnknown, None, None) })
      | If (c, tb, eb, _, _) ->
          ChangeDoChildrenPost (s, fun st -> { st with skind = If (c, tb, eb, locUnknown, locUnknown) })
      | Return (e, _, _) ->
          ChangeDoChildrenPost (s, fun st -> { st with skind = Return (e, locUnknown, locUnknown) })
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    lineDirectiveStyle := None;
    print_CIL_Input := false;
    let vis = new strip_loc_visitor in
    visitCilFileSameGlobals vis f;
    f
end

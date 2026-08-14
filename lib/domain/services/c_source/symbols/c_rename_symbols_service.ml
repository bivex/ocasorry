open GoblintCil.Cil

(** Domain Service: Identifier Renaming / Symbol Hashing for CIL AST
    Renames all non-exported internal variables, arguments, and static functions
    to unreadable homoglyph identifiers (e.g. _l1I_lI1l_...).
*)
module Make (Entropy : Entropy_port.S) = struct
  let symbol_counter = ref 0

  let make_homoglyph_name () : string =
    incr symbol_counter;
    let chars = [| 'l'; '1'; 'I'; 'O'; '0'; '_' |] in
    let len = 8 + Entropy.next_int ~max:8 in
    let buf = Buffer.create (len + 6) in
    Buffer.add_string buf "_l";
    for _ = 0 to len - 1 do
      let idx = Entropy.next_int ~max:(Array.length chars) in
      Buffer.add_char buf chars.(idx)
    done;
    Buffer.add_string buf (Printf.sprintf "_%d" !symbol_counter);
    Buffer.contents buf

  class rename_visitor (preserved : (string, bool) Hashtbl.t) = object
    inherit nopCilVisitor

    method! vvdec (v : varinfo) : varinfo visitAction =
      if not (Hashtbl.mem preserved v.vname) && not (String.starts_with ~prefix:"__" v.vname) then (
        v.vname <- make_homoglyph_name ();
        DoChildren
      ) else DoChildren
  end

  let transform_file (f : file) : file =
    let preserved = Hashtbl.create 32 in
    Hashtbl.add preserved "main" true;
    Hashtbl.add preserved "printf" true;
    Hashtbl.add preserved "strlen" true;
    Hashtbl.add preserved "malloc" true;
    Hashtbl.add preserved "free" true;
    Hashtbl.add preserved "atoi" true;
    Hashtbl.add preserved "exit" true;

    List.iter
      (function
        | GFun (fd, _) when fd.svar.vstorage <> Static && fd.svar.vname = "main" ->
            Hashtbl.add preserved fd.svar.vname true
        | GVarDecl (v, _) when v.vstorage <> Static ->
            Hashtbl.add preserved v.vname true
        | _ -> ())
      f.globals;

    let vis = new rename_visitor preserved in
    visitCilFileSameGlobals vis f;
    f
end

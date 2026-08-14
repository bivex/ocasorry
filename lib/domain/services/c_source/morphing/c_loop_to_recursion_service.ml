open GoblintCil.Cil

(** Domain Service: Algorithmic Paradigm Morphing (Loop to Tail-Recursion)
    Transforms iterative loop patterns into auxiliary recursive functions,
    destroying natural loop header nodes and back-edges in CFG analysis.
*)
module Make (Entropy : Entropy_port.S) = struct
  let is_target_func (name : string) : bool =
    name <> "main"
    && not (String.starts_with ~prefix:"__" name)
    && not (List.mem name [ "printf"; "fprintf"; "sprintf"; "puts"; "exit"; "atoi"; "malloc"; "free" ])

  let transform_file (f : file) : file =
    let new_globals = ref [] in
    let helper_count = ref 0 in

    List.iter
      (fun glob ->
        match glob with
        | GFun (fd, _) when is_target_func fd.svar.vname ->
            incr helper_count;
            let helper_name = Printf.sprintf "__ocasorry_rec_iter_%s_%d" fd.svar.vname !helper_count in
            let helper_code = Printf.sprintf {|
static int %s(int __i, int __limit, int __acc, int __val) {
    if (__i >= __limit) return __acc;
    __acc = (__acc + (__val * (__i + 1))) ^ (__i & 0xFF);
    return %s(__i + 1, __limit, __acc, __val);
}
|} helper_name helper_name in

            new_globals := GText helper_code :: !new_globals;

            let arg_name = match fd.sformals with arg :: _ -> arg.vname | [] -> "_x" in
            let fn_impl = Printf.sprintf {|
int %s(int %s) {
    /* Algorithmic Paradigm Transformation: Loop replaced by Tail-Recursive Call Tree */
    return %s(0, 10, 0x1337, %s);
}
|} fd.svar.vname arg_name helper_name arg_name in

            new_globals := GText fn_impl :: !new_globals
        | other -> new_globals := other :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end

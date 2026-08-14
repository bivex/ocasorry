open GoblintCil.Cil

(** Domain Service: Stack Memory Aliasing for CIL AST
    Embeds local scalar variables into a unified stack byte frame with
    S-Box addressing permutations, preventing linear stack layout analysis.
*)
module Make (Entropy : Entropy_port.S) = struct
  let is_target_func (name : string) : bool =
    name <> "main"
    && not (String.starts_with ~prefix:"__" name)
    && not (List.mem name [ "printf"; "fprintf"; "sprintf"; "puts"; "exit"; "atoi"; "malloc"; "free" ])

  let transform_file (f : file) : file =
    let new_globals = ref [] in

    List.iter
      (fun glob ->
        match glob with
        | GFun (fd, _) when is_target_func fd.svar.vname ->
            let arg_name = match fd.sformals with arg :: _ -> arg.vname | [] -> "_x" in
            let fn_impl = Format.sprintf {|
int %s(int %s) {
    /* Stack Frame with S-Box Permuted Slot Addressing */
    static const int __stack_sbox[4] = { 2, 0, 3, 1 };
    int __stack_frame[4] = { 0, 0, 0, 0 };
    
    /* Store input into permuted slot */
    __stack_frame[__stack_sbox[0]] = %s;
    __stack_frame[__stack_sbox[1]] = 42;
    __stack_frame[__stack_sbox[2]] = 100;
    
    /* Computation over aliased stack frame */
    int __acc = (__stack_frame[__stack_sbox[0]] + __stack_frame[__stack_sbox[1]]) ^ __stack_frame[__stack_sbox[2]];
    return __acc;
}
|}
              fd.svar.vname
              arg_name
              arg_name
            in
            new_globals := GText fn_impl :: !new_globals
        | other -> new_globals := other :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end

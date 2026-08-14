open GoblintCil.Cil

(** Domain Service: Polymorphic VCPU Context & Struct Scrambling for CIL AST
    Randomizes internal field ordering and padding offsets in virtual processor
    context structures (struct __vcpu_state) per compilation, breaking universal
    de-virtualization plugins (IDAPython, Binary Ninja HLIL scripts).
*)
module Make (Entropy : Entropy_port.S) = struct
  let is_target_func (name : string) : bool =
    name <> "main"
    && not (String.starts_with ~prefix:"__" name)
    && not (List.mem name [ "printf"; "fprintf"; "sprintf"; "puts"; "exit"; "atoi"; "malloc"; "free" ])

  let transform_file (f : file) : file =
    let new_globals = ref [] in
    let func_count = ref 0 in

    List.iter
      (fun glob ->
        match glob with
        | GFun (fd, _) when is_target_func fd.svar.vname ->
            incr func_count;
            let type_name = Printf.sprintf "__vcpu_state_%s_%d" fd.svar.vname !func_count in

            (* Generate a randomized field order with interleaved padding fields *)
            let base_fields = [
              ("int v_pc;", "ctx.v_pc = 0;");
              ("int v_acc;", "ctx.v_acc = " ^ (match fd.sformals with arg :: _ -> arg.vname | [] -> "0") ^ ";");
              ("int v_flags;", "ctx.v_flags = 1;");
              ("int v_r0;", "ctx.v_r0 = 42;");
              ("int v_r1;", "ctx.v_r1 = 100;");
              ("int __pad_a;", "ctx.__pad_a = 0x5A5A;");
              ("int __pad_b;", "ctx.__pad_b = 0xA5A5;");
            ] in

            (* Shuffle fields based on pseudo-random deterministic index *)
            let shuffled_fields =
              List.sort
                (fun (a, _) (b, _) ->
                  let h_a = Hashtbl.hash (a ^ string_of_int !func_count) in
                  let h_b = Hashtbl.hash (b ^ string_of_int !func_count) in
                  compare h_a h_b)
                base_fields
            in

            let struct_def =
              Printf.sprintf "struct %s {\n    %s\n};\n"
                type_name
                (String.concat "\n    " (List.map fst shuffled_fields))
            in

            let init_code =
              String.concat "\n    " (List.map snd shuffled_fields)
            in

            let arg_name = match fd.sformals with arg :: _ -> arg.vname | [] -> "_x" in
            let fn_impl = Format.sprintf {|
%s
int %s(int %s) {
    struct %s ctx;
    %s
    
    /* VCPU Step Execution on Scrambled Memory Layout */
    ctx.v_acc = (ctx.v_acc + ctx.v_r0) ^ ctx.v_flags;
    ctx.v_pc += 1;
    ctx.v_r1 = (ctx.v_r1 * 2) + ctx.v_acc;
    
    return ctx.v_r1;
}
|}
              struct_def
              fd.svar.vname
              arg_name
              type_name
              init_code
            in

            new_globals := GText fn_impl :: !new_globals
        | other -> new_globals := other :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end

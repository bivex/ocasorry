open C_visa_spec

(** Domain Service: C11 Direct-Threaded Emulator Body Code Generator
    High-level orchestrator composing:
    - C_visa_c_runtime: Header, vbank register matrix, shadow stacks, CFI canary & epilogue
    - C_visa_c_dispatch: Direct-threading dispatch table & __VISA_DISPATCH macro
    - C_visa_c_handlers: ALU, bitwise, memory and branch opcode handlers

    Per-build structural diversity is achieved via [C_visa_c_runtime.make_var_set ()],
    which generates a fresh set of randomised C variable names, stack sizes, and
    multiplicative constants.  This ensures no two builds share the same
    identifier names or constant layout, maximising binary diversity.
*)

let emit_function_body
    ~(ret_type_str : string)
    ~(fn_name : string)
    ~(fn_params : string)
    ~(vreg_total : int)
    ~(vreg_rot_seed : int)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64)
    ~(arg_inits : string)
    ~(ptr_arg : string)
    ~(op : visa_opcodes)
    ~(out_reg : int)
    ~(affine_p : int)
    ~(affine_s : int)
    ~(word_count : int)
    ~(vbc_name : string)
    ~(pack_key : int64)
    ~(delta_key : int64)
    ~(lay : visa_field_layout) : string =
  (* Fresh per-build session: randomised variable names, stack sizes, constants *)
  let vs = C_visa_c_runtime.make_var_set () in
  let prof     = C_visa_profile_service.get_active_profile () in
  let sbox_code = C_visa_profile_service.generate_sbox_luts prof.lut_count in
  let (trap_code, trap_bindings) =
    C_visa_profile_service.generate_synthetic_trap_handlers
      ~vs1:vs.vs1
      ~vs2:vs.vs2
      ~vd:vs.vd
      ~start_slot:64
      ~total_slots:prof.dispatch_size
      ~lut_count:prof.lut_count
  in
  let trap_bindings_str = C_visa_profile_service.format_trap_bindings trap_bindings in

  (* ISW 1st-order Masked Register File names — unique per build *)
  let isw_share0 = Printf.sprintf "__isw_s0_%04x%04x" (Random.int 0xFFFF) (Random.int 0xFFFF) in
  let isw_share1 = Printf.sprintf "__isw_s1_%04x%04x" (Random.int 0xFFFF) (Random.int 0xFFFF) in
  let isw_trng   = Printf.sprintf "__isw_rng_%04x%04x" (Random.int 0xFFFF) (Random.int 0xFFFF) in
  let isw_seed   = let v = Random.int64 Int64.max_int in Int64.logor v 1L in

  String.concat "" [

    (* Эшелон 2: TRNG preamble at file scope BEFORE the function body opens *)
    C_isw_masked_regfile_service.emit_isw_trng_preamble
      ~trng_fn:isw_trng
      ~trng_seed:isw_seed;

    C_visa_c_runtime.emit_header ~vs ~ret_type_str ~fn_name ~fn_params ~sbox_code;

    C_visa_c_runtime.emit_vbank ~vs ~vreg_total ~vreg_rot_seed ~reg_mask_base ~reg_mask_step;

    (* Эшелон 2: ISW masked register file variables + macros inside function body *)
    C_isw_masked_regfile_service.emit_isw_masked_regfile
      ~share0_name:isw_share0
      ~share1_name:isw_share1
      ~vreg_total
      ~trng_fn:isw_trng;

    C_visa_c_runtime.emit_shadow_and_cfi ~vs ~word_count ~vbc_name ~ptr_arg ~reg_mask_base ~reg_mask_step ~arg_inits;
    C_visa_c_dispatch.emit_dispatch_table ~op ~prof ~trap_bindings_str;
    C_visa_c_dispatch.emit_dispatch_macro ~vs ~word_count ~affine_p ~affine_s ~pack_key ~delta_key ~lay ~prof;

    (* ISW masked AND / XOR handlers injected before standard handlers *)
    C_isw_masked_regfile_service.emit_masked_and_handler
      ~label:"__h_visw_and"
      ~vs
      ~disp_macro:"__VISA_DISPATCH()";
    C_isw_masked_regfile_service.emit_masked_xor_handler
      ~label:"__h_visw_xor"
      ~vs
      ~disp_macro:"__VISA_DISPATCH()";

    C_visa_c_handlers.emit_handlers ~vs ~trap_code ~vd_shift:lay.vd_shift;
    C_visa_c_runtime.emit_epilogue ~vs ~out_reg ~ret_type_str ~reg_mask_step;
  ]

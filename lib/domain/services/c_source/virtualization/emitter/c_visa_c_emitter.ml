open C_visa_spec

(** Domain Service: C11 Direct-Threaded Emulator Body Code Generator
    High-level orchestrator composing:
    - C_visa_c_runtime: Header, vbank register matrix, shadow stacks, CFI canary & epilogue
    - C_visa_c_dispatch: Direct-threading dispatch table & __VISA_DISPATCH macro
    - C_visa_c_handlers: ALU, bitwise, memory and branch opcode handlers
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
  let prof = C_visa_profile_service.get_active_profile () in
  let sbox_code = C_visa_profile_service.generate_sbox_luts prof.lut_count in
  let (trap_code, trap_bindings) =
    C_visa_profile_service.generate_synthetic_trap_handlers
      ~start_slot:64
      ~total_slots:prof.dispatch_size
      ~lut_count:prof.lut_count
  in
  let trap_bindings_str = C_visa_profile_service.format_trap_bindings trap_bindings in

  String.concat "" [
    C_visa_c_runtime.emit_header ~ret_type_str ~fn_name ~fn_params ~sbox_code;
    C_visa_c_runtime.emit_vbank ~vreg_total ~vreg_rot_seed ~reg_mask_base ~reg_mask_step;
    C_visa_c_runtime.emit_shadow_and_cfi ~word_count ~vbc_name ~ptr_arg ~reg_mask_base ~reg_mask_step ~arg_inits;
    C_visa_c_dispatch.emit_dispatch_table ~op ~prof ~trap_bindings_str;
    C_visa_c_dispatch.emit_dispatch_macro ~word_count ~affine_p ~affine_s ~pack_key ~delta_key ~lay ~prof;
    C_visa_c_handlers.emit_handlers ~trap_code ~vd_shift:lay.vd_shift;
    C_visa_c_runtime.emit_epilogue ~out_reg ~ret_type_str ~reg_mask_step;
  ]

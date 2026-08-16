open C_visa_spec

(** Domain Service: C11 Direct-Threading Dispatcher and Decoy S-Box Traps Generator *)

let emit_dispatch_table
    ~(op : visa_opcodes)
    ~(prof : C_visa_profile_service.vm_profile_config)
    ~(trap_bindings_str : string) : string =
  let size = prof.dispatch_size in
  Printf.sprintf {|
    /* Direct Threading Dispatch Table via GNU C Computed Gotos */
    static const void * const __dispatch_table[%d] = {
        [0 ... %d] = &&__h_default,
        [0x%X] = &&__h_vadd,
        [0x%X] = &&__h_vsub,
        [0x%X] = &&__h_vmul,
        [0x%X] = &&__h_vxor,
        [0x%X] = &&__h_vand,
        [0x%X] = &&__h_vor,
        [0x%X] = &&__h_vsll,
        [0x%X] = &&__h_vsrl,
        [0x%X] = &&__h_vli,
        [0x%X] = &&__h_vmv,
        [0x%X] = &&__h_vle8,
        [0x%X] = &&__h_vse8,
        [0x%X] = &&__h_vret,
        [0x%X] = &&__h_vbge,
        [0x%X] = &&__h_vj,
        /* Polymorphic Multi-Alias Opcode Handlers */
        [0x%X] = &&__h_vadd_alt1,
        [0x%X] = &&__h_vadd_alt2,
        [0x%X] = &&__h_vsub_alt1,
        [0x%X] = &&__h_vsub_alt2,
        [0x%X] = &&__h_vxor_alt1,
        [0x%X] = &&__h_vxor_alt2,
        [0x%X] = &&__h_vand_alt1,
        [0x%X] = &&__h_vor_alt1,
        [0x%X] = &&__h_vmul_alt1,
        [0x%X] = &&__h_vmv_alt1,
        [0x%X] = &&__h_vli_alt1,
        /* Architecture A: Dynamic In-VM Ephemeral JIT Escape Handlers */
        [0x%X] = &&__h_vjit,
        [0x%X] = &&__h_vjit_alt1,
%s
    };
|} size (size - 1)
   op.vadd_vv op.vsub_vv op.vmul_vv op.vxor_vv op.vand_vv op.vor_vv op.vsll_vv op.vsrl_vv
   op.vli_vi op.vmv_vv op.vle8_v op.vse8_v op.vret_v op.vbge_vv op.vj
   op.vadd_alt1 op.vadd_alt2 op.vsub_alt1 op.vsub_alt2 op.vxor_alt1 op.vxor_alt2
   op.vand_alt1 op.vor_alt1 op.vmul_alt1 op.vmv_alt1 op.vli_alt1
   op.vjit_vv op.vjit_alt1
   trap_bindings_str

let emit_dispatch_macro
    ~(vs : C_visa_c_runtime.var_set)
    ~(word_count : int)
    ~(affine_p : int)
    ~(affine_s : int)
    ~(pack_key : int64)
    ~(delta_key : int64)
    ~(lay : visa_field_layout)
    ~(prof : C_visa_profile_service.vm_profile_config) : string =
  let pk32     = Int64.to_int32 pack_key in
  let dk32     = Int64.to_int32 delta_key in
  let mask_size = prof.dispatch_size - 1 in
  Printf.sprintf {|
    #define __VISA_DISPATCH() do { \
        if (%s >= %d) goto __h_vret; \
        unsigned int __slot = ((%s * %uU) + %uU) %% %uU; \
        %s = %s[__slot]; \
        %s = 0x%lXU ^ (%s * 0x%lXU); \
        %s = %s ^ %s; \
        %s = (unsigned char)((%s >> %d) & 0x%X); \
        %s = (unsigned char)((%s >> %d) & 0x01); \
        %s = (unsigned char)((%s >> %d) & 0x1F); \
        %s = (unsigned char)((%s >> %d) & 0x1F); \
        %s = (unsigned char)((%s >> %d) & 0x07); \
        %s = (unsigned char)((%s >> %d)  & 0x1F); \
        /* Anti-Pushan: Non-linear Quadratic VPC Stepper */ \
        %s = (%s + 1U) + (unsigned int)((%s * (%s + 1ULL)) & 1ULL); \
        %s = ((%s * 0x%LxULL) ^ (%s + %s + ((unsigned long long)%s * 0x9E3779B9ULL))) * 0x517CC1B727220A95ULL; \
        goto *__dispatch_table[%s & 0x%X]; \
    } while (0)

    /* Enter Direct Threading pipeline */
    __VISA_DISPATCH();
|}
  (* pc bounds *)
  vs.pc word_count
  (* slot *)
  vs.pc affine_p affine_s word_count
  (* raw = vbl[slot] *)
  vs.rw vs.vbl
  (* key *)
  vs.ky pk32 vs.pc dk32
  (* inst *)
  vs.ins vs.rw vs.ky
  (* field decodes — funct6 *)
  vs.f6 vs.ins lay.funct6_shift lay.funct6_mask
  (* vm *)
  vs.vm vs.ins lay.vm_shift
  (* vs2 *)
  vs.vs2 vs.ins lay.vs2_shift
  (* vs1 *)
  vs.vs1 vs.ins lay.vs1_shift
  (* funct3 *)
  vs.f3 vs.ins lay.funct3_shift
  (* vd *)
  vs.vd vs.ins lay.vd_shift
  (* pc step *)
  vs.pc vs.pc vs.vma vs.vma
  (* state acc *)
  vs.vma vs.vma vs.gold1 vs.vd vs.f6 vs.pc
  (* dispatch *)
  vs.f6 mask_size

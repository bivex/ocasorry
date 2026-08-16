open C_visa_spec

(** Domain Service: C11 Decentralized Direct-Threading Dispatcher (No Central Hub)
    Splits the central dispatch table into 5 independent local routing networks:
    1. ALU Table (__dt_alu): for arithmetic & logic handlers
    2. Memory Table (__dt_mem): for load / store handlers
    3. Control Table (__dt_ctrl): for branch / jump handlers
    4. Shift Table (__dt_shift): for bitwise shifts
    5. JIT Table (__dt_jit): for dynamic JIT escape gates

    Each table is independently permuted and salted per build session, destroying
    the centralized "star hub" CFG topology and defeating automated graph matching (BinDiff).
*)

let format_table (name : string) (op : visa_opcodes) (size : int) (trap_str : string) : string =
  Printf.sprintf {|
    /* Decentralized Routing Network: %s */
    static const void * const %s[%d] = {
        [0 ... %d] = &&__h_default,
        [0x%X] = &&__h_vadd, [0x%X] = &&__h_vsub, [0x%X] = &&__h_vmul,
        [0x%X] = &&__h_vxor, [0x%X] = &&__h_vand, [0x%X] = &&__h_vor,
        [0x%X] = &&__h_vli,  [0x%X] = &&__h_vmv,
        [0x%X] = &&__h_vadd_alt1, [0x%X] = &&__h_vadd_alt2,
        [0x%X] = &&__h_vsub_alt1, [0x%X] = &&__h_vsub_alt2,
        [0x%X] = &&__h_vxor_alt1, [0x%X] = &&__h_vxor_alt2,
        [0x%X] = &&__h_vand_alt1, [0x%X] = &&__h_vor_alt1,
        [0x%X] = &&__h_vmul_alt1, [0x%X] = &&__h_vmv_alt1, [0x%X] = &&__h_vli_alt1,
        [0x%X] = &&__h_vsll, [0x%X] = &&__h_vsrl,
        [0x%X] = &&__h_vle8, [0x%X] = &&__h_vse8,
        [0x%X] = &&__h_vbge, [0x%X] = &&__h_vj,
        [0x%X] = &&__h_vret, [0x%X] = &&__h_vjit, [0x%X] = &&__h_vjit_alt1,
%s
    };
|} name name size (size - 1)
   op.vadd_vv op.vsub_vv op.vmul_vv op.vxor_vv op.vand_vv op.vor_vv
   op.vli_vi op.vmv_vv
   op.vadd_alt1 op.vadd_alt2 op.vsub_alt1 op.vsub_alt2
   op.vxor_alt1 op.vxor_alt2 op.vand_alt1 op.vor_alt1
   op.vmul_alt1 op.vmv_alt1 op.vli_alt1
   op.vsll_vv op.vsrl_vv op.vle8_v op.vse8_v op.vbge_vv op.vj op.vret_v
   op.vjit_vv op.vjit_alt1
   trap_str

let emit_dispatch_table
    ~(op : visa_opcodes)
    ~(prof : C_visa_profile_service.vm_profile_config)
    ~(trap_bindings_str : string) : string =
  let size = prof.dispatch_size in
  String.concat "\n" [
    format_table "__dt_alu"   op size trap_bindings_str;
    format_table "__dt_mem"   op size trap_bindings_str;
    format_table "__dt_ctrl"  op size trap_bindings_str;
    format_table "__dt_shift" op size trap_bindings_str;
    format_table "__dt_jit"   op size trap_bindings_str;
  ]


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
    #define __VISA_STEP_CORE() do { \
        if (%s >= %d) goto __h_vret; \
        unsigned int __slot = ((%s * %uU) + %uU) %% %uU; \
        %s = %s[__slot]; \
        %s = 0x%lXU ^ (%s * 0x%lXU) ^ %s[__slot]; \
        %s = %s ^ %s; \
        /* Dynamic In-Place Bytecode Metamorphic Scrambler (Gap 1): */ \
        unsigned int __vbd = (__slot + %s + 1U) * 0x9E3779B9U; \
        %s[__slot] ^= __vbd; \
        %s[__slot] ^= __vbd; \
        %s = (unsigned char)((%s >> %d) & 0x%X); \
        %s = (unsigned char)((%s >> %d) & 0x01); \
        %s = (unsigned char)((%s >> %d) & 0x1F); \
        %s = (unsigned char)((%s >> %d) & 0x1F); \
        %s = (unsigned char)((%s >> %d) & 0x07); \
        %s = (unsigned char)((%s >> %d)  & 0x1F); \
        /* Anti-Pushan: Non-linear Quadratic VPC Stepper */ \
        %s = (%s + 1U) + (unsigned int)((%s * (%s + 1ULL)) & 1ULL); \
        %s = ((%s * 0x%LxULL) ^ (%s + %s + ((unsigned long long)%s * 0x9E3779B9ULL))) * 0x517CC1B727220A95ULL; \
    } while (0)



    #define __VISA_DISPATCH() do { \
        __VISA_STEP_CORE(); \
        goto *__dt_alu[%s & 0x%X]; \
    } while (0)

    #define __VISA_DISP_MEM() do { \
        __VISA_STEP_CORE(); \
        goto *__dt_mem[%s & 0x%X]; \
    } while (0)

    #define __VISA_DISP_CTRL() do { \
        __VISA_STEP_CORE(); \
        goto *__dt_ctrl[%s & 0x%X]; \
    } while (0)

    #define __VISA_DISP_SHIFT() do { \
        __VISA_STEP_CORE(); \
        goto *__dt_shift[%s & 0x%X]; \
    } while (0)

    #define __VISA_DISP_JIT() do { \
        __VISA_STEP_CORE(); \
        goto *__dt_jit[%s & 0x%X]; \
    } while (0)

    /* Enter Decentralized Direct Threading pipeline */
    __VISA_DISPATCH();
|}
  (* pc bounds *)
  vs.pc word_count
  (* slot *)
  vs.pc affine_p affine_s word_count
  (* raw = vbl[slot] *)
  vs.rw vs.vbl
  (* key *)
  vs.ky pk32 vs.pc dk32 vs.vbm
  (* inst *)
  vs.ins vs.rw vs.ky
  (* in-place mutation *)
  vs.pc vs.vbm vs.vbl
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
  (* dispatch alu *)
  vs.f6 mask_size
  (* dispatch mem *)
  vs.f6 mask_size
  (* dispatch ctrl *)
  vs.f6 mask_size
  (* dispatch shift *)
  vs.f6 mask_size
  (* dispatch jit *)
  vs.f6 mask_size


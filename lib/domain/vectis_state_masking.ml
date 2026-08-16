(** Vectis Next Dynamic State Masking & Non-Linear VPC Stepping
    Implements algebraic state masking, rotating key schedule, and
    pluggable state transition steppers.
*)

module KeySchedule = struct
  (** Rotating key derivation: K(pc, state, epoch) with domain separation *)
  let derive_key ~(domain : string) ~(pc : int) ~(state : int64) ~(epoch : int64) : int64 =
    let d_hash =
      let h = ref 0xCBF29CE484222325L in
      String.iter (fun c ->
        let b = Int64.of_int (Char.code c) in
        h := Int64.logxor !h b;
        h := Int64.mul !h 0x100000001B3L
      ) domain;
      !h
    in
    let pc64 = Int64.of_int pc in
    let k1 = Int64.logxor d_hash (Int64.mul pc64 0x9E3779B97F4A7C15L) in
    let k2 = Int64.logxor state (Int64.mul epoch 0x517CC1B727220A95L) in
    Int64.add (Int64.mul k1 0x63C63CD93839C9B9L) k2
end

module StateMasking = struct
  type mask_state = {
    mutable epoch     : int64;
    mutable base_mask : int64;
    mutable step_mask : int64;
    rot_seed          : int;
    reg_epochs        : int64 array;
  }

  let create ?(seed=0xDEADBEEFL) ?(reg_count=64) () : mask_state =
    {
      epoch = 0L;
      base_mask = seed;
      step_mask = Int64.logxor seed 0xCAFEBABE5A5A5A5AL;
      rot_seed = Int64.to_int (Int64.logand seed 0x3FL);
      reg_epochs = Array.make reg_count 0L;
    }

  let get_reg_mask (st : mask_state) (reg_idx : int) (epoch : int64) : int64 =
    let rot_idx = (reg_idx + st.rot_seed) mod 64 in
    let offset = Int64.mul (Int64.of_int rot_idx) st.step_mask in
    Int64.logxor (Int64.add st.base_mask offset) (Int64.mul epoch 0x9E3779B9L)

  let mask_value (st : mask_state) (reg_idx : int) (logical_val : int64) : int64 =
    if reg_idx >= 0 && reg_idx < Array.length st.reg_epochs then (
      st.reg_epochs.(reg_idx) <- st.epoch;
      Int64.logxor logical_val (get_reg_mask st reg_idx st.epoch)
    ) else logical_val

  let unmask_value (st : mask_state) (reg_idx : int) (physical_val : int64) : int64 =
    if reg_idx >= 0 && reg_idx < Array.length st.reg_epochs then (
      let ep = st.reg_epochs.(reg_idx) in
      Int64.logxor physical_val (get_reg_mask st reg_idx ep)
    ) else physical_val

  let advance_epoch (st : mask_state) : unit =
    st.epoch <- Int64.add st.epoch 1L
end



module Stepper = struct
  type stepper_kind =
    | Linear
    | NonLinear
    | Randomized

  type t = {
    kind : stepper_kind;
    mutable state : int64;
    g1 : int64;
    g2 : int64;
  }

  let create (kind : stepper_kind) ?(seed=0x9E3779B97F4A7C15L) () : t =
    {
      kind;
      state = seed;
      g1 = 0x63C63CD93839C9B9L;
      g2 = 0x517CC1B727220A95L;
    }

  let step (s : t) (current_pc : int) (opcode_val : int) : int =
    match s.kind with
    | Linear ->
        current_pc + 1
    | NonLinear ->
        (* S[n+1] = ((S[n] * G1) ^ (opcode + pc * G2)) * G1 *)
        let op64 = Int64.of_int opcode_val in
        let pc64 = Int64.of_int current_pc in
        let acc = Int64.logxor (Int64.mul s.state s.g1) (Int64.add op64 (Int64.mul pc64 s.g2)) in
        s.state <- Int64.mul acc s.g1;
        (* Anti-Pushan invariant: (state * (state + 1)) is always even, so & 1L is always 0 in absence of tampering *)
        let invariant = Int64.to_int (Int64.logand (Int64.mul s.state (Int64.add s.state 1L)) 1L) in
        current_pc + 1 + invariant
    | Randomized ->
        let r = Random.int 3 in
        if r = 0 then current_pc + 1
        else current_pc + 1
end

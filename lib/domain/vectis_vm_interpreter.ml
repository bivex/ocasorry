open Vectis_isa
open Vectis_state_masking

(** Vectis Next Reference Interpreter & Execution Engine *)

type vm_state = {
  reg_bank       : int64 array;
  flags          : vflags;
  memory         : (int64, int64) Hashtbl.t;
  call_stack     : int Stack.t;
  masking        : StateMasking.mask_state;
  stepper        : Stepper.t;
  mutable pc     : int;
  mutable halted : bool;
  mutable steps  : int;
  max_steps      : int;
  trace          : (int * string * int64) list ref;
}

let create_vm
    ?(reg_count=32)
    ?(stepper_kind=Stepper.NonLinear)
    ?(max_steps=100000)
    () : vm_state =
  {
    reg_bank   = Array.make reg_count 0L;
    flags      = default_flags ();
    memory     = Hashtbl.create 256;
    call_stack = Stack.create ();
    masking    = StateMasking.create ~reg_count ();

    stepper    = Stepper.create stepper_kind ();
    pc         = 0;
    halted     = false;
    steps      = 0;
    max_steps;
    trace      = ref [];
  }

let get_reg (vm : vm_state) (r : vreg) : int64 =
  if r >= 0 && r < Array.length vm.reg_bank then
    StateMasking.unmask_value vm.masking r vm.reg_bank.(r)
  else 0L

let set_reg (vm : vm_state) (r : vreg) (v : int64) : unit =
  if r >= 0 && r < Array.length vm.reg_bank then (
    vm.reg_bank.(r) <- StateMasking.mask_value vm.masking r v;
    StateMasking.advance_epoch vm.masking
  )

let eval_operand (vm : vm_state) = function
  | Reg r -> get_reg vm r
  | Imm i -> i
  | Mem { base; offset } ->
      let addr = Int64.add (get_reg vm base) offset in
      Hashtbl.find_opt vm.memory addr |> Option.value ~default:0L

let update_flags (flags : vflags) (res : int64) : unit =
  flags.zf <- (res = 0L);
  flags.nf <- (res < 0L)

let check_condition (flags : vflags) = function
  | V_ALWAYS   -> true
  | V_EQ       -> flags.zf
  | V_NE       -> not flags.zf
  | V_LT       -> flags.nf <> flags.vf
  | V_LE       -> flags.zf || (flags.nf <> flags.vf)
  | V_GT       -> (not flags.zf) && (flags.nf = flags.vf)
  | V_GE       -> flags.nf = flags.vf
  | V_CARRY    -> flags.cf
  | V_OVERFLOW -> flags.vf

type step_result =
  | StepOk
  | StepHalt of int64
  | StepError of string

let step_vm (vm : vm_state) (prog : vprogram) : step_result =
  if vm.halted then StepHalt (get_reg vm 0)
  else if vm.steps >= vm.max_steps then StepError "Execution step limit exceeded (infinite loop protection)"
  else if vm.pc < 0 || vm.pc >= Array.length prog.instructions then (
    vm.halted <- true;
    StepHalt (get_reg vm 0)
  ) else (
    vm.steps <- vm.steps + 1;
    let insn = prog.instructions.(vm.pc) in
    let current_pc = vm.pc in

    if not (check_condition vm.flags insn.cond) then (
      vm.pc <- Stepper.step vm.stepper current_pc 0;
      StepOk
    ) else (
      match insn.op with
      | OP_NOP ->
          vm.pc <- Stepper.step vm.stepper current_pc 0;
          StepOk

      | OP_MOV ->
          (match insn.dst, insn.src1 with
          | Some (Reg d), Some s ->
              let v = eval_operand vm s in
              set_reg vm d v;
              update_flags vm.flags v
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 1;
          StepOk

      | OP_ADD ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.add v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 2;
          StepOk

      | OP_SUB ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.sub v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 3;
          StepOk

      | OP_MUL ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.mul v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 4;
          StepOk

      | OP_XOR ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.logxor v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 5;
          StepOk

      | OP_AND ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.logand v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 6;
          StepOk

      | OP_OR ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let res = Int64.logor v1 v2 in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 7;
          StepOk

      | OP_SHL ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let sh = Int64.to_int (Int64.logand (eval_operand vm s2) 0x3FL) in
              let res = Int64.shift_left v1 sh in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 8;
          StepOk

      | OP_SHR ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let sh = Int64.to_int (Int64.logand (eval_operand vm s2) 0x3FL) in
              let res = Int64.shift_right_logical v1 sh in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 9;
          StepOk

      | OP_ROL ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let sh = Int64.to_int (Int64.logand (eval_operand vm s2) 0x3FL) in
              let l = Int64.shift_left v1 sh in
              let r = Int64.shift_right_logical v1 (64 - sh) in
              let res = Int64.logor l r in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 10;
          StepOk

      | OP_ROR ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let sh = Int64.to_int (Int64.logand (eval_operand vm s2) 0x3FL) in
              let r = Int64.shift_right_logical v1 sh in
              let l = Int64.shift_left v1 (64 - sh) in
              let res = Int64.logor l r in
              set_reg vm d res;
              update_flags vm.flags res
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 11;
          StepOk

      | OP_CMP ->
          (match insn.src1, insn.src2 with
          | Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let diff = Int64.sub v1 v2 in
              update_flags vm.flags diff
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 12;
          StepOk

      | OP_SELECT ->
          (match insn.dst, insn.src1, insn.src2 with
          | Some (Reg d), Some s1, Some s2 ->
              let v1 = eval_operand vm s1 in
              let v2 = eval_operand vm s2 in
              let chosen = if vm.flags.zf then v2 else v1 in
              set_reg vm d chosen
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 13;
          StepOk

      | OP_LOAD ->
          (match insn.dst, insn.src1 with
          | Some (Reg d), Some (Mem { base; offset }) ->
              let addr = Int64.add (get_reg vm base) offset in
              let v = Hashtbl.find_opt vm.memory addr |> Option.value ~default:0L in
              set_reg vm d v
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 14;
          StepOk

      | OP_STORE ->
          (match insn.src1, insn.dst with
          | Some s, Some (Mem { base; offset }) ->
              let addr = Int64.add (get_reg vm base) offset in
              let v = eval_operand vm s in
              Hashtbl.replace vm.memory addr v
          | _ -> ());
          vm.pc <- Stepper.step vm.stepper current_pc 15;
          StepOk

      | OP_BRANCH ->
          (match insn.src1 with
          | Some (Imm target) ->
              vm.pc <- Int64.to_int target
          | Some (Reg r) ->
              vm.pc <- Int64.to_int (get_reg vm r)
          | _ ->
              vm.pc <- current_pc + 1);
          StepOk

      | OP_CALL ->
          Stack.push (current_pc + 1) vm.call_stack;
          (match insn.src1 with
          | Some (Imm target) -> vm.pc <- Int64.to_int target
          | Some (Reg r)      -> vm.pc <- Int64.to_int (get_reg vm r)
          | _                 -> vm.pc <- current_pc + 1);
          StepOk

      | OP_RET ->
          if Stack.is_empty vm.call_stack then (
            vm.halted <- true;
            StepHalt (get_reg vm 0)
          ) else (
            vm.pc <- Stack.pop vm.call_stack;
            StepOk
          )

      | OP_ENTER_NESTED | OP_EXIT_NESTED ->
          vm.pc <- Stepper.step vm.stepper current_pc 18;
          StepOk

      | OP_JIT_ESC ->
          (* Simulated Ephemeral JIT Escape: Computes (V1 ^ V2) * K1 + K2 *)
          let a = get_reg vm 1 in
          let b = get_reg vm 2 in
          let k = insn.metadata in
          let res = Int64.add (Int64.mul (Int64.logxor a b) 3L) k in
          set_reg vm 0 res;
          vm.pc <- Stepper.step vm.stepper current_pc 19;
          StepOk
    )
  )

let run_vm (vm : vm_state) (prog : vprogram) : (int64, string) result =
  let rec loop () =
    match step_vm vm prog with
    | StepOk -> loop ()
    | StepHalt res -> Ok res
    | StepError err -> Error err
  in
  loop ()

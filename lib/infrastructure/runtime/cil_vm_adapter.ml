open Executor_port

type cil_executable = {
  bytecode : bytes;
}

module Adapter : Executor_port.S = struct
  type handle = cil_executable

  let allocate_executable (code : bytes) =
    Ok { bytecode = code }

  let execute_bytecode (exec : cil_executable) (initial_args : int64 array) : (int64, execution_error) result =
    let code = exec.bytecode in
    let len = Bytes.length code in
    let pc = ref 0 in
    let stack = ref [] in
    let args = Array.copy initial_args in
    let result = ref None in

    let pop () =
      match !stack with
      | hd :: tl ->
          stack := tl;
          hd
      | [] -> failwith "CIL Stack Underflow"
    in

    let push v =
      stack := v :: !stack
    in

    try
      while !pc < len && !result = None do
        let op = Bytes.get_uint8 code !pc in
        match op with
        | 0x00 -> (* Nop *)
            pc := !pc + 1

        | 0x02 -> (* Ldarg_0 *)
            push args.(0);
            pc := !pc + 1

        | 0x03 -> (* Ldarg_1 *)
            push args.(1);
            pc := !pc + 1

        | 0x04 -> (* Ldarg_2 *)
            push args.(2);
            pc := !pc + 1

        | 0x0E -> (* Ldarg.s idx *)
            let idx = Bytes.get_uint8 code (!pc + 1) in
            push args.(idx);
            pc := !pc + 2

        | 0x0A -> (* Starg.s 0 *)
            args.(0) <- pop ();
            pc := !pc + 1

        | 0x0B -> (* Starg.s 1 *)
            args.(1) <- pop ();
            pc := !pc + 1

        | 0x10 -> (* Starg.s idx *)
            let idx = Bytes.get_uint8 code (!pc + 1) in
            args.(idx) <- pop ();
            pc := !pc + 2

        | 0x20 -> (* Ldc_i4 *)
            let imm = Bytes.get_int32_ne code (!pc + 1) in
            push (Int64.of_int32 imm);
            pc := !pc + 5

        | 0x21 -> (* Ldc_i8 *)
            let imm = Bytes.get_int64_ne code (!pc + 1) in
            push imm;
            pc := !pc + 9

        | 0x25 -> (* Dup *)
            let v = pop () in
            push v;
            push v;
            pc := !pc + 1

        | 0x26 -> (* Pop *)
            ignore (pop ());
            pc := !pc + 1

        | 0x2A -> (* Ret *)
            let ret_val = pop () in
            result := Some ret_val;
            pc := !pc + 1

        | 0x38 -> (* Br *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            pc := !pc + 5 + offset

        | 0x3B -> (* Beq *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 = v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x3C -> (* Bge *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 >= v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x3D -> (* Bgt *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 > v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x3E -> (* Ble *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 <= v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x3F -> (* Blt *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 < v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x40 -> (* Bne_un *)
            let offset = Int32.to_int (Bytes.get_int32_ne code (!pc + 1)) in
            let v2 = pop () in
            let v1 = pop () in
            if v1 <> v2 then pc := !pc + 5 + offset else pc := !pc + 5

        | 0x58 -> (* Add *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.add v1 v2);
            pc := !pc + 1

        | 0x59 -> (* Sub *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.sub v1 v2);
            pc := !pc + 1

        | 0x5A -> (* Mul *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.mul v1 v2);
            pc := !pc + 1

        | 0x5F -> (* And *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.logand v1 v2);
            pc := !pc + 1

        | 0x60 -> (* Or *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.logor v1 v2);
            pc := !pc + 1

        | 0x61 -> (* Xor *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.logxor v1 v2);
            pc := !pc + 1

        | 0x62 -> (* Shl *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.shift_left v1 (Int64.to_int v2 land 63));
            pc := !pc + 1

        | 0x63 -> (* Shr *)
            let v2 = pop () in
            let v1 = pop () in
            push (Int64.shift_right_logical v1 (Int64.to_int v2 land 63));
            pc := !pc + 1

        | 0x66 -> (* Not *)
            let v1 = pop () in
            push (Int64.lognot v1);
            pc := !pc + 1

        | unknown ->
            failwith (Printf.sprintf "Unknown CIL opcode 0x%02X at pc=%d" unknown !pc)
      done;

      match !result with
      | Some v -> Ok v
      | None -> Error (ExecutionFault "Execution reached end without RET")
    with
    | Failure msg -> Error (ExecutionFault msg)
    | exn -> Error (ExecutionFault (Printexc.to_string exn))

  let run_fn1 handle arg =
    let args = Array.make 16 0L in
    args.(0) <- arg;
    execute_bytecode handle args

  let run_fn2 handle arg1 arg2 =
    let args = Array.make 16 0L in
    args.(0) <- arg1;
    args.(1) <- arg2;
    execute_bytecode handle args

  let free _handle = ()
end

open Cil_opcodes
open Cil_stack

let read_u8 (code : bytes) (pc : int) : int = Bytes.get_uint8 code pc
let read_i32_le (code : bytes) (pc : int) : int32 = Bytes.get_int32_le code pc
let read_i64_le (code : bytes) (pc : int) : int64 = Bytes.get_int64_le code pc

let execute (code : bytes) (x0 : int64) (x1 : int64) : (int64, string) result =
  let len = Bytes.length code in
  let state = create_state x0 x1 in
  let running = ref true in
  let ret_val = ref 0L in
  let steps = ref 0 in
  let max_steps = 100_000 in

  try
    while !running && state.pc < len do
      incr steps;
      if !steps > max_steps then failwith "Execution step limit exceeded (possible infinite loop)";

      let op = read_u8 code state.pc in
      state.pc <- state.pc + 1;

      if op = nop_op then ()
      else if op = ldc_i4 then (
        let v = read_i32_le code state.pc in
        state.pc <- state.pc + 4;
        state.eval_stack <- I32 v :: state.eval_stack
      )
      else if op = ldc_i8 then (
        let v = read_i64_le code state.pc in
        state.pc <- state.pc + 8;
        state.eval_stack <- I64 v :: state.eval_stack
      )
      else if op = ldloc then (
        let idx = read_u8 code state.pc in
        state.pc <- state.pc + 1;
        let v = try Hashtbl.find state.locals idx with Not_found -> I64 0L in
        state.eval_stack <- v :: state.eval_stack
      )
      else if op = stloc then (
        let idx = read_u8 code state.pc in
        state.pc <- state.pc + 1;
        match state.eval_stack with
        | hd :: tl ->
            state.eval_stack <- tl;
            Hashtbl.replace state.locals idx hd
        | [] -> failwith "Stack underflow on stloc"
      )
      else if op = pop_op then (
        match state.eval_stack with
        | _ :: tl -> state.eval_stack <- tl
        | [] -> failwith "Stack underflow on pop"
      )
      else if op = conv_i8 then (
        let v = pop_i64 state in
        push_i64 state v
      )
      else if op = add_op then (
        let b = pop_i64 state in
        let a = pop_i64 state in
        push_i64 state (Int64.add a b)
      )
      else if op = sub_op then (
        let b = pop_i64 state in
        let a = pop_i64 state in
        push_i64 state (Int64.sub a b)
      )
      else if op = and_op then (
        let b = pop_i64 state in
        let a = pop_i64 state in
        push_i64 state (Int64.logand a b)
      )
      else if op = or_op then (
        let b = pop_i64 state in
        let a = pop_i64 state in
        push_i64 state (Int64.logor a b)
      )
      else if op = xor_op then (
        let b = pop_i64 state in
        let a = pop_i64 state in
        push_i64 state (Int64.logxor a b)
      )
      else if op = not_op then (
        let a = pop_i64 state in
        push_i64 state (Int64.lognot a)
      )
      else if op = shl_op then (
        let shift = Int64.to_int (pop_i64 state) in
        let a = pop_i64 state in
        push_i64 state (Int64.shift_left a (shift land 63))
      )
      else if op = shr_un_op then (
        let shift = Int64.to_int (pop_i64 state) in
        let a = pop_i64 state in
        push_i64 state (Int64.shift_right_logical a (shift land 63))
      )
      else if op = br_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4 + offset
      )
      else if op = beq_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a = b then state.pc <- state.pc + offset
      )
      else if op = bne_un_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a <> b then state.pc <- state.pc + offset
      )
      else if op = bge_s || op = bge_un_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a >= b then state.pc <- state.pc + offset
      )
      else if op = bgt_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a > b then state.pc <- state.pc + offset
      )
      else if op = ble_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a <= b then state.pc <- state.pc + offset
      )
      else if op = blt_s || op = blt_un_s then (
        let offset = Int32.to_int (read_i32_le code state.pc) in
        state.pc <- state.pc + 4;
        let b = pop_i64 state in
        let a = pop_i64 state in
        if a < b then state.pc <- state.pc + offset
      )
      else if op = ret_op then (
        ret_val := pop_i64 state;
        running := false
      )
      else failwith (Printf.sprintf "Unknown CIL opcode: 0x%02X at offset %d" op (state.pc - 1))
    done;
    Ok !ret_val
  with Failure msg -> Error msg

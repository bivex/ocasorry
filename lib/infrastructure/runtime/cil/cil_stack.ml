type stack_val =
  | I32 of int32
  | I64 of int64

type vm_state = {
  mutable pc : int;
  mutable eval_stack : stack_val list;
  locals : (int, stack_val) Hashtbl.t;
}

let create_state (x0 : int64) (x1 : int64) : vm_state =
  let state = {
    pc = 0;
    eval_stack = [];
    locals = Hashtbl.create 32;
  } in
  Hashtbl.add state.locals 0 (I64 x0);
  Hashtbl.add state.locals 1 (I64 x1);
  state

let to_i64 (v : stack_val) : int64 =
  match v with
  | I32 x -> Int64.of_int32 x
  | I64 x -> x

let pop_i64 (state : vm_state) : int64 =
  match state.eval_stack with
  | hd :: tl ->
      state.eval_stack <- tl;
      to_i64 hd
  | [] -> failwith "VM Stack Underflow"

let push_i64 (state : vm_state) (v : int64) : unit =
  state.eval_stack <- I64 v :: state.eval_stack

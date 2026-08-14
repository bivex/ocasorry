open Executor_port

type c_handle

external c_jit_allocate : bytes -> c_handle = "caml_jit_allocate"
external c_jit_run_fn1 : c_handle -> int64 -> int64 = "caml_jit_run_fn1"
external c_jit_run_fn2 : c_handle -> int64 -> int64 -> int64 = "caml_jit_run_fn2"
external c_jit_free : c_handle -> unit = "caml_jit_free"

module Adapter : Executor_port.S = struct
  type handle = c_handle

  let allocate_executable (code : bytes) =
    try
      let h = c_jit_allocate code in
      Ok h
    with
    | Failure msg -> Error (AllocationFailed msg)
    | exn -> Error (AllocationFailed (Printexc.to_string exn))

  let run_fn1 handle arg =
    try
      let res = c_jit_run_fn1 handle arg in
      Ok res
    with
    | Failure msg -> Error (ExecutionFault msg)
    | exn -> Error (ExecutionFault (Printexc.to_string exn))

  let run_fn2 handle arg1 arg2 =
    try
      let res = c_jit_run_fn2 handle arg1 arg2 in
      Ok res
    with
    | Failure msg -> Error (ExecutionFault msg)
    | exn -> Error (ExecutionFault (Printexc.to_string exn))

  let free handle =
    try c_jit_free handle with _ -> ()
end

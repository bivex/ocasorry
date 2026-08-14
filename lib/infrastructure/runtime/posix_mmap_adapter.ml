open Executor_port

type jit_handle

external caml_jit_allocate : bytes -> jit_handle = "caml_jit_allocate"
external caml_jit_run_fn1 : jit_handle -> int64 -> int64 = "caml_jit_run_fn1"
external caml_jit_run_fn2 : jit_handle -> int64 -> int64 -> int64 = "caml_jit_run_fn2"
external caml_jit_free : jit_handle -> unit = "caml_jit_free"

external caml_two_tier_jit_run :
  bytes -> bytes -> int -> int64 -> int64 -> int64 = "caml_two_tier_jit_run"

module Adapter : Executor_port.S = struct
  type handle = jit_handle

  let allocate_executable (code : bytes) : (handle, execution_error) result =
    try
      let h = caml_jit_allocate code in
      Ok h
    with Failure msg ->
      Error (AllocationFailed msg)

  let run_fn1 (h : handle) (x0 : int64) : (int64, execution_error) result =
    try
      let res = caml_jit_run_fn1 h x0 in
      Ok res
    with Failure msg ->
      Error (ExecutionFault msg)

  let run_fn2 (h : handle) (x0 : int64) (x1 : int64) : (int64, execution_error) result =
    try
      let res = caml_jit_run_fn2 h x0 x1 in
      Ok res
    with Failure msg ->
      Error (ExecutionFault msg)

  let free (h : handle) : unit =
    caml_jit_free h
end

let run_two_tier_jit (tier1_code : bytes) (tier2_enc_code : bytes) (key : int) (x0 : int64) (x1 : int64) : (int64, string) result =
  try
    let res = caml_two_tier_jit_run tier1_code tier2_enc_code key x0 x1 in
    Ok res
  with Failure msg -> Error msg

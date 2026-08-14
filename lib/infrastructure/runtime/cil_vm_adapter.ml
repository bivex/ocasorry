open Executor_port

(** Infrastructure Adapter: ECMA-335 CIL Bytecode VM Executor *)
module Adapter : Executor_port.S = struct
  type handle = bytes

  let allocate_executable (code : bytes) : (handle, execution_error) result =
    Ok (Bytes.copy code)

  let run_fn1 (h : handle) (x0 : int64) : (int64, execution_error) result =
    match Cil_interpreter.execute h x0 0L with
    | Ok res -> Ok res
    | Error msg -> Error (ExecutionFault msg)

  let run_fn2 (h : handle) (x0 : int64) (x1 : int64) : (int64, execution_error) result =
    match Cil_interpreter.execute h x0 x1 with
    | Ok res -> Ok res
    | Error msg -> Error (ExecutionFault msg)

  let free (_h : handle) : unit = ()
end

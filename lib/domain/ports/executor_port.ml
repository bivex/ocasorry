type execution_error =
  | AllocationFailed of string
  | ProtectionFailed of string
  | ExecutionFault of string

(** Outbound port for JIT execution engines *)
module type S = sig
  type handle

  (** Allocates an executable buffer from machine code bytes and returns callable function *)
  val allocate_executable : bytes -> (handle, execution_error) result

  (** Executes a unary integer function f(x0) -> x0 *)
  val run_fn1 : handle -> int64 -> (int64, execution_error) result

  (** Executes a binary integer function f(x0, x1) -> x0 *)
  val run_fn2 : handle -> int64 -> int64 -> (int64, execution_error) result

  (** Frees JIT allocated page *)
  val free : handle -> unit
end

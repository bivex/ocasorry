(** Outbound port for entropy / randomness sources *)
module type S = sig
  val next_int : max:int -> int
  val next_int64 : unit -> int64
  val next_int32 : unit -> int32
  val choose : 'a list -> 'a
  val shuffle : 'a list -> 'a list
end

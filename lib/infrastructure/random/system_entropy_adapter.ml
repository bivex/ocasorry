(* Reseedable system entropy adapter.
   Default: self-initialized from OS entropy (unique per process).
   `seed n` switches to a deterministic PRNG stream — used by CLI --seed
   for reproducible synthesis. Functors consuming Entropy_port.S see only
   the port view, so the extra `seed` item causes no ripple. *)
module type Seeded = sig
  include Entropy_port.S

  val seed : int -> unit
end

module Adapter : Seeded = struct
  let state = ref (Random.State.make_self_init ())

  let seed (n : int) : unit = state := Random.State.make [| n |]

  let next_int ~max =
    if max <= 0 then 0 else Random.State.int !state max

  let next_int64 () =
    Random.State.int64 !state Int64.max_int

  let next_int32 () =
    Random.State.int32 !state Int32.max_int

  let choose list =
    match list with
    | [] -> failwith "choose: empty list"
    | [ x ] -> x
    | items ->
        let idx = next_int ~max:(List.length items) in
        List.nth items idx

  let shuffle list =
    let arr = Array.of_list list in
    let n = Array.length arr in
    for i = n - 1 downto 1 do
      let k = next_int ~max:(i + 1) in
      let temp = arr.(i) in
      arr.(i) <- arr.(k);
      arr.(k) <- temp
    done;
    Array.to_list arr
end

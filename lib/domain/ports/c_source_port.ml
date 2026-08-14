open GoblintCil.Cil

module type S = sig
  val parse_string : string -> file
  val parse_file : string -> file
  val emit_to_string : file -> string
  val emit_to_file : string -> file -> unit
end

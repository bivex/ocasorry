(** ECMA-335 Common Intermediate Language (CIL) Opcode Definitions *)

type cil_opcode =
  | Nop         (** 0x00 *)
  | Ldarg_0     (** 0x02 *)
  | Ldarg_1     (** 0x03 *)
  | Ldarg_2     (** 0x04 *)
  | Ldarg_3     (** 0x05 *)
  | Ldarg of int(** 0xFE 0x09 / 0x0E *)
  | Ldc_i4_0    (** 0x16 *)
  | Ldc_i4_1    (** 0x17 *)
  | Ldc_i4_2    (** 0x18 *)
  | Ldc_i4 of int32 (** 0x20 *)
  | Ldc_i8 of int64 (** 0x21 *)
  | Dup         (** 0x25 *)
  | Pop         (** 0x26 *)
  | Ret         (** 0x2A *)
  | Br of string    (** 0x38 (int32 target) *)
  | Br_s of string  (** 0x2B (int8 target) *)
  | Brfalse of string (** 0x39 *)
  | Brtrue of string  (** 0x3A *)
  | Beq of string     (** 0x3B *)
  | Bge of string     (** 0x3C *)
  | Bgt of string     (** 0x3D *)
  | Ble of string     (** 0x3E *)
  | Blt of string     (** 0x3F *)
  | Bne_un of string  (** 0x40 *)
  | Add         (** 0x58 *)
  | Sub         (** 0x59 *)
  | Mul         (** 0x5A *)
  | Div         (** 0x5B *)
  | And         (** 0x5F *)
  | Or          (** 0x60 *)
  | Xor         (** 0x61 *)
  | Shl         (** 0x62 *)
  | Shr         (** 0x63 *)
  | Neg         (** 0x65 *)
  | Not         (** 0x66 *)
  | Ceq         (** 0xFE 0x01 *)
  | Cgt         (** 0xFE 0x02 *)
  | Clt         (** 0xFE 0x04 *)

let opcode_to_bytes (op : cil_opcode) : int list =
  match op with
  | Nop -> [ 0x00 ]
  | Ldarg_0 -> [ 0x02 ]
  | Ldarg_1 -> [ 0x03 ]
  | Ldarg_2 -> [ 0x04 ]
  | Ldarg_3 -> [ 0x05 ]
  | Ldc_i4_0 -> [ 0x16 ]
  | Ldc_i4_1 -> [ 0x17 ]
  | Ldc_i4_2 -> [ 0x18 ]
  | Dup -> [ 0x25 ]
  | Pop -> [ 0x26 ]
  | Ret -> [ 0x2A ]
  | Add -> [ 0x58 ]
  | Sub -> [ 0x59 ]
  | Mul -> [ 0x5A ]
  | Div -> [ 0x5B ]
  | And -> [ 0x5F ]
  | Or  -> [ 0x60 ]
  | Xor -> [ 0x61 ]
  | Shl -> [ 0x62 ]
  | Shr -> [ 0x63 ]
  | Neg -> [ 0x65 ]
  | Not -> [ 0x66 ]
  | Ldarg _ | Ldc_i4 _ | Ldc_i8 _
  | Br _ | Br_s _ | Brfalse _ | Brtrue _
  | Beq _ | Bge _ | Bgt _ | Ble _ | Blt _ | Bne_un _
  | Ceq | Cgt | Clt -> []

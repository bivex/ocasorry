(** ECMA-335 Common Intermediate Language (CIL) Opcode Definitions *)

let nop_op    = 0x00
let ldloc     = 0x0E
let stloc     = 0x10
let ldc_i4    = 0x20
let ldc_i8    = 0x21
let pop_op    = 0x26
let ret_op    = 0x2A
let br_s      = 0x38
let beq_s     = 0x3B
let bge_s     = 0x3C
let bgt_s     = 0x3D
let ble_s     = 0x3E
let blt_s     = 0x3F
let bne_un_s  = 0x40
let bge_un_s  = 0x41
let blt_un_s  = 0x43
let add_op    = 0x58
let sub_op    = 0x59
let and_op    = 0x5F
let or_op     = 0x60
let xor_op    = 0x61
let shl_op    = 0x62
let shr_un_op = 0x64
let not_op    = 0x66
let conv_i8   = 0x68

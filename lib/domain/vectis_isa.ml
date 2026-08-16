(** Vectis Next Virtual ISA Specification
    Provides a rich, typed virtual instruction set architecture with
    virtual registers, condition flags, opaque state registers, and versioned headers.
*)

type vreg = int
type imm64 = int64

type voperand =
  | Reg of vreg
  | Imm of imm64
  | Mem of { base : vreg; offset : int64 }

type vcondition =
  | V_ALWAYS
  | V_EQ
  | V_NE
  | V_LT
  | V_LE
  | V_GT
  | V_GE
  | V_CARRY
  | V_OVERFLOW

type vflags = {
  mutable zf : bool;  (** Zero flag *)
  mutable nf : bool;  (** Negative / Sign flag *)
  mutable cf : bool;  (** Carry flag *)
  mutable vf : bool;  (** Overflow flag *)
}

let default_flags () : vflags = {
  zf = false;
  nf = false;
  cf = false;
  vf = false;
}

type vop =
  | OP_NOP
  | OP_MOV
  | OP_LOAD
  | OP_STORE
  | OP_ADD
  | OP_SUB
  | OP_MUL
  | OP_XOR
  | OP_AND
  | OP_OR
  | OP_SHL
  | OP_SHR
  | OP_ROL
  | OP_ROR
  | OP_CMP
  | OP_SELECT
  | OP_BRANCH
  | OP_CALL
  | OP_RET
  | OP_ENTER_NESTED
  | OP_EXIT_NESTED
  | OP_JIT_ESC

type vinstruction = {
  id       : int;
  op       : vop;
  dst      : voperand option;
  src1     : voperand option;
  src2     : voperand option;
  cond     : vcondition;
  metadata : int64;
}

type vprogram = {
  version      : int;
  arch_name    : string;
  reg_count    : int;
  instructions : vinstruction array;
}

(** Convert opcode to standard mnemonic string *)
let opcode_name = function
  | OP_NOP          -> "NOP"
  | OP_MOV          -> "MOV"
  | OP_LOAD         -> "LOAD"
  | OP_STORE        -> "STORE"
  | OP_ADD          -> "ADD"
  | OP_SUB          -> "SUB"
  | OP_MUL          -> "MUL"
  | OP_XOR          -> "XOR"
  | OP_AND          -> "AND"
  | OP_OR           -> "OR"
  | OP_SHL          -> "SHL"
  | OP_SHR          -> "SHR"
  | OP_ROL          -> "ROL"
  | OP_ROR          -> "ROR"
  | OP_CMP          -> "CMP"
  | OP_SELECT       -> "SELECT"
  | OP_BRANCH       -> "BRANCH"
  | OP_CALL         -> "CALL"
  | OP_RET          -> "RET"
  | OP_ENTER_NESTED  -> "ENTER_NESTED"
  | OP_EXIT_NESTED   -> "EXIT_NESTED"
  | OP_JIT_ESC      -> "JIT_ESC"

let condition_name = function
  | V_ALWAYS   -> ""
  | V_EQ       -> ".EQ"
  | V_NE       -> ".NE"
  | V_LT       -> ".LT"
  | V_LE       -> ".LE"
  | V_GT       -> ".GT"
  | V_GE       -> ".GE"
  | V_CARRY    -> ".CS"
  | V_OVERFLOW -> ".VS"

let operand_to_string = function
  | Reg r                  -> Printf.sprintf "V%d" r
  | Imm i                  -> Printf.sprintf "0x%LX" i
  | Mem { base; offset }   ->
      if offset = 0L then Printf.sprintf "[V%d]" base
      else Printf.sprintf "[V%d + 0x%LX]" base offset

let disasm_instruction (insn : vinstruction) : string =
  let cond_str = condition_name insn.cond in
  let op_str = opcode_name insn.op ^ cond_str in
  let args =
    [ insn.dst; insn.src1; insn.src2 ]
    |> List.filter_map (Option.map operand_to_string)
    |> String.concat ", "
  in
  if args = "" then Printf.sprintf "%04d:  %-16s" insn.id op_str
  else Printf.sprintf "%04d:  %-16s %s" insn.id op_str args

let disasm_program (prog : vprogram) : string =
  let header = Printf.sprintf "; Vectis vISA Disassembly (v%d, %s, %d regs, %d insns)\n"
    prog.version prog.arch_name prog.reg_count (Array.length prog.instructions)
  in
  let lines = Array.map disasm_instruction prog.instructions in
  header ^ (String.concat "\n" (Array.to_list lines)) ^ "\n"

(** Helper builder functions *)
let make_insn ?(cond=V_ALWAYS) ?(meta=0L) id op dst src1 src2 =
  { id; op; dst; src1; src2; cond; metadata = meta }

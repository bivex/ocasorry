open Types

(** AArch64 Machine Instructions AST *)
type instruction =
  | MovReg of reg * reg                (** mov Xd, Xm (implemented as orr Xd, xzr, Xm) *)
  | MovImm of reg * int64              (** mov Xd, #imm (MOVZ / MOVK sequence) *)
  | Add of reg * reg * reg             (** add Xd, Xn, Xm *)
  | AddImm of reg * reg * int          (** add Xd, Xn, #imm12 *)
  | Sub of reg * reg * reg             (** sub Xd, Xn, Xm *)
  | SubImm of reg * reg * int          (** sub Xd, Xn, #imm12 *)
  | And of reg * reg * reg             (** and Xd, Xn, Xm *)
  | Orr of reg * reg * reg             (** orr Xd, Xn, Xm *)
  | Eor of reg * reg * reg             (** eor Xd, Xn, Xm *)
  | Mvn of reg * reg                   (** mvn Xd, Xm (orn Xd, xzr, Xm) *)
  | Lsl of reg * reg * int             (** lsl Xd, Xn, #shift (ubfm) *)
  | Lsr of reg * reg * int             (** lsr Xd, Xn, #shift (ubfm) *)
  | Cmp of reg * reg                   (** cmp Xn, Xm (subs xzr, Xn, Xm) *)
  | CmpImm of reg * int                (** cmp Xn, #imm (subs xzr, Xn, #imm) *)
  | B of label                         (** b label *)
  | Bcc of condition * label           (** b.cond label *)
  | Ret of reg option                  (** ret Xn (defaults to x30) *)
  | Nop                                (** nop *)
  | Raw32 of int32                     (** raw 32-bit machine instruction / junk *)

let pp_instruction fmt = function
  | MovReg (d, m) -> Format.fprintf fmt "mov %s, %s" (reg_name d) (reg_name m)
  | MovImm (d, imm) -> Format.fprintf fmt "movz/k %s, #%Ld" (reg_name d) imm
  | Add (d, n, m) -> Format.fprintf fmt "add %s, %s, %s" (reg_name d) (reg_name n) (reg_name m)
  | AddImm (d, n, imm) -> Format.fprintf fmt "add %s, %s, #%d" (reg_name d) (reg_name n) imm
  | Sub (d, n, m) -> Format.fprintf fmt "sub %s, %s, %s" (reg_name d) (reg_name n) (reg_name m)
  | SubImm (d, n, imm) -> Format.fprintf fmt "sub %s, %s, #%d" (reg_name d) (reg_name n) imm
  | And (d, n, m) -> Format.fprintf fmt "and %s, %s, %s" (reg_name d) (reg_name n) (reg_name m)
  | Orr (d, n, m) -> Format.fprintf fmt "orr %s, %s, %s" (reg_name d) (reg_name n) (reg_name m)
  | Eor (d, n, m) -> Format.fprintf fmt "eor %s, %s, %s" (reg_name d) (reg_name n) (reg_name m)
  | Mvn (d, m) -> Format.fprintf fmt "mvn %s, %s" (reg_name d) (reg_name m)
  | Lsl (d, n, s) -> Format.fprintf fmt "lsl %s, %s, #%d" (reg_name d) (reg_name n) s
  | Lsr (d, n, s) -> Format.fprintf fmt "lsr %s, %s, #%d" (reg_name d) (reg_name n) s
  | Cmp (n, m) -> Format.fprintf fmt "cmp %s, %s" (reg_name n) (reg_name m)
  | CmpImm (n, imm) -> Format.fprintf fmt "cmp %s, #%d" (reg_name n) imm
  | B l -> Format.fprintf fmt "b %s" l
  | Bcc (c, l) -> Format.fprintf fmt "b.%d %s" (cond_to_code c) l
  | Ret None -> Format.fprintf fmt "ret"
  | Ret (Some r) -> Format.fprintf fmt "ret %s" (reg_name r)
  | Nop -> Format.fprintf fmt "nop"
  | Raw32 w -> Format.fprintf fmt ".inst 0x%08lx" w

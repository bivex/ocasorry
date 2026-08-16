(** Vectis Next Canonical Intermediate Representation (IR)
    Provides a strongly-typed, immutable representation of expressions and statements
    used by the E-Graph, Neural Rewriter, and Virtualizer.
*)

type ir_typ =
  | I1
  | I8
  | I16
  | I32
  | I64
  | Pointer of ir_typ

type ir_binop =
  | Add
  | Sub
  | Mul
  | Div
  | Mod
  | Xor
  | And
  | Or
  | Shl
  | Shr
  | Rol
  | Ror
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge

type ir_unop =
  | Neg
  | Not
  | Bswap

type ir_exp =
  | Const of int64 * ir_typ
  | Var of string * ir_typ
  | BinOp of ir_binop * ir_exp * ir_exp * ir_typ
  | UnOp of ir_unop * ir_exp * ir_typ
  | Select of ir_exp * ir_exp * ir_exp * ir_typ  (** condition, if_true, if_false *)
  | Cast of ir_typ * ir_exp

let exp_type = function

  | Const (_, t) -> t
  | Var (_, t) -> t
  | BinOp (_, _, _, t) -> t
  | UnOp (_, _, t) -> t
  | Select (_, _, _, t) -> t
  | Cast (t, _) -> t

let rec exp_size = function
  | Const _ | Var _ -> 1
  | UnOp (_, e, _) | Cast (_, e) -> 1 + exp_size e
  | BinOp (_, e1, e2, _) -> 1 + exp_size e1 + exp_size e2
  | Select (c, e1, e2, _) -> 1 + exp_size c + exp_size e1 + exp_size e2

let rec exp_depth = function
  | Const _ | Var _ -> 1
  | UnOp (_, e, _) | Cast (_, e) -> 1 + exp_depth e
  | BinOp (_, e1, e2, _) -> 1 + max (exp_depth e1) (exp_depth e2)
  | Select (c, e1, e2, _) -> 1 + max (exp_depth c) (max (exp_depth e1) (exp_depth e2))

let binop_to_string = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Xor -> "^"
  | And -> "&"
  | Or  -> "|"
  | Shl -> "<<"
  | Shr -> ">>"
  | Rol -> "rol"
  | Ror -> "ror"
  | Eq  -> "=="
  | Ne  -> "!="
  | Lt  -> "<"
  | Le  -> "<="
  | Gt  -> ">"
  | Ge  -> ">="

let unop_to_string = function
  | Neg -> "-"
  | Not -> "~"
  | Bswap -> "bswap"

let rec to_string = function
  | Const (v, _) -> Printf.sprintf "%Ld" v
  | Var (name, _) -> name
  | UnOp (op, e, _) -> Printf.sprintf "(%s%s)" (unop_to_string op) (to_string e)
  | BinOp (op, e1, e2, _) ->
      Printf.sprintf "(%s %s %s)" (to_string e1) (binop_to_string op) (to_string e2)
  | Select (c, e1, e2, _) ->
      Printf.sprintf "(%s ? %s : %s)" (to_string c) (to_string e1) (to_string e2)
  | Cast (_, e) -> Printf.sprintf "(cast %s)" (to_string e)

(** Evaluate IR expression with a variable environment map *)
let rec eval (env : (string, int64) Hashtbl.t) (e : ir_exp) : int64 =
  match e with
  | Const (v, _) -> v
  | Var (name, _) ->
      Hashtbl.find_opt env name |> Option.value ~default:0L
  | UnOp (Neg, e1, _) -> Int64.neg (eval env e1)
  | UnOp (Not, e1, _) -> Int64.lognot (eval env e1)
  | UnOp (Bswap, e1, _) ->
      let v = eval env e1 in
      (* Simple 64-bit byte swap *)
      let b0 = Int64.logand v 0xFFL in
      let b1 = Int64.logand (Int64.shift_right_logical v 8) 0xFFL in
      let b2 = Int64.logand (Int64.shift_right_logical v 16) 0xFFL in
      let b3 = Int64.logand (Int64.shift_right_logical v 24) 0xFFL in
      let b4 = Int64.logand (Int64.shift_right_logical v 32) 0xFFL in
      let b5 = Int64.logand (Int64.shift_right_logical v 40) 0xFFL in
      let b6 = Int64.logand (Int64.shift_right_logical v 48) 0xFFL in
      let b7 = Int64.logand (Int64.shift_right_logical v 56) 0xFFL in
      Int64.logor (Int64.shift_left b0 56)
        (Int64.logor (Int64.shift_left b1 48)
          (Int64.logor (Int64.shift_left b2 40)
            (Int64.logor (Int64.shift_left b3 32)
              (Int64.logor (Int64.shift_left b4 24)
                (Int64.logor (Int64.shift_left b5 16)
                  (Int64.logor (Int64.shift_left b6 8) b7))))))
  | BinOp (Add, e1, e2, _) -> Int64.add (eval env e1) (eval env e2)
  | BinOp (Sub, e1, e2, _) -> Int64.sub (eval env e1) (eval env e2)
  | BinOp (Mul, e1, e2, _) -> Int64.mul (eval env e1) (eval env e2)
  | BinOp (Div, e1, e2, _) ->
      let v2 = eval env e2 in
      if v2 = 0L then 0L else Int64.div (eval env e1) v2
  | BinOp (Mod, e1, e2, _) ->
      let v2 = eval env e2 in
      if v2 = 0L then 0L else Int64.rem (eval env e1) v2
  | BinOp (Xor, e1, e2, _) -> Int64.logxor (eval env e1) (eval env e2)
  | BinOp (And, e1, e2, _) -> Int64.logand (eval env e1) (eval env e2)
  | BinOp (Or, e1, e2, _)  -> Int64.logor (eval env e1) (eval env e2)
  | BinOp (Shl, e1, e2, _) ->
      let sh = Int64.to_int (Int64.logand (eval env e2) 0x3FL) in
      Int64.shift_left (eval env e1) sh
  | BinOp (Shr, e1, e2, _) ->
      let sh = Int64.to_int (Int64.logand (eval env e2) 0x3FL) in
      Int64.shift_right_logical (eval env e1) sh
  | BinOp (Rol, e1, e2, _) ->
      let v1 = eval env e1 in
      let sh = Int64.to_int (Int64.logand (eval env e2) 0x3FL) in
      Int64.logor (Int64.shift_left v1 sh) (Int64.shift_right_logical v1 (64 - sh))
  | BinOp (Ror, e1, e2, _) ->
      let v1 = eval env e1 in
      let sh = Int64.to_int (Int64.logand (eval env e2) 0x3FL) in
      Int64.logor (Int64.shift_right_logical v1 sh) (Int64.shift_left v1 (64 - sh))
  | BinOp (Eq, e1, e2, _) -> if eval env e1 = eval env e2 then 1L else 0L
  | BinOp (Ne, e1, e2, _) -> if eval env e1 <> eval env e2 then 1L else 0L
  | BinOp (Lt, e1, e2, _) -> if eval env e1 < eval env e2 then 1L else 0L
  | BinOp (Le, e1, e2, _) -> if eval env e1 <= eval env e2 then 1L else 0L
  | BinOp (Gt, e1, e2, _) -> if eval env e1 > eval env e2 then 1L else 0L
  | BinOp (Ge, e1, e2, _) -> if eval env e1 >= eval env e2 then 1L else 0L
  | Select (c, e1, e2, _) ->
      if eval env c <> 0L then eval env e1 else eval env e2
  | Cast (_, e1) -> eval env e1

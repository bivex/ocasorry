open Vectis_lib
open Types
open Ast
open Cfg

let build_sample_cfg () : CFG.t =
  let block1 =
    BasicBlock.create
      ~id:"block_entry"
      ~instructions:[
        Add (X0, X0, X1);
        MovImm (X2, 0x5A5AL);
        B "block_finish";
      ]
  in
  let block2 =
    BasicBlock.create
      ~id:"block_finish"
      ~instructions:[
        Eor (X0, X0, X2);
        Ret None;
      ]
  in
  CFG.create ~entry:"block_entry" ~blocks:[ block1; block2 ]

let print_hex_dump (b : bytes) =
  let len = Bytes.length b in
  Printf.printf "  Size: %d bytes\n  Hex: " len;
  for i = 0 to len - 1 do
    Printf.printf "%02x " (Char.code (Bytes.get b i));
    if (i + 1) mod 16 = 0 && i + 1 < len then Printf.printf "\n       "
  done;
  Printf.printf "\n%!"

let sample_c_program = {|
extern int printf(const char *format, ...);

int compute(int x, int y) {
    if (x > y) {
        printf("Branch A: x is greater!\n");
    } else {
        printf("Branch B: y is greater or equal!\n");
    }
    int sum = x + y;
    int res = sum ^ 0x5A5A;
    return res;
}
|}

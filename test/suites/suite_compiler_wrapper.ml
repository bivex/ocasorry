open Helpers

let run () =
  Printf.printf "\n--- [Suite 7] Compiler Wrapper (ocasorry-cc) CLI Integration ---\n%!";

  let wrapper_bin =
    match find_wrapper_bin () with
    | Some p -> p
    | None -> failwith "Could not locate built ocasorry_cc.exe executable"
  in
  assert_bool "ocasorry-cc compiler wrapper binary found" (Sys.file_exists wrapper_bin);

  let src_file = Filename.temp_file "wrapper_test_" ".c" in
  let out_bin = Filename.temp_file "wrapper_out_" ".bin" in
  let oc = open_out src_file in
  output_string oc {|
extern int printf(const char *format, ...);

int multiply_and_offset(int x) {
    int factor = 7;
    int offset = 100;
    return x * factor + offset;
}

int main() {
    printf("%d\n", multiply_and_offset(5));
    return 0;
}
|};
  close_out oc;

  let cmd = Printf.sprintf "%s -w %s -o %s" (Filename.quote wrapper_bin) (Filename.quote src_file) (Filename.quote out_bin) in
  let res = Sys.command cmd in
  assert_bool "Compilation with ocasorry-cc succeeded" (res = 0);

  let ic = Unix.open_process_in out_bin in
  let out_val = input_line ic in
  ignore (Unix.close_process_in ic);

  assert_bool "ocasorry-cc compiled binary output == 135" (int_of_string (String.trim out_val) = 135);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove out_bin with _ -> ())

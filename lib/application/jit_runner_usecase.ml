open Cfg

type execution_result = {
  raw_bytes : bytes;
  result_val : int64;
}

module Make
    (Entropy : Entropy_port.S)
    (Encoder : Encoder_port.S)
    (Executor : Executor_port.S) =
struct
  module Pipeline = Obfuscation_pipeline.Make (Entropy)

  let obfuscate_and_run_fn1 (cfg : CFG.t) (arg : int64) (config : Obfuscation_pipeline.pipeline_config) : (execution_result, string) result =
    let obfuscated_cfg = Pipeline.run cfg config in
    match Encoder.encode_cfg obfuscated_cfg with
    | Error msg -> Error ("Encoding failed: " ^ msg)
    | Ok raw_bytes ->
        match Executor.allocate_executable raw_bytes with
        | Error (Executor_port.AllocationFailed err) -> Error ("Allocation failed: " ^ err)
        | Error (Executor_port.ProtectionFailed err) -> Error ("Protection failed: " ^ err)
        | Error (Executor_port.ExecutionFault err) -> Error ("Fault: " ^ err)
        | Ok handle ->
            let res = Executor.run_fn1 handle arg in
            Executor.free handle;
            match res with
            | Ok v -> Ok { raw_bytes; result_val = v }
            | Error (Executor_port.ExecutionFault err) -> Error ("Execution fault: " ^ err)
            | Error _ -> Error "Unknown execution error"

  let obfuscate_and_run_fn2 (cfg : CFG.t) (arg1 : int64) (arg2 : int64) (config : Obfuscation_pipeline.pipeline_config) : (execution_result, string) result =
    let obfuscated_cfg = Pipeline.run cfg config in
    match Encoder.encode_cfg obfuscated_cfg with
    | Error msg -> Error ("Encoding failed: " ^ msg)
    | Ok raw_bytes ->
        match Executor.allocate_executable raw_bytes with
        | Error (Executor_port.AllocationFailed err) -> Error ("Allocation failed: " ^ err)
        | Error (Executor_port.ProtectionFailed err) -> Error ("Protection failed: " ^ err)
        | Error (Executor_port.ExecutionFault err) -> Error ("Fault: " ^ err)
        | Ok handle ->
            let res = Executor.run_fn2 handle arg1 arg2 in
            Executor.free handle;
            match res with
            | Ok v -> Ok { raw_bytes; result_val = v }
            | Error (Executor_port.ExecutionFault err) -> Error ("Execution fault: " ^ err)
            | Error _ -> Error "Unknown execution error"
end

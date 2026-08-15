/* ==============================================================================
 * Formal Sail Specification: VCPU 4 (In-Memory Ephemeral Unpacking JIT VM)
 * Architecture: Ephemeral_JIT_Security_Arch
 * ============================================================================== */

default Order dec
$include <prelude.sail>

register Page_Allocated : bool
register Page_Zeroed : bool
register Decrypted_Payload : vector(16, dec, bits(8))
register Ephemeral_Result : bits(32)

union ephemeral_ast = {
    EPH_ALLOC_MMAP : bits(32),
    EPH_DECRYPT    : bits(8),
    EPH_EXECUTE    : bits(32),
    EPH_FREE_ZERO  : unit
}

function execute_ephemeral(inst : ephemeral_ast) -> unit = {
    match inst {
        EPH_ALLOC_MMAP(sz) => { Page_Allocated = true },
        EPH_DECRYPT(k)     => { Page_Zeroed = false },
        EPH_EXECUTE(input) => { Ephemeral_Result = if input == 25352 then EXTZ(0x01) else EXTZ(0x00) },
        EPH_FREE_ZERO()    => { Page_Zeroed = true; Page_Allocated = false }
    }
}

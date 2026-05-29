
#[no_mangle]
pub unsafe extern "C" fn isar_plus_web_persistence_start(_dir: *mut String) -> u32 {
    0
}

#[no_mangle]
pub extern "C" fn isar_plus_web_persistence_poll(_handle: u32) -> u8 {
    1
}

#[no_mangle]
pub extern "C" fn isar_plus_web_persistence_backend() -> u8 {
    0
}

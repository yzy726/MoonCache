///|
#borrow(path)
extern "C" fn file_store_mkdirs_ffi(path : Bytes) -> Int = "mooncache_file_store_mkdirs"

///|
#borrow(final_path, temp_dir, prefix, content)
extern "C" fn file_store_atomic_write_ffi(
  final_path : Bytes,
  temp_dir : Bytes,
  prefix : Bytes,
  content : Bytes,
  content_length : Int,
) -> Int = "mooncache_file_store_atomic_write"

///|
#borrow(source, destination)
extern "C" fn file_store_replace_ffi(
  source : Bytes,
  destination : Bytes,
) -> Int = "mooncache_file_store_replace"

///|
extern "C" fn file_store_error_ffi() -> Bytes = "mooncache_file_store_error"

///|
fn native_path(value : String) -> Bytes {
  let encoded = @utf8.encode(value)
  Bytes::makei(encoded.length() + 1, fn(index) {
    if index < encoded.length() {
      encoded[index]
    } else {
      b'\x00'
    }
  })
}

///|
fn native_text(value : String) -> Bytes {
  @utf8.encode(value)
}

///|
fn native_error_message() -> String {
  @utf8.decode_lossy(file_store_error_ffi())
}

///|
fn native_mkdirs(path : String) -> Unit raise FileStoreError {
  guard file_store_mkdirs_ffi(native_path(path)) == 0 else {
    raise FileStoreIo(native_error_message())
  }
}

///|
fn native_atomic_write(
  final_path : String,
  temp_dir : String,
  prefix : String,
  content : Bytes,
) -> Unit raise FileStoreError {
  let status = file_store_atomic_write_ffi(
    native_path(final_path),
    native_path(temp_dir),
    native_path(prefix),
    content,
    content.length(),
  )
  guard status == 0 else { raise FileStoreIo(native_error_message()) }
}

///|
fn native_replace(
  source : String,
  destination : String,
) -> Unit raise FileStoreError {
  let status = file_store_replace_ffi(
    native_path(source),
    native_path(destination),
  )
  guard status == 0 else { raise FileStoreIo(native_error_message()) }
}

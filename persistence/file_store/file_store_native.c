// Copyright 2026 MoonCache contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

#include "moonbit.h"

static char mooncache_file_store_last_error[512] = "";

static void mooncache_file_store_set_error(const char *operation,
                                           const char *path) {
#ifdef _WIN32
  DWORD code = GetLastError();
  char system_message[256] = "";
  FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                 NULL, code, 0, system_message,
                 (DWORD)sizeof(system_message), NULL);
  snprintf(mooncache_file_store_last_error,
           sizeof(mooncache_file_store_last_error),
           "%s failed for %s (Windows error %lu: %s)", operation, path,
           (unsigned long)code, system_message);
#else
  snprintf(mooncache_file_store_last_error,
           sizeof(mooncache_file_store_last_error), "%s failed for %s: %s",
           operation, path, strerror(errno));
#endif
}

static int mooncache_file_store_make_one_dir(const char *path) {
#ifdef _WIN32
  if (_mkdir(path) == 0 || errno == EEXIST) {
    return 0;
  }
#else
  if (mkdir(path, 0777) == 0 || errno == EEXIST) {
    return 0;
  }
#endif
  mooncache_file_store_set_error("mkdir", path);
  return -1;
}

MOONBIT_FFI_EXPORT int
mooncache_file_store_mkdirs(moonbit_bytes_t path_bytes) {
  const char *path = (const char *)path_bytes;
  size_t length = strlen(path);
  if (length == 0) {
    snprintf(mooncache_file_store_last_error,
             sizeof(mooncache_file_store_last_error),
             "cache directory path is empty");
    return -1;
  }
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    snprintf(mooncache_file_store_last_error,
             sizeof(mooncache_file_store_last_error),
             "out of memory while creating cache directories");
    return -1;
  }
  memcpy(copy, path, length + 1);
  for (size_t index = 1; index < length; index++) {
    if (copy[index] != '/' && copy[index] != '\\') {
      continue;
    }
#ifdef _WIN32
    if (index == 2 && copy[1] == ':') {
      continue;
    }
#endif
    char separator = copy[index];
    copy[index] = '\0';
    if (copy[0] != '\0' && mooncache_file_store_make_one_dir(copy) != 0) {
      free(copy);
      return -1;
    }
    copy[index] = separator;
  }
  int result = mooncache_file_store_make_one_dir(copy);
  free(copy);
  return result;
}

static uint64_t mooncache_file_store_next_nonce(void) {
#ifdef _WIN32
  static volatile LONG64 counter = 0;
  return (uint64_t)InterlockedIncrement64(&counter);
#else
  static uint64_t counter = 0;
  return __sync_add_and_fetch(&counter, 1);
#endif
}

static int mooncache_file_store_sync_file(FILE *file, const char *path) {
  if (fflush(file) != 0) {
    mooncache_file_store_set_error("fflush", path);
    return -1;
  }
#ifdef _WIN32
  if (_commit(_fileno(file)) != 0) {
    mooncache_file_store_set_error("_commit", path);
    return -1;
  }
#else
  if (fsync(fileno(file)) != 0) {
    mooncache_file_store_set_error("fsync", path);
    return -1;
  }
#endif
  return 0;
}

static int mooncache_file_store_replace_paths(const char *source,
                                              const char *destination) {
#ifdef _WIN32
  if (MoveFileExA(source, destination,
                  MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return 0;
  }
  mooncache_file_store_set_error("MoveFileEx", destination);
  return -1;
#else
  if (rename(source, destination) == 0) {
    return 0;
  }
  mooncache_file_store_set_error("rename", destination);
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int mooncache_file_store_replace(
    moonbit_bytes_t source_bytes, moonbit_bytes_t destination_bytes) {
  return mooncache_file_store_replace_paths((const char *)source_bytes,
                                            (const char *)destination_bytes);
}

MOONBIT_FFI_EXPORT int mooncache_file_store_atomic_write(
    moonbit_bytes_t final_path_bytes, moonbit_bytes_t temp_dir_bytes,
    moonbit_bytes_t prefix_bytes, moonbit_bytes_t content,
    int32_t content_length) {
  const char *final_path = (const char *)final_path_bytes;
  const char *temp_dir = (const char *)temp_dir_bytes;
  const char *prefix = (const char *)prefix_bytes;
#ifdef _WIN32
  int process_id = _getpid();
  const char separator = '\\';
#else
  int process_id = (int)getpid();
  const char separator = '/';
#endif
  uint64_t nonce = mooncache_file_store_next_nonce();
  size_t needed = strlen(temp_dir) + strlen(prefix) + 96;
  char *temp_path = (char *)malloc(needed);
  if (temp_path == NULL) {
    snprintf(mooncache_file_store_last_error,
             sizeof(mooncache_file_store_last_error),
             "out of memory while allocating temporary cache path");
    return -1;
  }
  snprintf(temp_path, needed, "%s%c%s.%d.%llu.tmp", temp_dir, separator,
           prefix, process_id, (unsigned long long)nonce);
  FILE *file = fopen(temp_path, "wb");
  if (file == NULL) {
    mooncache_file_store_set_error("fopen", temp_path);
    free(temp_path);
    return -1;
  }
  size_t written =
      fwrite(content, 1, (size_t)content_length, file);
  if (written != (size_t)content_length) {
    mooncache_file_store_set_error("fwrite", temp_path);
    fclose(file);
    remove(temp_path);
    free(temp_path);
    return -1;
  }
  if (mooncache_file_store_sync_file(file, temp_path) != 0) {
    fclose(file);
    remove(temp_path);
    free(temp_path);
    return -1;
  }
  if (fclose(file) != 0) {
    mooncache_file_store_set_error("fclose", temp_path);
    remove(temp_path);
    free(temp_path);
    return -1;
  }
  int result = mooncache_file_store_replace_paths(temp_path, final_path);
  if (result != 0) {
    remove(temp_path);
  }
  free(temp_path);
  return result;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mooncache_file_store_error(void) {
  size_t length = strlen(mooncache_file_store_last_error);
  moonbit_bytes_t bytes = moonbit_make_bytes(length, 0);
  memcpy(bytes, mooncache_file_store_last_error, length);
  return bytes;
}

#ifdef __cplusplus
}
#endif

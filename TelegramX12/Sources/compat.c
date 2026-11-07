/*
 * Compat shim for the prebuilt TDLib static framework.
 *
 * TDLibFramework's BoringSSL was compiled against a newer iOS SDK and
 * references ___darwin_check_fd_set_overflow, which only exists in the
 * system C library starting with iOS 13. iOS 12 does not export it, so we
 * provide a small equivalent here.
 */
#include <stddef.h>

int __darwin_check_fd_set_overflow(int fd, const void *set, int set_size) {
    if (fd < 0 || set == NULL) {
        return 0;
    }
    return fd < set_size * 8;
}

// Read-only MTP bridge. Device writes and deletes are deliberately not exposed.
#import <Foundation/Foundation.h>
#include <libmtp.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

static uint32_t number(const char *value) {
  if (!value || !*value) @throw @"invalidRequest";
  for (const char *p = value; *p; p++) if (*p < '0' || *p > '9') @throw @"invalidRequest";
  errno = 0;
  unsigned long long result = strtoull(value, NULL, 10);
  if (errno || result > UINT32_MAX) @throw @"invalidRequest";
  return (uint32_t)result;
}
static NSString *text(const char *value) {
  return value ? [NSString stringWithUTF8String:value] ?: @"MTP" : @"MTP";
}
static NSString *token(LIBMTP_raw_device_t *raw) {
  return [NSString stringWithFormat:@"%u-%u-%u-%u", raw->bus_location, raw->devnum,
    raw->device_entry.vendor_id, raw->device_entry.product_id];
}
static void freeFiles(LIBMTP_file_t *file) {
  while (file) { LIBMTP_file_t *next = file->next; LIBMTP_destroy_file_t(file); file = next; }
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    int jsonOutput = dup(STDOUT_FILENO);
    dup2(STDERR_FILENO, STDOUT_FILENO); // libmtp diagnostics must not corrupt JSON.
    LIBMTP_raw_device_t *raw = NULL;
    int count = 0;
    LIBMTP_mtpdevice_t *device = NULL;
    id response = nil;
    int result = 0;
    @try {
      if (argc < 2) @throw @"invalidRequest";
      NSString *operation = text(argv[1]);
      if (![operation isEqual:@"devices"] && ![operation isEqual:@"storages"] &&
          ![operation isEqual:@"list"] && ![operation isEqual:@"get"]) @throw @"invalidRequest";
      LIBMTP_Init();
      LIBMTP_error_number_t detected = LIBMTP_Detect_Raw_Devices(&raw, &count);
      if (detected != LIBMTP_ERROR_NONE && detected != LIBMTP_ERROR_NO_DEVICE_ATTACHED) @throw @"usbUnavailable";
      if ([operation isEqual:@"devices"]) {
        if (argc != 2) @throw @"invalidRequest";
        NSMutableArray *devices = [NSMutableArray array];
        for (int i = 0; i < count && i < 64; i++) {
          [devices addObject:@{@"id":token(&raw[i]), @"name":text(raw[i].device_entry.product)}];
        }
        response = devices;
      } else {
        if (argc < 3) @throw @"invalidRequest";
        NSString *requested = text(argv[2]);
        for (int i = 0; i < count; i++) {
          if ([token(&raw[i]) isEqual:requested]) {
            device = LIBMTP_Open_Raw_Device_Uncached(&raw[i]); break;
          }
        }
        if (!device) @throw @"deviceUnavailable";
        LIBMTP_Clear_Errorstack(device);
        if ([operation isEqual:@"storages"]) {
          if (argc != 3) @throw @"invalidRequest";
          if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) @throw @"storageUnavailable";
          NSMutableArray *storages = [NSMutableArray array];
          for (LIBMTP_devicestorage_t *s = device->storage; s; s = s->next) {
            [storages addObject:@{@"id":@(s->id), @"name":text(s->StorageDescription)}];
          }
          response = storages;
        } else if ([operation isEqual:@"list"]) {
          if (argc != 5) @throw @"invalidRequest";
          uint32_t storage = number(argv[3]), parent = number(argv[4]);
          LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(device, storage, parent);
          if (LIBMTP_Get_Errorstack(device)) { freeFiles(files); @throw @"readUnavailable"; }
          NSMutableArray *items = [NSMutableArray array];
          for (LIBMTP_file_t *file = files; file; file = file->next) {
            if (items.count >= 100000) { freeFiles(files); @throw @"tooManyItems"; }
            [items addObject:@{@"id":@(file->item_id), @"name":text(file->filename),
              @"directory":@(file->filetype == LIBMTP_FILETYPE_FOLDER), @"size":@(file->filesize)}];
          }
          freeFiles(files); response = items;
        } else {
          if (argc != 6) @throw @"invalidRequest";
          uint32_t storage = number(argv[3]), object = number(argv[4]);
          LIBMTP_file_t *file = LIBMTP_Get_Filemetadata(device, object);
          if (!file) @throw @"readUnavailable";
          BOOL valid = file->storage_id == storage && file->filetype != LIBMTP_FILETYPE_FOLDER;
          uint64_t expectedSize = file->filesize;
          LIBMTP_destroy_file_t(file);
          if (!valid) @throw @"readUnavailable";
          int fd = open(argv[5], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
          if (fd < 0) @throw @"destinationUnavailable";
          int copied = LIBMTP_Get_File_To_File_Descriptor(device, object, fd, NULL, NULL);
          struct stat info;
          BOOL complete = copied == 0 && fstat(fd, &info) == 0 && (uint64_t)info.st_size == expectedSize && fsync(fd) == 0;
          close(fd);
          if (!complete) { unlink(argv[5]); @throw @"readUnavailable"; }
          response = @{@"bytes":@(expectedSize)};
        }
      }
    } @catch (NSString *error) {
      response = @{@"error":error}; result = 1;
    }
    if (device) LIBMTP_Release_Device(device);
    free(raw);
    NSData *data = [NSJSONSerialization dataWithJSONObject:response ?: @[] options:0 error:nil];
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining) {
      ssize_t written = write(jsonOutput, bytes, remaining);
      if (written < 0 && errno == EINTR) continue;
      if (written <= 0) { result = 1; break; }
      bytes += written; remaining -= written;
    }
    close(jsonOutput);
    return result;
  }
}

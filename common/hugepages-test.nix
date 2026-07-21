let
  pageSizeKiB = 2048;
  pageSizeBytes = pageSizeKiB * 1024;
  calculate =
    sharedMemorySegmentsBytes:
    (import ./hugepages.nix {
      kernelRelease = "7.0.0";
      hugePageSizeKiB = pageSizeKiB;
      inherit sharedMemorySegmentsBytes;
    }).nrHugepages;
in
assert calculate [ ] == 1;
assert calculate [ 0 ] == 1;
assert calculate [ 1 ] == 2;
assert calculate [ pageSizeBytes ] == 2;
assert calculate [ (pageSizeBytes + 1) ] == 3;
true

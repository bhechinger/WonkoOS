{
  kernelRelease,
  hugePageSizeKiB,
  sharedMemorySegmentsBytes ? [ ],
}:

let
  kernelVersion = builtins.match "([0-9]+)\\.([0-9]+).*" kernelRelease;

  kernelMajorMinor =
    if kernelVersion == null then
      throw "kernelRelease must start with a major.minor version, got ${kernelRelease}"
    else
      "${builtins.elemAt kernelVersion 0}.${builtins.elemAt kernelVersion 1}";

  hugePageSizeBytes = hugePageSizeKiB * 1024;

  pagesForSegment =
    segmentBytes:
    let
      minPages = builtins.div segmentBytes hugePageSizeBytes;
    in
    if minPages > 0 then minPages + 1 else 0;

  nrHugepages =
    1
    + builtins.foldl' (
      total: segmentBytes: total + pagesForSegment segmentBytes
    ) 0 sharedMemorySegmentsBytes;

  isLinux24 = kernelMajorMinor == "2.4";
  settingName = if isLinux24 then "vm.hugetlb_pool" else "vm.nr_hugepages";
  settingValue = if isLinux24 then builtins.div (nrHugepages * hugePageSizeKiB) 1024 else nrHugepages;
in
{
  inherit
    kernelRelease
    kernelMajorMinor
    hugePageSizeKiB
    hugePageSizeBytes
    sharedMemorySegmentsBytes
    nrHugepages
    ;

  recommendedSetting = {
    name = settingName;
    value = settingValue;
  };

  sysctl = {
    "${settingName}" = settingValue;
  };

  message = "Recommended setting: ${settingName} = ${toString settingValue}";
}

#ifndef BuildInfo_h
#define BuildInfo_h
// 由 CI 在编译前覆盖为真实提交哈希；本地编译用 local
#ifndef kBuildSHA
#define kBuildSHA @"local"
#endif
#endif

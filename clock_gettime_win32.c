// Including the missing function clock_gettime from Zig's minGW
// REMOVE once Zig includes it
#include <windows.h>

#include <time.h>

int clock_gettime(int clk_id, struct timespec *spec)
{
    __int64 wintime; GetSystemTimeAsFileTime((FILETIME*)&wintime);
    wintime      -= 116444736000000000ull;           //1jan1601 to 1jan1970
    spec->tv_sec  = wintime / 10000000ull;           //seconds
    spec->tv_nsec = wintime % 10000000ull *100;      //nano-seconds
    return 0;
}

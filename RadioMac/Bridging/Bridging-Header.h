// Swift/Objective-C bridge for the BASS audio library (un4seen).
// The real `bass_fx.h` collides with Objective-C `BOOL`, so only the
// minimal peak-EQ shim is imported on top of `bass.h`.
#import "../../ThirdParty/BASS/bass.h"
#import "../../ThirdParty/BASS/bass_fx_shim.h"

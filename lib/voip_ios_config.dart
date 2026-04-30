// MUST be true if you need incoming calls when the app is force-quit (kill mode).
// Apple only allows the OS to wake a VoIP app from terminated state via PushKit (VoIP push).
// Your PBX/backend must send an Apple VoIP push for every incoming call, using the token from
// SiprixVoipSdk().getPushKitToken() (see AppAccountsModel). Background mode also relies on
// that push + SIP; plain SIP INVITE alone cannot wake a killed iOS process.
const bool kIosUsePushKit = true;


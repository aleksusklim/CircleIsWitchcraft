unit SHL_Classes; // SemVersion: 0.1.0

// Contains all classes and stuff from other modules.

// Changelog:
// 0.1.0 - test version

interface // SpyroHackingLib is licensed under WTFPL

uses
  SHL_PlayStream, SHL_WaveStream, SHL_LameStream, SHL_ProcessStream,
  SHL_IsoReader, SHL_Progress, SHL_XaMusic;

type
  TPlayStream = SHL_PlayStream.TPlayStream;

type
  TWaveStream = SHL_WaveStream.TWaveStream;

type
  TLameStream = SHL_LameStream.TLameStream;

type
  TProcessStream = SHL_ProcessStream.TProcessStream;

type
  TIsoReader = SHL_IsoReader.TIsoReader;

type
  TImageFormat = SHL_IsoReader.TImageFormat;

type
  TConsoleProgress = SHL_Progress.TConsoleProgress;

type
  TXaDecoder = SHL_XaMusic.TXaDecoder;

implementation

end.


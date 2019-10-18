unit SHL_XaMusic; // SemVersion: 0.2.0

// Contains TXaDecoder unfinished class.

// Changelog:
// 0.1.0 - test version
// 0.2.0 - class functions

interface // SpyroHackingLib is licensed under WTFPL

uses
  SysUtils, Classes, SHL_Types, SHL_WaveStream, SHL_IsoReader;

type
  TXaDecoder = class(TStream)
  private
    FImage: TIsoReader;
    FQuality: Boolean;
    FInStereo: Boolean;
    FOutStereo: Boolean;
    FSector: Integer;
    FStride: Integer;
    FWaveSize: Integer;
    FSamples: Integer;
    FExtra: array[0..31] of Byte;
    FBuffer: PDataChar;
    FCount: Integer;
    FPos: Integer;
    FVolume: Double;
  public
    function Start(Image: TIsoReader; Quality, InStereo, OutStereo: Boolean; Sector, Stride: Integer; Count: Integer = 0; Volume: Double = 1.0): Boolean;
    function DecodeSector(WaveOut: Pointer; Volume: Double = 1.0): Boolean;
    function SaveSector(Stream: TStream; Volume: Double = 1.0): Boolean;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    property Image: TIsoReader read FImage;
    property Quality: Boolean read FQuality;
    property InStereo: Boolean read FInStereo;
    property OutStereo: Boolean read FOutStereo;
    property Sector: Integer read FSector;
    property Stride: Integer read FStride;
    property Samples: Integer read FSamples;
    property WaveSize: Integer read FWaveSize;
  public
    class function TrackInfoByXa(XaHeader: Integer; out Channel: Byte; out Stereo: Boolean; out HiQuality: Boolean; out MinStride: Byte): Boolean; overload;
    class function TrackInfoByXa(XaHeader: Pointer): Boolean; overload;
    class function DecodeXaData(SectorData: Pointer; SaveWave: Pointer; HiQuality: Boolean; InStereo: Boolean; OutStereo: Boolean; SpecialStuff: Pointer; Volume: Double = 1.0): Boolean;
    class procedure XaEmprySector(WriteBodyTo: Pointer);
  end;

implementation

function TXaDecoder.Start(Image: TIsoReader; Quality, InStereo, OutStereo: Boolean; Sector, Stride: Integer; Count: Integer = 0; Volume: Double = 1.0): Boolean;
begin
  ZeroMemory(@FExtra[0], 32);
  FImage := Image;
  FQuality := Quality;
  FInStereo := InStereo;
  FOutStereo := OutStereo;
  FSector := Sector;
  FStride := Stride;
  FImage.SeekToSector(FSector);
  if FInStereo = FOutStereo then
    FWaveSize := 8064
  else
  begin
    if FInStereo then
      FWaveSize := 4032
    else
      FWaveSize := 16128;
  end;
  if FQuality then
    FSamples := 37800
  else
    FSamples := 18900;
  if FImage.Body > 2336 then
  begin
    FImage := nil;
    Result := False;
  end
  else
    Result := True;
  if Count > 0 then
    if FBuffer = nil then
      GetMem(FBuffer, 16128);
  FCount := Count;
  FPos := FWaveSize;
  FVolume := Volume;
end;

function TXaDecoder.DecodeSector(WaveOut: Pointer; Volume: Double = 1.0): Boolean;
var
  Buffer: array[0..3000] of Byte;
  Next: Integer;
begin
  if FImage = nil then
  begin
    Result := False;
    Exit;
  end;
  Next := FImage.Sector + FStride;
  ZeroMemory(@Buffer[0], 3000);
  FImage.ReadSectors(@Buffer[0]);
  FImage.SeekToSector(Next);
  Result := DecodeXaData(@Buffer[8], WaveOut, FQuality, FInStereo, FOutStereo, @FExtra[0], Volume);
end;

function TXaDecoder.SaveSector(Stream: TStream; Volume: Double = 1.0): Boolean;
var
  Buffer: array[0..16127] of Byte;
begin
  Result := DecodeSector(@Buffer[0], Volume);
  Stream.WriteBuffer(Buffer, FWaveSize);
end;

function TXaDecoder.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TXaDecoder.Read(var Buffer; Count: Longint): Longint;
var
  Have: Integer;
  Save: PDataChar;
begin
  Result := 0;
  if FCount = 0 then
    Exit;
  Save := @Buffer;
  while Count > 0 do
  begin
    Have := FWaveSize - FPos;
    if Have <= 0 then
    begin
      if FCount <= 0 then
        Exit;
      DecodeSector(FBuffer, FVolume);
      Dec(FCount);
      FPos := 0;
      Have := FWaveSize;
    end;
    if Count < Have then
      Have := Count;
    Move((FBuffer + FPos)^, Save^, Have);
    Inc(FPos, Have);
    Inc(Save, Have);
    Inc(Result, Have);
    Dec(Count, Have);
  end;
end;

function TXaDecoder.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result := 0;
end;

class function TXaDecoder.TrackInfoByXa(XaHeader: Integer; out Channel: Byte; out Stereo: Boolean; out HiQuality: Boolean; out MinStride: Byte): Boolean;
begin
  Result := False;
  Channel := 255;
  if XaHeader = -1 then
    Exit;
  Channel := (XaHeader shr 8) and 255;
  Result := (((XaHeader shr 16) and 255) = 100);
  XaHeader := XaHeader shr 24;
  Stereo := (XaHeader and 1) > 0;
  HiQuality := (XaHeader and 4) = 0;
  MinStride := 16;
  if Stereo or HiQuality then
    MinStride := 8;
  if Stereo and HiQuality then
    MinStride := 4;
end;

class function TXaDecoder.TrackInfoByXa(XaHeader: Pointer): Boolean;
var
  Header: PInteger;
  Data: Integer;
  Channel, MinStride: Byte;
  Stereo, HiQuality: Boolean;
begin
  Result := False;
  Header := Pinteger(XaHeader);
  Data := Header^;
  Inc(Header);
  if Data <> Header^ then
    Exit;
  Result := TrackInfoByXa(Data, Channel, Stereo, HiQuality, MinStride);
end;

class function TXaDecoder.DecodeXaData(SectorData: Pointer; SaveWave: Pointer; HiQuality: Boolean; InStereo: Boolean; OutStereo: Boolean; SpecialStuff: Pointer; Volume: Double = 1.0): Boolean;
const
  k0: array[0..3] of Single = (0.0, 0.9375, 1.796875, 1.53125);
  k1: array[0..3] of Single = (0.0, 0.0, -0.8125, -0.859375);
var
  Data: PChar;
  Save: PSmallInt;
  Stuff: PDouble;
  a, b, c, d: Double;
  x, y: array[0..1] of Double;
  f, r: array[0..1] of Integer;
  Loop, Cnt, Index, Temp, Sec: Integer;
  DoCopy, DoMix: Boolean;
begin
  Result := False;
  Data := SectorData;
  Save := SaveWave;
  if (SectorData = nil) or (SaveWave = nil) or (SpecialStuff = nil) then
    Exit;
  DoCopy := not InStereo and OutStereo;
  DoMix := InStereo and not OutStereo;
  if DoMix then
    Volume := Volume / 2;
  Stuff := SpecialStuff;
  x[0] := Stuff^;
  Inc(Stuff);
  y[0] := Stuff^;
  if InStereo then
  begin
    Inc(Stuff);
    x[1] := Stuff^;
    Inc(Stuff);
    y[1] := Stuff^;
  end;
  for Loop := 1 to 18 do
  begin
    Cnt := 0;
    while Cnt < 8 do
    begin
      Temp := Ord(Data[4 + Cnt]);
      r[0] := Temp and 15;
      f[0] := (Temp shr 4) and 3;
      if InStereo then
      begin
        Temp := Ord(Data[4 + Cnt + 1]);
        r[1] := Temp and 15;
        f[1] := (Temp shr 4) and 3;
      end;
      for Index := 0 to 27 do
      begin
        Sec := 0;
        while True do
        begin
          a := 1 shl (12 - r[Sec]);
          Temp := (Ord(Data[16 + ((Cnt + Sec) shr 1) + (Index shl 2)]) shr (((Cnt + Sec) and 1) shl 2)) and 15;
          if Temp > 7 then
            b := (Temp - 16) * a
          else
            b := Temp * a;
          c := k0[f[Sec]] * x[Sec];
          d := k1[f[Sec]] * y[Sec];
          y[Sec] := x[Sec];
          x[Sec] := b + c + d;
          if Sec = 0 then
          begin
            if not DoMix then
            begin
              Temp := Round(Volume * x[0]);
              if Temp < -32768 then
                Temp := -32768
              else if Temp > 32767 then
                Temp := 32767;
              if Temp <> 0 then
                Result := True;
              Save^ := Temp;
              Inc(Save);
              if DoCopy then
              begin
                Save^ := Temp;
                Inc(Save);
              end;
            end;
            if InStereo then
            begin
              Sec := 1;
              Continue;
            end;
          end
          else
          begin
            if DoMix then
              Temp := Round(Volume * (x[0] + x[1]))
            else
              Temp := Round(Volume * x[1]);
            if Temp < -32768 then
              Temp := -32768
            else if Temp > 32767 then
              Temp := 32767;
            if Temp <> 0 then
              Result := True;
            Save^ := Temp;
            Inc(Save);
          end;
          Break;
        end;
      end;
      if InStereo then
        Inc(Cnt, 2)
      else
        Inc(Cnt);
    end;
    Inc(Data, 128);
  end;
  Stuff := SpecialStuff;
  Stuff^ := x[0];
  Inc(Stuff);
  Stuff^ := y[0];
  if InStereo then
  begin
    Inc(Stuff);
    Stuff^ := x[1];
    Inc(Stuff);
    Stuff^ := y[1];
  end;
end;

class procedure TXaDecoder.XaEmprySector(WriteBodyTo: Pointer);
var
  Block: Integer;
  Data: PInteger;
begin
  Data := PInteger(WriteBodyTo);
  ZeroMemory(Data, 2328);
  for Block := 1 to 18 do
  begin
    Data^ := $0C0C0C0C;
    Inc(Data);
    Data^ := $0C0C0C0C;
    Inc(Data);
    Data^ := $0C0C0C0C;
    Inc(Data);
    Data^ := $0C0C0C0C;
    Inc(Data, 29);
  end;
end;

end.


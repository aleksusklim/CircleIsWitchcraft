unit SHL_WaveStream; // SemVersion: 0.3.0

// Contains TWaveStream class for reading and writing wave files
// (just auto-populates WAVE header; write samples as TFileStream)
// Full pascal implementation

// Changelog:
// 0.1.0 - test version
// 0.2.0 - Ended()
// 0.3.0 - from stream

// TODO:
// - maybe use TFileStream's default constructor?

interface // SpyroHackingLib is licensed under WTFPL

uses Windows,
  SysUtils, Classes, SHL_Types;

type
  // actually a FileStream with some header-related functions:
  TWaveStream = class(TStream)
    // create new file and write a stub header:
    constructor CreateNew(const Filename: TextString);
    // open existing file read-only; read header and seek to data:
    constructor CreateRead(const Filename: TextString); overload;
    // open existing file; read header if present, or write a stub if none:
    constructor CreateWrite(const Filename: TextString); overload;

    //
    constructor CreateRead(FromStream: TStream); overload;
    //
    constructor CreateWrite(ToStream: TStream); overload;

    // after Free, the header will be updated if not read-only:
    destructor Destroy(); override;
  protected
    // hide TFileStream's constructors:
    constructor Create();
  private
    FStream: TStream;
    FOwnStream: Boolean;
    FBitsPerSample: Integer; // usually 8 or 16, from header
    FSampleRate: Integer; // f.e. 8000, 16000, 18900, 22050, 32000, 37800, 44100, 48000
    FChannels: Integer; // 1 for mono, 2 for stereo
    FIsValid: Boolean; // true when header is correct
    FIsReadOnly: Boolean; // true when instantiated by CreateRead
    FOkToUpdate: Boolean; //
    procedure Defaults(); // mono, 44.1 kHz, 16 bit
  public
    // read format from the header, seek back if was at data
    procedure ReadHeader();
    // set desired format and write it to the header; seek back if at data;
    // if anything is zero - then use current, don't change:
    procedure WriteHeader(SampleRate: Integer = 0; Channels: Integer = 0; BitsPerSample: Integer = 0; DataSize: Integer = 0); overload;
    // overloaded to use booleans:
    procedure WriteHeader(SampleRate: Integer; IsStereo: Boolean; Is16Bit: Boolean = True); overload;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    function GetSize(): Int64; override;
    // getters for privates:
    property BitsPerSample: Integer read FBitsPerSample;
    property SampleRate: Integer read FSampleRate;
    property Channels: Integer read FChannels;
    property IsValid: Boolean read FIsValid;
    property IsReadOnly: Boolean read FIsReadOnly;
    function IsStereo(): Boolean;
    function Is16Bit(): Boolean;
    function Ended(): Boolean;
  end;

implementation

type
  // WAVE format spec:
  TRiffHeader = record // sizeof = 44
    chunkId: Integer;
    chunkSize: Integer;
    format: Integer;
    subchunk1Id: Integer;
    subchunk1Size: Integer;
    audioFormat: Smallint;
    numChannels: Smallint;
    sampleRate: Integer;
    byteRate: Integer;
    blockAlign: Smallint;
    bitsPerSample: Smallint;
    subchunk2Id: Integer;
    subchunk2Size: Integer;
  end;

const // for header, since declared as itegers:
  FCC_RIFF = $46464952; // "RIFF"
  FCC_WAVE = $45564157; // "WAVE"
  FCC_fmt = $20746D66; // "fmt "
  FCC_data = $61746164; // "data"

constructor TWaveStream.Create();
begin
  Abort; // should never be called
end;

constructor TWaveStream.CreateRead(const Filename: TextString);
begin
  inherited Create();
  FIsReadOnly := True;
  FStream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyNone);
  FOwnStream := True;
  Defaults(); // will use this if empty file
  ReadHeader();
end;

constructor TWaveStream.CreateWrite(const Filename: TextString);
begin
  inherited Create();
  FStream := TFileStream.Create(Filename, fmOpenReadWrite or fmShareDenyWrite);
  FOwnStream := True;
  Defaults();
  if Size < 44 then
    WriteHeader()
  else
    ReadHeader(); // allowed at wrong files
  FOkToUpdate := True;
end;

constructor TWaveStream.CreateNew(const Filename: TextString);
begin
  inherited Create();
  FStream := TFileStream.Create(Filename, fmCreate);
  FOwnStream := True;
  Defaults();
  WriteHeader(); // write defaults, to seek at data
  FOkToUpdate := True;
end;

constructor TWaveStream.CreateRead(FromStream: TStream);
begin
  FStream := FromStream;
  Defaults();
  FIsReadOnly := True;
  ReadHeader();
end;

constructor TWaveStream.CreateWrite(ToStream: TStream);
begin
  FStream := ToStream;
  Defaults();
  FOkToUpdate := True;
end;

destructor TWaveStream.Destroy();
begin
  if FOkToUpdate then
    WriteHeader(); // update filesize in header
  if FOwnStream and (FStream <> nil) then
    FStream.Free();
  inherited Destroy();
end;

procedure TWaveStream.Defaults();
begin
  FBitsPerSample := 16; // 2 bytes
  FSampleRate := 44100; // 44.1
  FChannels := 1; // mono
  FIsValid := False;
end;

procedure TWaveStream.ReadHeader();
var
  Header: TRiffHeader;
  OldPos: Integer;
begin
  FIsValid := False;
  if FStream = nil then
    Exit;
  OldPos := Position;
  Position := 0;
  if 44 <> Read(Header, 44) then // no header
  begin
    Position := OldPos; // do nothing
    Exit;
  end;
  if OldPos > 44 then // seek back
    Position := OldPos;
  FChannels := Header.numChannels;
  FSampleRate := Header.sampleRate;
  FBitsPerSample := Header.bitsPerSample;
  // now check some features in the header:
  if Header.chunkId <> FCC_RIFF then
    Exit;
  if Header.format <> FCC_WAVE then
    Exit;
  if Header.subchunk1Id <> FCC_fmt then
    Exit;
  if Header.subchunk1Size <> 16 then
    Exit;
  if Header.audioFormat <> 1 then
    Exit;
  if (FChannels <> 1) and (FChannels <> 2) then
    Exit;
  if (FBitsPerSample <> 8) and (FBitsPerSample <> 16) then
    Exit;
  if Header.blockAlign <> FBitsPerSample * FChannels div 8 then
    Exit;
  if Header.byteRate <> Header.blockAlign * FSampleRate then
    Exit;
  if Header.subchunk2Id <> FCC_data then
    Exit;
  FIsValid := True; // all ok
end;

procedure TWaveStream.WriteHeader(SampleRate: Integer = 0; Channels: Integer = 0; BitsPerSample: Integer = 0; DataSize: Integer = 0);
var
  Header: TRiffHeader;
  OldPos: Integer;
begin
  if (FStream = nil) or FIsReadOnly then
    Exit;
  if DataSize <= 0 then // get current size
  begin
    DataSize := Size - 44;
    if DataSize < 0 then
      DataSize := 0; // write zero if no header
  end;
  // get currents:
  if BitsPerSample > 0 then
    FBitsPerSample := BitsPerSample;
  if Channels > 0 then
    FChannels := Channels;
  if SampleRate > 0 then
    FSampleRate := SampleRate;
  // create a header:
  Header.chunkId := FCC_RIFF;
  Header.chunkSize := DataSize + 36;
  if Header.chunkSize < 0 then
    Header.chunkSize := 0;
  Header.format := FCC_WAVE;
  Header.subchunk1Id := FCC_fmt;
  Header.subchunk1Size := 16;
  Header.audioFormat := 1;
  Header.numChannels := FChannels;
  Header.sampleRate := FSampleRate;
  Header.blockAlign := FBitsPerSample * FChannels div 8;
  Header.byteRate := Header.blockAlign * FSampleRate;
  Header.bitsPerSample := FBitsPerSample;
  Header.subchunk2Id := FCC_data;
  Header.subchunk2Size := DataSize;
  OldPos := Position;
  Position := 0; // to beginning
  WriteBuffer(Header, 44);
  if OldPos > 44 then
    Position := OldPos; // seek back
end;

procedure TWaveStream.WriteHeader(SampleRate: Integer; IsStereo: Boolean; Is16Bit: Boolean = True);
begin
  // convert booleans to proper values:
  WriteHeader(SampleRate, 1 + Ord(IsStereo), 1 shl (3 + Ord(Is16Bit)));
end;

function TWaveStream.Write(const Buffer; Count: Longint): Longint;
begin
  if FStream <> nil then
    Result := FStream.Write(Buffer, Count)
  else
    Result := 0;
end;

function TWaveStream.Read(var Buffer; Count: Longint): Longint;
begin
  if FStream <> nil then
    Result := FStream.Read(Buffer, Count)
  else
    Result := 0;
end;

function TWaveStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  if FStream <> nil then
    Result := FStream.Seek(Offset, Origin)
  else
    Result := 0;
end;

function TWaveStream.GetSize(): Int64;
begin
  if FStream <> nil then
    Result := FStream.Size
  else
    Result := 0;
end;

function TWaveStream.IsStereo(): Boolean;
begin
  Result := (FChannels = 2);
end;

function TWaveStream.Is16Bit(): Boolean;
begin
  Result := (FBitsPerSample = 16);
end;

function TWaveStream.Ended(): Boolean;
begin
  Result := FStream.Position >= FStream.Size;
end;

end.


unit SHL_PlayStream; // SemVersion: 0.2.0

// Contains TPlayStream class for playing WAVE sounds.
// Currently only for Windows!

// Changelog:
// 0.1.0 - test version
// 0.2.0 - position, wavestream, volume

// TODO:
// - error exceptions
// - emulated device
// - Linux compatibility?

interface // SpyroHackingLib is licensed under WTFPL

uses
  Windows, MMSystem, SysUtils, Classes, Contnrs, SHL_Types, SHL_WaveStream;

type
  // one local stream of audio
  TPlayStream = class(TStream)
   // stream can be instantiated by default Create(); this constructor will call Open:
    constructor Create(Device: Integer; Samples: Integer; IsStereo: Boolean; Is16Bit: Boolean = True; Limit: Integer = 4); overload;
   // get all settings from a TWaveStream:
    constructor Create(Device: Integer; WaveStream: TWaveStream; Limit: Integer = 4); overload;
    // Free will stop the sound
    destructor Destroy(); override;
  private
    FDevice: THandle; // handle to a device
    FLimit: Integer; // buffers count for Write
    FSize: Integer; // track of used memory
    FEvent: THandle; // when audio buffer done
    FBuffers: TQueue; // play sequence
    FPaused: Boolean; // user request
    FIsStereo: Boolean; // stereo format
    FIs16Bit: Boolean; // 16-bit format
    FSamples: Integer; // sample rate
    FVolume: Byte; // ratio to lower sound volume, in 2^n, 0..15
    FDump: TWaveStream; // debug wave file output
    procedure SetPause(Pause: Boolean); // toggle pause
  public
    // get all devices, result is a list of names:
    class function EnumDrivers(): ArrayOfWide;
    // open sound driver (-1 for default mixer), set stream properties; true if successful:
    function Open(Device: Integer; Samples: Integer; IsStereo: Boolean; Is16Bit: Boolean = True; Limit: Integer = 4): Boolean; overload;
    // for second constructor:
    function Open(Device: Integer; WaveStream: TWaveStream; Limit: Integer = 4): Boolean; overload;
    // stop sound and close driver:
    procedure Close();
    // copy sound data buffer, put in the queue, play immediately if not paused; true when ok:
    function Send(WaveData: Pointer; SizeInBytes: Integer): Boolean;
    // plays specifed wave stream up to Bytes, or until there no more data:
    procedure Play(FromStream: TStream; Bytes: Integer = -1);
    // block execution until this or less buffers are left; -1 means Limit:
    procedure WaitFor(Count: Integer = -1);
    // check the queue and return size; remove played buffers and free memory:
    function InQueue(): Integer;
    // for debugging, set a wave file to copy all played sound data there; empty = stop dumping:
    procedure Dump(Filename: WideString = '');
    // for streaming support; calls WaitFor(Limit) and Send:
    function Write(const Buffer; Count: Longint): Longint; override;
    // not supported, zero:
    function Read(var Buffer; Count: Longint): Longint; override;
    // also not supported, zero:
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    // set to true to prevent playing after :
    property Paused: Boolean read FPaused write SetPause;
    // auto buffer limit for Write:
    property Limit: Integer read FLimit write FLimit;
    // properties of sound:
    property IsStereo: Boolean read FIsStereo;
    property Is16Bit: Boolean read FIs16Bit;
    property Volume: Byte read FVolume write FVolume; // effect for all new buffers
  protected
    // Size will return the used memory in bytes:
    function GetSize(): Int64; override;
    // return number of played samples:
    function GetPosition(): Cardinal;
  public
    property Position: Cardinal read GetPosition;
  end;

implementation

class function TPlayStream.EnumDrivers(): ArrayOfWide;
var
  Len, Index: Integer;
  Caps: WAVEOUTCAPSW;
begin
  Len := waveOutGetNumDevs(); // get drivers count
  ZeroMemory(@Caps, SizeOf(Caps));
  if Len < 0 then
    Len := 0;
  SetLength(Result, Len);
  for Index := 0 to Len - 1 do
  begin // get each name:
    waveOutGetDevCapsW(Index, @Caps, SizeOf(Caps));
    Result[Index] := Caps.szPname;
  end;
end;

constructor TPlayStream.Create(Device: Integer; Samples: Integer; IsStereo: Boolean; Is16Bit: Boolean = True; Limit: Integer = 4);
begin
  if not Open(Device, Samples, IsStereo, Is16Bit, Limit) then
    Abort;
end;

constructor TPlayStream.Create(Device: Integer; WaveStream: TWaveStream; Limit: Integer = 4);
begin
  if not Open(Device, WaveStream, Limit) then
    Abort;
end;

destructor TPlayStream.Destroy();
begin
  Dump(); // flush dump-file
  Close(); // stop sound, free all buffers
  if FEvent <> 0 then
    CloseHandle(FEvent); // free event
  FBuffers.Free(); // destroy empty queue
end;

function TPlayStream.Open(Device: Integer; Samples: Integer; IsStereo: Boolean; Is16Bit: Boolean = True; Limit: Integer = 4): Boolean;
var
  Format: TWaveFormatEx;
begin
  if Device < 0 then
    Device := Integer(WAVE_MAPPER); // default device
  if FEvent = 0 then
    FEvent := CreateEvent(nil, False, False, nil); // at first call
  if FBuffers = nil then
    FBuffers := TQueue.Create(); // at first call
  FLimit := Limit;
  Close(); // stop and discard remaining stuff
  ZeroMemory(@Format, SizeOf(Format));
  // fill format:
  Format.wFormatTag := WAVE_FORMAT_PCM;
  FIsStereo := IsStereo;
  FIs16Bit := Is16Bit;
  if FIsStereo then
    Format.nChannels := 2
  else
    Format.nChannels := 1;
  FSamples := Samples;
  Format.nSamplesPerSec := FSamples;
  if FIs16Bit then
    Format.wBitsPerSample := 16
  else
    Format.wBitsPerSample := 8;
  Format.nBlockAlign := Format.nChannels * Format.wBitsPerSample div 8;
  Format.nAvgBytesPerSec := Format.nSamplesPerSec * Format.nBlockAlign;
  // get handle:
  Result := (waveOutOpen(@FDevice, Device, @Format, FEvent, 0, CALLBACK_EVENT) = MMSYSERR_NOERROR) and (FDevice <> 0);
end;

function TPlayStream.Open(Device: Integer; WaveStream: TWaveStream; Limit: Integer = 4): Boolean;
begin
  Result := Open(Device, WaveStream.SampleRate, WaveStream.IsStereo, WaveStream.Is16Bit, Limit);
end;

procedure TPlayStream.Close();
var
  Header: PWaveHdr;
begin
  if FDevice <> 0 then
  begin
    waveOutReset(FDevice); // stop sound
    waveOutClose(FDevice); // free driver
    FDevice := 0;
  end;
  while FBuffers.Count > 0 do
  begin // free all memory:
    Header := PWaveHdr(FBuffers.Pop());
    Dec(FSize, Header.dwUser);
    waveOutUnprepareHeader(FDevice, Header, SizeOf(TWaveHdr));
    FreeMem(Header);
  end;
end;

function TPlayStream.Send(WaveData: Pointer; SizeInBytes: Integer): Boolean;
var
  Header: PWaveHdr;
  MemSize, Mask, Value, Total: Integer;
  Source, Desten: PInteger;
begin
  Result := False;
  if (FDevice = 0) or (SizeInBytes < 2) then // no Open
    Exit;
  MemSize := SizeOf(TWaveHdr) + SizeInBytes;
  GetMem(Header, MemSize); // data will be after a header
  ZeroMemory(Header, SizeOf(TWaveHdr));
  Header.lpData := (PDataChar(Header)) + SizeOf(TWaveHdr); // here
  Header.dwBufferLength := SizeInBytes;
  if FVolume > 0 then // volume control
  begin
    if FVolume < 16 then // effective
    begin
      Total := SizeInBytes shr 2; // num of words
      Source := Pointer(WaveData);
      Desten := Pointer(Header.lpData);
      if FIs16Bit then // 16-bit algo
      begin
        Mask := 1 shl (15 - FVolume); // mask bit to sign-extend
        while Total <> 0 do
        begin
          Value := Source^; // actually, a shift and sign-extend operation for lower and upper half:
          Desten^ := (((((Value and $ffff) shr FVolume) xor Mask) - Mask) and $ffff) or ((((Value shr 16) shr FVolume) xor Mask) - Mask) shl 16;
          Inc(Source);
          Inc(Desten);
          Dec(Total);
        end
      end
      else
      begin // 8-bit algo
        Mask := $ff shr FVolume;
        Mask := Mask or (Mask shl 8) or (Mask shl 16) or (Mask shl 24); // mask of effective bits
        Value := Cardinal($80808080) - (Cardinal($80808080) shr FVolume); // difference to center the value
        while Total <> 0 do
        begin
          Desten^ := ((Source^ shr FVolume) and Mask) + Value; // shift and adjust to center
          Inc(Source);
          Inc(Desten);
          Dec(Total);
        end;
      end;
    end
    else
      ZeroMemory(Header.lpData, SizeInBytes);
  end
  else
    Move(WaveData^, Header.lpData^, SizeInBytes); // just copy samples
  if FDump <> nil then // debug stream
    FDump.WriteBuffer(Header.lpData^, SizeInBytes);
  Header.dwUser := MemSize; // size of memory to keep track
  if waveOutPrepareHeader(FDevice, Header, SizeOf(TWaveHdr)) = MMSYSERR_NOERROR then
  begin // ok block
    if waveOutWrite(FDevice, Header, SizeOf(TWaveHdr)) <> MMSYSERR_NOERROR then
    begin // fail write
      waveOutUnprepareHeader(FDevice, Header, SizeOf(TWaveHdr)); // free block
      FreeMem(Header);
      Result := False;
    end
    else
    begin
      Result := True;
      Inc(FSize, MemSize);
      FBuffers.Push(Header); // fill queue
    end;
  end;
end;

procedure TPlayStream.Play(FromStream: TStream; Bytes: Integer = -1);
const
  Size = 32768;
var
  Buffer: array[0..Size - 1] of Byte;
  Count, Value: Integer;
  One: Boolean;
begin
  if Bytes = 0 then
  begin
    Bytes := -1;
    One := True;
  end
  else
    One := False;
  if Bytes = -1 then
    Bytes := $7fffffff;
  while Bytes > 0 do
  begin
    Value := Bytes;
    if Value > Size then
      Value := Size;
    Count := FromStream.Read(Buffer, Value);
    if Count <= 0 then
      Break;
    Write(Buffer, Count);
    Dec(Bytes, Count);
    if One then
      Break;
  end;
end;

procedure TPlayStream.SetPause(Pause: Boolean);
begin
  FPaused := Pause; // no check of previous state
  if FPaused then
    waveOutPause(FDevice)
  else
    waveOutRestart(FDevice); // ok to call already resumed
end;

function TPlayStream.InQueue(): Integer;
var
  Header: PWaveHdr;
begin
  Result := 0;
  if FBuffers = nil then // no Open
    Exit;
  while FBuffers.Count > 0 do
  begin // check all:
    Header := FBuffers.Peek();
    if (Header.dwFlags and WHDR_DONE) = 0 then // this is not done yet
      Break;
    Dec(FSize, Header.dwUser);
    waveOutUnprepareHeader(FDevice, Header, SizeOf(TWaveHdr));
    FreeMem(Header); // this is done, free it
    FBuffers.Pop();
  end;
  Result := FBuffers.Count; // active buffers
end;

procedure TPlayStream.Dump(Filename: WideString = '');
begin
  if Filename = '' then
  begin
    if FDump = nil then
      Exit;
    FreeAndNil(FDump);
  end
  else
  begin
    if FDump <> nil then
      Dump();
    FDump := TWaveStream.CreateNew(Filename);
    FDump.WriteHeader(FSamples, FIsStereo, FIs16Bit);
  end;
end;

procedure TPlayStream.WaitFor(Count: Integer = -1);
begin
  if FDevice = 0 then
    Exit;
  if Count < 0 then
  begin
    Count := FLimit;
    if Count < 0 then
      Exit;
  end;
  FPaused := False;
  waveOutRestart(FDevice); // shouldn't wait in paused state
  ResetEvent(FEvent);
  while InQueue() > Count do // continiously checking
    WaitForSingleObject(FEvent, INFINITE); // fired when a buffer is done
end;

function TPlayStream.Write(const Buffer; Count: Longint): Longint;
begin
  WaitFor(Limit); // default 4, can be set by user
  if Send(@Buffer, Count) then
    Result := Count // ok
  else
    Result := 0; // fail
end;

function TPlayStream.GetSize(): Int64;
begin
  Result := FSize; // size of memory used
end;

function TPlayStream.GetPosition(): Cardinal;
var
  Time: tMMTIME;
begin
  Time.wType := TIME_SAMPLES; // set samples format
  waveOutGetPosition(FDevice, @Time, SizeOf(Time));
  Result := Time.sample;
end;

function TPlayStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result := 0; // impossible
end;

function TPlayStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0; // impossible
end;

end.


library mp3play;

{$APPTYPE CONSOLE}

uses
  SHL_Types,
  SHL_Classes,
  SysUtils,
  Classes,
  Windows,
  MMSystem,
  SyncObjs;

function NtClose(h: cardinal): integer; stdcall; external 'ntdll.dll';

var
  LamePath: string;

const
  MaxSlot = 15;

type
  TReason = (ReasonNone, ReasonStop, ReasonPlay, ReasonSample, ReasonVolume);

var
  Playing: array[0..MaxSlot] of TPlayStream;
  Mp3s: array[0..MaxSlot] of TLameStream;
  Wavs: array[0..MaxSlot] of TWaveStream;
  Volumes: array[0..MaxSlot] of Byte;
  Thread: THandle;
  Request, Success: TEvent;
  Reason: TReason;
  Question: Integer;
  FilePath: string;
  BeepHandle: Cardinal;

function Lame(Path: PChar): Double; stdcall;
var
  Exe: string;
begin
  Result := 0;
  Exe := string(Path);
  if not FileExists(Exe) then
    Exit;
  LamePath := Exe;
  Result := 1;
end;

function SlotToIndex(Slot: Double; out Index: Integer): Boolean;
begin
  Index := Round(Slot);
  if (Index < 0) or (Index > MaxSlot) then
    Result := True
  else
    Result := False;
end;

function ThreadBody(Param: Pointer): Integer; stdcall;
var
  Index: Integer;
begin
  Result := 0;
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
  while True do
  begin
    Request.WaitFor(10);
    case Reason of
      ReasonStop:
        begin
          if Question < 0 then
            for Index := 0 to MaxSlot do
            begin
              FreeAndNil(Playing[Index]);
              FreeAndNil(Mp3s[Index]);
              FreeAndNil(Wavs[Index]);
            end
          else
          begin
            FreeAndNil(Playing[Question]);
            FreeAndNil(Mp3s[Question]);
            FreeAndNil(Wavs[Question]);
          end;
          Reason := ReasonNone;
          Question := 0;
          for Index := 0 to MaxSlot do
            if Playing[Index] <> nil then
              Inc(Question);
          if Question = 0 then
          begin
            Success.SetEvent();
            ExitThread(0);
            Exit;
          end;
          Success.SetEvent();
        end;
      ReasonPlay:
        begin
          FreeAndNil(Playing[Question]);
          FreeAndNil(Mp3s[Question]);
          FreeAndNil(Wavs[Question]);
          Playing[Question] := TPlayStream.Create();
          if FileExists(FilePath) then
          begin
            if LowerCase(ExtractFileExt(FilePath)) = '.mp3' then
            begin
              Mp3s[Question] := TLameStream.Create(LamePath);
              Mp3s[Question].Decode(WideString(FilePath), False);
              Wavs[Question] := TWaveStream.CreateRead(Mp3s[Question]);
              Playing[Question].Open(-1, Wavs[Question], 99);
              FreeAndNil(Wavs[Question]);
              Mp3s[Question].Free();
              Mp3s[Question] := TLameStream.Create(LamePath);
              Mp3s[Question].Decode(WideString(FilePath), True);
              Mp3s[Question].SetPriority(HIGH_PRIORITY_CLASS);
            end
            else
            begin
              Wavs[Question] := TWaveStream.CreateRead(FilePath);
              Playing[Question].Open(-1, Wavs[Question], 99);
            end;
            Playing[Question].Volume := Volumes[Question];
//            Playing[Question].Dump(IntToStr(timeGetTime()) + '.wav');
          end;
          Reason := ReasonNone;
          Success.SetEvent();
        end;
      ReasonSample:
        begin
          if Playing[Question] <> nil then
            Question := Integer(Playing[Question].Position)
          else
            Question := -1;
          Reason := ReasonNone;
          Success.SetEvent();
        end;
      ReasonVolume:
        begin
          if Playing[Question] <> nil then
            Playing[Question].Volume := Volumes[Question];
          Reason := ReasonNone;
          Success.SetEvent();
        end;
    end;
    for Index := 0 to MaxSlot do
      if (Playing[Index] <> nil) and (Playing[Index].InQueue < 8) then
      begin
        if Mp3s[Index] <> nil then
        begin
          if Mp3s[Index].IsTerminated() and (Playing[Index].InQueue = 0) then
          begin
            FreeAndNil(Playing[Index]);
            FreeAndNil(Mp3s[Index]);
          end
          else
            Playing[Index].Play(Mp3s[Index], 0);
        end
        else if Wavs[Index] <> nil then
        begin
          if Wavs[Index].Ended() then
          begin
            FreeAndNil(Playing[Index]);
            FreeAndNil(Wavs[Index]);
          end
          else
            Playing[Index].Play(Wavs[Index], 8192);
        end;
      end;
  end;
end;

function Talk(Operation: TReason; SlotIndex: Integer): Integer;
begin
  Result := -1;
  if Thread = 0 then
    Exit;
  Reason := Operation;
  Question := SlotIndex;
  Request.SetEvent();
  Success.WaitFor(INFINITE);
  Result := Question;
end;

procedure StartThread();
var
  Tid: Cardinal;
begin
  if Thread <> 0 then
    Exit;
  IsMultiThread := True;
  Reason := ReasonNone;
  Request := TEvent.Create(nil, False, False, '');
  Success := TEvent.Create(nil, False, False, '');
  Thread := CreateThread(nil, 0, @ThreadBody, nil, 0, Tid);
end;

function Stop(Slot: Double): Double; stdcall;
var
  Index: Integer;
begin
  Result := 0;
  if SlotToIndex(Slot, Index) then
    if Index <> -1 then
      Exit
    else
    begin
      NtClose(BeepHandle);
      BeepHandle := 0;
    end;
  if Talk(ReasonStop, Index) = 0 then
  begin
    WaitForSingleObject(Thread, INFINITE);
    Thread := 0;
    FreeAndNil(Request);
    FreeAndNil(Success);
  end;
end;

procedure SetVol(Index: Integer; Level: Double);
begin
  if Level > 16 then
    Level := 16
  else if Level < 0 then
    Level := 0;
  Volumes[Index] := Round(Level);
end;

function Play(Path: PChar; Slot, Level: Double): Double; stdcall;
var
  Index: Integer;
begin
  Result := 0;
  if SlotToIndex(Slot, Index) then
    Exit;
  StartThread();
  SetVol(Index, Level);
  FilePath := string(Path);
  Talk(ReasonPlay, Index);
  Result := 1;
end;

function Sample(Slot: Double): Double; stdcall;
var
  Index: Integer;
begin
  Result := -1;
  if SlotToIndex(Slot, Index) then
    Exit;
  Result := Talk(ReasonSample, Index);
end;

function Volume(Slot, Level: Double): Double; stdcall;
var
  Index: Integer;
begin
  Result := 0;
  if SlotToIndex(Slot, Index) then
    Exit;
  SetVol(Index, Level);
  Talk(ReasonVolume, Index);
end;

function Empty(): Double; stdcall;
var
  Index: Integer;
begin
  Index := 0;
  while Index <= MaxSlot do
  begin
    if Playing[Index] <> nil then
      Inc(Index)
    else
      Break;
  end;
  if Index <= MaxSlot then
    Result := Index
  else
    Result := -1;
end;

type
  TObjectAttributes = record
    Length: Cardinal;
    RootDirectory: THandle;
    ObjectName: pointer;
    Attributes: Cardinal;
    SecurityDescriptor: Pointer;
    SecurityQualityOfService: Pointer;
  end;

procedure RtlInitUnicodeString(d, s: pointer); stdcall; external 'ntdll.dll';

function NtDeviceIoControlFile(h: cardinal; x1, x2, x3: cardinal; s: pointer; c: cardinal; i: pointer; l: cardinal; x4: pointer; x5: cardinal): integer; stdcall; external 'ntdll.dll';

function NtCreateFile(p: pointer; a: cardinal; f, s: pointer; x5, x6, x7, x8, x9, x10, x11: cardinal): integer; stdcall; external 'ntdll.dll';

var
  DeviceBeep, DeviceBeepUnicode: array[0..64] of Byte;
  ObjectAttributes: TObjectAttributes;
  Status: Cardinal;
  Tone: array[0..1] of Cardinal;

function Beeps(Freq, Dur: Double): Double; stdcall;
begin
  Result := 0;
  if BeepHandle = 0 then
  begin
    Status := 0;
    StringToWideChar('\Device\Beep', PWideChar(@DeviceBeep[0]), 64);
    RtlInitUnicodeString(@DeviceBeepUnicode[0], PWideChar(@DeviceBeep[0]));
    ObjectAttributes.Length := SIZEOF(ObjectAttributes);
    ObjectAttributes.RootDirectory := 0;
    ObjectAttributes.Attributes := 0;
    ObjectAttributes.ObjectName := @DeviceBeepUnicode[0];
    ObjectAttributes.SecurityDescriptor := nil;
    ObjectAttributes.SecurityQualityOfService := nil;
    NtCreateFile(@BeepHandle, 1, @ObjectAttributes, @Status, 0, 128, 1, 1, 64, 0, 0);
  end;
  Tone[0] := Round(Freq);
  Tone[1] := Round(Dur);
  NtDeviceIoControlFile(BeepHandle, 0, 0, 0, @Status, 65536, @Tone, 8, nil, 0);
end;

var
  Protect: TList;

function Hold(filename: PChar): Double; stdcall;
var
  name: string;
  i: Integer;
  s: TFileStream;
begin
  name := string(filename);
  if name = '' then
  begin
    Result := 0;
    if Protect <> nil then
    begin
      Result := -1;
      for i := 0 to Protect.Count - 1 do
        TFileStream(Protect[i]).Free();
      Protect.Clear();
    end;
    FreeAndNil(Protect);
    Exit;
  end;
  Result := 1;
  if not FileExists(name) then
    Exit;
  try
    s := TFileStream.Create(name, fmOpenRead or fmShareDenyWrite);
  except
    Exit;
  end;
  if Protect = nil then
    Protect := TList.Create();
  Protect.Add(s);
  Result := 0;
end;

exports
  Lame,
  Play,
  Stop,
  Volume,
  Sample,
  Empty,
  Beeps,
  Hold;

begin
end.


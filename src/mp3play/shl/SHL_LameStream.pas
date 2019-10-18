unit SHL_LameStream; // SemVersion: 0.3.0

// Contains TLameStream class for

// Changelog:
// 0.1.0 - test version
// 0.2.0 - priority
// 0.3.0 - no header

// TODO:
//

interface // SpyroHackingLib is licensed under WTFPL

uses
  SysUtils, Classes, SHL_ProcessStream, SHL_Types;

type
  TLameStream = class(TStream)
    constructor Create(const PathToLamaExe: WideString);
    destructor Destroy(); override;
  private
    FLame: WideString;
    FProcess: TProcessStream;
    FIsEncode, FIsDecode: Boolean;
//    FDump: TFileStream;
  public
    procedure Decode(const ReadFromMp3: WideString; NoHeader: Boolean = False);
    procedure Encode(const SaveToMp3: WideString; InRate, OutRate: TextString; InStereo, OutStereo: Boolean);
    procedure WaitExit(Timeout: Integer = 10000);
    function IsTerminated(): Boolean;
    procedure SetPriority(Prio: Cardinal);
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
  end;

implementation

constructor TLameStream.Create(const PathToLamaExe: WideString);
begin
  inherited Create();
  FLame := PathToLamaExe;
  if not FileExists(FLame) then
    Abort;
//  FDump := TFileStream.Create(IntToStr(GetTickCount()) + '_.wav', fmCreate);
end;

destructor TLameStream.Destroy();
begin
  FProcess.Free();
//  FDump.Free();
  inherited Destroy();
end;

procedure TLameStream.WaitExit(Timeout: Integer = 10000);
begin
  if FIsEncode then
    FProcess.Close(True, False);
  if FIsDecode then
    FProcess.Close(False, True);
  FProcess.IsRunning(Timeout);
end;

procedure TLameStream.Encode(const SaveToMp3: WideString; InRate, OutRate: TextString; InStereo, OutStereo: Boolean);
var
  Line: WideString;
begin
  FIsEncode := True;
  if InStereo and OutStereo then
    Line := ' -m j'
  else if InStereo and not OutStereo then
    Line := ' -a'
  else if not InStereo and OutStereo then
    Line := ' -m d'
  else if not InStereo and not OutStereo then
    Line := ' -m m';
  Line := ExtractFileName(FLame) + Line + ' -r -x -s ' + InRate + ' --resample ' + OutRate + ' --silent --preset extreme - "' + SaveToMp3 + '"';
  FProcess := TProcessStream.Create(FLame, Line, '', True, False, False, False);
end;

procedure TLameStream.Decode(const ReadFromMp3: WideString; NoHeader: Boolean = False);
var
  Line: WideString;
begin
  FIsDecode := True;
  Line := ExtractFileName(FLame);
  if NoHeader then
    Line := Line + ' -t';
  Line := Line + ' --quiet --decode "' + ReadFromMp3 + '" -';
  FProcess := TProcessStream.Create(FLame, Line, '', False, True, False, False);
end;

function TLameStream.IsTerminated(): Boolean;
begin
  Result := not FProcess.IsRunning();
end;

procedure TLameStream.SetPriority(Prio: Cardinal);
begin
  FProcess.SetPriority(Prio);
end;

function TLameStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := FProcess.Write(Buffer, Count);
end;

function TLameStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := FProcess.Read(Buffer, Count);
//  FDump.Write(Buffer, Result);
end;

function TLameStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result := 0;
end;

end.


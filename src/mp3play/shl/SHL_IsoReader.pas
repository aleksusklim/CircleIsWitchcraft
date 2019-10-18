unit SHL_IsoReader; // SemVersion: 0.1.0

interface // SpyroHackingLib is licensed under WTFPL

// TODO:
// - reading filelist
// - recognize more formats

uses
  StrUtils, SysUtils, Classes, SHL_Types;

type
  TImageFormat = (ifUnknown, ifIso, ifMdf, ifStr);

type
  TIsoReader = class(TFileStream)
    constructor Create(Filename: TextString; DenyWrite: Boolean = False);
    constructor CreateWritable(Filename: TextString; DenyWrite: Boolean = False);
  protected
    function GetSize(): Int64; override;
  public
    function SetFormat(Header: Integer = 0; Footer: Integer = 0; Body: Integer =
      2336; Offset: Integer = 0): Boolean; overload;
    function SetFormat(Format: TImageFormat): Boolean; overload;
    procedure SeekToSector(Sector: Integer);
    function ReadSectors(SaveDataTo: Pointer; Count: Integer = 0): Integer;
    function WriteSectors(ReadDataFrom: Pointer; Count: Integer = 0): Integer;
    function GuessImageFormat(Text: PChar = nil): TImageFormat;
  private
    FCachedSize: Integer;
    FSectorsCount: Integer;
    FHeader: Integer;
    FFooter: Integer;
    FBody: Integer;
    FOffset: Integer;
    FTotal: Integer;
    FSector: Integer;
  public
    property SectorsCount: Integer read FSectorsCount;
    property Header: Integer read FHeader;
    property Footer: Integer read FFooter;
    property Body: Integer read FBody;
    property Total: Integer read FTotal;
    property Offset: Integer read FOffset;
    property Sector: Integer read FSector write SeekToSector;
  end;

implementation

function TIsoReader.GetSize(): Int64;
begin
  Result := Int64(FCachedSize);
end;

constructor TIsoReader.Create(Filename: TextString; DenyWrite: Boolean = False);
begin
  if DenyWrite then
    inherited Create(Filename, fmOpenRead or fmShareDenyWrite)
  else
    inherited Create(Filename, fmOpenRead or fmShareDenyNone);
  SetFormat();
end;

function TIsoReader.SetFormat(Header: Integer = 0; Footer: Integer = 0; Body:
  Integer = 2336; Offset: Integer = 0): Boolean;
begin
  FHeader := Header;
  FFooter := Footer;
  FBody := Body;
  FTotal := FHeader + FBody + FFooter;
  FCachedSize := Integer(inherited GetSize());
  FSectorsCount := FCachedSize div FTotal;
  Result := (FCachedSize mod FTotal) = 0;
end;

function TIsoReader.SetFormat(Format: TImageFormat): Boolean;
begin
  Result := False;
  case Format of
    ifIso:
      Result := SetFormat(16, 0);
    ifMdf:
      Result := SetFormat(16, 96);
    ifStr:
      Result := SetFormat(0, 0);
    ifUnknown:
      Result := SetFormat(0, 0);
  end;
end;

procedure TIsoReader.SeekToSector(Sector: Integer);
begin
  FSector := Sector;
  Position := FOffset + FTotal * FSector + FHeader;
end;

function TIsoReader.ReadSectors(SaveDataTo: Pointer; Count: Integer = 0): Integer;
begin
  if Count = 0 then
    Result := Ord(inherited Read(SaveDataTo^, FBody) = FBody)
  else
    Result := inherited Read(SaveDataTo^, FTotal * Count) div FTotal;
  Inc(FSector, Result);
end;

function TIsoReader.WriteSectors(ReadDataFrom: Pointer; Count: Integer = 0): Integer;
begin
  if Count = 0 then
    Result := Ord(inherited Write(ReadDataFrom^, FBody) = FBody)
  else
    Result := inherited Write(ReadDataFrom^, FTotal * Count) div FTotal;
  Inc(FSector, Result);
end;

function TIsoReader.GuessImageFormat(Text: PChar = nil): TImageFormat;
var
  Sector: array[0..615] of Integer;
  OldPos: Integer;
begin
  Result := ifUnknown;
  FBody := 2336;
  FHeader := 0;
  FFooter := 0;
  OldPos := Position;
  ReadBuffer(Sector, 2464);
  Position := OldPos;
  while True do
  begin
    if (Sector[0] = Sector[1]) and (Sector[584] = Sector[585]) then
    begin
      if Text <> nil then
        StrCopy(Text, 'STR');
      Result := ifStr;
      Break;
    end;
    FHeader := 16;
    if (Sector[0] = Sector[588]) and (Sector[1] = Sector[589]) then
    begin
      if Text <> nil then
        StrCopy(Text, 'ISO');
      Result := ifIso;
      Break;
    end;
    FFooter := 96;
    if (Sector[0] = Sector[612]) and (Sector[1] = Sector[613]) then
    begin
      if Text <> nil then
        StrCopy(Text, 'MDF');
      Result := ifMdf;
      Break;
    end;
    if Text <> nil then
      StrCopy(Text, 'UNK');
    Break;
  end;
  SetFormat(Result);
end;

constructor TIsoReader.CreateWritable(Filename: TextString; DenyWrite: Boolean = False);
begin
  if FileExists(Filename) then
  begin
    if DenyWrite then
      inherited Create(Filename, fmOpenReadWrite or fmShareDenyWrite)
    else
      inherited Create(Filename, fmOpenReadWrite or fmShareDenyNone);
  end
  else
    inherited Create(Filename, fmCreate);
  SetFormat();
end;

end.


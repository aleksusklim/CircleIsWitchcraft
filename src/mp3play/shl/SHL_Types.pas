unit SHL_Types; // SemVersion: 0.1.0

interface // SpyroHackingLib is licensed under WTFPL

type
  TextString = type AnsiString;

  DataString = type AnsiString;

  TextChar = type AnsiChar;

  DataChar = type AnsiChar;

type
  PTextChar = ^TextChar;

  PDataChar = PChar;

  ArrayOfText = array of TextString;

  ArrayOfData = array of DataString;

  ArrayOfWide = array of WideString;

procedure FillChar(out x; Count: Integer; Value: Char); overload;

procedure FillChar(out x; Count: Integer; Value: Byte); overload;

procedure ZeroMemory(Destination: Pointer; Length: Integer);

implementation

procedure FillChar(out x; Count: Integer; Value: Char); overload;
begin
  System.FillChar(x, Count, Value);
end;

procedure FillChar(out x; Count: Integer; Value: Byte); overload;
begin
  System.FillChar(x, Count, Chr(Value));
end;

procedure ZeroMemory(Destination: Pointer; Length: Integer);
begin
  System.FillChar(Destination^, Length, #0);
end;

end.


program oldbeat;

{$APPTYPE CONSOLE}

uses SysUtils,Classes;

var
s:string;
stream:TFileStream;
save:text;
v:Smallint;
a:array[1..1000]of Smallint;
min,max,i:integer;


begin
s:='ciw.wav';
Assign(save,s+'.txt');
Rewrite(save);
stream:=TFileStream.Create(s,fmOpenRead or fmShareDenyNone);
stream.Seek(40,soFromBeginning);
while(stream.Position<>stream.Size)do begin
stream.Read(a,1000);
min:=0;
max:=0;
for i:=1 to 1000 do begin
v:=a[i];
if min>v then min:=v;
if max<v then max:=v;
end;
Writeln(save,(-min)+1,' ',max+1);
end;
stream.Free;
Close(save);
end.

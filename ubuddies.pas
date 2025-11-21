unit uBuddies;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  TBuddy = record
    Name: string;
    Host: string;
    Port: string;
  end;

  TBuddyManager = class
  private
    FBuddies: array of TBuddy;
    FFileName: string;
  public
    constructor Create(const AFileName: string);

    procedure Load;
    procedure Save;

    function CountBuddies: Integer;
    function GetBuddy(Index: Integer): TBuddy;
    procedure SetBuddy(Index: Integer; const B: TBuddy);

    procedure AddBuddy(const B: TBuddy);
    procedure RemoveBuddy(Index: Integer);

    // helper for UI
    function GetDisplayName(Index: Integer): string;
  end;

implementation

{ TBuddyManager }

constructor TBuddyManager.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

procedure TBuddyManager.Load;
var
  ini: TIniFile;
  Count, i: Integer;
  sec: string;
begin
  ini := TIniFile.Create(FFileName);
  try
    Count := ini.ReadInteger('General', 'Count', 0);
    SetLength(FBuddies, Count);

    for i := 0 to Count - 1 do
    begin
      sec := 'Buddy' + IntToStr(i);
      FBuddies[i].Name := ini.ReadString(sec, 'Name', '');
      FBuddies[i].Host := ini.ReadString(sec, 'Host', '');
      FBuddies[i].Port := ini.ReadString(sec, 'Port', '');
    end;
  finally
    ini.Free;
  end;
end;

procedure TBuddyManager.Save;
var
  ini: TIniFile;
  i: Integer;
  sec: string;
begin
  ini := TIniFile.Create(FFileName);
  try
    ini.EraseSection('General');
    ini.WriteInteger('General', 'Count', Length(FBuddies));

    for i := 0 to High(FBuddies) do
    begin
      sec := 'Buddy' + IntToStr(i);
      ini.EraseSection(sec);
      ini.WriteString(sec, 'Name', FBuddies[i].Name);
      ini.WriteString(sec, 'Host', FBuddies[i].Host);
      ini.WriteString(sec, 'Port', FBuddies[i].Port);
    end;
  finally
    ini.Free;
  end;
end;

function TBuddyManager.CountBuddies: Integer;
begin
  Result := Length(FBuddies);
end;

function TBuddyManager.GetBuddy(Index: Integer): TBuddy;
begin
  if (Index < 0) or (Index >= Length(FBuddies)) then
    raise Exception.Create('Buddy index out of range');
  Result := FBuddies[Index];
end;

procedure TBuddyManager.SetBuddy(Index: Integer; const B: TBuddy);
begin
  if (Index < 0) or (Index >= Length(FBuddies)) then
    raise Exception.Create('Buddy index out of range');
  FBuddies[Index] := B;
end;

procedure TBuddyManager.AddBuddy(const B: TBuddy);
var
  n: Integer;
begin
  n := Length(FBuddies);
  SetLength(FBuddies, n + 1);
  FBuddies[n] := B;
end;

procedure TBuddyManager.RemoveBuddy(Index: Integer);
var
  i: Integer;
begin
  if (Index < 0) or (Index >= Length(FBuddies)) then Exit;

  for i := Index to High(FBuddies) - 1 do
    FBuddies[i] := FBuddies[i + 1];

  SetLength(FBuddies, Length(FBuddies) - 1);
end;

function TBuddyManager.GetDisplayName(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Length(FBuddies)) then
    Exit('');
  if FBuddies[Index].Name <> '' then
    Result := FBuddies[Index].Name
  else
    Result := FBuddies[Index].Host;
end;

end.


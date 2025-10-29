unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, blcksock, synsock, ExtCtrls;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    Edit1: TEdit;
    Edit2: TEdit;
    Label1: TLabel;
    Memo1: TMemo;
    port: TEdit;
    procedure Edit1Change(Sender: TObject);
    procedure Memo1Change(Sender: TObject);
    procedure portChange(Sender: TObject);
    procedure Label1Click(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
  private
    FSocket: TTCPBlockSocket;  // The socket object
    FConnected: Boolean;        // Connection state

  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.Label1Click(Sender: TObject);
begin

end;

procedure TForm1.Button1Click(Sender: TObject);
var
  Host: string;
  PortToConnect: Integer;
begin
   if not FConnected then
  begin
    Host := Edit1.Text;  // IP field
    PortToConnect := StrToIntDef(port.Text, 8080);  // Port field

    FSocket := TTCPBlockSocket.Create;
    FSocket.Connect(Host, IntToStr(PortToConnect));

    if FSocket.LastError = 0 then
    begin
      FConnected := True;
      Memo1.Lines.Add('Connected to ' + Host + ':' + IntToStr(PortToConnect));
    end
    else
    begin
      Memo1.Lines.Add('Error: ' + FSocket.LastErrorDesc);
      FSocket.Free;
    end;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin

end;

procedure TForm1.Button3Click(Sender: TObject);
begin

end;

procedure TForm1.portChange(Sender: TObject);
begin

end;

procedure TForm1.Edit1Change(Sender: TObject);
begin

end;

procedure TForm1.Memo1Change(Sender: TObject);
begin

end;

end.


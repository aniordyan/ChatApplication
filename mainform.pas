unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, blcksock, synsock, ExtCtrls;

type

  { TReceiverThread - Background thread for receiving data }
  TReceiverThread = class(TThread)
  private
    FSocket: TTCPBlockSocket;
    FReceivedData: string;
    procedure UpdateMemo;
  protected
    procedure Execute; override;
  public
    constructor Create(ASocket: TTCPBlockSocket);
  end;

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
    //Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
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
    FReceiverThread: TReceiverThread;

  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TReceiverThread }

constructor TReceiverThread.Create(ASocket: TTCPBlockSocket);
begin
  inherited Create(False);  // Create not suspended
  FreeOnTerminate := True;  // Auto-free when done
  FSocket := ASocket;
end;

procedure TReceiverThread.Execute;
var
  ReceivedLine: string;
begin
  while not Terminated do
  begin
    // Wait for data with timeout (1 second)
    ReceivedLine := FSocket.RecvString(1000);

    // Check if data was received
    if (FSocket.LastError = 0) and (ReceivedLine <> '') then
    begin
      FReceivedData := ReceivedLine;
      Synchronize(@UpdateMemo);  // Safely update GUI
    end
    else if FSocket.LastError <> 0 then
    begin
      // Connection lost or error
      if FSocket.LastError <> WSAETIMEDOUT then  // Ignore timeout errors
      begin
        FReceivedData := 'Կապը խզվեց: ' + FSocket.LastErrorDesc;
        Synchronize(@UpdateMemo);
        Break;  // Exit thread
      end;
    end;

    Sleep(10);  // Small delay to reduce CPU usage
  end;
end;

procedure TReceiverThread.UpdateMemo;
begin
  // This runs in main thread - safe to update GUI
  Form1.Memo1.Lines.Add('◄ Ստացված: ' + FReceivedData);
end;

{ TForm1 }
procedure TForm1.FormCreate(Sender: TObject);
begin
  // Initialize variables
  FConnected := False;
  FSocket := nil;
  FReceiverThread := nil;

  // Setup UI
  Memo1.Clear;
  Memo1.Lines.Add('Պատրաստ է կապվելու...');

  // Set default values
  Edit1.Text := '127.0.0.1';
  port.Text := '8080';

  // Disable disconnect and send buttons initially
  Button2.Enabled := False;
  Button3.Enabled := False;
end;

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
      FReceiverThread := TReceiverThread.Create(FSocket);
      Application.ProcessMessages;
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
var
  Message: string;
begin
  if not FConnected then
  begin
    Memo1.Lines.Add('Սխալ: Կապ չկա։');
    Exit;
  end;

  Message := Edit2.Text;

  if Message = '' then Exit;

  // Send the message with newline
  FSocket.SendString(Message + #13#10);

  if FSocket.LastError = 0 then
  begin
    Memo1.Lines.Add('Ուղարկված: ' + Message);
    Edit2.Clear;
  end
  else
  begin
    Memo1.Lines.Add('Սխալ: ' + FSocket.LastErrorDesc);
  end;

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

procedure TForm1.FormDestroy(Sender: TObject);
begin
  // Stop receiver thread if running
  if Assigned(FReceiverThread) then
  begin
    FReceiverThread.Terminate;
    FReceiverThread := nil;
  end;

  // Close socket if open
  if Assigned(FSocket) then
  begin
    FSocket.Free;
    FSocket := nil;
  end;
end;

end.


unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  blcksock, synsock; // tcp/ip library

type
  TForm1 = class;

 type    //recieve data, append to memo
  TReceiverThread = class(TThread)
  private
    FSocket: TTCPBlockSocket;
    FMemo: TMemo;
    FBuf: string;
    FLines: TStringList;
    procedure AppendLines;
  public
    constructor Create(ASocket: TTCPBlockSocket; AMemo: TMemo);
    destructor Destroy; override;
    procedure Execute; override;      //main
  end;


  { TAcceptorThread }
  type
  TAcceptorThread = class(TThread)
  private
    FListenSock: TTCPBlockSocket;
    FPort: string;
    FOwner: TForm1;
    FAcceptedSock: TTCPBlockSocket;  // <— add this
    procedure SyncAccepted;          // <— add this
  protected
    procedure Execute; override;
  public
    constructor Create(APort: string; AOwner: TForm1);
    destructor Destroy; override;
    procedure StopListening;
  end;


  { TForm1 }
  TForm1 = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    Label1: TLabel;
    Label3: TLabel;
    port: TEdit;      // client port
    port2: TEdit;     // listen port
    Edit1: TEdit;     // remote IP
    Memo1: TMemo;     // messages
    Edit2: TEdit;     // message input
    Button1: TButton; // Connect (կպնել)
    Button3: TButton; // Send (ուղարկել)
    Button5: TButton; // Start Listening (լսել)
    Button6: TButton; // Stop/Disconnect (խզել)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button1Click(Sender: TObject); // Connect
    procedure Button3Click(Sender: TObject); // Send
    procedure Button5Click(Sender: TObject); // Start Listening
    procedure Button6Click(Sender: TObject); // Stop/Disconnect
  private
    FClientSock: TTCPBlockSocket; // active connected socket (client or accepted)
    FRecvThread: TReceiverThread;
    FAcceptor: TAcceptorThread;
    procedure Log(const S: string);
    procedure StartReceiver(ASocket: TTCPBlockSocket);
    procedure OnAccepted(ASocket: TTCPBlockSocket);
    procedure CloseActiveSocket;
    function IsConnected: Boolean;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

function TForm1.IsConnected: Boolean;
begin
  Result := Assigned(FClientSock) and (FClientSock.Socket <> INVALID_SOCKET);
end;


{ TReceiverThread }

constructor TReceiverThread.Create(ASocket: TTCPBlockSocket; AMemo: TMemo);
begin
  inherited Create(False);     //start thread
  FreeOnTerminate := True;
  FSocket := ASocket;
  FMemo := AMemo;
  FBuf := '';
  FLines := TStringList.Create;
end;

destructor TReceiverThread.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TReceiverThread.AppendLines;
var
  i: Integer;
begin
  for i := 0 to FLines.Count - 1 do
    if FLines[i] <> '' then
      FMemo.Lines.Add('[ուրվական] ' + FLines[i]);
end;

procedure TReceiverThread.Execute;
var
  chunk, line: string;
  p: SizeInt;
begin
  while not Terminated do
  begin
    // wait until there is data to read, timeout every 100
    if FSocket.CanRead(100) then
    begin
      chunk := FSocket.RecvPacket(100);

      if FSocket.LastError <> 0 then
        Break;

      if chunk <> '' then
      begin
        // if we got data, buffer and split lines
        FBuf := FBuf + chunk;
        FLines.Clear;

        // CRLF to LF
        FBuf := StringReplace(FBuf, #13#10, #10, [rfReplaceAll]);

        while True do
        begin
          p := Pos(#10, FBuf);
          if p = 0 then Break;
          line := Copy(FBuf, 1, p - 1);
          Delete(FBuf, 1, p); // remove line + LF
          FLines.Add(line);
        end;

        if FLines.Count > 0 then
          Synchronize(@AppendLines);
      end;
    end;
  end;
end;


{ TAcceptorThread }

constructor TAcceptorThread.Create(APort: string; AOwner: TForm1);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FPort := APort;
  FOwner := AOwner;
  FListenSock := TTCPBlockSocket.Create;
end;

destructor TAcceptorThread.Destroy;
begin
  if Assigned(FListenSock) then
    FListenSock.Free;
  inherited Destroy;
end;

procedure TAcceptorThread.StopListening;
begin
  Terminate;
  try
    if Assigned(FListenSock) then
      FListenSock.CloseSocket;
  except end;
end;

procedure TAcceptorThread.Execute;
var
  s: TSocket;
  clientSock: TTCPBlockSocket;
begin
  try
    FListenSock.CreateSocket;
    FListenSock.SetLinger(True, 1000);
    FListenSock.Bind('0.0.0.0', FPort);
    FListenSock.Listen;
    FOwner.Log('Listening on port ' + FPort);

    while not Terminated do
    begin
      if FListenSock.CanRead(1000) then
      begin
        s := FListenSock.Accept; // returns TSocket
        if s <> INVALID_SOCKET then
        begin
          clientSock := TTCPBlockSocket.Create;
          clientSock.Socket := s;

          // pass to ui
          FAcceptedSock := clientSock;
          Synchronize(@SyncAccepted);
          // now form have the socket
        end;
      end;
      Sleep(1);
    end;
  except
    on E: Exception do
      FOwner.Log('Listener error: ' + E.Message);
  end;
  FOwner.Log('Listener stopped');
end;


procedure TAcceptorThread.SyncAccepted;
begin
  // socket to form
  FOwner.OnAccepted(FAcceptedSock);
  FAcceptedSock := nil;
end;


{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FClientSock := nil;
  FRecvThread := nil;
  FAcceptor := nil;
  Memo1.Lines.Clear;
  Memo1.Lines.Add('զրուցարան');
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FAcceptor) then
  begin
    FAcceptor.StopListening;
    FAcceptor.WaitFor;
    FreeAndNil(FAcceptor);
  end;
  CloseActiveSocket;
end;

procedure TForm1.Log(const S: string);
begin
  Memo1.Lines.Add(S);
end;

procedure TForm1.StartReceiver(ASocket: TTCPBlockSocket);
begin
  if Assigned(FRecvThread) then
  begin
    FRecvThread.Terminate;
    FRecvThread.WaitFor;
    FRecvThread := nil;
  end;
  FRecvThread := TReceiverThread.Create(ASocket, Memo1);
end;

procedure TForm1.OnAccepted(ASocket: TTCPBlockSocket);
begin
  // take socket, start recieving
  CloseActiveSocket;
  FClientSock := ASocket;
  Log('ստացած՝ ' + FClientSock.GetRemoteSinIP + ':' + IntToStr(FClientSock.GetRemoteSinPort));
  StartReceiver(FClientSock);
end;

procedure TForm1.CloseActiveSocket;
begin
  if Assigned(FRecvThread) then
  begin
    FRecvThread.Terminate;
    FRecvThread.WaitFor;
    FRecvThread := nil;
  end;
  if Assigned(FClientSock) then
  begin
    try FClientSock.CloseSocket; except end;
    FreeAndNil(FClientSock);
  end;
end;

procedure TForm1.Button5Click(Sender: TObject); // start Listening
begin
  if Assigned(FAcceptor) then
  begin
    Log('լսում է՝');
    Exit;
  end;
  FAcceptor := TAcceptorThread.Create(Trim(port2.Text), Self);
  Log('սկսել լսել՝');
end;

procedure TForm1.Button6Click(Sender: TObject); // stop
begin
  if Assigned(FAcceptor) then
  begin
    FAcceptor.StopListening;
    FAcceptor.WaitFor;
    FreeAndNil(FAcceptor);
  end;
  CloseActiveSocket;
  Log('ստոպ');
end;

procedure TForm1.Button1Click(Sender: TObject); // connect
begin
  CloseActiveSocket;
  FClientSock := TTCPBlockSocket.Create;
  try
    FClientSock.Connect(Trim(Edit1.Text), Trim(port.Text));
    if FClientSock.LastError = 0 then
    begin
      Log('կպնել՝ ' + Trim(Edit1.Text) + ':' + Trim(port.Text));
      StartReceiver(FClientSock);
    end
    else
    begin
      Log('կապը չստացվեց՝ ' + IntToStr(FClientSock.LastError));
      FreeAndNil(FClientSock);
    end;
  except
    on E: Exception do
    begin
      Log('exception: ' + E.Message);
      FreeAndNil(FClientSock);
    end;
  end;
end;

procedure TForm1.Button3Click(Sender: TObject); // send
var
  msg: string;
begin
  msg := Trim(Edit2.Text);
  if msg = '' then Exit;

  if IsConnected then
  begin
    FClientSock.SendString(msg + #13#10);
    if FClientSock.LastError = 0 then
      Log('[ես] ' + msg)
    else
      Log('error: ' + IntToStr(FClientSock.LastError));
  end
  else
    Log('կապ չկա');

  Edit2.Text := '';
end;

end.


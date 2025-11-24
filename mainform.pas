unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Sockets, BaseUnix, IniFiles, uBuddies, Buttons; // use FPC networking units

type
  TForm1 = class;


  TSocketHandle = cint;
const
  INVALID_SOCKET = -1;

type
  // =========================
  // Receiver thread (incoming data)
  // =========================
  TReceiverThread = class(TThread)
  private
    FSocket: TSocketHandle;
    FMemo: TMemo;
    FBuf: string;
    FLines: TStringList;
    procedure AppendLines;
  public
    constructor Create(ASocket: TSocketHandle; AMemo: TMemo);
    destructor Destroy; override;
    procedure Execute; override;      //main
  end;


  // =========================
  // Acceptor thread (server side)
  // =========================
  TAcceptorThread = class(TThread)
  private
    FListenSock: TSocketHandle;
    FPort: string;
    FOwner: TForm1;
    FAcceptedSock: TSocketHandle;
    procedure SyncAccepted;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TForm1; const APort: string);
    destructor Destroy; override;
    procedure StopListening;
  end;


  { TForm1 }
  TForm1 = class(TForm)
    Label2: TLabel;
    Panel1: TPanel;     // buddies panel
    Label1: TLabel;     // "տնեցիք"
    Button1: TButton;   // "+" (Add buddy)
    Button6: TButton;   // "-" (Remove buddy)

    Edit1: TEdit;       // IP/host
    port: TEdit;        // port
    Memo1: TMemo;       // chat log
    Edit2: TEdit;       // outgoing message

    Button2: TButton;   // "կպնել" (Connect)
    Button4: TButton;   // "խզել" (Disconnect)
    Button5: TButton;   // "լսել" (Listen)
    Button3: TButton;   // "ուղարկել" (Send)

    lstBuddies: TListBox;
    Shape1: TShape;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    procedure Button1Click(Sender: TObject); // add buddy
    procedure Button6Click(Sender: TObject); // remove buddy
    procedure lstBuddiesDblClick(Sender: TObject);

    procedure Button2Click(Sender: TObject); // connect
    procedure Button4Click(Sender: TObject); // disconnect
    procedure Button5Click(Sender: TObject); // listen
    procedure Button3Click(Sender: TObject); // send

    procedure Edit1Change(Sender: TObject);
    procedure Memo1Change(Sender: TObject);
    procedure portChange(Sender: TObject);
    procedure Label1Click(Sender: TObject);
  private
    FSocket: TSocketHandle;
    FConnected: Boolean;
    FReceiverThread: TReceiverThread;
    FAcceptorThread: TAcceptorThread;

    FBuddyManager: TBuddyManager;

    procedure AttachIncomingSocket(ASocket: TSocketHandle);
    procedure UpdateButtons;

    function GetConfigFileName: string;
    procedure RefreshBuddyList;
    procedure ConnectToHost(const Host, PortStr: string);
  public
  end;


var
  Form1: TForm1;

implementation

{$R *.lfm}

{ =========================
  Helper functions for FPC sockets
  ========================= }

function SocketCanRead(Sock: TSocketHandle; TimeoutMs: LongInt): Boolean;
var
  FDSet: TFDSet;
  TV: TTimeVal;
  Res: cint;
begin
  Result := False;
  if Sock = INVALID_SOCKET then Exit;

  fpFD_ZERO(FDSet);
  fpFD_SET(Sock, FDSet);

  TV.tv_sec  := TimeoutMs div 1000;
  TV.tv_usec := (TimeoutMs mod 1000) * 1000;

  Res := fpSelect(Sock + 1, @FDSet, nil, nil, @TV);
  Result := (Res > 0) and (fpFD_ISSET(Sock, FDSet) <> 0);
end;

function SocketRecvPacket(Sock: TSocketHandle; TimeoutMs: LongInt): string;
const
  BUF_SIZE = 4096;
var
  Buf: array[0..BUF_SIZE - 1] of Byte;
  R: ssize_t;
begin
  Result := '';
  if not SocketCanRead(Sock, TimeoutMs) then Exit;

  R := fpRecv(Sock, @Buf[0], BUF_SIZE, 0);
  if R <= 0 then Exit; // connection closed or error

  SetLength(Result, R);
  Move(Buf[0], Result[1], R);
end;

function SocketSendString(Sock: TSocketHandle; const S: string): Boolean;
var
  SentTotal, ToSend: SizeInt;
  R: ssize_t;
begin
  Result := False;
  if Sock = INVALID_SOCKET then Exit;
  if S = '' then Exit(True);

  SentTotal := 0;
  ToSend := Length(S);
  while SentTotal < ToSend do
  begin
    R := fpSend(Sock, @S[SentTotal + 1], ToSend - SentTotal, 0);
    if R <= 0 then Exit; // error
    Inc(SentTotal, R);
  end;
  Result := True;
end;

procedure CloseSocketSafe(var Sock: TSocketHandle);
begin
  if Sock <> INVALID_SOCKET then
  begin
    fpClose(Sock);
    Sock := INVALID_SOCKET;
  end;
end;

function SocketGetPeerInfo6(Sock: TSocketHandle; out IP: string; out Port: Word): Boolean;
var
  Addr: TInetSockAddr6;
  Len: TSockLen;
begin
  IP := '';
  Port := 0;
  Len := SizeOf(Addr);
  FillChar(Addr, Len, 0);
  Result := (fpGetPeerName(Sock, @Addr, @Len) = 0);
  if Result then
  begin
    IP   := HostAddrToStr6(Addr.sin6_addr);
    Port := ntohs(Addr.sin6_port);
  end;
end;

{ TReceiverThread }

constructor TReceiverThread.Create(ASocket: TSocketHandle; AMemo: TMemo);
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
    // wait until there is data to read
    if SocketCanRead(FSocket, 100) then
    begin
      chunk := SocketRecvPacket(FSocket, 100);

      if chunk = '' then
        Break; // closed or error

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


{ TAcceptorThread }

constructor TAcceptorThread.Create(AOwner: TForm1; const APort: string);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FPort := APort;
  FListenSock := INVALID_SOCKET;
  FAcceptedSock := INVALID_SOCKET;
end;

destructor TAcceptorThread.Destroy;
begin
  CloseSocketSafe(FListenSock);
  inherited Destroy;
end;

procedure TAcceptorThread.StopListening;
begin
  Terminate;
  try
    if FListenSock <> INVALID_SOCKET then
      fpShutdown(FListenSock, 2); // wake select/accept
  except
  end;
end;

procedure TAcceptorThread.Execute;
var
  Addr6: TInetSockAddr6;
  ClientAddr6: TInetSockAddr6;
  Len: TSockLen;
  ClientSock: TSocketHandle;
  Opt: cint;
begin
  try
    // Pure IPv6 socket
    FListenSock := fpSocket(AF_INET6, SOCK_STREAM, 0);
    if FListenSock = INVALID_SOCKET then Exit;

    //
    Opt := 1;
    fpSetSockOpt(FListenSock, IPPROTO_IPV6, IPV6_V6ONLY, @Opt, SizeOf(Opt));

    // Bind to :: on specified port
    FillChar(Addr6, SizeOf(Addr6), 0);
    Addr6.sin6_family := AF_INET6;
    Addr6.sin6_port   := htons(StrToIntDef(FPort, 0));
    Addr6.sin6_addr   := StrToHostAddr6('::'); // all IPv6 interfaces

    if fpBind(FListenSock, @Addr6, SizeOf(Addr6)) <> 0 then
      Exit;

    if fpListen(FListenSock, 5) <> 0 then
      Exit;

    //if Assigned(FOwner) then
      //FOwner.Memo1.Lines.Add('Listening [IPv6] on port ' + FPort);

    while not Terminated do
    begin
      Len := SizeOf(ClientAddr6);
      ClientSock := fpAccept(FListenSock, @ClientAddr6, @Len);
      if ClientSock >= 0 then
      begin
        FAcceptedSock := ClientSock;
        Synchronize(@SyncAccepted);
        FAcceptedSock := INVALID_SOCKET;
      end
      else
      begin
        if Terminated then Break;
        Sleep(10);
      end;
    end;
  except
    on E: Exception do
      if Assigned(FOwner) then
        FOwner.Memo1.Lines.Add('Listener error: ' + E.Message);
  end;

  if Assigned(FOwner) then
    FOwner.Memo1.Lines.Add('Listener stopped');
end;

procedure TAcceptorThread.SyncAccepted;
begin
  if Assigned(FOwner) and (FAcceptedSock <> INVALID_SOCKET) then
    FOwner.AttachIncomingSocket(FAcceptedSock);
end;


{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FSocket := INVALID_SOCKET;
  FReceiverThread := nil;
  FAcceptorThread := nil;
  FConnected := False;

  Memo1.Lines.Clear;
  Memo1.Lines.Add('զրուցարան');

  FBuddyManager := TBuddyManager.Create(GetConfigFileName);
  FBuddyManager.Load;
  RefreshBuddyList;

  UpdateButtons;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FBuddyManager.Save;
  FBuddyManager.Free;

  if Assigned(FAcceptorThread) then
  begin
    FAcceptorThread.StopListening;
    FAcceptorThread.WaitFor;
    FreeAndNil(FAcceptorThread);
  end;

  if Assigned(FReceiverThread) then
  begin
    FReceiverThread.Terminate;
    FReceiverThread := nil;
  end;

  CloseSocketSafe(FSocket);
end;

procedure TForm1.AttachIncomingSocket(ASocket: TSocketHandle);
var
  ip: string;
  p: Word;
begin
  CloseSocketSafe(FSocket);
  FSocket := ASocket;
  FConnected := True;

  if SocketGetPeerInfo6(FSocket, ip, p) then
    Memo1.Lines.Add('Միացում ստացվեց՝ [' + ip + ']:' + IntToStr(p))
  else
    Memo1.Lines.Add('Միացում ստացվեց։');

  FReceiverThread := TReceiverThread.Create(FSocket, Memo1);
  FAcceptorThread := nil; // we stop listening once connected

  UpdateButtons;
end;


{ ============= BUDDIES HANDLING ============= }

procedure TForm1.ConnectToHost(const Host, PortStr: string);
var
  Addr6: TInetSockAddr6;
  PortNum: Integer;
begin
  if Host = '' then
  begin
    Memo1.Lines.Add('Սխալ: IP/հասցե չի մուտքագրված։');
    Exit;
  end;

  if PortStr = '' then
  begin
    Memo1.Lines.Add('Սխալ: պորտը չի մուտքագրված։');
    Exit;
  end;

  if FConnected then
  begin
    Memo1.Lines.Add('Արդեն կա կապ: նախ խզիր հինը։');
    Exit;
  end;

  PortNum := StrToIntDef(PortStr, 0);
  if PortNum <= 0 then
  begin
    Memo1.Lines.Add('Սխալ պորտի համար։');
    Exit;
  end;

  FSocket := fpSocket(AF_INET6, SOCK_STREAM, 0);
  if FSocket = INVALID_SOCKET then
  begin
    Memo1.Lines.Add('Չստացվեց ստեղծել սոկետ։');
    Exit;
  end;

  FillChar(Addr6, SizeOf(Addr6), 0);
  Addr6.sin6_family := AF_INET6;
  Addr6.sin6_port   := htons(PortNum);

  //  expect literal IPv6 address in Edit1 - maybe chnage later
  Addr6.sin6_addr := StrToHostAddr6(Host);

  if fpConnect(FSocket, @Addr6, SizeOf(Addr6)) <> 0 then
  begin
    Memo1.Lines.Add('Սխալ կապի ժամանակ։');
    CloseSocketSafe(FSocket);
    Exit;
  end;

  FConnected := True;
  Memo1.Lines.Add('Միացա [' + Host + ']:' + PortStr);

  FReceiverThread := TReceiverThread.Create(FSocket, Memo1);
  UpdateButtons;
end;

procedure TForm1.lstBuddiesDblClick(Sender: TObject);
var
  idx: Integer;
  B: TBuddy;
begin
  idx := lstBuddies.ItemIndex;
  if idx < 0 then Exit;

  B := FBuddyManager.GetBuddy(idx);

  Edit1.Text := B.Host;
  port.Text  := B.Port;

  ConnectToHost(B.Host, B.Port);
end;

function TForm1.GetConfigFileName: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'buddies.conf';
end;

procedure TForm1.RefreshBuddyList;
var
  i: Integer;
begin
  lstBuddies.Items.Clear;
  for i := 0 to FBuddyManager.CountBuddies - 1 do
    lstBuddies.Items.Add(FBuddyManager.GetDisplayName(i));
end;


{ ============= BUTTONS ============= }

procedure TForm1.Button1Click(Sender: TObject); // add buddy
var
  B: TBuddy;
  Buddyname: string;
begin
  B.Host := '';
  B.Port := '';
  B.Name := '';

  if not InputQuery('Ավելացնել տնեցի', 'IPv6 հասցե:', B.Host) then
    Exit;

  B.Host := Trim(B.Host);
  if B.Host = '' then
  begin
    ShowMessage('Մուտքագրի՛ր IPv6 հասցեն։');
    Exit;
  end;

  if not InputQuery('Ավելացնել տնեցի', 'Պորտ:', B.Port) then
    Exit;

  B.Port := Trim(B.Port);
  if B.Port = '' then
  begin
    ShowMessage('Մուտքագրի՛ր պորտը։');
    Exit;
  end;

  Buddyname := B.Host;
  if not InputQuery('Ավելացնել տնեցի', 'Անուն (ցուցադրվող):', Buddyname) then
    Exit;

  B.Name := Trim(Buddyname);

  FBuddyManager.AddBuddy(B);
  FBuddyManager.Save;
  RefreshBuddyList;

  Memo1.Lines.Add('Տնեցին ավելացվեց: ' + B.Name);
end;

procedure TForm1.Button6Click(Sender: TObject);
var
  idx: Integer;
begin
  idx := lstBuddies.ItemIndex;
  if idx < 0 then Exit;

  if MessageDlg('Ջնջե՞լ ընտրված տնեցուն։',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FBuddyManager.RemoveBuddy(idx);
    FBuddyManager.Save;
    RefreshBuddyList;
  end;
end;

procedure TForm1.Button3Click(Sender: TObject);
var
  MessageStr: string;
begin
  if not FConnected then
  begin
    Memo1.Lines.Add('Սխալ: Կապ չկա։');
    Exit;
  end;

  MessageStr := Trim(Edit2.Text);
  if MessageStr = '' then Exit;

  if SocketSendString(FSocket, MessageStr + #13#10) then
  begin
    Memo1.Lines.Add('► Ուղարկված: ' + MessageStr);
    Edit2.Clear;
  end
  else
    Memo1.Lines.Add('Սխալ ուղարկելու ժամանակ։');
end;

procedure TForm1.Button5Click(Sender: TObject);
var
  PortStr: string;
begin
  if Assigned(FAcceptorThread) then
  begin
    Memo1.Lines.Add('Արդեն լսում ես։');
    Exit;
  end;

  PortStr := Trim(port.Text);
  if PortStr = '' then
    PortStr := '8080';

  Memo1.Lines.Add('Լսում եմ [IPv6] պորտի վրա ' + PortStr + ' ...');

  FAcceptorThread := TAcceptorThread.Create(Self, PortStr);
  UpdateButtons;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  ConnectToHost(Trim(Edit1.Text), Trim(port.Text));
end;

procedure TForm1.Button4Click(Sender: TObject);
begin
  if not FConnected and not Assigned(FAcceptorThread) then Exit;

  Memo1.Lines.Add('Կապը խզվեց (ձեռքով)։');

  if Assigned(FReceiverThread) then
  begin
    FReceiverThread.Terminate;
    FReceiverThread := nil;
  end;

  CloseSocketSafe(FSocket);
  FConnected := False;

  if Assigned(FAcceptorThread) then
  begin
    FAcceptorThread.StopListening;
    FAcceptorThread.WaitFor;
    FreeAndNil(FAcceptorThread);
  end;

  UpdateButtons;
end;

procedure TForm1.UpdateButtons;
begin
  Button2.Enabled := not FConnected;                       // connect
  Button5.Enabled := not FConnected and
                     not Assigned(FAcceptorThread);        // listen
  Button4.Enabled := FConnected or Assigned(FAcceptorThread); // disconnect
  Button3.Enabled := FConnected;                           // send

  Button1.Enabled := True;                                 // add buddy always
  Button6.Enabled := lstBuddies.ItemIndex >= 0;            // remove buddy if selected
end;


{ ============= OTHER UI HANDLERS ============= }

procedure TForm1.Edit1Change(Sender: TObject);
begin
end;

procedure TForm1.Memo1Change(Sender: TObject);
begin
end;

procedure TForm1.portChange(Sender: TObject);
begin
end;

procedure TForm1.Label1Click(Sender: TObject);
begin
end;

end.


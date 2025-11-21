unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  blcksock, synsock, IniFiles, uBuddies; // tcp/ip library    + conf file for storing buddies


type
  TForm1 = class;  // forward declaration


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
    FAcceptedSock: TTCPBlockSocket;
    procedure SyncAccepted;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TForm1; const APort: string);
    destructor Destroy; override;
    procedure StopListening;
  end;




  { TForm1 }
  type
  TForm1 = class(TForm)
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

    lstBuddies: TListBox; // ADD THIS in the designer inside Panel1

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
    FSocket: TTCPBlockSocket;
    FConnected: Boolean;
    FReceiverThread: TReceiverThread;
    FAcceptorThread: TAcceptorThread;

    //FBuddies: array of TBuddy;
    FBuddyManager: TBuddyManager;

    procedure AttachIncomingSocket(ASocket: TTCPBlockSocket);        //
    procedure UpdateButtons;                                           //no impl

    function GetConfigFileName: string;                            //
    procedure RefreshBuddyList;                                  //
    procedure ConnectToHost(const Host, PortStr: string);       //
  public
  end;


var
  Form1: TForm1;

implementation

{$R *.lfm}



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
constructor TAcceptorThread.Create(AOwner: TForm1; const APort: string);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FPort := APort;
  FListenSock := TTCPBlockSocket.Create;
  FAcceptedSock := nil;
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
  except
  end;
end;

procedure TAcceptorThread.Execute;
var
  s: TSocket;
begin
  FListenSock.CreateSocket;
  FListenSock.SetLinger(True, 1000);

  // Try IPv4 first (simpler for testing)
  FListenSock.Family := SF_IP4;
  FListenSock.Bind('127.0.0.1', FPort);

  if FListenSock.LastError <> 0 then
  begin
    // Can't log directly, but thread will exit
    Exit;
  end;

  FListenSock.Listen;

  if FListenSock.LastError <> 0 then
    Exit;

  while not Terminated do
  begin
    if FListenSock.CanRead(1000) then
    begin
      s := FListenSock.Accept;
      if s <> INVALID_SOCKET then
      begin
        FAcceptedSock := TTCPBlockSocket.Create;
        FAcceptedSock.Socket := s;
        Synchronize(@SyncAccepted);
        // Break after first connection (optional)
        // Break;
      end;
    end;
  end;
end;

procedure TAcceptorThread.SyncAccepted;
begin
  if Assigned(FOwner) and Assigned(FAcceptedSock) then
  begin
    FOwner.AttachIncomingSocket(FAcceptedSock);
    FAcceptedSock := nil; // owner now owns the socket
  end;
end;


{ TForm1 }

//SOCKETS START

procedure TForm1.FormCreate(Sender: TObject);
begin
  FSocket := nil;
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

  if Assigned(FSocket) then
  begin
    FSocket.Free;
    FSocket := nil;
  end;
end;

procedure TForm1.AttachIncomingSocket(ASocket: TTCPBlockSocket);
begin
  FSocket := ASocket;
  FConnected := True;

  Memo1.Lines.Add('Միացում ստացվեց։');

  FReceiverThread := TReceiverThread.Create(FSocket, Memo1);
  FAcceptorThread := nil; // we stop listening once connected

  UpdateButtons;
end;



//SOCKETS END



//BUDDIES HANDELING   START

procedure TForm1.ConnectToHost(const Host, PortStr: string);
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

  FSocket := TTCPBlockSocket.Create;

  FSocket.Connect(Host, PortStr);

  if FSocket.LastError = 0 then
  begin
    FConnected := True;
    Memo1.Lines.Add('Միացա ' + Host + ':' + PortStr);
    FReceiverThread := TReceiverThread.Create(FSocket, Memo1);
    UpdateButtons;
  end
  else
  begin
    Memo1.Lines.Add('Սխալ կապի ժամանակ: ' + FSocket.LastErrorDesc);
    FSocket.Free;
    FSocket := nil;
  end;
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

  ConnectToHost(B.Host, B.Port); // your existing connect helper
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
//BUDDIES HANDELING     END




//BUTTONS    START

procedure TForm1.Button1Click(Sender: TObject); // add buddy
var
  B: TBuddy;
  Buddyname: string;
begin
  // Initialize empty
  B.Host := '';
  B.Port := '';
  B.Name := '';

  // Ask for Host/IP
  if not InputQuery('Ավելացնել տնեցիք', 'IP/Հասցե:', B.Host) then
    Exit;

  B.Host := Trim(B.Host);
  if B.Host = '' then
  begin
    ShowMessage('Մուտքագրի՛ր IP/հասցեն։');
    Exit;
  end;

  // Ask for Port
  if not InputQuery('Ավելացնել տնեցիք', 'Պորտ:', B.Port) then
    Exit;

  B.Port := Trim(B.Port);
  if B.Port = '' then
  begin
    ShowMessage('Մուտքագրի՛ր պորտը։');
    Exit;
  end;

  // Ask for Display Name (pre-filled with host)
  Buddyname := B.Host;
  if not InputQuery('Ավելացնել տնեցիք', 'Անուն (ցուցադրվող):', Buddyname) then
    Exit;

  B.Name := Trim(Buddyname);

  // Add and save
  FBuddyManager.AddBuddy(B);
  FBuddyManager.Save;
  RefreshBuddyList;

  Memo1.Lines.Add('Տնեցիքը ավելացվեց: ' + B.Name);
end;

procedure TForm1.Button6Click(Sender: TObject);
var
  idx: Integer;
begin
  idx := lstBuddies.ItemIndex;
  if idx < 0 then Exit;

  if MessageDlg('Ջնջե՞լ ընտրված տնեցիքին։',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FBuddyManager.RemoveBuddy(idx);
    FBuddyManager.Save;
    RefreshBuddyList;
  end;
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

  Message := Trim(Edit2.Text);
  if Message = '' then Exit;

  FSocket.SendString(Message + #13#10);

  if FSocket.LastError = 0 then
  begin
    Memo1.Lines.Add('► Ուղարկված: ' + Message);
    Edit2.Clear;
  end
  else
  begin
    Memo1.Lines.Add('Սխալ ուղարկելու ժամանակ: ' + FSocket.LastErrorDesc);
  end;
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

  Memo1.Lines.Add('Լսում եմ պորտի վրա ' + PortStr + ' ...');

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

  if Assigned(FSocket) then
  begin
    FSocket.Free;
    FSocket := nil;
  end;

  FConnected := False;

  if Assigned(FAcceptorThread) then
  begin
    FAcceptorThread.Terminate;
    FAcceptorThread := nil;
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

//BUTTONS END


//OTHER UI COMPONENTS START
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

//COMPONENTS END

end.


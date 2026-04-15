program ClipboardSL;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Process, fphttpclient, HTTPDefs;

var
  LastText: string = '';
  LastServerText: string = '';
  Text: string;
  ServerText:string;
  ServerIP: string = '192.168.1.204';
  ServerPort: string = '8080';
  SERVER_URL: string;

 procedure ShowHelp;
begin
  Writeln('ClipboardSyncLinux - LAN clipboard sync tool');
  Writeln('');
  Writeln('Usage:');
  Writeln('  ./ClipboardSL -a <IP> -p <PORT>');
  Writeln('');
  Writeln('Options:');
  Writeln('  -a <ip>     Server IP address (default: 192.168.1.204)');
  Writeln('  -p <port>   Server port (default: 8080)');
  Writeln('  -h          Show this help message');
  Writeln('  --help      Show this help message');
  Writeln('');
  Writeln('Examples:');
  Writeln('  ./ClipboardSL');
  Writeln('  ./ClipboardSL -a 192.168.1.50');
  Writeln('  ./ClipboardSL -a 192.168.1.50 -p 9000');
  Writeln('');
end;

procedure ParseArgs;
var
  i: Integer;
begin
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
    begin
      ShowHelp;
      Halt;
    end

    else if ParamStr(i) = '-a' then
    begin
      if i < ParamCount then
      begin
        ServerIP := ParamStr(i + 1);
        Inc(i);
      end;
    end

    else if ParamStr(i) = '-p' then
    begin
      if i < ParamCount then
      begin
        ServerPort := ParamStr(i + 1);
        Inc(i);
      end;
    end;

    Inc(i);
  end;
end;

   
procedure SetClipboardText(const AText: string);
var
  P: TProcess;
  Bytes: TBytes;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := 'xclip';
    P.Parameters.Add('-selection');
    P.Parameters.Add('clipboard');
    P.Parameters.Add('-i');

    P.Options := [poUsePipes, poWaitOnExit];

    P.Execute;

    Bytes := TEncoding.UTF8.GetBytes(AText);

    if Length(Bytes) > 0 then
      P.Input.WriteBuffer(Bytes[0], Length(Bytes));

    // 🔥 KLUCZ: zamknięcie stdin (EOF)
    P.Input.CloseInput;  // jeśli Twoja wersja FPC to wspiera

    P.WaitOnExit;

  finally
    P.Free;
  end;
end;

  procedure SetClipboardTextold(const AText: string);
var
  P: TProcess;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := 'xclip';
    P.Parameters.Add('-selection');
    P.Parameters.Add('clipboard');
    P.Parameters.Add('-i');

    P.Options := P.Options + [poUsePipes];
    P.Execute;

    P.Input.WriteBuffer(Pointer(AText)^, Length(AText));
  finally
    P.Free;
  end;
end;


  function GetFromServer: string;
var
  Client: TFPHTTPClient;
  Response: TStringStream;
begin
  Result := '';

  Client := TFPHTTPClient.Create(nil);
  Response := TStringStream.Create('');
  try
    try
      Client.Get(SERVER_URL, Response);
      Result := Trim(Response.DataString);
    except
      on E: Exception do
        Writeln('GET error: ', E.Message);
    end;
  finally
    Response.Free;
    Client.Free;
  end;
end;


function IsXclipAvailable: Boolean;
var
  P: TProcess;
begin
  Result := False;

  P := TProcess.Create(nil);
  try
    P.Executable := 'which';
    P.Parameters.Add('xclip');

    P.Options := P.Options + [poWaitOnExit, poUsePipes];
    P.Execute;

    Result := P.ExitStatus = 0;

  finally
    P.Free;
  end;
end;
  function GetClipboardText: string;
var
  AProcess: TProcess;
  Output: TStringList;
begin
  Result := '';

  AProcess := TProcess.Create(nil);
  Output := TStringList.Create;
  try
    AProcess.Executable := 'xclip';
    AProcess.Parameters.Add('-selection');
    AProcess.Parameters.Add('clipboard');
    AProcess.Parameters.Add('-o');

    AProcess.Options := AProcess.Options + [poWaitOnExit, poUsePipes];

    AProcess.Execute;

    Output.LoadFromStream(AProcess.Output);
    Result := Trim(Output.Text);

  finally
    Output.Free;
    AProcess.Free;
  end;
end;
function GetClipboardTextold: string;
var
  AProcess: TProcess;
  Buffer: TStringStream;
begin
  Result := '';

  AProcess := TProcess.Create(nil);
  Buffer := TStringStream.Create('');
  try
    AProcess.Executable := 'xclip';
    AProcess.Parameters.Add('-selection');
    AProcess.Parameters.Add('clipboard');
    AProcess.Parameters.Add('-o');

    AProcess.Options := [poWaitOnExit, poUsePipes];

    AProcess.Execute;

    // czytaj ręcznie aż EOF
    Buffer.CopyFrom(AProcess.Output, AProcess.Output.Size);

    Result := Trim(Buffer.DataString);

  finally
    Buffer.Free;
    AProcess.Free;
  end;
end;

procedure SendToServer(const Text: string);
var
  Client: TFPHTTPClient;
  Response: TStringStream;
  Body: string;
begin
  Client := TFPHTTPClient.Create(nil);
  Response := TStringStream.Create('');
  try
    Body := 'data=' + HTTPEncode(Text);

    Client.AddHeader('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
    Client.RequestBody := TStringStream.Create(Body, TEncoding.UTF8);

    Client.Post(SERVER_URL, Response);

    Writeln('Wysłano OK: ', Length(Text), ' znaków');

  except
    on E: Exception do
      Writeln('HTTP error: ', E.Message);
  end;

  Client.Free;
end;

begin
  Writeln('Clipboard sync Linux started...');

  // 🔥 CHECK xclip BEFORE START
  if not IsXclipAvailable then
  begin
    Writeln('❌ You must install xclip first!');
    Writeln('👉 sudo apt install xclip');
    Writeln('');
    Writeln('Press ENTER to exit...');
    ReadLn;
    Halt;
  end;

  Writeln('✅ xclip detected. Running sync...');

   ParseArgs;
  SERVER_URL := 'http://' + ServerIP + ':' + ServerPort + '/api';

  Writeln('Target server: ', SERVER_URL);



  while True do
  begin
    try
      // =========================
      // LOCAL → SERVER
      // =========================
      Text := GetClipboardText;

      if (Text <> '') and (Text <> LastText) then
      begin
        LastText := Text;
        SendToServer(Text);
      end;

      // =========================
      // SERVER → LOCAL
      // =========================
      ServerText := GetFromServer;

      if (ServerText <> '') and (ServerText <> LastServerText) then
      begin
        LastServerText := ServerText;

        // avoid loop reflection
        if ServerText <> Text then
        begin
          SetClipboardText(ServerText);
          LastText := ServerText;
        end;
      end;

    except
      on E: Exception do
        Writeln('Sync error: ', E.Message);
    end;

    Sleep(2000);
  end;

end.



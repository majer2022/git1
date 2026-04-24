program ClipboardSL;

{$mode objfpc}{$H+}

uses
  Classes,
  SysUtils,
  Process,
  fphttpclient,
  HTTPDefs;

var
  SERVER_URL : string;
  ServerIP   : string = '192.168.1.212';
  ServerPort : string = '8080';

  procedure Log(const Msg: string); inline;
  begin
    WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] ', Msg);
    Flush(Output);
  end;

  procedure ShowHelp;
  begin
    WriteLn('ClipboardSL -- clipboard sync over LAN');
    WriteLn('');
    WriteLn('Usage:  ./ClipboardSL -a <IP> -p <PORT>');
    WriteLn('  -a <ip>    server address (default: 192.168.1.204)');
    WriteLn('  -p <port>  server port    (default: 8080)');
    WriteLn('  -h         show this help');
  end;

  procedure ParseArgs;
  var
    i: Integer;
  begin
    i := 1;
    while i <= ParamCount do
    begin
      if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
        begin ShowHelp; Halt; end
      else if (ParamStr(i) = '-a') and (i < ParamCount) then
        begin ServerIP := ParamStr(i+1); Inc(i); end
      else if (ParamStr(i) = '-p') and (i < ParamCount) then
        begin ServerPort := ParamStr(i+1); Inc(i); end;
      Inc(i);
    end;
  end;

  function GetClipboardText: string;
  var
    P: TProcess;
    SL: TStringList;
    T: QWord;
  begin
    Result := '';
    P := TProcess.Create(nil);
    SL := TStringList.Create;
    try
      P.Executable := 'xclip';
      P.Parameters.Add('-selection');
      P.Parameters.Add('clipboard');
      P.Parameters.Add('-o');
      P.Options := [poUsePipes, poStderrToOutPut];
      try
        P.Execute;
      except
        on E: Exception do begin Log('GET xclip failed: ' + E.Message); Exit; end;
      end;
      T := GetTickCount64;
      while P.Running do
      begin
        if GetTickCount64 - T > 2000 then
        begin
          P.Terminate(0);
          Log('GET xclip timeout');
          Exit;
        end;
        Sleep(10);
      end;
      if P.ExitCode <> 0 then
      begin
        SL.LoadFromStream(P.Output);
        Log('GET xclip exit=' + IntToStr(P.ExitCode) + ' msg="' + Trim(SL.Text) + '"');
        Exit;
      end;
      SL.LoadFromStream(P.Output);
      Result := Trim(SL.Text);
    finally
      SL.Free;
      P.Free;
    end;
  end;

  procedure SetClipboardText(const AText: string);
  var
    P: TProcess;
  begin
    P := TProcess.Create(nil);
    try
      P.Executable := '/bin/bash';
      P.Parameters.Add('-c');
      P.Parameters.Add('printf %s "$1" | xclip -selection clipboard');
      P.Parameters.Add('--');
      P.Parameters.Add(AText);
      P.Options := [poWaitOnExit];
      P.Execute;
    finally
      P.Free;
    end;
  end;

  function HttpGet(const URL: string): string;
  var
    C: TFPHTTPClient;
    R: TStringStream;
  begin
    Result := '';
    C := TFPHTTPClient.Create(nil);
    R := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      try
        C.Get(URL, R);
        Result := Trim(R.DataString);
      except
        on E: Exception do Log('HTTP GET: ' + E.Message);
      end;
    finally
      R.Free;
      C.Free;
    end;
  end;

  procedure HttpPost(const URL, Body: string);
  var
    C: TFPHTTPClient;
    Req, Res: TStringStream;
  begin
    C := TFPHTTPClient.Create(nil);
    Req := TStringStream.Create(Body, TEncoding.UTF8);
    Res := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      C.AddHeader('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
      Req.Position := 0;
      C.RequestBody := Req;
      try
        C.Post(URL, Res);
      except
        on E: Exception do Log('HTTP POST: ' + E.Message);
      end;
    finally
      Res.Free;
      Req.Free;
      C.Free;
    end;
  end;

var
  ClientID, TextzPC, ServerText, LastSetByUs: string;
  P: TProcess;
  SL: TStringList;
  O: string;

begin
  // -- Check xclip -----------------------------------------------------------
  P := TProcess.Create(nil);
  SL := TStringList.Create;
  try
    P.Executable := 'which';
    P.Parameters.Add('xclip');
    P.Options := [poUsePipes, poWaitOnExit];
    P.Execute;
    SL.LoadFromStream(P.Output);
    O := Trim(SL.Text);
  finally
    SL.Free;
    P.Free;
  end;
  if O = '' then
  begin
    WriteLn('ERROR: xclip not found -- install with: sudo apt install xclip');
    Halt(1);
  end;

  // -- Parse args ------------------------------------------------------------
  ParseArgs;
  SERVER_URL := 'http://' + ServerIP + ':' + ServerPort;

  // -- Hostname --------------------------------------------------------------
  P := TProcess.Create(nil);
  SL := TStringList.Create;
  try
    P.Executable := 'hostname';
    P.Options := [poUsePipes, poWaitOnExit];
    P.Execute;
    SL.LoadFromStream(P.Output);
    ClientID := Trim(SL.Text);
  finally
    SL.Free;
    P.Free;
  end;
  if ClientID = '' then ClientID := 'unknown';

  LastSetByUs := '';

  Log('START | client="' + ClientID + '" | server="' + SERVER_URL + '"');

  // ——— MAIN LOOP ——————————————————————————————————————————————————————————
  while True do
  begin
    try

      // 1. PULL — if server has something new, write it to local clipboard
      ServerText := HttpGet(SERVER_URL + '/api/pull');
      if (ServerText <> '') and (ServerText <> LastSetByUs) then
      begin
        Log('PULL: "' + Copy(ServerText, 1, 60) + '"');
        SetClipboardText(ServerText);
        LastSetByUs := ServerText;
      end;

      // 2. PUSH — if user changed clipboard (not us), send to server
      TextzPC := GetClipboardText;
      if TextzPC <> LastSetByUs then
      begin
        Log('PUSH: "' + Copy(TextzPC, 1, 60) + '"');
        HttpPost(SERVER_URL + '/api/push', 'data=' + HTTPEncode(TextzPC));
        LastSetByUs := TextzPC;
      end;

    except
      on E: Exception do Log('EX: ' + E.Message);
    end;

    Sleep(800);
  end;

end.

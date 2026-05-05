program ClipboardSL;

{$mode objfpc}{$H+}

{ ============================================================
  ClipboardSL  Ver. 3  --  sync logic
  ============================================================

  Client state variables:
    TextLocal    -- current text in the local clipboard
    LastPulled   -- last text PULLED from server (or pushed)
    ServerText   -- text the server currently holds
    ServerAuthor -- ClientID that last did PUSH on the server
    ClientID     -- own IP of this client

  Algorithm (every second):
  -------------------------------------------------------
  1. TextLocal  := GetClipboard()
  2. ServerText, ServerAuthor := GET /api/state

  3. if TextLocal == ServerText:
       -- state is in sync, do nothing

  4. if TextLocal != ServerText:

       A) TextLocal != LastPulled
          -- user copied something new locally
          -- PUSH regardless of who ServerAuthor is
          -- LastPulled := TextLocal

       B) TextLocal == LastPulled  AND  ServerAuthor != ClientID
          -- local clipboard has not changed since last pull
          -- someone else (other client or www) changed server
          -- PULL: SetClipboard(ServerText), LastPulled := ServerText

       C) TextLocal == LastPulled  AND  ServerAuthor == ClientID
          -- server has different text than us, but WE were the
             last author and local clipboard has not changed
          -- inconsistent state -- do nothing, wait

  Why this works better than Ver. 2:
  -------------------------------------------------------
  Ver. 2 decided only based on ServerAuthor.
  Bug: when author="" (www or fresh server), client did
  PULL and overwrote user clipboard with server data.
  Ver. 3 tracks LastPulled -- if local != LastPulled,
  user copied something -- always PUSH.
  ============================================================ }

{ ============================================================
  ClipboardSL  Ver. 4  --  Optimistic Locking
  ============================================================

  Problem with Ver. 3:
  -------------------------------------------------------
  For large strings transfer takes more than one second.
  During that time another client may PUSH and overwrite
  the server. The client that sent the large string gets
  200 back, but the server already holds data from someone
  else -- the large string is lost.

  Solution:
  -------------------------------------------------------
  GET /api/state returns "version":N.
  Client sends expected_version=N with every PUSH.
  Server:
    FVersion == expected_version -- save, return 200
    FVersion != expected_version -- return 409, save nothing
  Client on 409 does not update LastPulled -- retry next iter.

  New variable:
    ServerVersion -- last version from GET /api/state
  ============================================================ }

{ ============================================================
  ClipboardSL  Ver. 5  --  Base64 for clipboard text
  ============================================================

  Problem with Ver. 4:
  -------------------------------------------------------
  GET /api/state returned text through JSONEscape (server).
  The client parser ParseStateJSON did NOT decode escape
  sequences -- it saw \n as two characters instead of one.
  With programming text (lots of special chars: brackets,
  backslash, quotes, newlines) sizes never matched:
  TextLocal != ServerText always -- client fell into
  CASE C (wait forever) or did wrong PULL overwriting
  the clipboard.

  Solution -- Base64 everywhere:
  -------------------------------------------------------
  Client ALWAYS encodes text to Base64 before sending PUSH.
  Server stores and returns Base64 without any processing.
  GET /api/state returns field "text_b64" instead of "text":
    {"version":N,"author":"IP","text_b64":"BASE64..."}

  Base64 uses only A-Za-z0-9+/= -- zero special characters,
  zero problems with JSON, HTTP, newline, null, Unicode.

  Client after receiving /api/state:
    1. decodes text_b64 -- ServerText (raw text)
    2. compares ServerText with TextLocal (both raw)
    3. decides PUSH/PULL/wait on raw strings

  On PUSH sends Base64 as parameter data=.
  Server Ver. 5 encodes text from www (text/plain) to Base64
  before saving -- FPull is always Base64 regardless of source.

  Size overhead: ~33% -- irrelevant on LAN.

  New functions:
    EncodeBase64(s) -- string -> Base64
    DecodeBase64(s) -- Base64 -> string

  New flag:
    -d  enables [DBG] lines (off by default)
        Without -d output is clean, only key events.
        With -d identical behaviour to Ver. 4-DEBUG.

  Compatibility:
    Requires server Ver. 5 (field text_b64 in /api/state).
    If server returns old "text" without "text_b64",
    client logs WARNING and will not synchronise.
  ============================================================ }

{ ============================================================
  Ver. 5.1 -- SetClipboardText via temp file
  ============================================================
  Previous version: printf %s "$1" | xclip -selection clipboard
  xclip with large data forks into background to keep the
  clipboard alive for other X11 applications. TProcess with
  poWaitOnExit waited for the forked process that never exits
  -> deadlock, program hung forever.

  Fix: write text to a temp file, xclip reads it with -i and
  the main process exits immediately.
  Unique filename (PID) avoids conflicts with multiple
  instances on the same machine.
  ============================================================ }

uses
  Classes, SysUtils, Process, fphttpclient, HTTPDefs, base64;

var
  SERVER_URL : string;
  ServerIP   : string  = '192.168.1.204';
  ServerPort : string  = '8080';
  DebugMode  : Boolean = False;   // enabled by -d flag

  { -- Logging ------------------------------------------------------------ }

  procedure Log(const Msg: string); inline;
  begin
    WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] ', Msg);
    Flush(Output);
  end;

  // [DBG] lines -- only when launched with -d
  procedure LogD(const Msg: string); inline;
  begin
    if not DebugMode then Exit;
    WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] [DBG] ', Msg);
    Flush(Output);
  end;

  { -- Command line arguments --------------------------------------------- }

  procedure ShowHelp;
  begin
    WriteLn('ClipboardSL Ver. 5 -- clipboard sync over LAN');
    WriteLn('');
    WriteLn('Usage:  ./ClipboardSL -a <IP> -p <PORT> [-d]');
    WriteLn('  -a <ip>    server address (default: 192.168.1.204)');
    WriteLn('  -p <port>  server port    (default: 8080)');
    WriteLn('  -d         enable debug logging ([DBG] lines)');
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
        begin ServerPort := ParamStr(i+1); Inc(i); end
      else if ParamStr(i) = '-d' then
        DebugMode := True;
      Inc(i);
    end;
  end;

  { -- Base64 ------------------------------------------------------------- }

  // Encodes any string (special chars, newlines, null, Unicode)
  // to Base64. Result is safe in JSON and HTTP.
  function EncodeBase64(const S: string): string;
  var
    SS  : TStringStream;
    Enc : TBase64EncodingStream;
    Out : TStringStream;
  begin
    Result := '';
    if S = '' then Exit;
    SS  := TStringStream.Create(S);
    Out := TStringStream.Create('');
    try
      Enc := TBase64EncodingStream.Create(Out);
      try
        Enc.CopyFrom(SS, SS.Size);
      finally
        Enc.Free;   // Free forces flush of Base64 buffer
      end;
      Result := Out.DataString;
    finally
      Out.Free;
      SS.Free;
    end;
  end;

  // Decodes Base64 back to the original string.
  // Result is byte-for-byte identical to what was passed to EncodeBase64.
  //
  // Ver. 5.1 -- reads in a loop with 4KB buffer instead of Dec.Size.
  // TBase64DecodingStream does not support the Size property for large
  // data -- calling Dec.Size threw "Stream read error" for texts >~100KB.
  // Reading until BytesRead=0 works for any data size.
  function DecodeBase64(const S: string): string;
  var
    SS        : TStringStream;
    Dec       : TBase64DecodingStream;
    OutStr    : TStringStream;
    Buffer    : array[0..4095] of Byte;
    BytesRead : Integer;
  begin
    Result := '';
    if S = '' then Exit;
    SS     := TStringStream.Create(S);
    OutStr := TStringStream.Create('');
    try
      Dec := TBase64DecodingStream.Create(SS, bdmMIME);
      try
        repeat
          BytesRead := Dec.Read(Buffer, SizeOf(Buffer));
          if BytesRead > 0 then
            OutStr.Write(Buffer, BytesRead);
        until BytesRead = 0;
      finally
        Dec.Free;
      end;
      Result := OutStr.DataString;
    finally
      OutStr.Free;
      SS.Free;
    end;
  end;

  { -- System helpers ----------------------------------------------------- }

  // Returns own local IP -- first non-loopback from "hostname -I".
  // Used as ClientID so each machine is uniquely identified
  // without relying on hostname strings (which may collide).
  function GetLocalIP: string;
  var
    P     : TProcess;
    SL    : TStringList;
    Parts : TStringList;
    Raw   : string;
    i     : Integer;
  begin
    Result := '';
    P  := TProcess.Create(nil);
    SL := TStringList.Create;
    try
      P.Executable := 'hostname';
      P.Parameters.Add('-I');
      P.Options := [poUsePipes, poWaitOnExit];
      P.Execute;
      SL.LoadFromStream(P.Output);
      Raw := Trim(SL.Text);
      LogD('hostname -I raw: "' + Raw + '"');
      Parts := TStringList.Create;
      try
        Parts.Delimiter     := ' ';
        Parts.DelimitedText := Raw;
        LogD('parsed ' + IntToStr(Parts.Count) + ' address(es):');
        for i := 0 to Parts.Count - 1 do
          LogD('  [' + IntToStr(i) + '] "' + Trim(Parts[i]) + '"');
        if Parts.Count > 0 then
          Result := Trim(Parts[0]);
      finally
        Parts.Free;
      end;
    finally
      SL.Free;
      P.Free;
    end;
    if Result = '' then Result := '127.0.0.1';
    LogD('ClientID = "' + Result + '"');
  end;

  // Reads the current clipboard content via xclip.
  // Returns empty string on error or empty clipboard.
  function GetClipboardText: string;
  var
    P  : TProcess;
    MS : TMemoryStream;
    Buf: array[0..65535] of Byte;
    N  : LongInt;
    T  : QWord;
  begin
    Result := '';
    P  := TProcess.Create(nil);
    MS := TMemoryStream.Create;
    try
      P.Executable := 'xclip';
      P.Parameters.Add('-selection');
      P.Parameters.Add('clipboard');
      P.Parameters.Add('-o');
      P.Options := [poUsePipes, poStderrToOutPut];
      try
        P.Execute;
      except
        on E: Exception do begin Log('xclip GET ERROR: ' + E.Message); Exit; end;
      end;
      T := GetTickCount64;
      repeat
        while P.Output.NumBytesAvailable > 0 do
        begin
          N := P.Output.Read(Buf, SizeOf(Buf));
          if N > 0 then MS.Write(Buf, N);
        end;
        if GetTickCount64 - T > 5000 then
        begin
          P.Terminate(0);
          Log('xclip GET timeout');
          Exit;
        end;
        if P.Running then Sleep(20);
      until not P.Running;

      // Drain any remaining bytes after process exits
      while P.Output.NumBytesAvailable > 0 do
      begin
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then MS.Write(Buf, N);
      end;

      if P.ExitCode <> 0 then
      begin
        LogD('xclip ExitCode=' + IntToStr(P.ExitCode) + ' (clipboard empty?)');
        Exit;
      end;
      if MS.Size = 0 then Exit;

      SetLength(Result, MS.Size);
      MS.Position := 0;
      MS.Read(Result[1], MS.Size);
    finally
      MS.Free;
      P.Free;
    end;
  end;

  // Writes text to the clipboard via a temp file.
  //
  // Why temp file instead of pipe (printf | xclip):
  //   xclip forks into the background for large data to keep
  //   the clipboard alive for other X11 apps. TProcess with
  //   poWaitOnExit waited for the forked process that never
  //   exits -> deadlock. Writing to a temp file and passing it
  //   with -i lets xclip exit its main process immediately.
  procedure SetClipboardText(const AText: string);
  var
    P        : TProcess;
    TempFile : string;
    F        : TFileStream;
  begin
    TempFile := IncludeTrailingPathDelimiter(GetTempDir) +
                'clip_' + IntToStr(GetProcessID) + '.tmp';
    LogD('SetClipboard: ' + IntToStr(Length(AText)) + 'B via tempfile=' + TempFile);
    try
      // Binary write -- no character conversion
      F := TFileStream.Create(TempFile, fmCreate);
      try
        if Length(AText) > 0 then
          F.WriteBuffer(AText[1], Length(AText));
      finally
        F.Free;
      end;

      // xclip -i reads the file and exits its main process immediately
      P := TProcess.Create(nil);
      try
        P.Executable := 'xclip';
        P.Parameters.Add('-selection');
        P.Parameters.Add('clipboard');
        P.Parameters.Add('-i');
        P.Parameters.Add(TempFile);
        P.Options := [poWaitOnExit];
        P.Execute;
        LogD('SetClipboard: ExitCode=' + IntToStr(P.ExitCode));
      finally
        P.Free;
      end;

      // Data is now in xclip's RAM -- delete the temp file
      if FileExists(TempFile) then
        DeleteFile(TempFile);

    except
      on E: Exception do
      begin
        Log('SetClipboard ERROR: ' + E.Message);
        if FileExists(TempFile) then DeleteFile(TempFile);
      end;
    end;
  end;

  { -- HTTP helpers ------------------------------------------------------- }

  function HttpGet(const URL: string; out OutCode: Integer): string;
  var
    C: TFPHTTPClient;
    R: TStringStream;
    T: QWord;
  begin
    Result  := '';
    OutCode := 0;
    C := TFPHTTPClient.Create(nil);
    R := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      C.IOTimeout      := 30000;
      T := GetTickCount64;
      try
        C.Get(URL, R);
        OutCode := C.ResponseStatusCode;
        Result  := R.DataString;
        LogD('GET ' + URL + ' HTTP=' + IntToStr(OutCode) +
             ' size=' + IntToStr(Length(Result)) + 'B' +
             ' time=' + IntToStr(GetTickCount64 - T) + 'ms');
      except
        on E: Exception do
          Log('HTTP GET ERROR: ' + E.Message);
      end;
    finally
      R.Free;
      C.Free;
    end;
  end;

  function HttpPost(const URL, Body: string; out OutCode: Integer): string;
  var
    C   : TFPHTTPClient;
    Req : TStringStream;
    Res : TStringStream;
    T   : QWord;
  begin
    Result  := '';
    OutCode := 0;
    C   := TFPHTTPClient.Create(nil);
    Req := TStringStream.Create(Body, TEncoding.UTF8);
    Res := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      C.IOTimeout      := 30000;
      C.AddHeader('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
      Req.Position  := 0;
      C.RequestBody := Req;
      T := GetTickCount64;
      LogD('POST ' + URL + ' body=' + IntToStr(Length(Body)) + 'B');
      try
        C.Post(URL, Res);
        OutCode := C.ResponseStatusCode;
        Result  := Res.DataString;
        LogD('POST HTTP=' + IntToStr(OutCode) +
             ' resp="' + Trim(Result) + '"' +
             ' time=' + IntToStr(GetTickCount64 - T) + 'ms');
      except
        on E: Exception do
          Log('HTTP POST ERROR: ' + E.Message);
      end;
    finally
      Res.Free;
      Req.Free;
      C.Free;
    end;
  end;

  { -- JSON parser for /api/state Ver.5 ----------------------------------- }

  // Parses {"version":N,"author":"IP","text_b64":"BASE64"}
  //
  // text_b64 contains Base64 -- only A-Za-z0-9+/=
  // No special characters, so we search for closing " directly.
  // OutTextB64 = raw Base64, decoded in the main loop.
  // If field text_b64 is missing (old server) OutTextB64 = ''
  // and the client logs a WARNING.
  procedure ParseStateJSON(const JSON   : string;
                           out OutVer   : Int64;
                           out OutAuthor: string;
                           out OutB64   : string);
  var
    P1, P2: Integer;
  begin
    OutVer    := 0;
    OutAuthor := '';
    OutB64    := '';

    // version -- plain number, no quotes
    P1 := Pos('"version":', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"version":'));
      while (P1 <= Length(JSON)) and (JSON[P1] in [' ',#9,#10,#13]) do Inc(P1);
      P2 := P1;
      while (P2 <= Length(JSON)) and (JSON[P2] in ['0'..'9']) do Inc(P2);
      if P2 > P1 then
        OutVer := StrToInt64Def(Copy(JSON, P1, P2 - P1), 0);
    end;

    // author -- IP address, no special characters
    P1 := Pos('"author":"', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"author":"'));
      P2 := Pos('"', JSON, P1);
      if P2 > P1 then
        OutAuthor := Copy(JSON, P1, P2 - P1);
    end;

    // text_b64 -- Base64 only, safe chars, find closing " directly
    P1 := Pos('"text_b64":"', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"text_b64":"'));
      P2 := Pos('"', JSON, P1);
      if P2 > P1 then
        OutB64 := Copy(JSON, P1, P2 - P1);
    end;

    LogD('ParseJSON: v=' + IntToStr(OutVer) +
         ' author="' + OutAuthor + '"' +
         ' b64_len=' + IntToStr(Length(OutB64)) + 'B');
  end;

{ -- Global variables ----------------------------------------------------- }
var
  ClientID      : string;
  LastPulled    : string;   // raw text (not Base64) last pulled/pushed
  ServerVersion : Int64;
  TextLocal     : string;   // raw text from clipboard
  LocalB64      : string;   // TextLocal encoded as Base64 (for PUSH)
  StateResp     : string;
  ServerAuthor  : string;
  ServerTextB64 : string;   // Base64 from /api/state
  ServerText    : string;   // ServerTextB64 decoded (for comparisons)
  PushBody      : string;
  PushResp      : string;
  HttpCode      : Integer;
  LoopN         : Integer;
  P             : TProcess;
  SL            : TStringList;
  O             : string;

begin
  // -- Check xclip is installed ------------------------------------------
  P  := TProcess.Create(nil);
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

  ParseArgs;
  SERVER_URL    := 'http://' + ServerIP + ':' + ServerPort;
  LastPulled    := '';
  ServerVersion := 0;
  LoopN         := 0;

  ClientID := GetLocalIP;

  Log('START Ver.5 | client="' + ClientID + '" | server="' + SERVER_URL + '"');
  if DebugMode then
    Log('  debug ON  -- [DBG] lines enabled')
  else
    Log('  debug OFF -- run with -d to enable [DBG]');

  // -- Main loop -----------------------------------------------------------
  while True do
  begin
    try
      // 1. Read local clipboard (raw text)
      TextLocal := GetClipboardText;

      // 2. Encode to Base64 -- ready to send in PUSH
      LocalB64 := EncodeBase64(TextLocal);

      // 3. Fetch server state
      StateResp := HttpGet(SERVER_URL + '/api/state', HttpCode);

      if HttpCode <> 200 then
      begin
        if HttpCode <> 0 then
          Log('[' + IntToStr(LoopN) + '] STATE failed HTTP=' + IntToStr(HttpCode));
      end
      else
      begin
        // 4. Parse JSON -- get Base64 of server text
        ParseStateJSON(StateResp, ServerVersion, ServerAuthor, ServerTextB64);

        if ServerTextB64 = '' then
        begin
          // Missing text_b64 field -- server is old version
          Log('WARNING: server does not return "text_b64" -- update server to Ver.5!');
        end
        else
        begin
          // 5. Decode Base64 -- raw server text for comparison
          ServerText := DecodeBase64(ServerTextB64);

          Log('[' + IntToStr(LoopN) + ']' +
              ' local='      + IntToStr(Length(TextLocal)) + 'B' +
              ' server='     + IntToStr(Length(ServerText)) + 'B' +
              ' v='          + IntToStr(ServerVersion) +
              ' author="'    + ServerAuthor + '"' +
              ' lastPulled=' + IntToStr(Length(LastPulled)) + 'B');

          LogD('--- decision ---');
          LogD('  TextLocal==ServerText  : ' + BoolToStr(TextLocal = ServerText, True));
          LogD('  TextLocal==LastPulled  : ' + BoolToStr(TextLocal = LastPulled, True));
          LogD('  ServerAuthor==ClientID : ' + BoolToStr(ServerAuthor = ClientID, True) +
               '  ("' + ServerAuthor + '" vs "' + ClientID + '")');

          if TextLocal = ServerText then
          begin
            // In sync -- nothing to do
            LogD('  -> SYNCED');
            if LastPulled <> TextLocal then
              LastPulled := TextLocal;
          end
          else
          begin
            if TextLocal <> LastPulled then
            begin
              // CASE A: user copied new text locally -- PUSH Base64
              LogD('  -> CASE A: local changed -- PUSH');
              Log('PUSH ' + IntToStr(Length(TextLocal)) + 'B' +
                  ' (' + IntToStr(Length(LocalB64)) + 'B b64)' +
                  ' expected_v=' + IntToStr(ServerVersion));

              PushBody :=
                'client='            + HTTPEncode(ClientID) +
                '&expected_version=' + IntToStr(ServerVersion) +
                '&data='             + HTTPEncode(LocalB64);

              PushResp := HttpPost(SERVER_URL + '/api/push', PushBody, HttpCode);

              if HttpCode = 200 then
              begin
                LastPulled := TextLocal;
                Log('PUSH OK v=' + Trim(PushResp));
                LogD('  LastPulled=' + IntToStr(Length(LastPulled)) + 'B');
              end
              else if HttpCode = 409 then
              begin
                // Optimistic lock conflict: someone pushed before us.
                // Do NOT update LastPulled -- retry next iteration.
                Log('PUSH CONFLICT 409 -- retry next iteration');
                LogD('  LastPulled NOT updated');
              end
              else
                Log('PUSH FAILED HTTP=' + IntToStr(HttpCode) + ': ' + PushResp);
            end
            else if ServerAuthor <> ClientID then
            begin
              // CASE B: local unchanged, someone else changed server -- PULL
              // ServerText is already decoded from Base64 -- ready to paste
              LogD('  -> CASE B: server changed -- PULL');
              Log('PULL ' + IntToStr(Length(ServerText)) + 'B' +
                  ' from="' + ServerAuthor + '" v=' + IntToStr(ServerVersion));
              SetClipboardText(ServerText);
              LastPulled := ServerText;
              LogD('  LastPulled=' + IntToStr(Length(LastPulled)) + 'B');
            end
            else
            begin
              // CASE C: local == LastPulled AND author == us -- wait
              // Server has different text but we were the last author
              // and local has not changed. Inconsistent state, skip.
              LogD('  -> CASE C: waiting (inconsistent state)');
            end;
          end;

          LogD('--- end decision ---');
        end;
      end;

    except
      on E: Exception do Log('LOOP ERROR: ' + E.Message);
    end;

    Inc(LoopN);
    Sleep(1000);
  end;

end.

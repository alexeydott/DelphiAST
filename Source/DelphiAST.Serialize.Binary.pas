 unit DelphiAST.Serialize.Binary;
 
 {$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes,
  Generics.Collections,
  DelphiAST.Consts,
  DelphiAST.Classes;

type
  TNodeClass = (ntSyntax, ntCompound, ntValued, ntComment);

  TBinarySerializer = class
  strict private
    FStream     : TStream;
    FVersion    : Integer;
    FStringList : TStringList;
    FStringTable: TDictionary<string,integer>;
  strict protected
    function CheckSignature: boolean;
    function CheckVersion: boolean;
    function CreateNode(nodeClass: TNodeClass; nodeType: TSyntaxNodeType): TSyntaxNode;
    function ReadNode(var node: TSyntaxNode): boolean;
    function ReadNumber(var num: cardinal): Boolean;
    function ReadString(var str: string): boolean;
    function WriteNode(Node: TSyntaxNode): Boolean;
    function WriteNumber(Num: cardinal): Boolean;
    function WriteString(const S: string): Boolean;
  public
    function Read(Stream: TStream; var Root: TSyntaxNode): boolean;
    function Write(Stream: TStream; Root: TSyntaxNode): boolean;
  end;

implementation

uses
  SysUtils;

const
  CSignature: AnsiString = 'DAST binary file'#26;
  CBinaryVersion = $01000001;
  CStringReadChunkSize = 16384;

function TBinarySerializer.CheckSignature: boolean;
var
  sig: AnsiString;
begin
  SetLength(sig, Length(CSignature));
  Result := (FStream.Read(sig[1], Length(CSignature)) = Length(CSignature))
        and (sig = CSignature);
end;

function TBinarySerializer.CheckVersion: boolean;
var
  version: Integer;
begin
  version := 0;
  // Version 1.0.0 was written with incompatible TSyntaxNodeType orderings.
  // Its header cannot identify the producer, so accepting it can silently
  // turn one node kind into another. Such caches must be rebuilt from source.
  Result := (FStream.Read(version, 4) = 4)
        and (version = CBinaryVersion);
  FVersion := version;
end;

function TBinarySerializer.CreateNode(nodeClass: TNodeClass; nodeType: TSyntaxNodeType):
  TSyntaxNode;
begin
  case nodeClass of
    ntSyntax:   Result := TSyntaxNode.Create(nodeType);
    ntCompound: Result := TCompoundSyntaxNode.Create(nodeType);
    ntValued:   Result := TValuedSyntaxNode.Create(nodeType);
    ntComment:  Result := TCommentNode.Create(nodeType);
    else raise Exception.Create('TBinarySerializer.CreateNode: Unexpected node class');
  end;
end;

function TBinarySerializer.Read(Stream: TStream; var Root: TSyntaxNode): boolean;
var
  node: TSyntaxNode;
begin
  Result := false;
  if Stream = nil then
    Exit;

  FStringList := TStringList.Create;
  try
    FStream := Stream;
    if not CheckSignature then
      Exit;
    if not CheckVersion then
      Exit;
    if not ReadNode(node) then
      Exit;
    Root := node;
  finally
    FreeAndNil(FStringList);
    FStream := nil;
  end;

  Result := true;
end;

function TBinarySerializer.ReadNode(var node: TSyntaxNode): boolean;
var
  childNode: TSyntaxNode;
  i        : Integer;
  nodeClass: TNodeClass;
  num      : cardinal;
  numSub: cardinal;
  str      : string;
  attributesSeen: TAttributeNames;
begin
  Result := false;
  node := nil;
  if (not ReadNumber(num)) or (num > cardinal(Ord(High(TNodeClass)))) then
    Exit;
  nodeClass := TNodeClass(num);
  if (not ReadNumber(num)) or (num > Ord(High(TSyntaxNodeType))) then
    Exit;
  node := CreateNode(nodeClass, TSyntaxNodeType(num));
  try

    if (not ReadNumber(num)) or (num > cardinal(High(integer))) then
      Exit;
    Node.Col := num;
    if (not ReadNumber(num)) or (num > cardinal(High(integer))) then
      Exit;
    Node.Line := num;
    if FVersion >= $01000001 then
    begin
      if (not ReadNumber(num)) or (num > cardinal(High(Integer))) then Exit;
      Node.LineSeq := num;
    end;

    case nodeClass of
      ntCompound:
        begin
          if (not ReadNumber(num)) or (num > cardinal(High(integer))) then
            Exit;
          TCompoundSyntaxNode(Node).EndCol := num;
          if (not ReadNumber(num)) or (num > cardinal(High(integer))) then
            Exit;
          TCompoundSyntaxNode(Node).EndLine := num;
        end;
      ntValued:
        begin
          if not ReadString(str) then
            Exit;
          TValuedSyntaxNode(Node).Value := str;
        end;
      ntComment:
        begin
          if not ReadString(str) then
            Exit;
          TCommentNode(Node).Text := str;
        end;
    end;

    if (not ReadNumber(numSub)) or
      (numSub > cardinal(Ord(High(TAttributeName)) + 1)) then
      Exit;
    attributesSeen := [];
    for i := 1 to numSub do begin
      if (not ReadNumber(num)) or (num > cardinal(Ord(High(TAttributeName)))) then
        Exit;
      if TAttributeName(num) in attributesSeen then
        Exit;
      Include(attributesSeen, TAttributeName(num));
      if not ReadString(str) then
        Exit;
      Node.SetAttribute(TAttributeName(num), str);
    end;

    if (not ReadNumber(numSub)) or (numSub > cardinal(High(Integer))) then
      Exit;
    for i := 1 to numSub do begin
      if not ReadNode(childNode) then
        Exit;
      Node.AddChild(childNode);
    end;

    Result := true;
  finally
    if not Result then begin
      node.Free;
      node := nil;
    end;
  end;
end;

function TBinarySerializer.ReadNumber(var num: cardinal): Boolean;
var
  lowPart: byte;
  shift  : Integer;
begin
  Result := false;

  shift := 0;
  num := 0;
  repeat
    if FStream.Read(lowPart, 1) <> 1 then
      Exit;
    // A Cardinal has only four payload bits left in its fifth byte.
    // This also rejects continuation beyond five bytes before a shift can
    // wrap around and turn an overflowing value into a valid small number.
    if (shift = 28) and ((lowPart and $F0) <> 0) then
      Exit;
    num := num OR (cardinal(lowPart AND $7F) SHL shift);
    if (lowPart AND $80) = 0 then
    begin
      Result := true;
      Exit;
    end;
    Inc(shift, 7);
  until false;
end;

function TBinarySerializer.ReadString(var str: string): boolean;
var
  id: integer;
  len: cardinal;
  readPosition, readCount, capacity: cardinal;
  u8: UTF8String;
  unicodeText: UnicodeString;
begin
  Result := false;

  if not ReadNumber(len) then
    Exit;
  if (len SHR 24) = $FF then begin
    id := len AND $00FFFFFF;
    if id >= FStringList.Count then
      Exit;
    str := FStringList[id];
  end
  else begin
    // TStream.Read uses a signed Integer count, including on Win64.
    if len > cardinal(High(Integer)) then
      Exit;
    // Grow only as payload arrives. A truncated stream with a huge advertised
    // length must not first allocate gigabytes, and the reader must also work
    // with streams that do not implement Size or Seek.
    capacity := 0;
    readPosition := 0;
    while readPosition < len do
    begin
      readCount := len - readPosition;
      if readCount > CStringReadChunkSize then
        readCount := CStringReadChunkSize;
      if readPosition + readCount > capacity then
      begin
        if capacity = 0 then
          capacity := readCount
        else if capacity > len div 2 then
          capacity := len
        else
          capacity := capacity * 2;
        SetLength(u8, capacity);
      end;
      if FStream.Read(u8[readPosition + 1], Integer(readCount)) <> Integer(readCount) then
        Exit;
      Inc(readPosition, readCount);
    end;
    SetLength(u8, len);
    {$IFDEF FPC}
    // The parser's FPC strings contain UTF-8. Keep those bytes instead of
    // routing them through the process-dependent ANSI code page.
    unicodeText := UTF8Decode(u8);
    str := string(u8);
    {$ELSE}
    unicodeText := UTF8ToUnicodeString(u8);
    str := string(unicodeText);
    {$ENDIF}
    // Wire string IDs use Delphi's UTF-16 length, not FPC's byte length.
    if Length(unicodeText) > 4 then
      FStringList.Add(str);
  end;

  Result := true;
end;

function TBinarySerializer.Write(Stream: TStream; Root: TSyntaxNode): boolean;
var
  version: Integer;
begin
  Result := false;
  if (Stream = nil) or (Root = nil) then
    Exit;

  FStringTable := TDictionary<string,integer>.Create;
  try
    FStream := Stream;
    if FStream.Write(CSignature[1], Length(CSignature)) <> Length(CSignature) then
      Exit;
    version := CBinaryVersion;
    if FStream.Write(version, 4) <> 4 then
      Exit;
    if not WriteNode(Root) then
      Exit;
  finally
    FreeAndNil(FStringTable);
    FStream := nil;
  end;

  Result := true;
end;

function TBinarySerializer.WriteNode(Node: TSyntaxNode): Boolean;
var
  attr     : TAttributeEntry;
  childNode: TSyntaxNode;
  nodeClass: TNodeClass;
begin
  Result := false;
  if Node = nil then
    Exit;
  if (Node.Col < 0) or (Node.Line < 0) or (Node.LineSeq < 0) then
    Exit;
  if Node is TCompoundSyntaxNode then
    if (TCompoundSyntaxNode(Node).EndCol < 0) or
      (TCompoundSyntaxNode(Node).EndLine < 0) then
      Exit;

  if Node is TCompoundSyntaxNode then
    nodeClass := ntCompound
  else if Node is TValuedSyntaxNode then
    nodeClass := ntValued
  else if Node is TCommentNode then
    nodeClass := ntComment
  else
    nodeClass := ntSyntax;

  if not WriteNumber(Ord(nodeClass)) then Exit;
  if not WriteNumber(Ord(Node.Typ)) then Exit;
  if not WriteNumber(Node.Col) then Exit;
  if not WriteNumber(Node.Line) then Exit;
  if not WriteNumber(Node.LineSeq) then Exit;

  case nodeClass of
    ntCompound:
      begin
        if not WriteNumber(TCompoundSyntaxNode(Node).EndCol) then Exit;
        if not WriteNumber(TCompoundSyntaxNode(Node).EndLine) then Exit;
      end;
    ntValued:
      if not WriteString(TValuedSyntaxNode(Node).Value) then Exit;
    ntComment:
      if not WriteString(TCommentNode(Node).Text) then Exit;
  end;

  if not WriteNumber(Length(Node.Attributes)) then Exit;
  for attr in Node.Attributes do begin // causes dynamic array assignment, yuck
    if not WriteNumber(Ord(attr.Key)) then Exit;
    if not WriteString(attr.Value) then Exit;
  end;

  if not WriteNumber(Length(Node.ChildNodes)) then Exit;
  for childNode in Node.ChildNodes do // causes dynamic array assignment, yuck
    if not WriteNode(childNode) then Exit;

  Result := true;
end;

function TBinarySerializer.WriteNumber(Num: cardinal): Boolean;
var
  lowPart: byte;
begin
  Result := false;

  repeat
    lowPart := Num AND $7F;
    Num := Num SHR 7;
    if Num <> 0 then
      lowPart := lowPart OR $80;
    if FStream.Write(lowPart, 1) <> 1 then
      Exit;
  until Num = 0;

  Result := true;
end;

function TBinarySerializer.WriteString(const S: string): Boolean;
var
  i: Integer;
  id: integer;
  u8: UTF8String;
  unicodeText: UnicodeString;
begin
  Result := false;
  {$IFDEF FPC}
  unicodeText := UTF8Decode(S);
  {$ELSE}
  unicodeText := UnicodeString(S);
  {$ENDIF}

  if (Length(unicodeText) > 4) and FStringTable.TryGetValue(S, id) then begin
    if not WriteNumber(cardinal(id) OR $FF000000) then
      Exit;
  end
  else begin
    if Length(unicodeText) > 4 then begin
      FStringTable.Add(S, FStringTable.Count);
      if FStringTable.Count > $FFFFFF then
        raise Exception.Create('TBinarySerializer.WriteString: Too many strings!');
    end;
    u8 := UTF8Encode(unicodeText);
    i := Length(u8);
    if not WriteNumber(i) then
      Exit;
    if i > 0 then
      if FStream.Write(u8[1], i) <> i then
        Exit;
  end;

  Result := true;
end;

end.

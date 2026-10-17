unit DelphiAST.Binary.Review.Tests;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

procedure RunBinaryReviewTests;

implementation

uses
  Classes, SysUtils, DelphiAST.Classes, DelphiAST.Consts,
  DelphiAST.Serialize.Binary, DelphiAST.TestFramework;

const
  // Fixed wire values from the 1.0.1 format. Do not replace these with Ord:
  // doing so would hide a future enum reorder that needs a new wire version.
  CFixtureUnitType = 147;
  CFixtureLiteralType = 102;
  CShortUnicode: UnicodeString = #$0410#$0411#$0412;

procedure PutByte(Stream: TStream; Value: Byte);
begin
  Stream.WriteBuffer(Value, SizeOf(Value));
end;

procedure PutNumber(Stream: TStream; Value: Cardinal);
var
  B: Byte;
begin
  repeat
    B := Value and $7F;
    Value := Value shr 7;
    if Value <> 0 then
      B := B or $80;
    PutByte(Stream, B);
  until Value = 0;
end;

procedure PutHeader(Stream: TStream; Version: Cardinal = $01000001);
const
  Signature: AnsiString = 'DAST binary file'#26;
begin
  Stream.WriteBuffer(Signature[1], Length(Signature));
  PutByte(Stream, Version and $FF);
  PutByte(Stream, (Version shr 8) and $FF);
  PutByte(Stream, (Version shr 16) and $FF);
  PutByte(Stream, (Version shr 24) and $FF);
end;

procedure PutPrefix(Stream: TStream; NodeClass, NodeType: Cardinal);
begin
  PutNumber(Stream, NodeClass);
  PutNumber(Stream, NodeType);
  PutNumber(Stream, 3);  // Col
  PutNumber(Stream, 4);  // Line
  PutNumber(Stream, 9);  // LineSeq differs from physical Line
end;

procedure PutLeafSuffix(Stream: TStream);
begin
  PutNumber(Stream, 0); // attributes
  PutNumber(Stream, 0); // children
end;

procedure PutASCIIString(Stream: TStream; const Text: AnsiString);
begin
  PutNumber(Stream, Length(Text));
  if Text <> '' then
    Stream.WriteBuffer(Text[1], Length(Text));
end;

procedure PutUnicodeFixture(Stream: TStream);
begin
  PutHeader(Stream);
  PutPrefix(Stream, 0, CFixtureUnitType);
  PutNumber(Stream, 0);
  PutNumber(Stream, 3);

  PutPrefix(Stream, 2, CFixtureLiteralType);
  PutNumber(Stream, 6);
  PutByte(Stream, $D0); PutByte(Stream, $90);
  PutByte(Stream, $D0); PutByte(Stream, $91);
  PutByte(Stream, $D0); PutByte(Stream, $92);
  PutLeafSuffix(Stream);

  PutPrefix(Stream, 2, CFixtureLiteralType);
  PutASCIIString(Stream, 'abcde');
  PutLeafSuffix(Stream);

  // The preceding three Cyrillic letters occupy six UTF-8 bytes, but only
  // three UTF-16 units. They must not consume an entry in the string table.
  PutPrefix(Stream, 2, CFixtureLiteralType);
  PutNumber(Stream, $FF000000);
  PutLeafSuffix(Stream);
end;

procedure SetFixturePosition(Node: TSyntaxNode);
begin
  Node.Col := 3;
  Node.Line := 4;
  Node.LineSeq := 9;
end;

function MakeUnicodeFixtureTree: TSyntaxNode;
var
  Child: TValuedSyntaxNode;
  I: Integer;
begin
  Result := TSyntaxNode.Create(ntUnit);
  try
    SetFixturePosition(Result);
    for I := 0 to 2 do
    begin
      Child := TValuedSyntaxNode.Create(ntLiteral);
      Result.AddChild(Child);
      SetFixturePosition(Child);
      if I = 0 then
        {$IFDEF FPC}
        Child.Value := string(UTF8Encode(CShortUnicode))
        {$ELSE}
        Child.Value := string(CShortUnicode)
        {$ENDIF}
      else
        Child.Value := 'abcde';
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure AssertRejected(Stream: TMemoryStream; const Message: string);
var
  Serializer: TBinarySerializer;
  Sentinel, Restored: TSyntaxNode;
begin
  Serializer := TBinarySerializer.Create;
  Sentinel := TSyntaxNode.Create(ntUnknown);
  Restored := Sentinel;
  try
    Stream.Position := 0;
    AssertFalse(Serializer.Read(Stream, Restored), Message);
    AssertTrue(Restored = Sentinel, 'A failed read replaced the caller''s root');
  finally
    if Restored <> Sentinel then
      Restored.Free;
    Sentinel.Free;
    Serializer.Free;
  end;
end;

procedure AssertTreesEqual(Expected, Actual: TSyntaxNode);
var
  I: Integer;
  Attribute: TAttributeEntry;
begin
  AssertNotNil(Actual);
  AssertTrue(Expected.ClassType = Actual.ClassType, 'Node class changed');
  AssertEquals(Ord(Expected.Typ), Ord(Actual.Typ), 'Node type.');
  AssertEquals(Expected.Col, Actual.Col, 'Column.');
  AssertEquals(Expected.Line, Actual.Line, 'Line.');
  AssertEquals(Expected.LineSeq, Actual.LineSeq, 'Logical line.');
  if Expected is TCompoundSyntaxNode then
  begin
    AssertEquals(TCompoundSyntaxNode(Expected).EndCol,
      TCompoundSyntaxNode(Actual).EndCol, 'End column.');
    AssertEquals(TCompoundSyntaxNode(Expected).EndLine,
      TCompoundSyntaxNode(Actual).EndLine, 'End line.');
  end;
  if Expected is TValuedSyntaxNode then
    AssertEquals(TValuedSyntaxNode(Expected).Value,
      TValuedSyntaxNode(Actual).Value, 'Value.');
  if Expected is TCommentNode then
    AssertEquals(TCommentNode(Expected).Text, TCommentNode(Actual).Text, 'Comment.');
  AssertEquals(Length(Expected.Attributes), Length(Actual.Attributes), 'Attributes.');
  for Attribute in Expected.Attributes do
    AssertEquals(Attribute.Value, Actual.Attribute[Attribute.Key], 'Attribute value.');
  AssertEquals(Integer(Expected.ChildCount), Integer(Actual.ChildCount), 'Children.');
  for I := 0 to Integer(Expected.ChildCount) - 1 do
  begin
    AssertTrue(Actual.ChildNode[I].ParentNode = Actual, 'Missing restored parent');
    AssertTreesEqual(Expected.ChildNode[I], Actual.ChildNode[I]);
  end;
end;

procedure AssertSameBytes(Expected, Actual: TMemoryStream);
var
  I: Integer;
  ExpectedByte, ActualByte: Byte;
begin
  AssertTrue(Expected.Size = Actual.Size, 'Wire size changed');
  Expected.Position := 0;
  Actual.Position := 0;
  for I := 0 to Integer(Expected.Size) - 1 do
  begin
    Expected.ReadBuffer(ExpectedByte, 1);
    Actual.ReadBuffer(ActualByte, 1);
    AssertEquals(ExpectedByte, ActualByte, 'Wire byte ' + IntToStr(I) + '.');
  end;
end;

procedure TestRejectAmbiguousLegacy;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, $01000000);
    PutNumber(Stream, 0);
    PutNumber(Stream, 128); // ntUnit in the original enum, a different kind now
    PutNumber(Stream, 1);
    PutNumber(Stream, 1);
    PutLeafSuffix(Stream); // 1.0.0 had no LineSeq field
    AssertRejected(Stream, 'Ambiguous 1.0.0 cache was accepted');
  finally
    Stream.Free;
  end;
end;

procedure TestRejectUnknownVersion;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, $01000002);
    PutPrefix(Stream, 0, CFixtureUnitType);
    PutLeafSuffix(Stream);
    AssertRejected(Stream, 'An unknown wire version was accepted');
  finally
    Stream.Free;
  end;
end;

procedure TestReadKnownUnicodeFixture;
var
  Stream: TMemoryStream;
  Serializer: TBinarySerializer;
  Expected, Restored: TSyntaxNode;
begin
  Stream := TMemoryStream.Create;
  Serializer := TBinarySerializer.Create;
  Expected := MakeUnicodeFixtureTree;
  Restored := nil;
  try
    PutUnicodeFixture(Stream);
    Stream.Position := 0;
    AssertTrue(Serializer.Read(Stream, Restored), 'Known 1.0.1 fixture was rejected');
    AssertTreesEqual(Expected, Restored);
    AssertTrue(Stream.Position = Stream.Size, 'Fixture was not fully consumed');
  finally
    Restored.Free;
    Expected.Free;
    Serializer.Free;
    Stream.Free;
  end;
end;

procedure TestWriteKnownUnicodeFixture;
var
  Expected, Actual: TMemoryStream;
  Serializer: TBinarySerializer;
  Root: TSyntaxNode;
begin
  Expected := TMemoryStream.Create;
  Actual := TMemoryStream.Create;
  Serializer := TBinarySerializer.Create;
  Root := MakeUnicodeFixtureTree;
  try
    PutUnicodeFixture(Expected);
    AssertTrue(Serializer.Write(Actual, Root), 'Fixture write failed');
    AssertSameBytes(Expected, Actual);
  finally
    Root.Free;
    Serializer.Free;
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TestAllNodeKindsRoundTrip;
var
  Stream: TMemoryStream;
  Serializer: TBinarySerializer;
  Root, Restored, Child: TSyntaxNode;
  NodeType: TSyntaxNodeType;
  AttributeName: TAttributeName;
begin
  Stream := TMemoryStream.Create;
  Serializer := TBinarySerializer.Create;
  Root := TCompoundSyntaxNode.Create(ntUnit);
  Restored := nil;
  try
    SetFixturePosition(Root);
    TCompoundSyntaxNode(Root).EndCol := 71;
    TCompoundSyntaxNode(Root).EndLine := 142;
    for AttributeName := Low(TAttributeName) to High(TAttributeName) do
      Root.SetAttribute(AttributeName, 'attribute ' + IntToStr(Ord(AttributeName)));
    for NodeType := Low(TSyntaxNodeType) to High(TSyntaxNodeType) do
    begin
      Child := Root.AddChild(NodeType);
      Child.Col := Ord(NodeType);
      Child.Line := 127;
      Child.LineSeq := 128;
    end;
    Child := Root.AddChild(TValuedSyntaxNode.Create(ntLiteral));
    TValuedSyntaxNode(Child).Value := StringOfChar('x', 100003);
    Child := Root.AddChild(TCommentNode.Create(ntSlashesComment));
    TCommentNode(Child).Text := 'A repeated comment value';
    Child.AddChild(TCommentNode.Create(ntBorComment));
    TCommentNode(Child.ChildNode[0]).Text := 'A repeated comment value';
    AssertTrue(Serializer.Write(Stream, Root), 'Full tree write failed');
    Stream.Position := 0;
    AssertTrue(Serializer.Read(Stream, Restored), 'Full tree read failed');
    AssertTreesEqual(Root, Restored);
  finally
    Restored.Free;
    Root.Free;
    Serializer.Free;
    Stream.Free;
  end;
end;

procedure TestTruncatedStreams;
var
  Full, Truncated: TMemoryStream;
  I: Integer;
begin
  Full := TMemoryStream.Create;
  Truncated := TMemoryStream.Create;
  try
    PutUnicodeFixture(Full);
    for I := 0 to Integer(Full.Size) - 1 do
    begin
      Truncated.Clear;
      if I > 0 then
        Truncated.WriteBuffer(Full.Memory^, I);
      AssertRejected(Truncated, 'Truncation accepted at byte ' + IntToStr(I));
    end;
  finally
    Truncated.Free;
    Full.Free;
  end;
end;

procedure TestOverflowingVarints;
var
  Stream: TMemoryStream;
  I, Variant: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    for Variant := 0 to 1 do
    begin
      Stream.Clear;
      PutHeader(Stream);
      for I := 1 to 4 do
        PutByte(Stream, $80);
      if Variant = 0 then
        PutByte(Stream, $10) // overflow of the fifth byte used to decode as 0
      else
      begin
        PutByte(Stream, $80); // continued past the maximum five bytes
        PutByte(Stream, 0);
      end;
      PutNumber(Stream, CFixtureUnitType);
      PutNumber(Stream, 0);
      PutNumber(Stream, 0);
      PutNumber(Stream, 0);
      PutLeafSuffix(Stream);
      AssertRejected(Stream, 'An overflowing varint was accepted');
    end;
  finally
    Stream.Free;
  end;
end;

procedure TestInvalidCountsAndDuplicateAttributes;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream);
    PutPrefix(Stream, 0, CFixtureUnitType);
    PutNumber(Stream, $80000000);
    PutNumber(Stream, 0);
    AssertRejected(Stream, 'Out-of-range attribute count was accepted');
    Stream.Clear;
    PutHeader(Stream);
    PutPrefix(Stream, 0, CFixtureUnitType);
    PutNumber(Stream, 0);
    PutNumber(Stream, $80000000);
    AssertRejected(Stream, 'Out-of-range child count was accepted');
    Stream.Clear;
    PutHeader(Stream);
    PutPrefix(Stream, 0, CFixtureUnitType);
    PutNumber(Stream, 2);
    PutNumber(Stream, Ord(anName)); PutASCIIString(Stream, 'first');
    PutNumber(Stream, Ord(anName)); PutASCIIString(Stream, 'second');
    PutNumber(Stream, 0);
    AssertRejected(Stream, 'Duplicate attribute keys were silently overwritten');
  finally
    Stream.Free;
  end;
end;

procedure TestInvalidStringLengthsAndReferences;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream);
    PutPrefix(Stream, 2, CFixtureLiteralType);
    PutNumber(Stream, $80000000);
    AssertRejected(Stream, 'A string length outside TStream.Read range was accepted');
    Stream.Clear;
    PutHeader(Stream);
    PutPrefix(Stream, 2, CFixtureLiteralType);
    PutNumber(Stream, $7FFFFFFF);
    AssertRejected(Stream, 'A huge truncated string was accepted');
    Stream.Clear;
    PutHeader(Stream);
    PutPrefix(Stream, 2, CFixtureLiteralType);
    PutNumber(Stream, $FF000000);
    PutLeafSuffix(Stream);
    AssertRejected(Stream, 'Reference to a missing string was accepted');
  finally
    Stream.Free;
  end;
end;

procedure TestInvalidWriteAndSerializerReuse;
var
  Stream: TMemoryStream;
  Serializer: TBinarySerializer;
  Root, Restored: TSyntaxNode;
begin
  Stream := TMemoryStream.Create;
  Serializer := TBinarySerializer.Create;
  Root := TCompoundSyntaxNode.Create(ntUnit);
  Restored := nil;
  try
    AssertFalse(Serializer.Write(nil, Root), 'nil stream was accepted');
    AssertFalse(Serializer.Write(Stream, nil), 'nil root was accepted');
    AssertFalse(Serializer.Read(nil, Restored), 'nil input stream was accepted');
    Root.LineSeq := -1;
    AssertFalse(Serializer.Write(Stream, Root), 'Negative logical line was serialized');
    Root.LineSeq := 0;
    TCompoundSyntaxNode(Root).EndLine := -1;
    AssertFalse(Serializer.Write(Stream, Root), 'Negative end line was serialized');
    TCompoundSyntaxNode(Root).EndLine := 0;
    Stream.Clear;
    AssertTrue(Serializer.Write(Stream, Root), 'Failed write poisoned the serializer');
    Stream.Position := 0;
    AssertTrue(Serializer.Read(Stream, Restored), 'Serializer reuse failed');
    AssertTreesEqual(Root, Restored);
  finally
    Restored.Free;
    Root.Free;
    Serializer.Free;
    Stream.Free;
  end;
end;

procedure RunBinaryReviewTests;
begin
  RunTest('BinaryReview.RejectAmbiguousLegacy', TestRejectAmbiguousLegacy);
  RunTest('BinaryReview.RejectUnknownVersion', TestRejectUnknownVersion);
  RunTest('BinaryReview.ReadKnownUnicodeFixture', TestReadKnownUnicodeFixture);
  RunTest('BinaryReview.WriteKnownUnicodeFixture', TestWriteKnownUnicodeFixture);
  RunTest('BinaryReview.AllNodeKindsRoundTrip', TestAllNodeKindsRoundTrip);
  RunTest('BinaryReview.TruncatedStreams', TestTruncatedStreams);
  RunTest('BinaryReview.OverflowingVarints', TestOverflowingVarints);
  RunTest('BinaryReview.InvalidCountsAndDuplicateAttributes', TestInvalidCountsAndDuplicateAttributes);
  RunTest('BinaryReview.InvalidStringLengthsAndReferences', TestInvalidStringLengthsAndReferences);
  RunTest('BinaryReview.InvalidWriteAndSerializerReuse', TestInvalidWriteAndSerializerReuse);
end;

end.

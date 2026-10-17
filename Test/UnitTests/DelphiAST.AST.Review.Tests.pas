unit DelphiAST.AST.Review.Tests;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

procedure RunASTReviewTests;

implementation

uses
  Classes, SysUtils, DelphiAST, DelphiAST.Classes, DelphiAST.Consts,
  DelphiAST.TestFramework, DelphiAST.TestSupport;

type
  TFailingReadStream = class(TMemoryStream)
  public
    FailReads: Boolean;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

function TFailingReadStream.Read(var Buffer; Count: Longint): Longint;
begin
  if FailReads then
    raise EReadError.Create('Injected source read failure');
  Result := inherited Read(Buffer, Count);
end;

procedure SetMemorySource(Stream: TMemoryStream; const Source: AnsiString);
begin
  Stream.Clear;
  if Source <> '' then
    Stream.WriteBuffer(Source[1], Length(Source));
  Stream.Position := 0;
end;

function FindNamed(Node: TSyntaxNode; Typ: TSyntaxNodeType;
  const Name: string): TSyntaxNode;
var
  Child, NameNode: TSyntaxNode;
begin
  Result := nil;
  if Node.Typ = Typ then
  begin
    NameNode := Node.FindNode(ntName);
    if (Node.GetAttribute(anName) = Name) or
      ((NameNode <> nil) and (NameNode.GetAttribute(anName) = Name)) then
      Exit(Node);
  end;
  for Child in Node.ChildNodes do
  begin
    Result := FindNamed(Child, Typ, Name);
    if Result <> nil then
      Exit;
  end;
end;

procedure TestFindNodeArrayLiteral;
var
  Root, Leaf: TSyntaxNode;
begin
  Root := TSyntaxNode.Create(ntUnit);
  try
    Leaf := Root.AddChild(ntAbsolute).AddChild(ntValue).
      AddChild(ntExpression).AddChild(ntIdentifier);
    AssertTrue(Root.FindNode([ntAbsolute, ntValue, ntExpression,
      ntIdentifier]) = Leaf, 'Array literals must search the complete path');
    AssertTrue(Root.FindNode([ntAbsolute, ntUnknown, ntExpression,
      ntIdentifier]) = Leaf, 'Wildcard path must preserve its ordering');
  finally
    Root.Free;
  end;
end;

procedure TestFindNodeEmptyPathAndTypeSet;
var
  Root, Child: TSyntaxNode;
  EmptyPath: array of TSyntaxNodeType;
begin
  Root := TSyntaxNode.Create(ntUnit);
  try
    Child := Root.AddChild(ntInterface);
    SetLength(EmptyPath, 0);
    AssertTrue(Root.FindNode(EmptyPath) = nil, 'An empty path has no result');
    AssertTrue(Root.FindNode([]) = nil, 'An empty array literal has no result');
    AssertTrue(Root.FindNodeOfTypes([ntInterface, ntImplementation]) = Child);
    AssertTrue(Root.FindNodeOfTypes([ntVariable, ntType]) = nil);
  finally
    Root.Free;
  end;
end;

procedure TestHasAttributesCompatibility;
var
  Node: TSyntaxNode;
begin
  Node := TSyntaxNode.Create(ntUnit);
  try
    AssertFalse(Node.HasAttributes);
    Node.SetAttribute(anName, 'Example');
    AssertTrue(Node.HasAttributes);
    Node.SetAttribute(anName, '');
    AssertFalse(Node.HasAttributes);
    Node.SetAttribute(anName, 'Again');
    Node.ClearAttributes;
    AssertFalse(Node.HasAttributes);
  finally
    Node.Free;
  end;
end;

procedure TestAbsoluteVariable;
var
  Root, AliasNode, AbsoluteNode: TSyntaxNode;
begin
  Root := ParseSource('unit AbsoluteVar; interface var Base: Integer; ' +
    'Alias: Integer absolute Base; Initialized: Integer = 5; implementation end.');
  try
    AliasNode := FindNamed(Root, ntVariable, 'Alias');
    AssertNotNil(AliasNode);
    AbsoluteNode := AliasNode.FindNode(ntAbsolute);
    AssertNotNil(AbsoluteNode, 'An absolute alias must retain an ntAbsolute node');
    AssertTrue(AliasNode.FindNode(ntValue) = nil,
      'An absolute alias must not masquerade as an initializer');
    AssertEquals('Base', FindDescendant(AbsoluteNode, ntIdentifier).GetAttribute(anName));
    AssertNotNil(FindNamed(Root, ntVariable, 'Initialized').FindNode(ntValue),
      'Normal variable initializers must be retained');
  finally
    Root.Free;
  end;
end;

procedure TestAbsoluteExpression;
var
  Root, AliasNode, AbsoluteNode: TSyntaxNode;
begin
  Root := ParseSource('unit AbsoluteExpr; interface ' +
    'var Base: array[0..1] of Integer; Alias: Integer absolute Base[0]; ' +
    'implementation end.');
  try
    AliasNode := FindNamed(Root, ntVariable, 'Alias');
    AssertNotNil(AliasNode);
    AbsoluteNode := AliasNode.FindNode(ntAbsolute);
    AssertNotNil(AbsoluteNode, 'Absolute expressions must not be discarded');
    AssertNotNil(FindDescendant(AbsoluteNode, ntIndexed));
    AssertEquals('Base', FindDescendant(AbsoluteNode, ntIdentifier).GetAttribute(anName));
  finally
    Root.Free;
  end;
end;

procedure TestClassStorageDoesNotLeak;
var
  Root: TSyntaxNode;
begin
  Root := ParseSource('unit StorageScope; interface type ' +
    'TOne = class class var Shared: Integer; end; ' +
    'TTwo = class Instance: Integer; end; implementation end.');
  try
    AssertEquals('true', FindNamed(Root, ntField, 'Shared').GetAttribute(anClass));
    AssertEquals('', FindNamed(Root, ntField, 'Instance').GetAttribute(anClass),
      'Class storage must not leak into another class');
  finally
    Root.Free;
  end;
end;

procedure TestClassStorageAcrossVisibility;
var
  Root: TSyntaxNode;
begin
  Root := ParseSource('unit StorageVisibility; interface type ' +
    'TOne = class public class var Shared: Integer; ' +
    'private Instance: Integer; end; implementation end.');
  try
    AssertEquals('true', FindNamed(Root, ntField, 'Shared').GetAttribute(anClass));
    AssertEquals('', FindNamed(Root, ntField, 'Instance').GetAttribute(anClass),
      'A new visibility section ends the class var section');
  finally
    Root.Free;
  end;
end;

procedure TestClassStorageNestedFieldType;
var
  Root: TSyntaxNode;
begin
  Root := ParseSource('unit StorageNested; interface type ' +
    'TOne = class class var Shared: record Inner: Integer; end; ' +
    'NextShared: Integer; end; implementation end.');
  try
    AssertEquals('true', FindNamed(Root, ntField, 'Shared').GetAttribute(anClass));
    AssertEquals('', FindNamed(Root, ntField, 'Inner').GetAttribute(anClass),
      'Nested record fields must not inherit the containing field storage');
    AssertEquals('true', FindNamed(Root, ntField, 'NextShared').GetAttribute(anClass),
      'Parsing a nested field type must restore the outer class var section');
  finally
    Root.Free;
  end;
end;

procedure TestOperatorKeywordCase;
var
  Root, MethodNode: TSyntaxNode;
begin
  Root := ParseSource('unit OperatorCase; interface type TRec = record ' +
    'class OPERATOR Add(const Left, Right: TRec): TRec; end; implementation end.');
  try
    MethodNode := FindDescendant(Root, ntMethod);
    AssertNotNil(MethodNode);
    AssertEquals('operator', MethodNode.GetAttribute(anKind),
      'Keyword case must not change the method kind');
  finally
    Root.Free;
  end;
end;

procedure TestDirectiveTextCase;
var
  Root, DirectiveNode: TSyntaxNode;
begin
  Root := ParseSource('unit DirectiveCase; interface ' +
    '{$MESSAGE HINT ''Keep MixedCase''} implementation end.');
  try
    DirectiveNode := FindDescendant(Root, ntCompilerDirective);
    AssertNotNil(DirectiveNode);
    AssertEquals('{$MESSAGE HINT ''Keep MixedCase''}',
      TValuedSyntaxNode(DirectiveNode).Value, 'Directive source text must be preserved');
    AssertEquals('MESSAGE', DirectiveNode.GetAttribute(anType));
    AssertEquals('HINT ''Keep MixedCase''', DirectiveNode.GetAttribute(anKind));
  finally
    Root.Free;
  end;
end;

procedure TestDirectiveWhitespace;
var
  Root, DirectiveNode: TSyntaxNode;
begin
  Root := ParseSource('unit DirectiveSpace; interface ' +
    '{$message' + #9 + 'HINT ''Keep MixedCase''} implementation end.');
  try
    DirectiveNode := FindDescendant(Root, ntCompilerDirective);
    AssertNotNil(DirectiveNode);
    AssertEquals('MESSAGE', DirectiveNode.GetAttribute(anType));
    AssertEquals('HINT ''Keep MixedCase''', DirectiveNode.GetAttribute(anKind));
  finally
    Root.Free;
  end;
end;

procedure TestMemoryStreamFailureAndReuse;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TMemoryStream;
  Root: TSyntaxNode;
  Rejected: Boolean;
begin
  Builder := TPasSyntaxTreeBuilder.Create;
  Stream := TMemoryStream.Create;
  Root := nil;
  try
    SetMemorySource(Stream, 'unit BrokenStream; interface implementation begin');
    Rejected := False;
    try
      Root := Builder.Run(Stream);
    except
      on E: ESyntaxTreeException do
      begin
        Rejected := True;
        AssertNotNil(E.SyntaxTree, 'The syntax diagnostic must retain its partial tree');
      end;
    end;
    AssertTrue(Rejected, 'Malformed non-string stream must be rejected');
    AssertTrue(Root = nil, 'Failed parse must not publish a root');
    // The caller still owns the input. Reuse also exercises cleanup of the
    // parser's temporary string stream; run with a heap checker for leaks.
    SetMemorySource(Stream, 'unit ReusedStream; interface implementation end.');
    Root := Builder.Run(Stream);
    AssertNotNil(FindDescendant(Root, ntUnit), 'Builder must remain reusable');
  finally
    Root.Free;
    Stream.Free;
    Builder.Free;
  end;
end;

procedure TestStreamReadFailureAndReuse;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TFailingReadStream;
  Root: TSyntaxNode;
  Rejected: Boolean;
begin
  Builder := TPasSyntaxTreeBuilder.Create;
  Stream := TFailingReadStream.Create;
  Root := nil;
  try
    SetMemorySource(Stream, 'unit ReadFailure; interface implementation end.');
    Stream.FailReads := True;
    Rejected := False;
    try
      Root := Builder.Run(Stream);
    except
      on EReadError do Rejected := True;
    end;
    AssertTrue(Rejected, 'Source read error must reach the caller');
    AssertTrue(Root = nil, 'Read failure must not publish a root');
    Stream.FailReads := False;
    Stream.Position := 0;
    Root := Builder.Run(Stream);
    AssertNotNil(FindDescendant(Root, ntUnit), 'Read failure must not poison reuse');
  finally
    Root.Free;
    Stream.Free;
    Builder.Free;
  end;
end;

procedure RunASTReviewTests;
begin
  RunTest('Review.AST.FindNodeArrayLiteral', TestFindNodeArrayLiteral);
  RunTest('Review.AST.FindNodeEmptyPathAndTypeSet', TestFindNodeEmptyPathAndTypeSet);
  RunTest('Review.AST.HasAttributesCompatibility', TestHasAttributesCompatibility);
  RunTest('Review.AST.AbsoluteVariable', TestAbsoluteVariable);
  RunTest('Review.AST.AbsoluteExpression', TestAbsoluteExpression);
  RunTest('Review.AST.ClassStorageDoesNotLeak', TestClassStorageDoesNotLeak);
  RunTest('Review.AST.ClassStorageAcrossVisibility', TestClassStorageAcrossVisibility);
  RunTest('Review.AST.ClassStorageNestedFieldType', TestClassStorageNestedFieldType);
  RunTest('Review.AST.OperatorKeywordCase', TestOperatorKeywordCase);
  RunTest('Review.AST.DirectiveTextCase', TestDirectiveTextCase);
  RunTest('Review.AST.DirectiveWhitespace', TestDirectiveWhitespace);
  RunTest('Review.AST.MemoryStreamFailureAndReuse', TestMemoryStreamFailureAndReuse);
  RunTest('Review.AST.StreamReadFailureAndReuse', TestStreamReadFailureAndReuse);
end;

end.

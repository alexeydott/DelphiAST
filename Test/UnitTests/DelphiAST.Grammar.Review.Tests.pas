unit DelphiAST.Grammar.Review.Tests;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

procedure RunGrammarReviewTests;

implementation

uses
  Classes, SysUtils, DelphiAST, DelphiAST.Classes, DelphiAST.Consts,
  DelphiAST.TestFramework, DelphiAST.TestSupport, SimpleParser,
  SimpleParser.Lexer, SimpleParser.Lexer.Types;

type
  TStrictGrammarParser = class(TmwSimplePasPar)
  private
    procedure ParserMessage(Sender: TObject; const Typ: TMessageEventType;
      const Msg: string; X, Y: Integer);
  public
    constructor Create; override;
  end;

constructor TStrictGrammarParser.Create;
begin
  inherited;
  OnMessage := ParserMessage;
end;

procedure TStrictGrammarParser.ParserMessage(Sender: TObject;
  const Typ: TMessageEventType; const Msg: string; X, Y: Integer);
begin
  if Typ = meError then
    raise ESyntaxError.CreatePos(Msg, Lexer.PosXY);
end;

procedure ParseWithoutTree(const Source: string);
var
  Parser: TStrictGrammarParser;
  Stream: TStringStream;
begin
  Parser := TStrictGrammarParser.Create;
  Stream := TStringStream.Create(Source);
  try
    Parser.Run('', Stream);
    AssertEquals(Ord(ptNull), Ord(Parser.Lexer.TokenID),
      'The grammar parser must consume the complete compilation unit.');
  finally
    Stream.Free;
    Parser.Free;
  end;
end;

procedure AssertRejected(const Source: string);
var
  Root: TSyntaxNode;
  Rejected: Boolean;
begin
  Root := nil;
  Rejected := False;
  try
    Root := ParseSource(Source);
  except
    on ESyntaxTreeException do
      Rejected := True;
  end;
  Root.Free;
  AssertTrue(Rejected, 'Malformed declaration must be rejected: ' + Source);
end;

procedure TestCompactAssemblyEnd;
var
  Root, Statement: TSyntaxNode;
begin
  Root := ParseSource('unit CompactAssembly; interface implementation ' +
    'procedure Run; begin asm nop end; Value := 1; end; end.');
  try
    AssertEquals(1, CountDescendants(Root, ntAsmStatement),
      'The compact assembly block contains one instruction.');
    Statement := FindDescendant(Root, ntAsmStatement);
    AssertEquals('nop', TValuedSyntaxNode(Statement).Value,
      'The Pascal end token must not enter the assembly instruction.');
    AssertEquals(1, CountDescendants(Root, ntAssign),
      'The Pascal assignment after the assembly block must be preserved.');
  finally
    Root.Free;
  end;
end;

procedure TestAssemblySemicolonSeparators;
var
  Root: TSyntaxNode;
begin
  Root := ParseSource('unit AssemblySeparators; interface implementation ' +
    'procedure Run; begin asm nop; nop; end; Value := 1; end; end.');
  try
    AssertEquals(2, CountDescendants(Root, ntAsmStatement),
      'Semicolons separate assembly statements just like line endings.');
    AssertEquals(1, CountDescendants(Root, ntAssign),
      'The Pascal assignment after the assembly block must be preserved.');
  finally
    Root.Free;
  end;
end;

procedure TestAssemblyReservedLocalLabels;
var
  Root, Statements: TSyntaxNode;
begin
  Root := ParseSource('unit AssemblyLabels; interface implementation ' +
    'procedure Run; begin asm' + sLineBreak +
    '  JMP @@End' + sLineBreak +
    '@@End: nop' + sLineBreak +
    'end; Value := 1; end; end.');
  try
    AssertEquals(2, CountDescendants(Root, ntAsmStatement),
      'The reserved word in a local label must not end the assembly block.');
    Statements := FindDescendant(Root, ntAsmStatement);
    AssertEquals('JMP @@End', TValuedSyntaxNode(Statements).Value);
    AssertEquals(1, CountDescendants(Root, ntAssign));
  finally
    Root.Free;
  end;
end;

procedure TestAssemblyStateAfterError;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStringStream;
  Root: TSyntaxNode;
  Rejected: Boolean;
begin
  Builder := TPasSyntaxTreeBuilder.Create;
  Stream := TStringStream.Create('unit BrokenAssembly; interface implementation ' +
    'procedure Run; asm nop');
  Root := nil;
  try
    Rejected := False;
    try
      Root := Builder.Run(Stream);
    except
      on ESyntaxTreeException do
        Rejected := True;
    end;
    AssertTrue(Rejected, 'An assembly block without end must be rejected.');
    AssertFalse(Builder.Lexer.Lexer.AsmCode,
      'An assembly syntax error must restore the Pascal lexical mode.');
  finally
    Root.Free;
    Stream.Free;
    Builder.Free;
  end;
end;

procedure TestSimpleParserAnonymousMethodTypes;
begin
  ParseWithoutTree('unit ReferenceGrammar; interface type ' +
    'TProcedure = reference to procedure; ' +
    'TEmptyProcedure = reference to procedure(); ' +
    'TParameterProcedure = reference to procedure(A: Integer); ' +
    'TFunction = reference to function: Integer; ' +
    'TEmptyFunction = reference to function(): Integer; ' +
    'TParameterFunction = reference to function(A: Integer): Integer; ' +
    'TAfter = Integer; implementation end.');
end;

procedure TestAnonymousMethodTypeTree;
var
  Root: TSyntaxNode;
begin
  Root := ParseSource('unit ReferenceTree; interface type ' +
    'TProcedure = reference to procedure; ' +
    'TEmptyProcedure = reference to procedure(); ' +
    'TParameterProcedure = reference to procedure(A: Integer); ' +
    'TFunction = reference to function: Integer; ' +
    'TEmptyFunction = reference to function(): Integer; ' +
    'TParameterFunction = reference to function(A: Integer): Integer; ' +
    'TAfter = Integer; implementation end.');
  try
    AssertEquals(6, CountDescendants(Root, ntAnonymousMethodType));
    AssertEquals(3, CountDescendants(Root, ntReturnType));
    AssertEquals(2, CountDescendants(Root, ntParameter));
    AssertEquals(7, CountDescendants(Root, ntTypeDecl),
      'The declaration after the anonymous method types must be preserved.');
  finally
    Root.Free;
  end;
end;

procedure TestAnonymousMethodRequiresMethodKind;
begin
  AssertRejected('unit MissingMethodKind; interface type ' +
    'TCallback = reference to; implementation end.');
end;

procedure TestNamedRecordVariantTag;
var
  Root, Tag: TSyntaxNode;
begin
  Root := ParseSource('unit TaggedVariant; interface type TVariant = record ' +
    'case Kind: Boolean of True: (A: Integer); False: (B: Byte); ' +
    'end; implementation end.');
  try
    Tag := FindDescendant(Root, ntVariantTag);
    AssertNotNil(Tag);
    AssertEquals('Kind', Tag.GetAttribute(anName));
    AssertEquals('Boolean', Tag.GetAttribute(anType));
    AssertEquals(2, CountDescendants(Root, ntField));
  finally
    Root.Free;
  end;
end;

procedure TestQualifiedRecordVariantTypes;
var
  Root, Tag: TSyntaxNode;
  Declaration: string;
begin
  for Declaration in [
    'case Kind: System.Boolean of True: (A: Integer); False: (B: Byte);',
    'case System.Boolean of True: (A: Integer); False: (B: Byte);'] do
  begin
    Root := ParseSource('unit ScopedVariant; interface type TVariant = record ' +
      Declaration + ' end; implementation end.');
    try
      Tag := FindDescendant(Root, ntVariantTag);
      AssertNotNil(Tag);
      AssertEquals('System.Boolean', Tag.GetAttribute(anType));
      AssertEquals(2, CountDescendants(Root, ntField));
    finally
      Root.Free;
    end;
  end;
end;

procedure TestOpenArrayAndGenericInitializer;
begin
  ParseWithoutTree('unit ArrayGrammar; interface type ' +
    'TCallback = procedure(const Values: array of const); ' +
    'var List: TList<Integer>=nil; implementation end.');
end;

procedure TestUnicodeStringType;
var
  Root: TSyntaxNode;
begin
  ParseWithoutTree('unit UnicodeGrammar; interface type TText = UnicodeString; ' +
    'var Value: UnicodeString; implementation end.');
  Root := ParseSource('unit UnicodeTree; interface type TText = UnicodeString; ' +
    'var Value: UnicodeString; implementation end.');
  try
    AssertNotNil(FindDescendant(Root, ntVariable));
  finally
    Root.Free;
  end;
end;

procedure TestSourceWithUtf8Bom;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStringStream;
  Bytes: TBytes;
  Root: TSyntaxNode;
begin
  Builder := TPasSyntaxTreeBuilder.Create;
  Stream := TStringStream.Create('');
  Root := nil;
  try
    Bytes := TEncoding.UTF8.GetPreamble;
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Bytes := TEncoding.UTF8.GetBytes('unit BomSource; interface implementation end.');
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Stream.Position := 0;
    Root := Builder.Run(Stream);
    AssertEquals('BomSource', Root.GetAttribute(anName));
  finally
    Root.Free;
    Stream.Free;
    Builder.Free;
  end;
end;

procedure RunGrammarReviewTests;
begin
  RunTest('Grammar.Assembly.CompactEnd', TestCompactAssemblyEnd);
  RunTest('Grammar.Assembly.SemicolonSeparators', TestAssemblySemicolonSeparators);
  RunTest('Grammar.Assembly.ReservedLocalLabels', TestAssemblyReservedLocalLabels);
  RunTest('Grammar.Assembly.StateAfterError', TestAssemblyStateAfterError);
  RunTest('Grammar.ReferenceTypes.BaseParser', TestSimpleParserAnonymousMethodTypes);
  RunTest('Grammar.ReferenceTypes.Tree', TestAnonymousMethodTypeTree);
  RunTest('Grammar.ReferenceTypes.MissingMethodKind', TestAnonymousMethodRequiresMethodKind);
  RunTest('Grammar.RecordVariant.NamedTag', TestNamedRecordVariantTag);
  RunTest('Grammar.RecordVariant.QualifiedTypes', TestQualifiedRecordVariantTypes);
  RunTest('Grammar.Types.OpenArrayAndInitializer', TestOpenArrayAndGenericInitializer);
  RunTest('Grammar.Types.UnicodeString', TestUnicodeStringType);
  RunTest('Grammar.Source.Utf8Bom', TestSourceWithUtf8Bom);
end;

end.

unit DelphiAST.Actualization.Tests;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
procedure RunActualizationTests;
implementation
uses Classes, SysUtils, SimpleParser.Lexer.Types, SimpleParser.Lexer, DelphiAST, DelphiAST.Classes, DelphiAST.Consts,
  SimpleParser, DelphiAST.TestFramework, DelphiAST.TestSupport, DelphiAST.Writer;
type
  TStrictParser = class(TmwSimplePasPar)
    procedure Message(Sender:TObject; const Typ:TMessageEventType;
      const Msg:string; X,Y:Integer);
  end;
procedure TStrictParser.Message(Sender:TObject; const Typ:TMessageEventType;
  const Msg:string; X,Y:Integer);
begin
  if Typ=meError then raise Exception.Create(Msg);
end;
function Named(Node:TSyntaxNode; Typ:TSyntaxNodeType; const Name:string):TSyntaxNode;
var C,N:TSyntaxNode;
begin
  Result:=nil;
  if Node.Typ=Typ then begin
    N:=Node.FindNode(ntName);
    if (Node.GetAttribute(anName)=Name) or ((N<>nil) and (N.GetAttribute(anName)=Name)) then Exit(Node);
  end;
  for C in Node.ChildNodes do begin Result:=Named(C,Typ,Name);if Result<>nil then Exit;end;
end;
procedure TestClassStorage;
var Root,N:TSyntaxNode;S:string;
begin
  Root:=ParseSource('unit ClassStorage; interface type TExample=class public class var A,B:Integer; C:Integer; var D:Integer; class const X=1; const Y=2; end; implementation end.');
  try
    for S in ['A','B','C'] do begin N:=Named(Root,ntField,S);AssertNotNil(N,S);AssertEquals('true',N.GetAttribute(anClass),S);end;
    N:=Named(Root,ntField,'D');AssertNotNil(N);AssertEquals('',N.GetAttribute(anClass),'Instance field after class var');
    N:=Named(Root,ntConstant,'X');AssertNotNil(N);AssertEquals('true',N.GetAttribute(anClass));
    N:=Named(Root,ntConstant,'Y');AssertNotNil(N);AssertEquals('',N.GetAttribute(anClass));
  finally Root.Free;end;
end;
procedure TestRootKinds;
var Root:TSyntaxNode;
begin
  Root:=ParseSource('{$WARNINGS OFF} program P; begin end.');try AssertEquals(Ord(ntProgram),Ord(Root.Typ));finally Root.Free;end;
  Root:=ParseSource('library L; begin end.');try AssertEquals(Ord(ntLibrary),Ord(Root.Typ));finally Root.Free;end;
  Root:=ParseSource('package P; requires rtl; end.');try AssertEquals(Ord(ntPackage),Ord(Root.Typ));finally Root.Free;end;
end;
procedure TestMalformedHeaders;
var S:string;Root:TSyntaxNode;Rejected:Boolean;
begin
  for S in ['', '"""unit', 'un{$ENDIF}it U;', '{$IF (}', '{$WARNINGS OFF} garbage',
    'unit U; interface implementation procedure Foo; {$'] do begin
    Root:=nil;Rejected:=False;
    try Root:=ParseSource(S);except on ESyntaxTreeException do Rejected:=True;end;
    Root.Free;AssertTrue(Rejected,'Malformed input must raise a syntax exception: '+S);
  end;
end;
procedure TestConditionalDecimals;
var Root:TSyntaxNode;Old:TFormatSettings;
begin
  Old:=FormatSettings;
  try
    FormatSettings.DecimalSeparator:=',';
    Root:=ParseSource('unit Versions; interface {$IF (CompilerVersion >= 0.0) AND (RTLVersion >= 0.0)} type TIncluded=class end; {$ELSE} invalid syntax here {$IFEND} implementation end.');
    try AssertNotNil(Named(Root,ntTypeDecl,'TIncluded'));finally Root.Free;end;
  finally FormatSettings:=Old;end;
end;
procedure TestProceduralMetadata;
var Root,N:TSyntaxNode;
begin
  Root:=ParseSource('unit ProcTypes; interface type TProc=procedure of object; TRef=reference to function(A:Integer):Boolean stdcall; implementation end.');
  try
    N:=Named(Root,ntTypeDecl,'TProc');AssertNotNil(N);AssertContains('of object',TSyntaxTreeWriter.ToXML(N,False,False));
    N:=Named(Root,ntTypeDecl,'TRef');AssertNotNil(N);AssertNotNil(FindDescendant(N,ntAnonymousMethodType));
    AssertNotNil(FindDescendant(N,ntReturnType));AssertEquals(1,CountDescendants(N,ntParameter));
  finally Root.Free;end;
end;
procedure TestGenericMethodMetadata;
var Root,N:TSyntaxNode;
begin
  Root:=ParseSource('unit GenericMethods; interface type TBox<T>=class class function Convert<U>(const Value:U):U; static; end; implementation end.');
  try N:=FindDescendant(Root,ntMethod);AssertNotNil(N);AssertNotNil(FindDescendant(N,ntTypeParams));AssertNotNil(FindDescendant(N,ntReturnType));finally Root.Free;end;
end;
procedure TestAttributeUpdates;
var Node,Child,Clone:TSyntaxNode;I:Integer;
begin
  Node:=TSyntaxNode.Create(ntUnit);
  try
    Node.SetAttribute(anName,'Initial');Node.SetAttribute(anKind,'unit');
    for I:=1 to 1000 do Node.SetAttribute(anName,IntToStr(I));
    AssertEquals('1000',Node.GetAttribute(anName));
    Node.SetAttribute(anName,'');AssertFalse(Node.HasAttribute(anName));
    AssertEquals('unit',Node.GetAttribute(anKind));
    Node.SetAttribute(anName,'Restored');AssertEquals(2,Length(Node.Attributes));
    Clone:=Node.Clone;
    try Clone.SetAttribute(anName,'Clone');AssertEquals('Restored',Node.GetAttribute(anName));finally Clone.Free;end;
    Child:=Node.AddChild(ntType);AssertTrue(Child.ParentNode=Node);
    Node.ExtractChild(Child);AssertTrue(Child.ParentNode=nil);Node.AddChild(Child);
  finally Node.Free;end;
end;
procedure TestLiteralBoundaries;
var Root,N:TSyntaxNode; Q,S:string; I:Integer;
begin
  Q:=Chr(39);
  for I:=1 to 3 do begin
    case I of 1:S:=#10; 2:S:=#13#10; else S:=#13; end;
    Root:=ParseSource('unit Literals; interface const Text='+Q+Q+Q+S+
      '  a '+Q+Q+' b'+S+'  '+Q+Q+Q+'; After=$fF_Ff; implementation end.');
    try
      N:=FindDescendant(Root,ntLiteral);AssertNotNil(N);
      AssertEquals(S+'  a '+Q+Q+' b'+S+'  ',TValuedSyntaxNode(N).Value,'Multiline source content');
      N:=Named(Root,ntConstant,'After');AssertNotNil(N,'Declaration after multiline string');
      N:=FindDescendant(N,ntLiteral);AssertNotNil(N);
      AssertEquals('$fF_Ff',TValuedSyntaxNode(N).Value,'Hex spelling must be preserved');
    finally Root.Free;end;
  end;
  Root:=ParseSource('unit HexValues; interface const A=$0; B=$FFFFFFFF; C=$FFFFFFFFFFFFFFFF; D=-$80000000; implementation end.');
  Root.Free;
end;
procedure TestMalformedLiterals;
var Q:string;
  procedure Reject(const S:string);
  var Root:TSyntaxNode; Rejected:Boolean;
  begin
    Root:=nil;Rejected:=False;
    try Root:=ParseSource('unit BadLiteral; interface const A='+S+'; implementation end.');
    except on ESyntaxTreeException do Rejected:=True;end;
    Root.Free;AssertTrue(Rejected,'Malformed literal accepted: '+S);
  end;
begin
  Q:=Chr(39);
  Reject('$'); Reject('$_'); Reject(Q); Reject(Q+'unterminated');
  Reject(Q+Q+Q+#10+'text');
  Reject(Q+Q+Q+#10+'text'+Q+Q+Q);
  Reject(Q+Q+Q+#10+'text'+#10+Q+Q);
end;
procedure TestReferenceTypeConsumption;
const Source='unit Refs; interface type TFunc=reference to function(A:Integer):Boolean; TProc=reference to procedure(B:Integer); TEmpty=reference to procedure; implementation end.';
var Parser:TStrictParser; Stream:TStringStream; Root:TSyntaxNode;
begin
  Parser:=TStrictParser.Create;Parser.OnMessage:=Parser.Message;Stream:=TStringStream.Create(Source);
  try Parser.Run('Refs',Stream);finally Stream.Free;Parser.Free;end;
  Root:=ParseSource(Source);
  try AssertEquals(2,CountDescendants(Root,ntParameter));
    AssertEquals(3,CountDescendants(Root,ntAnonymousMethodType));
    AssertNotNil(FindDescendant(Root,ntReturnType));
  finally Root.Free;end;
end;
procedure TestNamedVariantTag;
var Root,N:TSyntaxNode;
begin
  Root:=ParseSource('unit Variants; interface type TRec=record case Kind:Byte of 0:(A:Integer); 1:(B:Double); end; implementation end.');
  try N:=FindDescendant(Root,ntVariantTag);AssertNotNil(N);
    AssertEquals('Kind',N.GetAttribute(anName));AssertEquals('Byte',N.GetAttribute(anType));
    AssertEquals(2,CountDescendants(Root,ntField));
  finally Root.Free;end;
end;
procedure TestAbsoluteVariable;
var Root,N,A:TSyntaxNode;
begin
  Root:=ParseSource('unit Aliases; interface var Original:Integer; AliasValue:Integer absolute Original; AddressValue:Byte absolute $1234; InitialValue:Integer=42; implementation end.');
  try
    N:=Named(Root,ntVariable,'AliasValue');AssertNotNil(N);
    AssertTrue(N.FindNode(ntValue)=nil,'Absolute alias must not be an initializer');
    A:=N.FindNode(ntAbsolute);AssertNotNil(A);AssertNotNil(FindDescendant(A,ntIdentifier));
    N:=Named(Root,ntVariable,'AddressValue');AssertNotNil(N);
    AssertTrue(N.FindNode(ntValue)=nil);A:=N.FindNode(ntAbsolute);AssertNotNil(A);
    AssertNotNil(FindDescendant(A,ntLiteral));
    N:=Named(Root,ntVariable,'InitialValue');AssertNotNil(N.FindNode(ntValue));
    AssertTrue(N.FindNode(ntAbsolute)=nil);
  finally Root.Free;end;
end;
procedure TestFindNodePathOverload;
var Root,A,N:TSyntaxNode;
begin
  Root:=TSyntaxNode.Create(ntVariable);
  try
    A:=Root.AddChild(ntAbsolute);N:=A.AddChild(ntValue).AddChild(ntExpression).AddChild(ntIdentifier);
    AssertTrue(Root.FindNode([ntAbsolute,ntValue,ntExpression,ntIdentifier])=N,'Array literal must select path lookup');
    AssertTrue(Root.FindNode([ntAbsolute,ntUnknown,ntExpression,ntIdentifier])=N);
    AssertTrue(Root.FindNodeOfTypes([ntValue,ntAbsolute])=A);
    AssertTrue(Root.FindNode([])=nil);
  finally Root.Free;end;
end;
procedure TestClassStorageBoundaries;
var Root,N:TSyntaxNode;
  procedure Check(const S,Expected:string);
  begin N:=Named(Root,ntField,S);AssertNotNil(N,S);AssertEquals(Expected,N.GetAttribute(anClass),S);end;
begin
  Root:=ParseSource('unit Storage; interface type TOuter=class public class var A:record Inner:Integer; end; B:Integer; private C:Integer; public D:Integer; end; TNext=class E:Integer; end; implementation end.');
  try
    Check('A','true');Check('B','true');Check('Inner','');
    Check('C','');Check('D','');Check('E','');
  finally Root.Free;end;
end;
procedure TestOperatorKind;
var Root,N:TSyntaxNode;
begin
  Root:=ParseSource('unit Operators; interface type TRec=record Value:Integer; class operator Add(const A,B:TRec):TRec; end; implementation class operator TRec.Add(const A,B:TRec):TRec; begin end; end.');
  try
    N:=Named(Root,ntMethod,'Add');AssertNotNil(N);AssertEquals('operator',N.GetAttribute(anKind));
    N:=Named(Root,ntMethod,'TRec.Add');AssertNotNil(N);AssertEquals('operator',N.GetAttribute(anKind));
  finally Root.Free;end;
end;
procedure TestIncludeLexerContext;
var Lexer,CopyLexer:TmwBasePasLex;Handler:IIncludeHandler;
begin
  Lexer:=TmwBasePasLex.Create;CopyLexer:=TmwBasePasLex.Create;
  try
    Handler:=TTestIncludeHandler.Create(ResolveSnippetPath);
    Lexer.IncludeHandler:=Handler;
    Lexer.Origin:='{$I includefile.inc}';
    AssertTrue(Lexer.FileName<>'','Include must provide a filename');
    CopyLexer.InitFrom(Lexer);
    AssertEquals(Lexer.FileName,CopyLexer.FileName,'Lookahead must retain include context');
  finally CopyLexer.Free;Lexer.Free;end;
end;
procedure RunActualizationTests;
begin
  RunTest('Lexer.IncludeContext',TestIncludeLexerContext);
  RunTest('AST.FindNodePathOverload',TestFindNodePathOverload);
  RunTest('AST.ClassStorageBoundaries',TestClassStorageBoundaries);
  RunTest('AST.OperatorKind',TestOperatorKind);
  RunTest('AST.AbsoluteVariable',TestAbsoluteVariable);
  RunTest('Modern.ReferenceTypeConsumption',TestReferenceTypeConsumption);
  RunTest('Modern.NamedVariantTag',TestNamedVariantTag);
  RunTest('Literals.Boundaries',TestLiteralBoundaries);
  RunTest('Literals.Malformed',TestMalformedLiterals);
  RunTest('Modern.ClassStorage',TestClassStorage);
  RunTest('Modern.RootKinds',TestRootKinds);
  RunTest('Modern.MalformedHeaders',TestMalformedHeaders);
  RunTest('Modern.ConditionalDecimals',TestConditionalDecimals);
  RunTest('Modern.ProceduralMetadata',TestProceduralMetadata);
  RunTest('Modern.GenericMethods',TestGenericMethodMetadata);
  RunTest('AST.AttributeUpdatesAndOwnership',TestAttributeUpdates);
end;
end.

unit DelphiAST.Actualization.Tests;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
procedure RunActualizationTests;
implementation
uses Classes, SysUtils, DelphiAST, DelphiAST.Classes, DelphiAST.Consts,
  DelphiAST.TestFramework, DelphiAST.TestSupport, DelphiAST.Writer;
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
procedure RunActualizationTests;
begin
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

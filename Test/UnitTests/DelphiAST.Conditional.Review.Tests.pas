unit DelphiAST.Conditional.Review.Tests;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

procedure RunConditionalReviewTests;

implementation

uses
  SysUtils, Classes, SimpleParser.Lexer, SimpleParser.Lexer.Types,
  DelphiAST, DelphiAST.Classes, DelphiAST.TestSupport, DelphiAST.TestFramework;

type
  TDeclarationScope = class
  public
    Calls: Integer;
    CheckLocation: Boolean;
    ExpectedFileName: string;
    ExpectedLine, ExpectedColumn, ExpectedSequence: Integer;
    function Resolve(Sender: TmwBasePasLex; const Identifier: string;
      out ADeclared: Boolean): Boolean;
  end;

  TCountingIncludeHandler = class(TInterfacedObject, IIncludeHandler)
  public
    Calls: Integer;
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content, FileName: string): Boolean;
  end;

function TDeclarationScope.Resolve(Sender: TmwBasePasLex;
  const Identifier: string; out ADeclared: Boolean): Boolean;
begin
  AssertNotNil(Sender, 'Resolver must receive its lexer');
  if CheckLocation then
  begin
    AssertEquals(ExpectedFileName, Sender.FileName, 'Declaration scope filename');
    AssertEquals(ExpectedLine, Sender.PosXY.Y, 'Declaration scope line');
    AssertEquals(ExpectedColumn, Sender.PosXY.X, 'Declaration scope column');
    AssertEquals(ExpectedSequence, Sender.PosXY.LineSeq, 'Declaration scope line sequence');
  end;
  Inc(Calls);
  ADeclared := SameText(Identifier, 'Present');
  Result := ADeclared or SameText(Identifier, 'Absent');
end;

function TCountingIncludeHandler.GetIncludeFileContent(const ParentFileName,
  IncludeName: string; out Content, FileName: string): Boolean;
begin
  Inc(Calls);
  if SameText(IncludeName, 'outer.inc') then
    Content := 'outer {$I inner.inc}'
  else if SameText(IncludeName, 'inner.inc') then
    Content := 'inner'
  else if SameText(IncludeName, 'scope.inc') then
    Content := 'head' + #10 + '{$IF Declared(Present)}yes{$ELSE}no{$ENDIF} tail'
  else
    Content := 'included';
  FileName := IncludeName;
  Result := True;
end;

function ReadSymbols(Lexer: TmwBasePasLex): string;
begin
  Result := '';
  while Lexer.TokenID <> ptNull do
  begin
    if not Lexer.IsJunk then
    begin
      if Result <> '' then Result := Result + ' ';
      Result := Result + Lexer.Token;
    end;
    Lexer.Next;
  end;
end;

function Symbols(const Source: string;
  Resolver: TResolveDeclarationEvent = nil): string;
var
  Lexer: TmwBasePasLex;
begin
  Lexer := TmwBasePasLex.Create;
  try
    Lexer.OnResolveDeclaration := Resolver;
    Lexer.Origin := Source;
    Result := ReadSymbols(Lexer);
  finally
    Lexer.Free;
  end;
end;

function ParenthesizedDirectives(const Source: string): string;
begin
  Result := StringReplace(Source, '{$', '(*$', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '*)', [rfReplaceAll]);
end;

procedure CheckCondition(const Expression: string; Expected: Boolean);
var
  Source, ExpectedSymbol: string;
begin
  if Expected then ExpectedSymbol := 'yes' else ExpectedSymbol := 'no';
  Source := '{$IF ' + Expression + '} yes {$ELSE} no {$IFEND}';
  AssertEquals(ExpectedSymbol, Symbols(Source), Expression);
  AssertEquals(ExpectedSymbol, Symbols(ParenthesizedDirectives(Source)),
    'Parenthesized directive: ' + Expression);
end;

procedure TestBooleanPrecedence;
var
  Mask: Integer;
  Prefix, Expected: string;
  A, B, C: Boolean;
begin
  for Mask := 0 to 7 do
  begin
    A := (Mask and 1) <> 0;
    B := (Mask and 2) <> 0;
    C := (Mask and 4) <> 0;
    Prefix := '';
    if A then Prefix := Prefix + '{$DEFINE A}';
    if B then Prefix := Prefix + '{$DEFINE B}';
    if C then Prefix := Prefix + '{$DEFINE C}';
    if A or (B and not C) then Expected := 'yes' else Expected := 'no';
    AssertEquals(Expected, Symbols(Prefix +
      '{$IF DEFINED(A) OR DEFINED(B) AND NOT DEFINED(C)}yes{$ELSE}no{$IFEND}'),
      'OR/AND/NOT truth table, mask ' + IntToStr(Mask));
    if (A or B) xor C then Expected := 'yes' else Expected := 'no';
    AssertEquals(Expected, Symbols(Prefix +
      '{$IF DEFINED(A) OR DEFINED(B) XOR DEFINED(C)}yes{$ELSE}no{$IFEND}'),
      'OR/XOR are left associative, mask ' + IntToStr(Mask));
  end;
  CheckCondition('TRUE OR FALSE AND FALSE', True);
  CheckCondition('NOT FALSE AND FALSE', False);
  CheckCondition('NOT (FALSE AND FALSE)', True);
  CheckCondition('FALSE AND (TRUE OR TRUE)', False);
  CheckCondition('FALSE AND TRUE OR TRUE', True);
  CheckCondition('TRUE OR TRUE XOR TRUE', False);
  CheckCondition('TRUE OR TRUE = FALSE', False);
  CheckCondition('TRUE = FALSE OR TRUE', True);
  CheckCondition('true and'#9'(not false)', True);
  CheckCondition('defined ( Anything )', False);
end;

procedure TestNumericComparisons;
var
  OldSettings: TFormatSettings;
begin
  OldSettings := FormatSettings;
  try
    FormatSettings.DecimalSeparator := ',';
    CheckCondition('CompilerVersion >= 0.0', True);
    CheckCondition('RTLVersion < 9999.5', True);
    CheckCondition('CompilerVersion > 9999.5', False);
    CheckCondition('(CompilerVersion >= 0.0) AND (RTLVersion < 9999.5)', True);
    CheckCondition('1.25 < 1.5', True);
    CheckCondition('1.5 <= 1.5', True);
    CheckCondition('1.5 > 1.25', True);
    CheckCondition('1.5 >= 1.5', True);
    CheckCondition('1.5 = 1.5', True);
    CheckCondition('1.5 <> 1.25', True);
    CheckCondition('-1.5 < +1.5', True);
    CheckCondition('1e2 = 100.0', True);
    CheckCondition('1e-2 < 1e+2', True);
    CheckCondition('9007199254740993 > 9007199254740992', True);
    CheckCondition('9223372036854775807 > 9223372036854775806', True);
  finally
    FormatSettings := OldSettings;
  end;
end;

procedure TestDeclaredResolver;
var
  Scope: TDeclarationScope;
begin
  Scope := TDeclarationScope.Create;
  try
    AssertEquals('yes', Symbols(
      '{$IF Declared(Present)}yes{$ELSE}no{$IFEND}', Scope.Resolve));
    AssertEquals('no', Symbols(
      '{$DEFINE Absent}{$IF Declared(Absent)}yes{$ELSE}no{$IFEND}', Scope.Resolve));
    AssertEquals('yes', Symbols(
      '(*$IF NOT Declared(Absent)*)yes(*$ELSE*)no(*$IFEND*)', Scope.Resolve));
    AssertEquals(3, Scope.Calls);
    Scope.Calls := 0;
    AssertEquals('yes', Symbols(
      '{$IF TRUE OR Declared(Unresolved)}yes{$ELSE}no{$IFEND}', Scope.Resolve));
    AssertEquals('no', Symbols(
      '{$IF FALSE AND Declared(Unresolved)}yes{$ELSE}no{$IFEND}', Scope.Resolve));
    AssertEquals(0, Scope.Calls, 'Short-circuited declarations need no resolution');
  finally
    Scope.Free;
  end;
end;

procedure TestDeclaredRequiresScope;
var
  Rejected: Boolean;
  Scope: TDeclarationScope;
begin
  Rejected := False;
  try
    Symbols('{$DEFINE Present}{$IF DECLARED(Present)}yes{$ELSE}no{$IFEND}');
  except
    on E: EConditionalExpressionError do
    begin
      Rejected := True;
      AssertContains('OnResolveDeclaration', E.Message);
    end;
  end;
  AssertTrue(Rejected, 'Compiler defines must not substitute declaration visibility');
  Scope := TDeclarationScope.Create;
  try
    Rejected := False;
    try
      Symbols('{$IF Declared(Unresolved)}yes{$ELSE}no{$IFEND}', Scope.Resolve);
    except
      on E: EConditionalExpressionError do
      begin
        Rejected := True;
        AssertContains('Cannot resolve', E.Message);
      end;
    end;
    AssertTrue(Rejected, 'An unresolved declaration must not select an AST branch');
  finally
    Scope.Free;
  end;
end;

procedure TestElseIfBranches;
var
  Mask: Integer;
  Source, Expected: string;
begin
  for Mask := 0 to 7 do
  begin
    Source := '';
    if (Mask and 1) <> 0 then Source := Source + '{$DEFINE A}';
    if (Mask and 2) <> 0 then Source := Source + '{$DEFINE B}';
    if (Mask and 4) <> 0 then Source := Source + '{$DEFINE C}';
    Source := Source + '{$IF DEFINED(A)}a{$ELSEIF DEFINED(B)}b' +
      '{$ELSEIF DEFINED(C)}c{$ELSE}other{$IFEND} tail';
    if (Mask and 1) <> 0 then Expected := 'a tail'
    else if (Mask and 2) <> 0 then Expected := 'b tail'
    else if (Mask and 4) <> 0 then Expected := 'c tail'
    else Expected := 'other tail';
    AssertEquals(Expected, Symbols(Source), 'ELSEIF mask ' + IntToStr(Mask));
    AssertEquals(Expected, Symbols(ParenthesizedDirectives(Source)),
      'Parenthesized ELSEIF mask ' + IntToStr(Mask));
  end;
  AssertEquals('first tail', Symbols(
    '{$IF TRUE}first{$ELSEIF Declared(Unresolved)}wrong{$ELSE}wrong{$IFEND}tail'));
end;

procedure TestInactiveNestedDirectives;
var
  Source: string;
begin
  Source := '{$IF FALSE}before{$IF UnknownConstant > 0}wrong' +
    '{$ELSEIF Declared(Unresolved)}wrong{$ELSE}wrong{$IFEND}' +
    '{$ELSE}good{$IF TRUE}nested{$ELSE}wrong{$IFEND}{$IFEND}tail';
  AssertEquals('good nested tail', Symbols(Source));
  AssertEquals('good nested tail', Symbols(ParenthesizedDirectives(Source)));
end;

procedure TestInactiveMutatingDirectives;
var
  Lexer: TmwBasePasLex;
  Counter: TCountingIncludeHandler;
  IncludeHandler: IIncludeHandler;
begin
  Counter := TCountingIncludeHandler.Create;
  IncludeHandler := Counter;
  Lexer := TmwBasePasLex.Create;
  try
    Lexer.IncludeHandler := IncludeHandler;
    Lexer.AddDefine('KEEP');
    Lexer.Origin := '{$IF FALSE}(*$DEFINE LEAK*)(*$UNDEF KEEP*)' +
      '(*$SCOPEDENUMS ON*)(*$I skipped.inc*){$ELSE}good{$IFEND}' +
      '(*$IFDEF KEEP*)kept(*$ENDIF*){$IFDEF LEAK}wrong{$ENDIF}';
    AssertEquals('good kept', ReadSymbols(Lexer));
    AssertEquals(0, Counter.Calls, 'Inactive includes must not be read');
    AssertTrue(Lexer.IsDefined('KEEP'), 'Inactive UNDEF must not change defines');
    AssertFalse(Lexer.IsDefined('LEAK'), 'Inactive DEFINE must not change defines');
    AssertFalse(Lexer.ScopedEnums, 'Inactive SCOPEDENUMS must not change lexer state');
  finally
    Lexer.Free;
  end;
  AssertEquals('yes', Symbols('(*$DEFINE ACTIVE*)(*$IFDEF ACTIVE*)yes(*$ENDIF*)'));
  AssertEquals('yes', Symbols(
    '(*$DEFINE ACTIVE*)(*$UNDEF ACTIVE*)(*$IFNDEF ACTIVE*)yes(*$ENDIF*)'));
end;

procedure TestMalformedExpressions;
const
  Expressions: array[0..28] of string = (
    '', '(', '()', 'DEFINED()', 'DEFINED(A', 'DECLARED(A', 'DEFINED(A))',
    'DEFINED(A) OR', 'NOT', 'NOTTRUE', 'TRUE TRUE', 'TRUE XOR',
    'CompilerVersion >', 'CompilerVersion >=', '1 == 1', '1 >< 1',
    '1 => 1', '1e+ > 0', '1.0.1 = 1', 'TRUE AND 1', '1',
    'UNKNOWN > 0', 'DEFINED(A) ANDNOT DEFINED(B)', '1 < 2 < 3',
    '1e9999 > 0', '9223372036854775808 > 0', '1. = 1',
    'DECLARED(TObject.Field)', 'CompilerVersion >= 0 AND TRUE');
var
  Expression: string;
  Rejected: Boolean;
begin
  for Expression in Expressions do
  begin
    Rejected := False;
    try
      Symbols('{$IF ' + Expression + '}first{$ELSE}second{$IFEND}');
    except
      on EConditionalExpressionError do Rejected := True;
    end;
    AssertTrue(Rejected, 'Malformed or unsupported condition: ' + Expression);
  end;
end;

procedure TestMalformedConditionalStack;
const
  Sources: array[0..9] of string = (
    '{$ELSE}token', '{$ELSEIF TRUE}token', '{$ENDIF}token', '{$IFEND}token',
    '{$IF TRUE}a{$ELSE}b{$ELSE}c{$IFEND}',
    '{$IF TRUE}a{$ELSE}b{$ELSEIF TRUE}c{$IFEND}',
    '{$IF TRUE}token', '{$IF FALSE}token', '{$IF', '(*$IF');
var
  Source: string;
  Rejected: Boolean;
begin
  for Source in Sources do
  begin
    Rejected := False;
    try Symbols(Source); except on EConditionalExpressionError do Rejected := True; end;
    AssertTrue(Rejected, 'Malformed conditional stack: ' + Source);
  end;
end;

procedure TestConditionalLexerReuse;
var
  Lexer: TmwBasePasLex;
  Rejected: Boolean;
begin
  Lexer := TmwBasePasLex.Create;
  try
    Lexer.AddDefine('FromCaller');
    Rejected := False;
    try
      Lexer.Origin := '{$IF FALSE}hidden';
      ReadSymbols(Lexer);
    except on EConditionalExpressionError do Rejected := True; end;
    AssertTrue(Rejected);
    Lexer.Origin := '{$IFDEF FromCaller}kept{$ELSE}wrong{$ENDIF}';
    AssertEquals('kept', ReadSymbols(Lexer), 'A failed source must not retain an IF frame');
    Lexer.ClearDefines;
    Lexer.Origin := '{$IFDEF FromCaller}wrong{$ELSE}cleared{$ENDIF}';
    AssertEquals('cleared', ReadSymbols(Lexer));
  finally
    Lexer.Free;
  end;
end;

procedure TestResolverInLookahead;
var
  Lexer: TmwPasLex;
  CopyLexer: TmwBasePasLex;
  Scope: TDeclarationScope;
  Counter: TCountingIncludeHandler;
  IncludeHandler: IIncludeHandler;
begin
  Lexer := TmwPasLex.Create;
  CopyLexer := TmwBasePasLex.Create;
  Scope := TDeclarationScope.Create;
  try
    Lexer.OnResolveDeclaration := Scope.Resolve;
    Lexer.Origin := 'start {$IF DECLARED(Present)}yes{$ELSE}no{$IFEND}';
    CopyLexer.InitFrom(Lexer);
    AssertEquals(0, Scope.Calls, 'InitFrom must not execute future directives');
    AssertEquals('start yes', ReadSymbols(CopyLexer));
    AssertEquals(1, Scope.Calls);
    Lexer.InitAhead;
    AssertEquals('yes', Lexer.AheadToken, 'Lookahead must retain the declaration resolver');
    AssertEquals('start yes', ReadSymbols(Lexer));
    Lexer.Origin := '{$IF FALSE}{$ENDIF}token';
    AssertEquals('token', ReadSymbols(Lexer),
      'New source lookahead must clone the current conditional state');
    Counter := TCountingIncludeHandler.Create;
    IncludeHandler := Counter;
    Lexer.IncludeHandler := IncludeHandler;
    Lexer.Origin := '{$IF TRUE}{$I example.inc}{$ENDIF}tail';
    Lexer.NextNoJunk;
    AssertEquals('included', Lexer.Token);
    CopyLexer.InitFrom(Lexer);
    AssertEquals('example.inc', CopyLexer.FileName);
    AssertEquals('included tail', ReadSymbols(CopyLexer),
      'A copied include must continue in its parent source');
    Lexer.InitAhead;
    AssertEquals('tail', Lexer.AheadToken);
    AssertEquals('included tail', ReadSymbols(Lexer));
  finally
    CopyLexer.Free;
    Lexer.Free;
    Scope.Free;
  end;
end;

procedure TestIncludeScopeLookahead;
var
  Lexer: TmwPasLex;
  Scope: TDeclarationScope;
  IncludeHandler: IIncludeHandler;
  I: Integer;
begin
  Lexer := TmwPasLex.Create;
  Scope := TDeclarationScope.Create;
  IncludeHandler := TCountingIncludeHandler.Create;
  try
    Scope.CheckLocation := True;
    Scope.ExpectedFileName := 'scope.inc';
    Scope.ExpectedLine := 2;
    Scope.ExpectedColumn := 1;
    Scope.ExpectedSequence := 2;
    Lexer.IncludeHandler := IncludeHandler;
    Lexer.OnResolveDeclaration := Scope.Resolve;
    Lexer.Origin := '{$SCOPEDENUMS ON}' + #10 + '{$I scope.inc} finish';
    Lexer.NextNoJunk;
    AssertEquals('head', Lexer.Token);
    Lexer.AsmCode := True;
    for I := 1 to 3 do
    begin
      Lexer.InitAhead;
      AssertEquals('yes', Lexer.AheadToken);
      AssertEquals('scope.inc', Lexer.AheadLex.FileName);
      AssertTrue(Lexer.AheadLex.ScopedEnums);
      AssertTrue(Lexer.AheadLex.AsmCode);
    end;
    Lexer.NextNoJunk;
    AssertEquals('yes tail finish', ReadSymbols(Lexer));

    Lexer.AsmCode := False;
    Lexer.Origin := '{$IF TRUE}{$I outer.inc}after{$ENDIF}';
    Lexer.NextNoJunk;
    AssertEquals('outer', Lexer.Token);
    Lexer.NextNoJunk;
    AssertEquals('inner', Lexer.Token);
    for I := 1 to 25 do
    begin
      Lexer.InitAhead;
      AssertEquals('after', Lexer.AheadToken, 'Lookahead must cross two include parents');
      AssertEquals('inner', Lexer.Token, 'Lookahead must preserve the owning lexer position');
    end;
    AssertEquals('inner after', ReadSymbols(Lexer));

    // Destroy while both the owning lexer and lookahead retain include frames.
    Lexer.Origin := '{$I outer.inc}finish';
    Lexer.NextNoJunk;
    AssertEquals('inner', Lexer.Token);
  finally
    Lexer.Free;
    Scope.Free;
  end;
end;

procedure TestBuilderConditionalDiagnostic;
var
  Root: TSyntaxNode;
  Rejected: Boolean;
begin
  Root := nil;
  Rejected := False;
  try
    Root := ParseSource('unit Example; interface {$IF Declared(Unknown)}' +
      'type TSelected = Integer; {$IFEND} implementation end.');
  except
    on E: ESyntaxTreeException do
    begin
      Rejected := True;
      AssertContains('OnResolveDeclaration', E.Message);
    end;
  end;
  Root.Free;
  AssertTrue(Rejected, 'Builder must report the unresolved condition as a syntax diagnostic');
end;

procedure RunConditionalReviewTests;
begin
  RunTest('Conditional.BooleanPrecedence', TestBooleanPrecedence);
  RunTest('Conditional.NumericComparisons', TestNumericComparisons);
  RunTest('Conditional.DeclaredResolver', TestDeclaredResolver);
  RunTest('Conditional.DeclaredRequiresScope', TestDeclaredRequiresScope);
  RunTest('Conditional.ElseIfBranches', TestElseIfBranches);
  RunTest('Conditional.InactiveNestedDirectives', TestInactiveNestedDirectives);
  RunTest('Conditional.InactiveMutatingDirectives', TestInactiveMutatingDirectives);
  RunTest('Conditional.MalformedExpressions', TestMalformedExpressions);
  RunTest('Conditional.MalformedStack', TestMalformedConditionalStack);
  RunTest('Conditional.LexerReuse', TestConditionalLexerReuse);
  RunTest('Conditional.ResolverInLookahead', TestResolverInLookahead);
  RunTest('Conditional.IncludeScopeLookahead', TestIncludeScopeLookahead);
  RunTest('Conditional.BuilderDiagnostic', TestBuilderConditionalDiagnostic);
end;

end.

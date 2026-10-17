program ParseProbe;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
uses SysUtils, DelphiAST, DelphiAST.Classes, DelphiAST.TestSupport;
var Root:TSyntaxNode;
procedure Validate(Node, Parent:TSyntaxNode; Depth:Integer);
var Child:TSyntaxNode;
begin
  if Depth>512 then raise Exception.Create('AST depth exceeded');
  if Node.ParentNode<>Parent then raise Exception.Create('Invalid AST parent');
  if (Node.Line<0) or (Node.Col<0) or (Node.LineSeq<0) then raise Exception.Create('Invalid AST position');
  for Child in Node.ChildNodes do Validate(Child,Node,Depth+1);
end;
begin
  Root:=nil;
  try
    try
      Root:=ParseFile(ParamStr(1),ParamStr(2));
      Validate(Root,nil,0);
      Writeln('OK');
    except
      on E:ESyntaxTreeException do begin Writeln('REJECT: '+E.Message);ExitCode:=10;end;
      on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=2;end;
    end;
  finally Root.Free;end;
end.

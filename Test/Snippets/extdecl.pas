unit ExtdeclTypes;
interface
type TCallback = procedure(Value: Integer); extdecl;
procedure ExternalCall(Value: Integer); extdecl; external 'example';
implementation
end.

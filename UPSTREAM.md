# Upstream compatibility and attribution

This fork follows [RomanYankovsky/DelphiAST](https://github.com/RomanYankovsky/DelphiAST).
The current integration starts at upstream `38402535ad6018b981f08920836aac99b554cb86`
and reviews the public pull requests and fork heads available on October 18, 2026.

The parser and cross-compiler headless suite incorporate the relevant source from
[jimmckeeth/DelphiAST](https://github.com/jimmckeeth/DelphiAST), revision
`e89ce1f93f6c01450d2eacacfb05bc0e1c0f3b19`. This includes work by JBontes,
Wosi, Uwe Raabe and luebbe, as well as the modern directive changes by Stefan Glienke.
Unrelated demos, allocator dependencies and planning documents were not imported.

## Pull request coverage

| Upstream PR | Integration |
| --- | --- |
| [350](https://github.com/RomanYankovsky/DelphiAST/pull/350) | Decimal CompilerVersion/RTLVersion operands are supported by the integrated expression evaluator; the PR's regression snippet is included. |
| [349](https://github.com/RomanYankovsky/DelphiAST/pull/349) | Lexer warning fixes, reconciled with the existing compiler guards. |
| [348](https://github.com/RomanYankovsky/DelphiAST/pull/348) | Procedural variants are represented by procedural type and anonymous-method nodes; the PR's snippet and structural assertions are included. |
| [346](https://github.com/RomanYankovsky/DelphiAST/pull/346) | Varargs, external/unsafe directives, managed-record defines, calling conventions and conditional parentheses through the integrated grammar. |
| [343](https://github.com/RomanYankovsky/DelphiAST/pull/343), [340](https://github.com/RomanYankovsky/DelphiAST/pull/340) | Anonymous/reference calling conventions and regression snippets. |
| [342](https://github.com/RomanYankovsky/DelphiAST/pull/342), [341](https://github.com/RomanYankovsky/DelphiAST/pull/341) | Record alignment expressions, including parenthesized constants and identifiers. |
| [337](https://github.com/RomanYankovsky/DelphiAST/pull/337) | Multiline string parsing fix. |
| [318](https://github.com/RomanYankovsky/DelphiAST/pull/318) | Adjacent generic closing bracket and assignment operator. |
| [316](https://github.com/RomanYankovsky/DelphiAST/pull/316) | WinApi calling convention. |
| [315](https://github.com/RomanYankovsky/DelphiAST/pull/315) | Unit/program/library/package roots; malformed and leading-directive handling additionally repaired. |
| [313](https://github.com/RomanYankovsky/DelphiAST/pull/313) | Shared file reads and encoding diagnostics. |
| [304](https://github.com/RomanYankovsky/DelphiAST/pull/304) | General variable references in for-in loops. |
| [268](https://github.com/RomanYankovsky/DelphiAST/pull/268) | Helpers on literals. |
| [231](https://github.com/RomanYankovsky/DelphiAST/pull/231) | Broad grammar/AST fixes through the maintained fork; attribute updates, removal and source coordinates additionally repaired. |
| [215](https://github.com/RomanYankovsky/DelphiAST/pull/215) | Class storage metadata, using the corrected De-Novo implementation strategy rather than the old section-wide flag. |
| [213](https://github.com/RomanYankovsky/DelphiAST/pull/213) | Structured generic method parameters under the method name node. |
| [165](https://github.com/RomanYankovsky/DelphiAST/pull/165) | Forward declarations, including the existing semicolon regression snippets. |

The [De-Novo-Research fork](https://github.com/De-Novo-Research/DelphiAST)
contributed the corrected class-var/class-const strategy (`1da8dac`), with tests
for multiple names, multiple declarations and subsequent instance fields.

PR 319's `extdecl` calling convention is also supported and regression-tested.
Older FPC/Lazarus PRs 319 and 312 overlap with the working cross-compiler suite;
demo-specific project changes and replacement compiler-configuration machinery
are not imported wholesale. PR 185's alternative comment-attachment API is not
introduced: existing comment collection remains available. PRs 172 and 173
(global string caches and bulk allocation) and PR 325 (FastMM dependency) are
not language features and remain excluded from the core parser.

Other reviewed fork changes that only merge upstream, alter demos or package
metadata, or introduce contradictory target-platform/compiler defines are not
part of this parser integration.

## Validation and API notes

Run `Test/Run-Tests.ps1` for native RAD Studio 12/13 Win32/Win64 tests and
deterministic grammar/mutation fuzzing. Build products and fuzz failures go to
`%LOCALAPPDATA%\DelphiAST-actualization`, outside the checkout. Every fuzz input
runs in a separate process with a timeout; syntax errors are expected rejection,
while access violations, unexpected exceptions and hangs fail the run.

FPC/Linux runs the shared suite and fuzz target in GitHub Actions. This tests
syntax trees rather than pretending that every parsed syntax feature can be
compiled by every host compiler.

Method and constant names may be represented by `ntName` child nodes. Generic
method parameters are retained structurally. Consumers should inspect those
nodes rather than relying exclusively on the parent's `anName` attribute.
`LineSeq` is initialized and binary serialization revision 1.0.1 preserves it.

### Node lookup API

`FindNode([ntAbsolute, ntValue, ntExpression, ntIdentifier])` follows an ordered child path. To find the first direct child whose type belongs to a set, use `FindNodeOfTypes([ntValue, ntAbsolute])`. The set overload was renamed because Delphi cannot unambiguously resolve array literals against both overloads. `FindNode(TSyntaxNodeType)` is unchanged.

## Review follow-up: compatibility and API

### Syntax tree consumers

`TSyntaxNode.HasAttributes` is restored. An empty lookup path returns `nil`;
`ntUnknown` remains a wildcard at intermediate path positions. The
`FindNodeOfTypes` API introduced in master is retained.

Class storage metadata is confined to its declaration section and does not
propagate into nested record fields. Section boundaries follow the
[Delphi field declaration rules](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Fields_%28Delphi%29).
Operator keywords are recognized independently of letter case. Compiler
directive nodes retain source text and operand case while normalizing the
directive name in `anType`.

### Binary caches

`TBinarySerializer.Read` now rejects version **1.0.0** with `False`. That version
was written with incompatible `TSyntaxNodeType` ordinal orderings, and the
header cannot identify which ordering to use. Rebuild affected caches from
their source files. The **1.0.1** layout is retained for reading and writing;
`FileName` is still not serialized. An unsuccessful read leaves the caller's
`Root` unchanged. The reader validates numeric encodings, counts and string
references, and grows string buffers as data arrives. String-reference IDs use
the same UTF-16 length convention in Delphi and FPC; FPC string values are UTF-8.

### Conditional compilation

`DECLARED(Identifier)` needs declaration visibility for the current scope,
as specified by the [Delphi IF directive](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/IF_directive_%28Delphi%29).
Supply it before `Builder.Run` through
`Builder.Lexer.Lexer.OnResolveDeclaration`; the intermediate `TPasLexer`
wrapper exposes the underlying lexer through its own `Lexer` property. The
event type in `SimpleParser.Lexer` is:

```pascal
TResolveDeclarationEvent = function(Sender: TmwBasePasLex;
  const Identifier: string; out ADeclared: Boolean): Boolean of object;
```

Return `True` when the answer is known and set `ADeclared` to `True` for a
visible declaration or `False` for a known absence. Return `False` when the
caller cannot resolve the identifier. A missing resolver or an unresolved
declaration in a condition that must be evaluated raises
`EConditionalExpressionError`; `Builder.Run` exposes it as
`ESyntaxTreeException`. Unsupported active expressions also fail explicitly.
There is no built-in declaration symbol table, and conditional defines do not
substitute for declarations.

The existing **`$IFOPT` limitation remains**: compiler-switch values are not
evaluated. With conditional processing enabled, its branch is treated as
false; the low-level parser reports `meNotSupported`.

### Regression coverage

The shared Delphi/FPC review units cover
[AST APIs and metadata](Test/UnitTests/DelphiAST.AST.Review.Tests.pas),
[binary fixtures and malformed streams](Test/UnitTests/DelphiAST.Binary.Review.Tests.pas),
[conditional evaluation, scope resolution and lexer reuse](Test/UnitTests/DelphiAST.Conditional.Review.Tests.pas),
and [assembly boundaries, anonymous method types and record variants](Test/UnitTests/DelphiAST.Grammar.Review.Tests.pas).
These complement the existing snippet suite and deterministic fuzz target.
Owned stream-conversion buffers are released on syntax and I/O errors; the
caller retains ownership of the input stream and can reuse the parser.
Use the respective Delphi and FPC test runners to validate a build.

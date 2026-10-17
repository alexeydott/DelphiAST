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
`LineSeq` is initialized and binary serialization revision 1.0.1 preserves it;
the reader also accepts the previous 1.0.0 layout for the current node enums.

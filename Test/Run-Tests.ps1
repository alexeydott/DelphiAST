param(
    [string]$Rad12 = 'D:\Embarcadero RAD Studio\23.0',
    [string]$Rad13 = 'D:\Embarcadero RAD Studio\37.0',
    [int]$FuzzCount = 500,
    [string]$OutputDir = "$env:LOCALAPPDATA\DelphiAST-actualization"
)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    foreach($toolchain in @(@{Name='rad12';Root=$Rad12},@{Name='rad13';Root=$Rad13})) {
        foreach($platform in @('Win32','Win64')) {
            $out=Join-Path $OutputDir "$($toolchain.Name)-$platform"
            New-Item -ItemType Directory -Force $out | Out-Null
            $compiler=if($platform -eq 'Win32'){'dcc32'}else{'dcc64'}
            foreach($program in @('DelphiASTTests','ParseProbe')) {
                & cmd.exe /d /c "`"$($toolchain.Root)\bin\rsvars.bat`" && $compiler -B --codepage:65001 -NSSystem;System.Win;Winapi -ISource\SimpleParser -USource;Source\SimpleParser;Test\UnitTests `"-E$out`" `"-N0$out`" Test\UnitTests\$program.dpr" *> "$out\$program-build.log"
                if($LASTEXITCODE){throw "Compile failed: $out\$program-build.log"}
            }
            & "$out\DelphiASTTests.exe" Test\Snippets *> "$out\tests.log"
            if($LASTEXITCODE){throw "Tests failed: $out\tests.log"}
            python Test\fuzz.py "$out\ParseProbe.exe" --output "$out\fuzz" --count $FuzzCount *> "$out\fuzz.log"
            if($LASTEXITCODE){throw "Fuzz failed: $out\fuzz.log"}
            Get-Content "$out\tests.log" -Tail 1
            Get-Content "$out\fuzz.log" -Tail 1
        }
    }
} finally { Pop-Location }

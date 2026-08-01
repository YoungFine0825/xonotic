# ============================================================================
# Build QuakeC gamecode with a C preprocessor + gmqcc (mirrors tools/qcc.sh):
#   1) expand the unity source progs.inc with the C preprocessor (cl /E or gcc -E)
#   2) convert #line directives into #pragma file / #pragma line for gmqcc
#   3) invoke gmqcc with the same options as qcsrc/Makefile
# Usage example:
#   powershell -File qcc.ps1 -Cpp cl.exe -Qcc gmqcc.exe -Mode client `
#       -In client/progs.inc -Out csprogs.dat -WorkDir .tmp -Include .
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Cpp,      # cl.exe or gcc/cc
    [Parameter(Mandatory = $true)][string]$Qcc,      # gmqcc executable
    [Parameter(Mandatory = $true)][ValidateSet('client', 'menu', 'server')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$In,       # full path to progs.inc
    [Parameter(Mandatory = $true)][string]$Out,      # output .dat path
    [Parameter(Mandatory = $true)][string]$WorkDir,  # scratch directory
    [Parameter(Mandatory = $true)][string]$Include,  # include root (qcsrc dir)
    [string]$Watermark = ""                          # version watermark (optional)
)

# NOTE: do NOT use ErrorActionPreference=Stop here. PowerShell 5.1 converts
# native-command stderr into a terminating error, and cl/gmqcc normally write
# to stderr. Exit codes are checked explicitly below instead.
$ErrorActionPreference = 'Continue'

function Resolve-ResidualDirectives {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$KnownDefines
    )

    $defSet = @{}
    foreach ($d in $KnownDefines) { $defSet[$d] = $true }

    function Test-Defined([string]$name) {
        # A numeric token means MSVC substituted a defined macro's value,
        # so the original directive was true.
        if ($name -match '^\d+$') { return $true }
        return $defSet.ContainsKey($name)
    }

    function Eval-Expr([string]$expr, [ref]$ok) {
        # returns boolean; minimal parser for: || && ! ( ) defined(NAME) NAME number
        $tokens = New-Object System.Collections.ArrayList
        $s = $expr.Trim()
        $i = 0
        while ($i -lt $s.Length) {
            $ch = $s[$i]
            if ($ch -match '\s') { $i++; continue }
            if ($s.Substring($i).StartsWith('defined')) {
                $i += 7
                while ($i -lt $s.Length -and $s[$i] -match '\s') { $i++ }
                if ($i -lt $s.Length -and $s[$i] -eq '(') {
                    $i++
                    $name = ''
                    while ($i -lt $s.Length -and $s[$i] -ne ')') { $name += $s[$i]; $i++ }
                    $i++
                    [void]$tokens.Add(@{ t = 'bool'; v = Test-Defined $name.Trim() })
                } else {
                    $ok.Value = $false; return $false
                }
                continue
            }
            if ($ch -eq '(' -or $ch -eq ')') { [void]$tokens.Add(@{ t = 'paren'; v = $ch }); $i++; continue }
            if ($ch -eq '!') { [void]$tokens.Add(@{ t = 'not'; v = $true }); $i++; continue }
            if ($s.Substring($i).StartsWith('&&')) { [void]$tokens.Add(@{ t = 'and'; v = $true }); $i += 2; continue }
            if ($s.Substring($i).StartsWith('||')) { [void]$tokens.Add(@{ t = 'or'; v = $true }); $i += 2; continue }
            $m = [regex]::Match($s.Substring($i), '^[A-Za-z_][A-Za-z0-9_]*')
            if ($m.Success) {
                [void]$tokens.Add(@{ t = 'bool'; v = (Test-Defined $m.Value) })
                $i += $m.Length
                continue
            }
            $m2 = [regex]::Match($s.Substring($i), '^\d+')
            if ($m2.Success) {
                [void]$tokens.Add(@{ t = 'bool'; v = ([int]$m2.Value -ne 0) })
                $i += $m2.Length
                continue
            }
            $ok.Value = $false
            return $false
        }

        # recursive descent over the token list ($pos is an array so nested
        # functions can mutate the shared parse position)
        $pos = @(0)
        function Parse-Or {
            $left = Parse-And
            while ($pos[0] -lt $tokens.Count -and $tokens[$pos[0]].t -eq 'or') {
                $pos[0]++
                $right = Parse-And
                $left = ($left -or $right)
            }
            return $left
        }
        function Parse-And {
            $left = Parse-Not
            while ($pos[0] -lt $tokens.Count -and $tokens[$pos[0]].t -eq 'and') {
                $pos[0]++
                $right = Parse-Not
                $left = ($left -and $right)
            }
            return $left
        }
        function Parse-Not {
            if ($pos[0] -lt $tokens.Count -and $tokens[$pos[0]].t -eq 'not') {
                $pos[0]++
                return (-not (Parse-Not))
            }
            return Parse-Primary
        }
        function Parse-Primary {
            if ($pos[0] -ge $tokens.Count) { $ok.Value = $false; return $false }
            $t = $tokens[$pos[0]]
            if ($t.t -eq 'bool') { $pos[0]++; return [bool]$t.v }
            if ($t.t -eq 'paren' -and $t.v -eq '(') {
                $pos[0]++
                $v = Parse-Or
                if ($pos[0] -lt $tokens.Count -and $tokens[$pos[0]].t -eq 'paren' -and $tokens[$pos[0]].v -eq ')') { $pos[0]++ } else { $ok.Value = $false }
                return $v
            }
            $ok.Value = $false
            return $false
        }
        $result = Parse-Or
        if ($pos[0] -ne $tokens.Count) { $ok.Value = $false }
        return $result
    }

    $stack = New-Object System.Collections.ArrayList
    $out = New-Object System.Text.StringBuilder

    foreach ($line in ($Text -split "`n")) {
        $len = $line.Length
        $i = 0
        $segStart = 0
        $inStr = $null

        function Active-State {
            foreach ($f in $stack) { if (-not $f.active) { return $false } }
            return $true
        }

        while ($i -lt $len) {
            $ch = $line[$i]
            if ($null -ne $inStr) {
                if ($ch -eq '\') { $i += 2; continue }
                if ($ch -eq $inStr) { $inStr = $null }
                $i++
                continue
            }
            if ($ch -eq '"' -or $ch -eq "'") { $inStr = $ch; $i++; continue }
            if ($ch -eq '#') {
                $j = $i + 1
                while ($j -lt $len -and $line[$j] -match '\s') { $j++ }
                $m = [regex]::Match($line.Substring($j), '^(ifdef|ifndef|if|elif|else|endif)\b')
                if ($m.Success) {
                    $word = $m.Groups[1].Value
                    $afterWord = $j + $m.Length
                    if ($word -eq 'ifdef' -or $word -eq 'ifndef') {
                        # argument is a single macro name (may have been
                        # substituted to a number by MSVC)
                        $tm = [regex]::Match($line.Substring($afterWord), '^\s*([A-Za-z_][A-Za-z0-9_]*|\d+)')
                        $exprEnd = $afterWord + $tm.Length
                        $expr = $tm.Groups[1].Value
                    } elseif ($word -eq 'if' -or $word -eq 'elif') {
                        # expression extends to the next directive or EOL
                        $k = $afterWord
                        $exprEnd = $len
                        while ($k -lt $len) {
                            if ($line[$k] -eq '#') {
                                $k2 = $k + 1
                                while ($k2 -lt $len -and $line[$k2] -match '\s') { $k2++ }
                                if ([regex]::IsMatch($line.Substring($k2), '^(ifdef|ifndef|if|elif|else|endif)\b')) {
                                    $exprEnd = $k
                                    break
                                }
                            }
                            $k++
                        }
                        $expr = $line.Substring($afterWord, $exprEnd - $afterWord).Trim()
                    } else {
                        # else / endif
                        $exprEnd = $afterWord
                        $expr = ''
                    }
                    $seg = $line.Substring($segStart, $i - $segStart)
                    if (Active-State) { [void]$out.Append($seg) }

                    $ok = [ref]$true
                    switch ($word) {
                        'ifdef'  { $active = Test-Defined $expr }
                        'ifndef' { $active = -not (Test-Defined $expr) }
                        'if'     { $active = Eval-Expr $expr $ok }
                        'elif' {
                            $f = $stack[$stack.Count - 1]
                            if (-not $f.seenElse) {
                                if ($f.everTrue) { $f.active = $false }
                                else { $f.active = Eval-Expr $expr $ok; $f.everTrue = $f.active }
                            }
                            $active = $null
                        }
                        'else' {
                            $f = $stack[$stack.Count - 1]
                            if (-not $f.seenElse) {
                                $f.seenElse = $true
                                $f.active = -not $f.everTrue
                                $f.everTrue = $true
                            }
                            $active = $null
                        }
                        'endif' {
                            if ($stack.Count -gt 0) { [void]$stack.RemoveAt($stack.Count - 1) }
                            $active = $null
                        }
                    }
                    if ($word -eq 'ifdef' -or $word -eq 'ifndef' -or $word -eq 'if') {
                        [void]$stack.Add(@{ active = $active; everTrue = $active; seenElse = $false })
                    }
                    $i = $exprEnd
                    $segStart = $i
                    continue
                }
            }
            $i++
        }
        $seg = $line.Substring($segStart)
        if (Active-State) { [void]$out.Append($seg) }
        [void]$out.Append("`n")
    }

    return $out.ToString()
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# watermark header: avoids quoting /D defines on the command line
$wmHeader = Join-Path $WorkDir 'watermark.h'
Set-Content -Path $wmHeader -Value ("#define WATERMARK `"{0}`"" -f $Watermark) -Encoding Ascii

$defines = @(
    '/DGMQCC',
    '/DXONOTIC=1',
    '/DNDEBUG=1',
    '/DENABLE_EFFECTINFO=0',
    '/DENABLE_DEBUGDRAW=0',
    '/DENABLE_DEBUGTRACE=0'
)
switch ($Mode) {
    'client' { $defines += @('/DGAMEQC', '/DCSQC') }
    'menu'   { $defines += '/DMENUQC' }
    'server' { $defines += @('/DGAMEQC', '/DSVQC') }
}

$isMsvc = ([IO.Path]::GetFileName($Cpp) -ieq 'cl.exe')
if ($isMsvc) {
    # /D__STDC__: makes qcsrc select the standard (P99) OVERLOAD macros,
    #   matching GCC's preprocessor (GCC defines __STDC__ by default).
    # /Zc:preprocessor: MSVC's conformant preprocessor, required by P99.
    $ppArgs = @('/nologo', '/E', '/utf-8', '/D__STDC__', '/Zc:preprocessor',
                "/I`"$Include`"", "/FI`"$wmHeader`"") `
        + $defines + @("`"$In`"")
} else {
    $gccDefines = $defines -replace '^/', '-'
    $ppArgs = @('-E', '-x', 'c', "-I`"$Include`"", '-include', "`"$wmHeader`"") `
        + $gccDefines + @("`"$In`"")
}

# Run the preprocessor with raw byte redirection. Capturing native stdout in
# PowerShell would decode it with the console codepage and corrupt UTF-8
# sources (e.g. menu/xonotic/charmap.qc).
$ppOutFile = Join-Path $WorkDir "$Mode.pp.txt"
$ppErrFile = Join-Path $WorkDir "$Mode.pp.err"
$ppCmd = "`"$Cpp`" $($ppArgs -join ' ') > `"$ppOutFile`" 2> `"$ppErrFile`""
& cmd.exe /c $ppCmd
if ($LASTEXITCODE -ne 0) {
    if (Test-Path $ppErrFile) { Get-Content $ppErrFile | ForEach-Object { Write-Error $_ } }
    throw "preprocessing failed: $In"
}

# #line N "file" (MSVC) or # N "file" (GCC) -> #pragma file / #pragma line
# NOTE: MSVC may emit #line with leading whitespace, so the regex tolerates it.
$text = [IO.File]::ReadAllText($ppOutFile, [System.Text.Encoding]::UTF8)
$text = $text -replace "`r`n", "`n"

# MSVC /E does not splice backslash-newline (unlike GCC's cpp, which does it
# in translation phase 2). Splice them here to match GCC's output exactly.
$text = [regex]::Replace($text, '\\\n', '')

# GCC line markers may carry trailing flags: `# 1 "file" 1` (entering file),
# `# 0 "<command-line>" 2` (returning). MSVC emits plain `#line N "file"`.
$rx = [regex]'(?m)^[ \t]*#(?:line)?[ \t]*(\d+)[ \t]*"([^"]*)"(?:\s+[0-9]+)?[ \t]*$'
$text = $rx.Replace($text, {
    param($m)
    $file = $m.Groups[2].Value -replace '\\', '/'
    "`n#pragma file(`"$file`")`n#pragma line($($m.Groups[1].Value))"
})

# GCC's cpp consumes `#pragma once`; MSVC /E passes it through, but gmqcc
# treats it as an unknown pragma (error under -Werror). Strip it here.
$text = [regex]::Replace($text, '(?m)^[ \t]*#pragma[ \t]+once[ \t]*\r?$', '')

# gmqcc's lexer consumes the trailing newline while unrolling pragmas it does
# not recognize at the lexer level (e.g. `#pragma noref`), which would merge
# the following line (usually `#pragma file(...)`) into the same logical line.
# Insert a blank line after such pragmas to preserve line separation. The
# pragma itself is still parsed (noref semantics are kept).
$lines = $text -split "`n"
$outLines = New-Object System.Collections.ArrayList
foreach ($l in $lines) {
    [void]$outLines.Add($l)
    if ($l -match '^[ \t]*#pragma' -and $l -notmatch '^[ \t]*#pragma (file|line)\(') {
        [void]$outLines.Add('')
    }
}
$text = $outLines -join "`n"

# MSVC's preprocessor does not evaluate conditional directives that appear
# inside macro arguments (GCC's cpp does). They survive in the output as
# `#ifdef X ... #endif` fragments and must be resolved here. GCC's output
# does not contain them.
if ($isMsvc) {
    $modeDefines = @()
    switch ($Mode) {
        'client' { $modeDefines = @('CSQC') }
        'server' { $modeDefines = @('SVQC') }
        'menu'   { $modeDefines = @('MENUQC') }
    }
    $known = @('GMQCC', 'XONOTIC', 'NDEBUG', 'GAMEQC') + $modeDefines
    $text = Resolve-ResidualDirectives -Text $text -KnownDefines $known
}

$qcFile = Join-Path $WorkDir "$Mode.qc"
[IO.File]::WriteAllText($qcFile, $text, (New-Object System.Text.UTF8Encoding($false)))

$qccFlags = @(
    '-std=gmqcc', '-Ooverlap-locals', '-O3',
    '-Werror', '-Wall', '-Wno-field-redeclared',
    '-flno', '-futf8', '-fno-bail-on-werror',
    '-frelaxed-switch', '-freturn-assignments',
    '-o', "`"$Out`"", "`"$qcFile`""
)
& $Qcc @qccFlags
if ($LASTEXITCODE -ne 0) {
    throw "gmqcc compile failed: $Mode"
}

Write-Host "OK: $Mode -> $Out"

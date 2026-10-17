"""Deterministic grammar/mutation fuzzing with a separate process and timeout per case."""
import argparse, concurrent.futures, json, random, subprocess, tempfile
from pathlib import Path

def run(executable, snippets, output, count, seed):
    rng = random.Random(seed)
    corpus = []
    for p in sorted(snippets.glob('*.pas')):
        data=p.read_bytes()
        corpus.append(data.decode('utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig'))
    failures = []
    accepted = rejected = 0
    with tempfile.TemporaryDirectory(prefix='dast-fuzz-') as tmp:
        cases = [(s, True) for s in corpus]
        cases += [(p.read_text(encoding='utf-8-sig'), False)
                  for p in sorted((snippets.parent/'InvalidSnippets').glob('*.pas'))]
        for i in range(count):
            values = ','.join(str(rng.randrange(1000)) for _ in range(rng.randrange(1, 10)))
            s = f'unit Fuzz{i}; interface type TRec = record Value: Integer; end; implementation procedure Run; begin var a := [{values}]; for var x in a do begin if x > 5 then Continue; end; end; end.'
            cases.append((s, True))
            # Focused literal grammar and truncation fuzzing.
            quote = chr(39) * rng.choice([3, 5, 7, 9])
            newline = rng.choice(['\n', '\r\n', '\r'])
            body = '  text ' + chr(39) * rng.randrange(len(quote)) + ' $FF {not a comment}'
            digits = ''.join(rng.choice('0123456789abcdefABCDEF') for _ in range(rng.randrange(1, 17)))
            literal_source = (f'unit Literal{i}; interface const S=' + quote + newline +
                              body + newline + '  ' + quote + '; H=$' + '_'.join(digits) +
                              '; After=42; implementation end.')
            cases.append((literal_source, True))
            cut = rng.randrange(len(literal_source) + 1)
            malformed = literal_source[:cut]
            if rng.randrange(2):
                malformed += rng.choice([chr(39), chr(39)*3, '$', '$_', '$G', '\0', '\r'])
            cases.append((malformed, False))
            s = rng.choice(corpus)
            for _ in range(rng.randrange(1, 5)):
                pos = rng.randrange(len(s)+1)
                operation = rng.randrange(3)
                if operation == 0:
                    s = s[:pos] + rng.choice([';', "'", '{$IF (', '{$ENDIF}', '(*', '\0', '>', 'reference to ', '"""', '\n']) + s[pos:]
                elif operation == 1:
                    s = s[:pos] + s[pos+rng.randrange(1, 30):]
                else:
                    s = s[:pos]
            cases.append((s, False))
        def execute(case):
            i, (text, valid) = case
            source = Path(tmp) / f'Case{i}.pas'
            source.write_text(text, encoding='utf-8-sig')
            try:
                result = subprocess.run([str(executable), str(source),str(snippets.resolve())], capture_output=True, timeout=3)
                ok = result.returncode == 0 or (not valid and result.returncode == 10)
                if not ok:
                    return i, text, f'exit {result.returncode}: {result.stdout.decode(errors="replace")}', False
                return i, text, None, result.returncode == 0
            except subprocess.TimeoutExpired:
                return i, text, 'timeout', False
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for i, text, error, ok in pool.map(execute, enumerate(cases)):
                if error: failures.append((i, text, error))
                elif ok: accepted += 1
                else: rejected += 1
    output.mkdir(parents=True, exist_ok=True)
    for index, text, error in failures:
        (output / f'failure-{index}.pas').write_text(text, encoding='utf-8-sig')
    report = dict(seed=seed, accepted=accepted, rejected=rejected, failures=[dict(case=i,error=e) for i,_,e in failures])
    (output/'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
    return bool(failures)

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('executable',type=Path)
    p.add_argument('--snippets',type=Path,default=Path(__file__).parent/'Snippets')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--count',type=int,default=500)
    p.add_argument('--seed',type=int,default=20261018)
    a=p.parse_args()
    raise SystemExit(run(a.executable.resolve(),a.snippets,a.output,a.count,a.seed))

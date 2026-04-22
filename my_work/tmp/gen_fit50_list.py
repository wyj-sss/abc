import json, random
from pathlib import Path
root = Path('/mnt/d/My_abc_work/abc')
bench_dir = root / 'iwls26/results'
base_list = root / 'my_work/dynamic_scheduler_work/bench_ex200_209_one_each.txt'
out_list = root / 'my_work/dynamic_scheduler_work/bench_fit50_mix.txt'
out_meta = root / 'my_work/dynamic_scheduler_work/bench_fit50_mix_meta.json'
random.seed(20260420)
base_entries = []
for line in base_list.read_text(encoding='utf-8').splitlines():
    s = line.split('#', 1)[0].strip()
    if s:
        base_entries.append(s.replace('\\\\', '/'))
base_set = {Path(x).name for x in base_entries}
all_files = sorted(bench_dir.glob('*.aig'))
cand = [p for p in all_files if p.name not in base_set]
cand_sorted = sorted(cand, key=lambda p: p.stat().st_size, reverse=True)
large4 = cand_sorted[:4]
large_set = {p.name for p in large4}
rest = [p for p in cand if p.name not in large_set]
rest_sorted = sorted(rest, key=lambda p: p.stat().st_size)
cut = int(len(rest_sorted) * 0.8)
pool = rest_sorted[:max(cut, 36)]
sel36 = random.sample(pool, 36)
new40 = large4 + sel36
random.shuffle(new40)
full50 = base_entries + [str(Path('iwls26/results') / p.name).replace('\\\\', '/') for p in new40]
out_list.write_text('\n'.join(full50) + '\n', encoding='utf-8')
meta = {
  'total_all': len(all_files),
  'base10': base_entries,
  'new40_count': len(new40),
  'large4': [{'name': p.name, 'bytes': p.stat().st_size} for p in large4],
  'new40_top10_by_size': [{'name': p.name, 'bytes': p.stat().st_size} for p in sorted(new40, key=lambda p: p.stat().st_size, reverse=True)[:10]],
  'output_list': str(out_list)
}
out_meta.write_text(json.dumps(meta, indent=2), encoding='utf-8')
print('generated', out_list)
print('meta', out_meta)
print('all', len(all_files), 'base', len(base_entries), 'new40', len(new40), 'full', len(full50))
print('large4:', ', '.join(p.name for p in large4))
